# PreCompact / Stop hook (Windows / PowerShell).
# Appends a structured checkpoint stub to the resolved Checkpoint.md
# location. Re-scans the tree on every invocation so the hook stays in
# sync with whatever location SessionStart adopted (or the user moved
# to between hook calls).

$ErrorActionPreference = 'Stop'

# Force UTF-8 stdout so additionalContext reaches Claude correctly on
# Windows PowerShell 5.1.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

. (Join-Path $PSScriptRoot '_lib.ps1')

$cp = Resolve-ManagedFile -Filename 'Checkpoint.md'

# If somehow no file exists yet (e.g., SessionStart was skipped), create
# it at the resolved (root) location so we never crash.
if (-not (Test-Path -LiteralPath $cp.Path)) {
@"
# Checkpoint Log

This file is append-only. Each entry is written by the PreCompact / Stop
hook and captures session context: goals, decisions, open items,
completed items, files touched, and unresolved questions.

---
"@ | Set-Content -LiteralPath $cp.Path -Encoding UTF8
}

$ts   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$date = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")

# Read hook payload from stdin (JSON). Extract session_id + transcript_path.
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

$stub = @"

## Checkpoint @ $ts

- **Date:** $date
- **Session ID:** ``$sessionId``
- **Transcript:** ``$transcript``

### Goals for this session
<!-- Claude: fill in 1-3 bullets describing what we set out to do -->

### Decisions made
<!-- Claude: list concrete decisions with rationale + file:line evidence -->

### Completed / Resolved
<!-- Claude: bullet list of finished items, each with verifying command or PR link -->

### Open / In-flight
<!-- Claude: bullet list of things still in progress -->

### Blockers / Unresolved questions
<!-- Claude: anything that needs human input or external info -->

### Files touched
<!-- Claude: paths grouped by created/modified/deleted -->

### Verification evidence
<!-- Claude: tests run, commands executed, exit codes -- facts only -->

---
"@

Add-Content -LiteralPath $cp.Path -Value $stub -Encoding UTF8

# Use the canonical relative path the resolver already computed.
$cpRel = $cp.RelPath

$ctx = "A new checkpoint stub was appended at $ts to $cpRel ($($cp.Status)). " +
       "$($cp.Note) BEFORE doing anything else, edit that file and replace " +
       "each <!-- Claude: ... --> placeholder with factual content from this " +
       "session. Use file:line citations for decisions, exit codes for " +
       "verifications, and exact paths for files. Do NOT modify or remove " +
       "any prior checkpoint blocks. Append-only is non-negotiable."

$payload = @{
    hookSpecificOutput = @{
        additionalContext = $ctx
    }
} | ConvertTo-Json -Depth 5 -Compress

Write-Output $payload
