param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    & dotnet restore GHJump.slnx --locked-mode
    if ($LASTEXITCODE -ne 0) { throw 'Restore failed.' }
    & dotnet build GHJump.slnx -c $Configuration --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Build/analyzer checks failed.' }
    & dotnet test --solution GHJump.slnx -c $Configuration --no-build --no-restore
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
    & dotnet format GHJump.slnx --no-restore --verify-no-changes
    if ($LASTEXITCODE -ne 0) { throw 'Formatting/analyzer checks failed.' }
    & "$PSScriptRoot/Package.ps1" -Configuration $Configuration -Architecture $Architecture
    if ($Configuration -eq 'Release' -and $Architecture -eq 'x64') {
        & "$PSScriptRoot/Verify-Activation.ps1"
    }
} finally { Pop-Location }
