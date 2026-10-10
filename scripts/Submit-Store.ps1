param(
    [ValidateSet('verify', 'submit', 'listing-verify', 'listing-submit')][string]$Mode = 'verify',
    [string]$ListingPath = 'store/listings.json'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$productId = '9NN7GSPR8W9R'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Store-Listing.ps1')

# CLIの生出力には署名付きアップロードURLが含まれ得るため、ログへ流さない。
function Invoke-StoreCli {
    param([string[]]$Arguments)
    $startInfo = [Diagnostics.ProcessStartInfo]::new((Get-Command msstore -ErrorAction Stop).Source)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Environment['MSSTORE_OUTPUT_STREAM'] = 'stderr'
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($startInfo)
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $output = $outputTask.GetAwaiter().GetResult()
        $null = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Microsoft Store CLI failed (exit $($process.ExitCode)). Raw output was withheld to protect credentials and upload URLs."
        }
        return $output
    } finally { $process.Dispose() }
}

if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_REF -ne 'refs/heads/main') {
    throw 'Run this script through the Microsoft Store workflow on main.'
}
foreach ($name in @('MSSTORE_TENANT_ID', 'MSSTORE_CLIENT_ID', 'MSSTORE_SELLER_ID',
    'ACTIONS_ID_TOKEN_REQUEST_URL', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Required workflow setting is missing: $name"
    }
}

$listingInput = $null
$resolvedListingPath = $null
if ($Mode -like 'listing-*') {
    $resolvedListingPath = if ([IO.Path]::IsPathRooted($ListingPath)) { $ListingPath } else { Join-Path $root $ListingPath }
    $listingInput = Read-StoreListingInput -Path $resolvedListingPath
}

try {
    $tokenUrl = $env:ACTIONS_ID_TOKEN_REQUEST_URL + '&audience=api%3A%2F%2FAzureADTokenExchange'
    try {
        $token = Invoke-RestMethod -Uri $tokenUrl -Headers @{
            Authorization = "Bearer $env:ACTIONS_ID_TOKEN_REQUEST_TOKEN"
        } -TimeoutSec 30
        $env:MSSTORE_CLIENT_ASSERTION = $token.value
        if ([string]::IsNullOrWhiteSpace($env:MSSTORE_CLIENT_ASSERTION)) { throw 'Missing OIDC token.' }
    } catch { throw 'Could not obtain the GitHub OIDC token. Request details were withheld.' }
    Write-Output "::add-mask::$env:MSSTORE_CLIENT_ASSERTION"
    if ($Mode -like 'listing-*') {
        Invoke-StoreListingUpdate -Listings $listingInput -ResolvedListingPath $resolvedListingPath -Mode $Mode -ProductId $productId
        return
    }
    $null = Invoke-StoreCli -Arguments @('reconfigure', '--tenantId', $env:MSSTORE_TENANT_ID,
        '--clientId', $env:MSSTORE_CLIENT_ID, '--sellerId', $env:MSSTORE_SELLER_ID, '--clientAssertion')
    $application = Invoke-StoreCli -Arguments @('apps', 'get', $productId) | ConvertFrom-Json
    if ($application.Id -ne $productId -or $application.PackageIdentityName -ne 'apricot-cake.GHJump') {
        throw 'Store product identity does not match GH Jump.'
    }
    Write-Host "Store API authenticated; product $productId matches GH Jump."
    $pending = $application.PendingApplicationSubmission
    Write-Host "Pending submission: $([bool]$pending)"
    if ($Mode -eq 'verify') {
        $null = Invoke-StoreCli -Arguments @('submission', 'status', $productId)
        Write-Host 'Submission status read succeeded. No Store submission was changed.'
        return
    }
    if ($pending) {
        throw 'A pending submission exists. Finish or remove it in Partner Center before submitting a package update. No draft was overwritten.'
    }
    [xml]$manifest = Get-Content (Join-Path $root 'src/GHJump/Package.appxmanifest') -Raw
    $version = [version]$manifest.Package.Identity.Version
    if ($version.Major -lt 1 -or $version.Revision -ne 0) { throw 'Invalid Store package version.' }
    $published = Invoke-StoreCli -Arguments @('submission', 'get', $productId) | ConvertFrom-Json
    $publishedPackages = @($published.ApplicationPackages)
    if ($publishedPackages.Count -eq 0) { throw 'No published package version was returned.' }
    foreach ($package in $publishedPackages) {
        if ([string]::IsNullOrWhiteSpace($package.Version) -or $version -le [version]$package.Version) {
            throw 'The bundle version must be greater than every published package version.'
        }
    }
    $bundle = Join-Path $root "artifacts/packages/GHJump_${version}_Bundle.msixbundle"
    if (!(Test-Path -LiteralPath $bundle -PathType Leaf)) { throw 'Validated MSIXbundle was not found.' }
    $null = Invoke-StoreCli -Arguments @('publish', $bundle, '--appId', $productId)
    Write-Host 'Package update committed for Microsoft Store certification.'
    $null = Invoke-StoreCli -Arguments @('submission', 'status', $productId)
    Write-Host 'Submission status read succeeded. Certification and publication are separate from this workflow.'
} finally {
    $script:storeAccessToken = $null
    Remove-Item Env:MSSTORE_CLIENT_ASSERTION -ErrorAction SilentlyContinue
}
