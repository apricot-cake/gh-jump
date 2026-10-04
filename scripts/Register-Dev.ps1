param([ValidateSet('x64', 'arm64')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $root "artifacts/publish/$Architecture/AppxManifest.xml"
if (!(Test-Path $manifest)) { throw 'Run scripts/Package.ps1 first.' }
Add-AppxPackage -Register $manifest
Get-AppxPackage ApricotCake.GHJump | Select-Object Name, Version, InstallLocation
Write-Host 'Reload Command Palette extensions, then open GH Jump.'
