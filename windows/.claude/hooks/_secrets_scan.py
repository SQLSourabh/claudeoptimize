#!/usr/bin/env python
"""
Stdin: a Claude Code PreToolUse JSON payload.
Stdout: a single JSON object describing the verdict.
  {"action": "allow"} | {"action": "deny", "reason": "..."}

This file is the heart of the secrets-guard hook. It is intentionally
separate from the bash wrapper so stdin is reliably available (a heredoc
in the bash wrapper would consume stdin and silently break the scanner).
"""
import json
import re
import sys


# --- ALLOWLIST: paths where credential patterns are expected -----------
ALLOW_PATH_RE = re.compile(
    r"(\.env\.example|\.env\.template|\.env\.sample"
    r"|secrets[\\/]+(README|EXAMPLE)"
    r"|hooks[\\/]+_?secrets[_-]?(guard|scan)"
    r"|fixtures[\\/]+secrets"
    r"|test[s]?[\\/]+.*[\\/]+fixtures"
    r"|docs[\\/]+.*\.md$)",
    re.IGNORECASE,
)


# --- PLACEHOLDER tokens that mean "this is intentional, not a real secret"
# Deliberately conservative: must look like a deliberate placeholder.
# Words like EXAMPLE / REDACTED were removed because they false-trigger
# on real strings (e.g. "api.example.com" suppressed real key matches).
PLACEHOLDER_RE = re.compile(
    r"(<[A-Z0-9_\-]+>"           # <YOUR_KEY>
    r"|\$\{[A-Z0-9_]+\}"          # ${API_KEY}
    r"|process\.env\.[A-Z0-9_]+"  # process.env.API_KEY
    r"|os\.environ\["             # os.environ['X']
    r"|os\.getenv\(\s*['\"]"      # os.getenv("X")
    r"|getenv\(\s*['\"]"
    r"|YOUR_.*_HERE"
    r"|REPLACE_ME_WITH"
    r"|XXXX+)",
    re.IGNORECASE,
)


# --- Credential patterns. Conservative: prefer false-positive that the
# user can override (placeholder / allowlist) over false-negative.
PATTERNS = [
    ("AWS Access Key ID",
     re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("AWS Secret Access Key",
     re.compile(r"(?i)aws.{0,20}['\"][0-9a-zA-Z/+]{40}['\"]")),
    ("GitHub Personal Access Token",
     re.compile(r"\bghp_[A-Za-z0-9]{36,}\b")),
    ("GitHub OAuth token",
     re.compile(r"\bgho_[A-Za-z0-9]{36,}\b")),
    ("GitHub fine-grained token",
     re.compile(r"\bgithub_pat_[A-Za-z0-9_]{82,}\b")),
    ("Anthropic API key",
     re.compile(r"\bsk-ant-[A-Za-z0-9_-]{20,}\b")),
    ("OpenAI API key",
     re.compile(r"\bsk-[A-Za-z0-9]{20,}\b")),
    ("Stripe Live Key",
     re.compile(r"\b(sk|pk)_live_[A-Za-z0-9]{20,}\b")),
    ("Slack Bot Token",
     re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}\b")),
    ("Google API Key",
     re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("RSA / OpenSSH private key block",
     re.compile(r"-----BEGIN (RSA |EC |OPENSSH |DSA |PGP |)?PRIVATE KEY-----")),
    ("JWT token",
     re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b")),
    # `\b` won't fire between underscore and letter (both are word chars),
    # so `DB_PASSWORD = "..."` would slip past `\bpassword`. We anchor on
    # start-of-line OR a non-letter (space, underscore, dash, dot) instead.
    ("Generic secret assignment",
     re.compile(
         r"(?i)(?:^|[^A-Za-z0-9])"
         r"(api[_-]?key|api[_-]?secret|access[_-]?token"
         r"|client[_-]?secret|auth[_-]?token|private[_-]?key"
         r"|password|passwd|pwd|secret[_-]?key)"
         r"\s*[:=]\s*['\"]([^'\"\s]{16,})['\"]"
     )),
]


def _line_for_match(haystack: str, match: re.Match) -> str:
    start = haystack.rfind("\n", 0, match.start()) + 1
    end = haystack.find("\n", match.end())
    if end == -1:
        end = len(haystack)
    return haystack[start:end]


def _mask(s: str) -> str:
    if len(s) > 12:
        return f"{s[:4]}…{s[-4:]}"
    return "<redacted>"


def main() -> int:
    raw = sys.stdin.read()
    try:
        data = json.loads(raw or "{}")
    except json.JSONDecodeError:
        # Conservatively allow on unparseable input — don't break the
        # session if Claude Code ever changes the payload shape.
        print(json.dumps({"action": "allow", "reason": "unparseable hook payload"}))
        return 0

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}

    fields = []
    for key in ("content", "new_string", "command", "file_path"):
        v = tool_input.get(key)
        if isinstance(v, str):
            fields.append(v)

    haystack = "\n".join(fields)
    file_path = tool_input.get("file_path") or ""

    if file_path and ALLOW_PATH_RE.search(file_path):
        print(json.dumps({"action": "allow", "reason": "path on allowlist"}))
        return 0

    findings = []
    for label, rx in PATTERNS:
        for m in rx.finditer(haystack):
            line = _line_for_match(haystack, m)
            if PLACEHOLDER_RE.search(line):
                continue
            try:
                val = m.group(2)
                if PLACEHOLDER_RE.search(val):
                    continue
            except (IndexError, AttributeError):
                pass
            findings.append((label, _mask(m.group(0)), line.strip()[:120]))

    if not findings:
        print(json.dumps({"action": "allow"}))
        return 0

    parts = [
        f"BLOCKED by secrets-guard: tool '{tool_name}' would write "
        f"{len(findings)} suspected credential(s) into "
        f"{file_path or '<no file path>'}."
    ]
    for label, masked, ctx in findings[:3]:
        parts.append(f"  - {label}: {masked}  (line: {ctx!r})")
    parts.append(
        "\nResolve by ONE of: "
        "(a) replace the literal with a placeholder like ${VAR_NAME} or "
        "<YOUR_KEY_HERE>; "
        "(b) move the value to .env / .env.example with a placeholder; "
        "(c) if this is intentional test data, write to a file under "
        "fixtures/secrets/ which is on the allowlist."
    )
    print(json.dumps({"action": "deny", "reason": "\n".join(parts)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
