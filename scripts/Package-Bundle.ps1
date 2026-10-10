param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [string]$ArtifactDirectory = 'artifacts'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    [xml]$sourceManifest = Get-Content src/GHJump/Package.appxmanifest -Raw
    $identity = $sourceManifest.Package.Identity
    $version = $identity.Version
    foreach ($architecture in @('x64', 'arm64')) {
        & "$PSScriptRoot/Package.ps1" -Configuration $Configuration -Architecture $architecture -ArtifactDirectory $ArtifactDirectory
    }
    $output = Join-Path $root $ArtifactDirectory
    $packages = Join-Path $output 'packages'
    $mapping = Join-Path $packages 'bundle-mapping.txt'
    $lines = @('[Files]')
    foreach ($architecture in @('x64', 'arm64')) {
        $fileName = "GHJump_${version}_$architecture.msix"
        $package = Join-Path $packages $fileName
        $lines += '"' + $package + '" "' + $fileName + '"'
    }
    $lines | Set-Content -LiteralPath $mapping -Encoding utf8
    $kitBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $makeAppx = Get-ChildItem $kitBin -Filter makeappx.exe -Recurse |
        Where-Object { $_.Directory.Name -eq 'x64' } | Sort-Object FullName -Descending | Select-Object -First 1
    if (!$makeAppx) { throw 'Windows SDK MakeAppx.exe was not found.' }
    $bundle = Join-Path $packages "GHJump_${version}_Bundle.msixbundle"
    & $makeAppx.FullName bundle /f $mapping /p $bundle /bv $version /o *> (Join-Path $packages 'bundle.log')
    if ($LASTEXITCODE -ne 0) { throw 'MSIX bundle validation failed.' }
    $unpack = Join-Path $output 'validation/bundle'
    $artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($unpack)
    if (!$resolved.StartsWith($artifactsRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Generated output is outside the workspace artifacts directory.'
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    & $makeAppx.FullName unbundle /p $bundle /d $unpack /o *> (Join-Path $packages 'unbundle.log')
    if ($LASTEXITCODE -ne 0) { throw 'MSIX bundle round-trip validation failed.' }
    [xml]$manifest = Get-Content (Join-Path $unpack 'AppxMetadata/AppxBundleManifest.xml') -Raw
    $bundleIdentity = $manifest.Bundle.Identity
    if ($bundleIdentity.Name -ne $identity.Name -or $bundleIdentity.Publisher -ne $identity.Publisher -or $bundleIdentity.Version -ne $version) {
        throw 'Bundle identity or version does not match the source manifest.'
    }
    $applicationPackages = @($manifest.Bundle.Packages.Package | Where-Object Type -eq 'application')
    if ($applicationPackages.Count -ne 2) { throw 'The bundle must contain exactly two application packages.' }
    foreach ($architecture in @('x64', 'arm64')) {
        $entry = @($applicationPackages | Where-Object Architecture -eq $architecture)
        $fileName = "GHJump_${version}_$architecture.msix"
        if ($entry.Count -ne 1 -or $entry[0].FileName -ne $fileName -or $entry[0].Version -ne $version -or
            (Get-FileHash -LiteralPath (Join-Path $packages $fileName)).Hash -ne (Get-FileHash -LiteralPath (Join-Path $unpack $fileName)).Hash) {
            throw "Bundle package metadata or content is invalid: $architecture"
        }
    }
    Write-Host "Validated unsigned bundle: $bundle"
    Write-Host 'Store submission also requires the assigned Partner Center identity, a Store-compatible version, and certification.'
} finally { Pop-Location }
