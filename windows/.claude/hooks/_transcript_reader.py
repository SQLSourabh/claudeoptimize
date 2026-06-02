#!/usr/bin/env python
"""
Read a Claude Code transcript JSONL file and extract deterministic facts.

This is the deterministic-facts side of the Checkpoint contract:
- files_written     — every Write/Edit tool_use, deduplicated
- bash_commands     — every Bash tool_use with its exit code (paired via tool_use_id)
- slash_commands    — every user message that begins with "/"
- first_user_msg    — the first user-message text excerpt (≤140 chars)
- last_user_msg     — the most recent user-message text excerpt (≤140 chars)
- last_event_ts     — ISO timestamp of the most recent line that has one
- session_id        — sessionId from any line that has it
- block_id          — sha8(session_id + transcript_path), used by /checkpoint
                       to match a transcript to its Checkpoint block

CLI:
  python _transcript_reader.py <path-to-transcript.jsonl> [--json]

Without --json, prints a human-readable summary.
With --json, prints a JSON object suitable for piping to jq or another
script.

Cross-platform pure stdlib. No third-party deps. Same file ships to both
linux-macos and windows trees.
"""
import hashlib
import json
import re
import sys
from pathlib import Path


SLASH_COMMAND_RE = re.compile(r"^/[a-zA-Z][a-zA-Z0-9_-]*\b")


def _extract_text(content) -> str:
    """A user/assistant message's `content` is either a string OR a list of
    typed parts. Pull plain text out of either form."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                t = item.get("text", "")
                if isinstance(t, str):
                    parts.append(t)
        return "\n".join(parts)
    return ""


def _trim(s: str, n: int = 140) -> str:
    s = " ".join(s.split())  # collapse whitespace
    if len(s) <= n:
        return s
    return s[: n - 1].rstrip() + "…"


def read_transcript(path: str) -> dict:
    """Parse a JSONL transcript and return the deterministic-facts dict."""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Transcript not found: {path}")

    files_written: list[str] = []
    files_seen: set[str] = set()

    # tool_use events keyed by tool_use_id so we can attach exit codes
    # from the matching tool_result later.
    pending_bash: dict[str, dict] = {}
    bash_commands: list[dict] = []

    slash_commands: list[str] = []
    first_user_msg = ""
    last_user_msg = ""
    last_event_ts = ""
    session_id = ""

    with open(p, "r", encoding="utf-8", errors="replace") as f:
        for line_num, raw in enumerate(f, 1):
            raw = raw.rstrip("\n")
            if not raw.strip():
                continue
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                # Malformed line — skip but keep going.
                continue

            ts = obj.get("timestamp") or obj.get("ts")
            if isinstance(ts, str) and ts > last_event_ts:
                last_event_ts = ts

            sid = obj.get("sessionId") or obj.get("session_id")
            if isinstance(sid, str) and sid and not session_id:
                session_id = sid

            etype = obj.get("type")

            if etype == "user":
                msg = obj.get("message") or {}
                text = _extract_text(msg.get("content"))
                if text:
                    if not first_user_msg:
                        first_user_msg = _trim(text)
                    last_user_msg = _trim(text)
                    # Slash command detection — only if the very first non-
                    # whitespace token is a slash command.
                    stripped = text.lstrip()
                    m = SLASH_COMMAND_RE.match(stripped)
                    if m:
                        slash_commands.append(m.group(0))

                # tool_results may arrive inside user messages
                content = msg.get("content")
                if isinstance(content, list):
                    for item in content:
                        if not isinstance(item, dict):
                            continue
                        if item.get("type") != "tool_result":
                            continue
                        tu_id = item.get("tool_use_id")
                        if not tu_id or tu_id not in pending_bash:
                            continue
                        # Try to find an exit code in the result content.
                        result_text = _extract_text(item.get("content"))
                        exit_code = _extract_exit_code(result_text)
                        entry = pending_bash.pop(tu_id)
                        entry["exit_code"] = exit_code
                        entry["result_excerpt"] = _trim(result_text, 80)
                        bash_commands.append(entry)

            elif etype == "assistant":
                msg = obj.get("message") or {}
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                for item in content:
                    if not isinstance(item, dict):
                        continue
                    if item.get("type") != "tool_use":
                        continue
                    tname = item.get("name", "")
                    tinput = item.get("input") or {}
                    tu_id = item.get("id")

                    if tname in ("Write", "Edit", "NotebookEdit"):
                        fp = (tinput.get("file_path") or "").strip()
                        if fp and fp not in files_seen:
                            files_seen.add(fp)
                            files_written.append(fp)
                    elif tname == "Bash":
                        cmd = tinput.get("command", "")
                        if cmd and tu_id:
                            pending_bash[tu_id] = {
                                "command": _trim(cmd, 200),
                                "ts": ts or "",
                                "exit_code": None,
                                "result_excerpt": "",
                            }

    # Any pending bash entries never got a result line → unknown exit code.
    for tu_id, entry in pending_bash.items():
        bash_commands.append(entry)

    # Stable order (by ts when available)
    bash_commands.sort(key=lambda e: e.get("ts") or "")

    block_id = _block_id(session_id, str(p))

    return {
        "files_written": files_written,
        "bash_commands": bash_commands,
        "slash_commands": slash_commands,
        "first_user_msg": first_user_msg,
        "last_user_msg": last_user_msg,
        "last_event_ts": last_event_ts,
        "session_id": session_id or "unknown",
        "block_id": block_id,
        "transcript_path": str(p),
    }


_EXIT_CODE_RES = [
    re.compile(r"\bexit\s+code:?\s*(-?\d+)\b", re.I),
    re.compile(r"\bexit:?\s*(-?\d+)\b", re.I),
    re.compile(r"<exit_code>(-?\d+)</exit_code>"),
]


def _extract_exit_code(result_text: str):
    """Try several common shapes for exit-code fields. Returns int or None."""
    for rx in _EXIT_CODE_RES:
        m = rx.search(result_text)
        if m:
            try:
                return int(m.group(1))
            except ValueError:
                pass
    return None


def _block_id(session_id: str, transcript_path: str) -> str:
    """8-hex-char id used to bind a Checkpoint block to its source transcript.
    Stable across machines as long as inputs match."""
    raw = f"{session_id}|{transcript_path}".encode("utf-8")
    return hashlib.sha256(raw).hexdigest()[:8]


def _format_summary(facts: dict) -> str:
    out = []
    out.append(f"session_id:        {facts['session_id']}")
    out.append(f"block_id:          {facts['block_id']}")
    out.append(f"transcript_path:   {facts['transcript_path']}")
    out.append(f"last_event_ts:     {facts['last_event_ts']}")
    out.append(f"first_user_msg:    {facts['first_user_msg']}")
    out.append(f"last_user_msg:     {facts['last_user_msg']}")
    out.append(f"files_written:     {len(facts['files_written'])}")
    for f in facts["files_written"]:
        out.append(f"  - {f}")
    out.append(f"bash_commands:     {len(facts['bash_commands'])}")
    for b in facts["bash_commands"]:
        ec = b["exit_code"] if b["exit_code"] is not None else "?"
        out.append(f"  - {b['command']} → exit {ec}")
    out.append(f"slash_commands:    {len(facts['slash_commands'])}")
    for s in facts["slash_commands"]:
        out.append(f"  - {s}")
    return "\n".join(out)


def render_files_touched(edits_json: str) -> str:
    """Markdown rendering of session-state edits. Used by the hook to
    avoid inline-Python quoting issues across shells."""
    try:
        edits = json.loads(edits_json or "[]")
    except json.JSONDecodeError:
        edits = []
    written = sorted({e.get("file", "") for e in edits
                      if e.get("tool") == "Write" and e.get("file")})
    edited = sorted({e.get("file", "") for e in edits
                     if e.get("tool") == "Edit" and e.get("file")} - set(written))
    if not written and not edited:
        return "- (no edit events recorded by edit-recorder this session)"
    out = []
    if written:
        out.append("- created / written:")
        for f in written:
            out.append(f"  - {f}")
    if edited:
        out.append("- modified:")
        for f in edited:
            out.append(f"  - {f}")
    return "\n".join(out)


def render_bash_section(facts: dict) -> str:
    cmds = facts.get("bash_commands", [])
    if not cmds:
        return "- (no Bash tool calls observed in transcript)"
    lines = []
    for c in cmds:
        ec = c.get("exit_code")
        ec_s = str(ec) if ec is not None else "?"
        cmd = c.get("command", "")
        lines.append(f"- `{cmd}` -> exit {ec_s}")
    return "\n".join(lines)


def render_slash_section(facts: dict) -> str:
    sc = facts.get("slash_commands", [])
    if not sc:
        return "- (none observed)"
    return "\n".join(f"- {s}" for s in sc)


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(
            "usage: _transcript_reader.py <path> [--json|--markdown=<section>]\n"
            "  sections: bash | slash | files (with --edits-json=<json>)",
            file=sys.stderr,
        )
        return 2
    path = argv[1]
    rest = argv[2:]

    if "--json" in rest:
        try:
            facts = read_transcript(path)
        except FileNotFoundError as e:
            print(f"error: {e}", file=sys.stderr)
            return 1
        print(json.dumps(facts, indent=2))
        return 0

    # --markdown=<section> renders a specific section ready for the hook.
    md_arg = next((a for a in rest if a.startswith("--markdown=")), None)
    if md_arg:
        section = md_arg.split("=", 1)[1]

        if section == "files":
            edits_arg = next(
                (a for a in rest if a.startswith("--edits-json=")), None
            )
            edits_json = edits_arg.split("=", 1)[1] if edits_arg else "[]"
            print(render_files_touched(edits_json))
            return 0

        # bash / slash come from the transcript itself
        try:
            facts = read_transcript(path)
        except FileNotFoundError:
            facts = {"bash_commands": [], "slash_commands": []}

        if section == "bash":
            print(render_bash_section(facts))
            return 0
        if section == "slash":
            print(render_slash_section(facts))
            return 0
        if section == "block-id":
            print(facts.get("block_id", "unknown"))
            return 0

        print(f"unknown section: {section}", file=sys.stderr)
        return 2

    try:
        facts = read_transcript(path)
    except FileNotFoundError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(_format_summary(facts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
