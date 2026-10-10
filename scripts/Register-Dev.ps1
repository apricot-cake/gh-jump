param([ValidateSet('x64', 'arm64')][string]$Architecture = 'x64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $root "artifacts/publish/$Architecture/AppxManifest.xml"
if (!(Test-Path $manifest)) { throw 'Run scripts/Package.ps1 first.' }
Add-AppxPackage -Register $manifest
[xml]$packageManifest = Get-Content -LiteralPath $manifest -Raw
Get-AppxPackage -Name $packageManifest.Package.Identity.Name | Select-Object Name, Version, InstallLocation
& "$PSScriptRoot/Restart-CommandPalette.ps1"
Write-Host 'Open GH Jump in Command Palette.'
