# Installer for the Claude Code optimization pack (Windows / PowerShell).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Target C:\path\to\project
#
# Idempotent: re-running does not overwrite an existing CLAUDE.md or
# settings.json. Existing files are backed up with .bak.

[CmdletBinding()]
param(
    [string]$Target = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not (Test-Path -LiteralPath $Target -PathType Container)) {
    Write-Error "Target directory does not exist: $Target"
    exit 1
}

Write-Host "Installing Claude optimization pack:"
Write-Host "  source: $src"
Write-Host "  target: $Target"
Write-Host ""

# 1. Create .claude/ directory tree.
$claudeDir   = Join-Path $Target '.claude'
$hooksDir    = Join-Path $claudeDir 'hooks'
$commandsDir = Join-Path $claudeDir 'commands'
$agentsDir   = Join-Path $claudeDir 'agents'

$null = New-Item -ItemType Directory -Force -Path $hooksDir
$null = New-Item -ItemType Directory -Force -Path $commandsDir
$null = New-Item -ItemType Directory -Force -Path $agentsDir

# 2. Hooks (always overwrite — versioned by us).
Copy-Item -Force -Path (Join-Path $src '.claude\hooks\_lib.ps1') -Destination $hooksDir
Copy-Item -Force -Path (Join-Path $src '.claude\hooks\ensure-checkpoint-files.ps1') -Destination $hooksDir
Copy-Item -Force -Path (Join-Path $src '.claude\hooks\append-checkpoint.ps1') -Destination $hooksDir

# 3. Commands (always overwrite).
Get-ChildItem -Path (Join-Path $src '.claude\commands') -Filter '*.md' | ForEach-Object {
    Copy-Item -Force -Path $_.FullName -Destination $commandsDir
}

# 4. Agents (always overwrite).
Get-ChildItem -Path (Join-Path $src '.claude\agents') -Filter '*.md' | ForEach-Object {
    Copy-Item -Force -Path $_.FullName -Destination $agentsDir
}

# 5. CLAUDE.md — never clobber.
$claudeMd    = Join-Path $Target 'CLAUDE.md'
$srcClaudeMd = Join-Path $src 'CLAUDE.md'

if (Test-Path -LiteralPath $claudeMd) {
    $optMd = Join-Path $Target 'CLAUDE.optimization.md'
    Copy-Item -Force -Path $srcClaudeMd -Destination $optMd
    Write-Host "NOTE: $claudeMd already exists."
    Write-Host "      Wrote pack rules to CLAUDE.optimization.md - merge manually."
}
else {
    Copy-Item -Force -Path $srcClaudeMd -Destination $claudeMd
}

# 6. settings.json — never clobber. If present, back up + write a sibling
#    .pack.json that the user can merge into their existing config.
$settings    = Join-Path $claudeDir 'settings.json'
$srcSettings = Join-Path $src '.claude\settings.json'

if (Test-Path -LiteralPath $settings) {
    Copy-Item -Force -Path $settings -Destination "$settings.bak"
    Copy-Item -Force -Path $srcSettings -Destination (Join-Path $claudeDir 'settings.pack.json')
    Write-Host "NOTE: $settings already exists (backed up to settings.json.bak)."
    Write-Host "      Wrote pack hooks to settings.pack.json - merge the 'hooks' key manually."
}
else {
    Copy-Item -Force -Path $srcSettings -Destination $settings
}

Write-Host ""
Write-Host "Installation complete."
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Start a new Claude Code session in $Target"
Write-Host "  2. Checkpoint.md and EOD_Summary.md will be created automatically"
Write-Host "  3. Try /persona-roundtable, /llm-audit, or /EOD_Summary"
