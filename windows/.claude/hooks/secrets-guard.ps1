# PreToolUse hook on Write|Edit|Bash (Windows / PowerShell).
# Delegates to _secrets_scan.py. Returns the Claude Code hook contract:
#   permissionDecision=deny  -> tool call blocked
#   empty output             -> allow

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

# Inactive without python.
if (-not (Get-Command python -ErrorAction SilentlyContinue)) { exit 0 }

$payload = [Console]::In.ReadToEnd()
$scanner = Join-Path $PSScriptRoot '_secrets_scan.py'

$verdict = $payload | python $scanner

try {
    $obj = $verdict | ConvertFrom-Json -ErrorAction Stop
} catch {
    exit 0
}

if ($obj.action -eq 'deny') {
    $out = @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $obj.reason
        }
    } | ConvertTo-Json -Depth 6 -Compress
    Write-Output $out
}

exit 0
