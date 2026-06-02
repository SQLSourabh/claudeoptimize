# PreCompact / Stop hook (Windows / PowerShell).
#
# Contract (per CLAUDE.md §2):
# - Header (timestamp, session_id, transcript_path) — populated here.
# - Files touched              — populated from session-state edits.
# - Verification evidence      — populated from transcript Bash events.
# - Slash commands invoked     — populated from transcript user msgs.
# - Goals / Decisions / Open / Blockers — placeholders, filled by /checkpoint.
# - checkpoint-meta footer     — block_id used by /checkpoint to relocate.

$ErrorActionPreference = 'Stop'

# Force UTF-8 stdout so additionalContext reaches Claude correctly on
# Windows PowerShell 5.1.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

. (Join-Path $PSScriptRoot '_lib.ps1')

$cp = Resolve-ManagedFile -Filename 'Checkpoint.md'

# Bootstrap if missing.
if (-not (Test-Path -LiteralPath $cp.Path)) {
@"
# Checkpoint Log

This file is append-only. Each entry is written by the PreCompact / Stop
hook and captures session context: goals, decisions, open items,
completed items, files touched, and unresolved questions. The hook
populates deterministic facts (files touched, bash exit codes, slash
commands). Run ``/checkpoint`` to fill in the language-level sections
(goals, decisions, open, blockers).

---
"@ | Set-Content -LiteralPath $cp.Path -Encoding UTF8
}

$ts   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")

# Read hook payload from stdin.
$sessionId  = ''
$transcript = ''
try {
    $stdin = [Console]::In.ReadToEnd()
    if ($stdin) {
        $obj = $stdin | ConvertFrom-Json -ErrorAction Stop
        if ($obj.session_id)      { $sessionId  = [string]$obj.session_id }
        if ($obj.transcript_path) { $transcript = [string]$obj.transcript_path }
    }
} catch {
    # Stdin missing or not valid JSON.
}
if (-not $sessionId)  { $sessionId  = 'unknown' }
if (-not $transcript) { $transcript = 'unknown' }

# Fetch deterministic facts.
$pythonOk = $null -ne (Get-Command python -ErrorAction SilentlyContinue)

$readerPath = Join-Path $PSScriptRoot '_transcript_reader.py'
$statePath  = Join-Path $PSScriptRoot '_session_state.py'

# Sentinel transcript path for renderer when no transcript is available
# (some --markdown subcommands still need a positional path arg).
$transcriptForReader = if ($transcript -eq 'unknown') { 'NUL' } else { $transcript }

# 1. Files touched from _session_state.py + reader's --markdown=files renderer.
$filesSection = "- (no edit events recorded by edit-recorder this session)"
if ($pythonOk -and $sessionId -ne 'unknown') {
    try {
        $editsJson = & python $statePath 'list-edits' $sessionId 2>$null
        if ($editsJson -is [array]) { $editsJson = ($editsJson -join '') }
        if (-not $editsJson) { $editsJson = '[]' }
        $rendered = & python $readerPath $transcriptForReader '--markdown=files' "--edits-json=$editsJson" 2>$null
        if ($rendered) { $filesSection = $rendered }
    } catch {
        $filesSection = "- (failed to read session state)"
    }
}

# 2. Verification + slash from transcript.
$bashSection  = "- (no Bash tool calls observed in transcript)"
$slashSection = "- (none observed)"

if ($pythonOk -and $transcript -ne 'unknown' -and (Test-Path -LiteralPath $transcript)) {
    try {
        $bashOut = & python $readerPath $transcript '--markdown=bash' 2>$null
        if ($bashOut) { $bashSection = $bashOut }
        $slashOut = & python $readerPath $transcript '--markdown=slash' 2>$null
        if ($slashOut) { $slashSection = $slashOut }
    } catch {
        # Leave defaults
    }
} elseif ($transcript -eq 'unknown') {
    $bashSection = "- (transcript not available; no verification facts captured)"
    $slashSection = "- (transcript not available)"
}

# block_id from reader, or fallback.
$blockId = 'unknown'
if ($pythonOk -and $transcript -ne 'unknown' -and (Test-Path -LiteralPath $transcript)) {
    try {
        $bidOut = & python $readerPath $transcript '--markdown=block-id' 2>$null
        if ($bidOut) {
            $bidStr = ($bidOut -join '').Trim()
            if ($bidStr) { $blockId = $bidStr }
        }
    } catch {
        # leave 'unknown'
    }
}
if ($blockId -eq 'unknown' -and $pythonOk) {
    # Fallback: hash session_id + transcript path.
    try {
        $hashIn = "$sessionId|$transcript"
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($hashIn)
        $hashBytes = $sha.ComputeHash($bytes)
        $hexFull = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
        $blockId = $hexFull.Substring(0, 8)
    } catch {
        $blockId = 'unknown'
    }
}

# Compose block. PS arrays from python -c come in as multi-line strings;
# join them.
$filesSectionStr = ($filesSection -join "`n")
$bashSectionStr  = ($bashSection  -join "`n")
$slashSectionStr = ($slashSection -join "`n")

$block = @"

## Checkpoint @ $ts

- **Date:** $date
- **Session ID:** ``$sessionId``
- **Transcript:** ``$transcript``

### Files touched (deterministic -- from edit-recorder)
$filesSectionStr

### Verification evidence (deterministic -- from transcript Bash events)
$bashSectionStr

### Slash commands invoked (deterministic)
$slashSectionStr

### Goals for this session
<!-- Claude: fill in via /checkpoint -->

### Decisions made
<!-- Claude: fill in via /checkpoint -->

### Open / In-flight
<!-- Claude: fill in via /checkpoint -->

### Blockers / Unresolved questions
<!-- Claude: fill in via /checkpoint -->

<!-- checkpoint-meta: session_id=$sessionId transcript=$transcript block_id=$blockId -->

---
"@

Add-Content -LiteralPath $cp.Path -Value $block -Encoding UTF8

$cpRel = $cp.RelPath
$ctx = "A new checkpoint block was appended at $ts to $cpRel ($($cp.Status)). " +
       "$($cp.Note) The block contains DETERMINISTIC facts (files touched, " +
       "bash exit codes, slash commands). The four narrative sections " +
       "(Goals / Decisions / Open / Blockers) carry placeholders. Run " +
       "/checkpoint to fill them in. Append-only: never modify or remove " +
       "prior checkpoint blocks. block_id=$blockId."

$payload = @{
    hookSpecificOutput = @{
        additionalContext = $ctx
    }
} | ConvertTo-Json -Depth 6 -Compress

Write-Output $payload
