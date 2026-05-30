# PostToolUse hook on Write|Edit (Windows / PowerShell). Read-only state.

$ErrorActionPreference = 'Stop'

if (-not (Get-Command python -ErrorAction SilentlyContinue)) { exit 0 }

$payload = [Console]::In.ReadToEnd()
if (-not $payload) { exit 0 }

try {
    $obj = $payload | ConvertFrom-Json -ErrorAction Stop
} catch {
    exit 0
}

$sessionId = if ($obj.session_id) { [string]$obj.session_id } else { 'unknown' }
$toolName  = if ($obj.tool_name)  { [string]$obj.tool_name }  else { '' }
$filePath  = if ($obj.tool_input.file_path) { [string]$obj.tool_input.file_path } else { '' }

if (-not $filePath) { exit 0 }

$helper = Join-Path $PSScriptRoot '_session_state.py'
try {
    & python $helper append-edit $sessionId $filePath $toolName *> $null
} catch {
    # Non-fatal.
}

exit 0
