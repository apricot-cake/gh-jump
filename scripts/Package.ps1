param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [ValidateSet('x64', 'arm64')][string]$Architecture = 'x64',
    [string]$ArtifactDirectory = 'artifacts'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $output = Join-Path $root $ArtifactDirectory
    $publish = Join-Path $output "publish/$Architecture"
    $packages = Join-Path $output 'packages'
    $validation = Join-Path $output "validation/$Architecture"
    $artifactsRoot = [IO.Path]::GetFullPath((Join-Path $root 'artifacts')) + [IO.Path]::DirectorySeparatorChar
    foreach ($target in @($publish, $validation)) {
        $resolved = [IO.Path]::GetFullPath($target)
        if (!$resolved.StartsWith($artifactsRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Generated output is outside the workspace artifacts directory.'
        }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
    New-Item -ItemType Directory -Force $publish, $packages | Out-Null
    & dotnet publish src/GHJump/GHJump.csproj -c $Configuration -r "win-$Architecture" --self-contained true -o $publish
    if ($LASTEXITCODE -ne 0) { throw 'Publish failed.' }
    [xml]$manifest = Get-Content src/GHJump/Package.appxmanifest -Raw
    $manifest.Package.Identity.ProcessorArchitecture = $Architecture
    $manifest.Save((Join-Path $publish 'AppxManifest.xml'))
    New-Item -ItemType Directory -Force (Join-Path $publish 'Public') | Out-Null
    $kitBin = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/bin'
    $makeAppx = Get-ChildItem $kitBin -Filter makeappx.exe -Recurse |
        Where-Object { $_.Directory.Name -eq 'x64' } | Sort-Object FullName -Descending | Select-Object -First 1
    if (!$makeAppx) { throw 'Windows SDK MakeAppx.exe was not found.' }
    $packageVersion = $manifest.Package.Identity.Version
    $package = Join-Path $packages "GHJump_${packageVersion}_$Architecture.msix"
    & $makeAppx.FullName pack /d $publish /p $package /o *> (Join-Path $packages "pack-$Architecture.log")
    if ($LASTEXITCODE -ne 0) { throw 'MSIX schema/package validation failed.' }
    $unpack = $validation
    & $makeAppx.FullName unpack /p $package /d $unpack /o *> (Join-Path $packages "unpack-$Architecture.log")
    if ($LASTEXITCODE -ne 0) { throw 'MSIX round-trip validation failed.' }
    [xml]$packedManifest = Get-Content (Join-Path $unpack 'AppxManifest.xml') -Raw
    if ($packedManifest.Package.Identity.Name -ne $manifest.Package.Identity.Name -or
        $packedManifest.Package.Identity.Publisher -ne $manifest.Package.Identity.Publisher -or
        $packedManifest.Package.Identity.Version -ne $manifest.Package.Identity.Version -or
        $packedManifest.Package.Identity.ProcessorArchitecture -ne $Architecture -or
        !(Test-Path (Join-Path $unpack 'GHJump.exe')) -or
        $packedManifest.Package.Applications.Application.Extensions.Extension.AppExtension.Name -notcontains 'com.microsoft.commandpalette') {
        throw 'Package identity, version, architecture, executable or extension registration is invalid.'
    }
    $requiredLicenses = @(
        'LICENSE',
        'licenses/THIRD-PARTY-NOTICES.md',
        'licenses/CommandPalette-SDK-MIT.txt',
        'licenses/CsWinRT-MIT.txt',
        'licenses/WinRTServer-MIT.txt',
        'licenses/ToolGood-Words-Pinyin-MIT.txt',
        'licenses/Windows-SDK.rtf',
        'licenses/NET-Runtime-MIT.txt',
        'licenses/NET-Runtime-Third-Party-Notices.txt',
        'licenses/Octicons-MIT.txt'
    )
    foreach ($required in $requiredLicenses) {
        if (!(Test-Path -LiteralPath (Join-Path $root $required))) {
            throw "Required license source is missing: $required"
        }
    }
    $licenseSources = @((Get-Item (Join-Path $root 'LICENSE'))) + @(Get-ChildItem (Join-Path $root 'licenses') -Recurse -File)
    foreach ($source in $licenseSources) {
        $relative = [IO.Path]::GetRelativePath($root, $source.FullName)
        $packed = Join-Path $unpack $relative
        if (!(Test-Path -LiteralPath $packed) -or
            (Get-FileHash -LiteralPath $source.FullName).Hash -ne (Get-FileHash -LiteralPath $packed).Hash) {
            throw "Required license document is missing or changed in the package: $relative"
        }
    }
    Write-Host "Validated unsigned package: $package"
} finally { Pop-Location }
