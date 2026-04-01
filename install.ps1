# install.ps1 — installs the /sweep skill into %USERPROFILE%\.claude\skills\
$ErrorActionPreference = "Stop"

$dest = if ($env:CLAUDE_SKILLS_DIR) { $env:CLAUDE_SKILLS_DIR } else { "$env:USERPROFILE\.claude\skills" }
$src  = Join-Path $PSScriptRoot "skills\sweep"

if (-not (Test-Path $src)) {
    Write-Error "skills\sweep not found relative to this script."
    exit 1
}

New-Item -ItemType Directory -Force -Path $dest | Out-Null
$target = Join-Path $dest "sweep"
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
Copy-Item -Recurse $src $target

Write-Host "Installed: $target"
Write-Host "The /sweep skill is ready. Start a new Claude Code conversation to use it."
