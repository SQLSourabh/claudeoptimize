# PreToolUse hook on Write|Edit (Windows / PowerShell). Nudge, not block.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

if (-not (Get-Command python -ErrorAction SilentlyContinue)) { exit 0 }
if ($env:CLAUDE_SKIP_TEST_FIRST -eq '1') { exit 0 }

$payload = [Console]::In.ReadToEnd()
$scanner = Join-Path $PSScriptRoot '_test_first.py'

$verdict = $payload | python $scanner

try {
    $obj = $verdict | ConvertFrom-Json -ErrorAction Stop
} catch {
    exit 0
}

if ($obj.action -eq 'warn') {
    $out = @{
        hookSpecificOutput = @{
            hookEventName     = 'PreToolUse'
            additionalContext = $obj.reason
        }
    } | ConvertTo-Json -Depth 6 -Compress
    Write-Output $out
}

exit 0
