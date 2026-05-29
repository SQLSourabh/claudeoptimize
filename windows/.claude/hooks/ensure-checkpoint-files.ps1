# SessionStart hook (Windows / PowerShell).
# Ensures Checkpoint.md and EOD_Summary.md exist somewhere in the project
# tree. Adopts an existing file if found; creates a new one at project
# root only when none exists. Idempotent — never overwrites.

$ErrorActionPreference = 'Stop'

# Force UTF-8 stdout so additionalContext reaches Claude correctly on
# Windows PowerShell 5.1 (default OEM encoding mangles non-ASCII).
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

. (Join-Path $PSScriptRoot '_lib.ps1')

# --- Checkpoint.md ---
$cp = Resolve-ManagedFile -Filename 'Checkpoint.md'

if ($cp.Status -eq 'create') {
@"
# Checkpoint Log

This file is append-only. Each entry is written by the PreCompact / Stop
hook and captures session context: goals, decisions, open items,
completed items, files touched, and unresolved questions.

---
"@ | Set-Content -LiteralPath $cp.Path -Encoding UTF8
}

# --- EOD_Summary.md ---
$eod = Resolve-ManagedFile -Filename 'EOD_Summary.md'

if ($eod.Status -eq 'create') {
@"
# End-of-Day Summary

Populated by the ``/EOD_Summary`` command. Each day's section is appended,
never overwritten.

---
"@ | Set-Content -LiteralPath $eod.Path -Encoding UTF8
}

# Use the canonical relative paths the resolver already computed.
$cpRel  = $cp.RelPath
$eodRel = $eod.RelPath

$ctx = "Checkpoint resolution: $cpRel ($($cp.Status)). $($cp.Note) " +
       "EOD resolution: $eodRel ($($eod.Status)). $($eod.Note) " +
       "Append-only contract: NEVER overwrite either file. If you need " +
       "to reference them in this session, use the absolute paths logged " +
       "here, not assumptions about project root."

$payload = @{
    hookSpecificOutput = @{
        hookEventName     = 'SessionStart'
        additionalContext = $ctx
    }
} | ConvertTo-Json -Depth 5 -Compress

Write-Output $payload
