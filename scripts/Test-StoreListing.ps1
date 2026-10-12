$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Store-Listing.ps1')

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Message)
    $rejected = $false
    try { $null = & $Action } catch { $rejected = $true }
    Assert-True $rejected $Message
}

function ConvertTo-TestJson {
    param($Value)
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('gh-jump-store-listing-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'images') -Force
try {
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'store/images/repositories.png') -Destination (Join-Path $fixtureRoot 'images/repositories.png')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'store/images/actions.png') -Destination (Join-Path $fixtureRoot 'images/actions.png')
    [IO.File]::WriteAllBytes((Join-Path $fixtureRoot 'images/tiny.png'), [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='))
    $portrait = [Drawing.Bitmap]::new(768, 1366)
    try { $portrait.Save((Join-Path $fixtureRoot 'images/portrait.png'), [Drawing.Imaging.ImageFormat]::Png) } finally { $portrait.Dispose() }
    $jpeg = [Drawing.Bitmap]::new(1366, 768)
    try { $jpeg.Save((Join-Path $fixtureRoot 'images/jpeg.jpg'), [Drawing.Imaging.ImageFormat]::Jpeg) } finally { $jpeg.Dispose() }
    [IO.File]::WriteAllBytes((Join-Path $fixtureRoot 'images/corrupt.png'), [byte[]](137, 80, 78, 71, 13, 10, 26, 10))
    Copy-Item -LiteralPath (Join-Path $fixtureRoot 'images/actions.png') -Destination (Join-Path $fixtureRoot 'images/oversize.png')
    $oversizeFile = [IO.File]::OpenWrite((Join-Path $fixtureRoot 'images/oversize.png'))
    try { $oversizeFile.SetLength(50MB + 1) } finally { $oversizeFile.Dispose() }

    $published = @{
        applicationPackages = @(@{ fileName = 'existing.msixbundle'; fileStatus = 'Uploaded'; id = 'package-123'; version = '1.0.0.0' })
        pricing = @{ priceId = 'Free'; isAdvancedPricingModel = $false }
        targetPublishMode = 'Immediate'
        notesForCertification = 'Existing notes'
        listings = @{
            'en-us' = @{
                baseListing = @{
                    description = 'Old description'
                    title = 'GH Jump'
                    releaseNotes = 'Existing release notes'
                    images = @(
                        @{ fileName = 'existing-shot.png'; fileStatus = 'Uploaded'; imageType = 'Screenshot'; description = 'Old screenshot' },
                        @{ fileName = 'existing-icon.png'; fileStatus = 'Uploaded'; imageType = 'Icon'; description = 'Existing icon' }
                    )
                }
                platformOverrides = @{ Windows = @{ title = 'Windows title' } }
            }
            'ja-jp' = @{ baseListing = @{ description = 'Existing Japanese description'; title = 'GH Jump'; images = @() } }
        }
    }
    $publishedBefore = ConvertTo-TestJson $published
    $bundlePath = Join-Path $fixtureRoot 'GHJump_1.0.1.0_Bundle.msixbundle'
    $bundleArchive = [IO.Compression.ZipFile]::Open($bundlePath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $bundleEntry = $bundleArchive.CreateEntry('AppxMetadata/AppxBundleManifest.xml')
        $writer = [IO.StreamWriter]::new($bundleEntry.Open())
        try { $writer.Write('<Bundle><Identity Name="apricot-cake.GHJump" Version="1.0.1.0" /></Bundle>') } finally { $writer.Dispose() }
    } finally { $bundleArchive.Dispose() }
    $packageInput = Read-StorePackageInput -Path $bundlePath -Version ([version]'1.0.1.0')
    Assert-Rejected { Read-StorePackageInput -Path (Join-Path $fixtureRoot 'GHJump_1.0.2.0_Bundle.msixbundle') -Version ([version]'1.0.2.0') } 'Missing bundle files must be rejected.'
    Assert-Rejected { Read-StorePackageInput -Path $bundlePath -Version ([version]'1.0.2.0') } 'Bundle file names must match the application manifest version.'
    Assert-Rejected { Read-StorePackageInput -Path $bundlePath -Version ([version]'1.0.1.1') } 'Store bundle revisions must remain zero.'
    $wrongBundlePath = Join-Path $fixtureRoot 'GHJump_1.0.2.0_Bundle.msixbundle'
    Copy-Item -LiteralPath $bundlePath -Destination $wrongBundlePath
    Assert-Rejected { Read-StorePackageInput -Path $wrongBundlePath -Version ([version]'1.0.2.0') } 'The actual bundle manifest version must match the requested version.'
    $requested = @{
        'en-us' = @{
            description = 'Updated description'
            images = @(
                @{ fileName = 'images/repositories.png'; imageType = 'Screenshot'; description = 'Repositories' },
                @{ fileName = 'images/actions.png'; imageType = 'Screenshot'; description = 'Actions' }
            )
        }
    }
    $plan = New-StoreListingPlan -Published $published -Listings $requested -RootDirectory $fixtureRoot
    $combinedPlan = New-StoreListingPlan -Published $published -Listings $requested -RootDirectory $fixtureRoot -Package $packageInput
    Assert-True ($combinedPlan.PackageIncluded -and $combinedPlan.ImageCount -eq 2 -and $combinedPlan.Assets.Count -eq 3) 'Combined plans must include one bundle alongside localized screenshots.'
    Assert-True ($combinedPlan.Submission.applicationPackages[0].fileStatus -ceq 'PendingDelete' -and $combinedPlan.Submission.applicationPackages[0].id -ceq 'package-123') 'Combined plans must preserve the existing package identity while marking it for replacement.'
    $packageUpload = @($combinedPlan.Submission.applicationPackages | Where-Object { $_.fileStatus -eq 'PendingUpload' })
    Assert-True ($packageUpload.Count -eq 1 -and $packageUpload[0].fileName -ceq 'GHJump_1.0.1.0_Bundle.msixbundle' -and
        $packageUpload[0].minimumDirectXVersion -ceq 'None' -and $packageUpload[0].minimumSystemRam -ceq 'None' -and $packageUpload[0].Count -eq 4) 'New package metadata must contain the four official required fields.'
    $sameVersion = ConvertTo-TestJson $packageInput | ConvertFrom-Json -AsHashtable
    $sameVersion.Version = '1.0.0.0'
    Assert-Rejected { New-StoreListingPlan -Published $published -Listings $requested -RootDirectory $fixtureRoot -Package $sameVersion } 'The new version must exceed every published version.'
    $newerPublished = ConvertTo-TestJson $published | ConvertFrom-Json -AsHashtable
    $newerPublished.applicationPackages += @{ fileName = 'newer.msix'; fileStatus = 'Uploaded'; version = '1.0.2.0' }
    Assert-Rejected { New-StoreListingPlan -Published $newerPublished -Listings $requested -RootDirectory $fixtureRoot -Package $packageInput } 'A newer published package in another architecture must prevent downgrade.'
    $combinedArchivePath = Join-Path $fixtureRoot 'combined.zip'
    New-StoreImageArchive -Assets $combinedPlan.Assets -Path $combinedArchivePath
    $combinedArchive = [IO.Compression.ZipFile]::OpenRead($combinedArchivePath)
    try {
        Assert-True ($combinedArchive.Entries.Count -eq 3 -and $null -ne $combinedArchive.GetEntry('GHJump_1.0.1.0_Bundle.msixbundle') -and
            $null -ne $combinedArchive.GetEntry('en-us/images/repositories.png')) 'The same upload ZIP must contain package and listing images.'
    } finally { $combinedArchive.Dispose() }
    Assert-True ((ConvertTo-TestJson $published) -ceq $publishedBefore) 'Planning must not mutate the published submission.'
    Assert-True ((ConvertTo-TestJson $plan.Submission.applicationPackages) -ceq (ConvertTo-TestJson $published.applicationPackages)) 'Existing packages must be preserved.'
    Assert-True ((ConvertTo-TestJson $plan.Submission.pricing) -ceq (ConvertTo-TestJson $published.pricing)) 'Existing pricing must be preserved.'
    Assert-True ($plan.Submission.notesForCertification -ceq 'Existing notes') 'Unspecified submission fields must be preserved.'
    Assert-True ((ConvertTo-TestJson $plan.Submission.listings['ja-jp']) -ceq (ConvertTo-TestJson $published.listings['ja-jp'])) 'Unspecified locales must be preserved.'
    Assert-True ((ConvertTo-TestJson $plan.Submission.listings['en-us'].platformOverrides) -ceq (ConvertTo-TestJson $published.listings['en-us'].platformOverrides)) 'Platform overrides must be preserved.'
    $baseListing = $plan.Submission.listings['en-us'].baseListing
    Assert-True ($baseListing.description -ceq 'Updated description') 'Description must be updated.'
    Assert-True ($baseListing.releaseNotes -ceq 'Existing release notes') 'Unspecified listing fields must be preserved.'
    $oldShot = @($baseListing.images | Where-Object { $_.fileName -eq 'existing-shot.png' })
    Assert-True ($oldShot.Count -eq 1 -and $oldShot[0].fileStatus -eq 'PendingDelete') 'Only the replaced screenshot must be marked PendingDelete.'
    $icon = @($baseListing.images | Where-Object { $_.imageType -eq 'Icon' })
    Assert-True ($icon.Count -eq 1 -and $icon[0].fileStatus -eq 'Uploaded' -and $icon[0].fileName -eq 'existing-icon.png') 'Existing icons must be preserved.'
    $uploads = @($baseListing.images | Where-Object { $_.fileStatus -eq 'PendingUpload' })
    Assert-True ($uploads.Count -eq 2 -and @($plan.Assets).Count -eq 2 -and $plan.ImageCount -eq 2) 'Each new screenshot must have exactly one upload asset.'
    Assert-True (@($plan.Locales).Count -eq 1 -and $plan.Locales[0] -eq 'en-us') 'The plan must identify the changed locale.'
    foreach ($asset in $plan.Assets) {
        Assert-True (Test-Path -LiteralPath $asset.SourcePath -PathType Leaf) 'Upload source must exist.'
        Assert-True (@($uploads | Where-Object { $_.fileName -ceq $asset.ArchivePath }).Count -eq 1) 'ZIP entry name must match the localized submission reference.'
    }
    Assert-True (@($plan.Assets.ArchivePath | Select-Object -Unique).Count -eq 2) 'ZIP references must be unique.'

    $textOnly = New-StoreListingPlan -Published $published -Listings @{ 'en-us' = @{ description = 'Text only' } } -RootDirectory $fixtureRoot
    Assert-True ((ConvertTo-TestJson $textOnly.Submission.listings['en-us'].baseListing.images) -ceq (ConvertTo-TestJson $published.listings['en-us'].baseListing.images)) 'Text-only updates must preserve every image.'
    Assert-True (@($textOnly.Assets).Count -eq 0 -and $textOnly.ImageCount -eq 0) 'Text-only updates must not create image uploads.'

    $englishOnly = ConvertTo-TestJson $published | ConvertFrom-Json -AsHashtable
    $englishOnly.listings.Remove('ja-jp')
    $englishOnlyBefore = ConvertTo-TestJson $englishOnly
    $newJapanese = @{
        'ja-jp' = @{
            title = 'GH Jump'; description = 'GitHubのリポジトリを検索して開きます。'
            shortDescription = 'Command PaletteからGitHubへ移動。'
            features = @('取得済みのリポジトリを高速検索')
            images = @(@{ fileName = 'images/repositories.png'; imageType = 'Screenshot'; description = 'リポジトリ一覧' })
        }
    }
    $added = New-StoreListingPlan -Published $englishOnly -Listings $newJapanese -RootDirectory $fixtureRoot
    Assert-True ((ConvertTo-TestJson $englishOnly) -ceq $englishOnlyBefore) 'Adding a locale must not mutate the published submission.'
    Assert-True ((ConvertTo-TestJson $added.Submission.listings['en-us']) -ceq (ConvertTo-TestJson $englishOnly.listings['en-us'])) 'Adding Japanese must preserve every English listing field and image.'
    $addedBase = $added.Submission.listings['ja-jp'].baseListing
    Assert-True ($addedBase.title -ceq 'GH Jump' -and $addedBase.description -ceq $newJapanese['ja-jp'].description -and $addedBase.shortDescription -ceq $newJapanese['ja-jp'].shortDescription) 'The new locale must use explicitly supplied localized text.'
    Assert-True (!$addedBase.Contains('releaseNotes') -and $added.Submission.listings['ja-jp'].platformOverrides.Count -eq 0) 'New locales must not clone English fields or platform overrides.'
    Assert-True ($added.ImageCount -eq 1 -and $added.Assets[0].ArchivePath -ceq 'ja-jp/images/repositories.png') 'New locale uploads must use localized ZIP paths.'
    $japaneseArchivePath = Join-Path $fixtureRoot 'japanese.zip'
    New-StoreImageArchive -Assets $added.Assets -Path $japaneseArchivePath
    $japaneseArchive = [IO.Compression.ZipFile]::OpenRead($japaneseArchivePath)
    try { Assert-True ($japaneseArchive.Entries.Count -eq 1 -and $null -ne $japaneseArchive.GetEntry('ja-jp/images/repositories.png')) 'New Japanese ZIP entries must match the submission reference.' }
    finally { $japaneseArchive.Dispose() }
    foreach ($requiredField in @('title', 'description', 'images')) {
        $incomplete = ConvertTo-TestJson $newJapanese | ConvertFrom-Json -AsHashtable
        $incomplete['ja-jp'].Remove($requiredField)
        Assert-Rejected { New-StoreListingPlan -Published $englishOnly -Listings $incomplete -RootDirectory $fixtureRoot } "New locales must reject missing $requiredField."
    }
    foreach ($requiredText in @('title', 'description')) {
        $blank = ConvertTo-TestJson $newJapanese | ConvertFrom-Json -AsHashtable
        $blank['ja-jp'][$requiredText] = '   '
        Assert-Rejected { New-StoreListingPlan -Published $englishOnly -Listings $blank -RootDirectory $fixtureRoot } "New locales must reject blank $requiredText."
    }
    $emptyImages = ConvertTo-TestJson $newJapanese | ConvertFrom-Json -AsHashtable
    $emptyImages['ja-jp'].images = @()
    Assert-Rejected { New-StoreListingPlan -Published $englishOnly -Listings $emptyImages -RootDirectory $fixtureRoot } 'New locales must reject an empty screenshot collection.'

    $sharedImage = @{ fileName = 'images/actions.png'; imageType = 'Screenshot'; description = 'Actions' }
    $localized = New-StoreListingPlan -Published $published -Listings @{
        'en-us' = @{ images = @($sharedImage) }
        'ja-jp' = @{ images = @($sharedImage) }
    } -RootDirectory $fixtureRoot
    Assert-True ($localized.ImageCount -eq 2 -and @($localized.Assets).Count -eq 2) 'Locales must be able to share one image source.'
    Assert-True (@($localized.Assets.ArchivePath | Select-Object -Unique).Count -eq 2) 'Shared images must have distinct localized ZIP references.'
    foreach ($locale in @('en-us', 'ja-jp')) {
        $localizedUpload = @($localized.Submission.listings[$locale].baseListing.images | Where-Object { $_.fileStatus -eq 'PendingUpload' })
        Assert-True ($localizedUpload.Count -eq 1) 'Each locale must have one pending upload.'
        Assert-True (@($localized.Assets | Where-Object { $_.ArchivePath -ceq $localizedUpload[0].fileName }).Count -eq 1) 'Each localized upload must have its matching ZIP entry.'
    }
    $archivePath = Join-Path $fixtureRoot 'images.zip'
    New-StoreImageArchive -Assets $localized.Assets -Path $archivePath
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        Assert-True ($archive.Entries.Count -eq 2) 'The upload ZIP must contain exactly the planned localized images.'
        foreach ($asset in $localized.Assets) {
            $entry = $archive.GetEntry($asset.ArchivePath)
            Assert-True ($null -ne $entry) 'ZIP entry paths must exactly match the planned submission paths.'
            $stream = $entry.Open()
            $bytes = [IO.MemoryStream]::new()
            try {
                $stream.CopyTo($bytes)
                $expected = [Convert]::ToBase64String([IO.File]::ReadAllBytes($asset.SourcePath))
                Assert-True ([Convert]::ToBase64String($bytes.ToArray()) -ceq $expected) 'ZIP image bytes must match the source image.'
            } finally { $stream.Dispose(); $bytes.Dispose() }
        }
    } finally { $archive.Dispose() }

    $dimensions = Get-StoreImageDimensions -Path (Join-Path $fixtureRoot 'images/repositories.png')
    Assert-True ($dimensions.Width -ge 1366 -and $dimensions.Height -ge 768 -and $dimensions.Format -eq 'PNG') 'Committed PNG dimensions must be decoded correctly.'
    $tinyDimensions = Get-StoreImageDimensions -Path (Join-Path $fixtureRoot 'images/tiny.png')
    Assert-True ($tinyDimensions.Width -eq 1 -and $tinyDimensions.Height -eq 1) 'Dimension decoding must read actual image dimensions.'

    $inputPath = Join-Path $fixtureRoot 'listings.json'
    function Test-InvalidInput {
        param($InputValue, [string]$Message)
        [IO.File]::WriteAllText($inputPath, (ConvertTo-TestJson $InputValue))
        Assert-Rejected {
            $inputListings = Read-StoreListingInput -Path $inputPath
            New-StoreListingPlan -Published $published -Listings $inputListings -RootDirectory $fixtureRoot
        } $Message
    }
    foreach ($invalidPath in @('../outside.png', '..\outside.png', 'C:outside.png', (Join-Path $fixtureRoot 'images/repositories.png'), 'images/missing.png')) {
        Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = $invalidPath; imageType = 'Screenshot'; description = 'Invalid path' }) } } "Unsafe or missing image path must be rejected: $invalidPath"
    }
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/tiny.png'; imageType = 'Screenshot'; description = 'Tiny' }) } } 'Undersized screenshots must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/actions.png'; imageType = 'Screenshot'; description = 'One' }, @{ fileName = 'images/actions.png'; imageType = 'Screenshot'; description = 'Two' }) } } 'Duplicate image references must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ madeUpField = 'Value' } } 'Unsupported listing fields must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ description = 123 } } 'Non-string description must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ shortDescription = 123 } } 'Non-string short descriptions must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ shortDescription = ('x' * 1001) } } 'Short descriptions exceeding 1000 characters must be rejected.'
    [IO.File]::WriteAllText($inputPath, (ConvertTo-TestJson @{ 'en-us' = @{ shortDescription = ('x' * 1000) } }))
    $maximumShortInput = Read-StoreListingInput -Path $inputPath
    $maximumShortPlan = New-StoreListingPlan -Published $published -Listings $maximumShortInput -RootDirectory $fixtureRoot
    Assert-True ($maximumShortPlan.Submission.listings['en-us'].baseListing.shortDescription.Length -eq 1000) 'A 1000-character short description must be accepted.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/actions.png'; imageType = 'MadeUpType'; description = 'Invalid' }) } } 'Unsupported image types must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/actions.png'; imageType = 'Screenshot'; description = 'Invalid'; madeUpField = 'Value' }) } } 'Unsupported image fields must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ images = 'images/actions.png' } } 'Non-array image collection must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/jpeg.jpg'; imageType = 'Screenshot'; description = 'JPEG' }) } } 'Store screenshots must reject JPEG.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/corrupt.png'; imageType = 'Screenshot'; description = 'Corrupt' }) } } 'Truncated PNG bytes must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/oversize.png'; imageType = 'Screenshot'; description = 'Oversize' }) } } 'Screenshots over 50 MB must be rejected.'
    Test-InvalidInput @{ 'en-us' = @{ images = @(@{ fileName = 'images/actions.png'; imageType = 'Screenshot'; description = ('x' * 201) }) } } 'Screenshot captions over 200 characters must be rejected.'
    $tooManyImages = @(1..11 | ForEach-Object {
        $name = "images/shot-$_.png"
        Copy-Item -LiteralPath (Join-Path $fixtureRoot 'images/actions.png') -Destination (Join-Path $fixtureRoot $name)
        @{ fileName = $name; imageType = 'Screenshot'; description = "Screenshot $_" }
    })
    Test-InvalidInput @{ 'en-us' = @{ images = $tooManyImages } } 'More than ten screenshots in one locale must be rejected.'
    $tenImages = @($tooManyImages | Select-Object -First 10)
    $tenImages[0].description = 'x' * 200
    [IO.File]::WriteAllText($inputPath, (ConvertTo-TestJson @{ 'en-us' = @{ images = $tenImages } }))
    $tenInput = Read-StoreListingInput -Path $inputPath
    Assert-True ($tenInput['en-us'].images.Count -eq 10) 'Ten screenshots and a 200-character caption must be accepted.'
    [IO.File]::WriteAllText($inputPath, (ConvertTo-TestJson @{ 'en-us' = @{ images = @(@{ fileName = 'images/portrait.png'; imageType = 'Screenshot'; description = 'Portrait' }) } }))
    $portraitInput = Read-StoreListingInput -Path $inputPath
    Assert-True ($portraitInput['en-us'].images.Count -eq 1) 'Portrait 768 x 1366 screenshots must be accepted.'

    Assert-Rejected { Get-StoreImageDimensions -Path (Join-Path $fixtureRoot 'listings.json') } 'Non-image bytes must be rejected by image decoding.'

    $repositoryListings = Read-StoreListingInput -Path (Join-Path $repositoryRoot 'store/listings.json')
    $repositoryPlan = New-StoreListingPlan -Published $published -Listings $repositoryListings -RootDirectory (Join-Path $repositoryRoot 'store')
    Assert-True ($repositoryPlan.ImageCount -eq 3) 'The committed listing must contain three valid screenshots.'
    $japaneseListings = Read-StoreListingInput -Path (Join-Path $repositoryRoot 'store/listings.ja-jp.json')
    $japanesePlan = New-StoreListingPlan -Published $englishOnly -Listings $japaneseListings -RootDirectory (Join-Path $repositoryRoot 'store')
    Assert-True ($japanesePlan.ImageCount -eq 3 -and $japanesePlan.Locales.Count -eq 2 -and 'ja-jp' -in $japanesePlan.Locales -and 'en-us' -in $japanesePlan.Locales) 'The committed listing must add Japanese screenshots and update both locale names.'
    $expectedEnglish = ConvertTo-TestJson $englishOnly.listings['en-us'] | ConvertFrom-Json -AsHashtable
    $expectedEnglish.baseListing.title = $japaneseListings['en-us'].title
    $expectedEnglish.baseListing.description = $japaneseListings['en-us'].description
    Assert-True ((ConvertTo-TestJson $japanesePlan.Submission.listings['en-us']) -ceq (ConvertTo-TestJson $expectedEnglish)) 'The combined Japanese listing must preserve English fields except the explicitly changed title and description.'
    Assert-True ($japanesePlan.Submission.listings['en-us'].baseListing.title -ceq 'gh jump' -and
        $japanesePlan.Submission.listings['ja-jp'].baseListing.title -ceq 'gh jump') 'Both Store locales must use the reserved lowercase name.'
    Assert-True ((ConvertTo-TestJson $published) -ceq $publishedBefore) 'All planning and failure paths must leave the published submission unchanged.'

    $savedFunctions = @{}
    foreach ($name in @('Invoke-StoreApi', 'Send-StoreImageArchive', 'Invoke-RestMethod', 'Start-Sleep')) {
        $existingFunction = Get-Item -LiteralPath "Function:$name" -ErrorAction SilentlyContinue
        $savedFunctions[$name] = if ($null -ne $existingFunction) { $existingFunction.ScriptBlock } else { $null }
    }
    $savedEnvironment = @{}
    foreach ($name in @('MSSTORE_TENANT_ID', 'MSSTORE_CLIENT_ID', 'MSSTORE_CLIENT_ASSERTION')) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, 'offline-fixture')
    }
    $existingAccessToken = Get-Variable -Name storeAccessToken -Scope Script -ErrorAction SilentlyContinue
    $savedAccessToken = if ($null -ne $existingAccessToken) { $existingAccessToken.Value } else { $null }
    try {
        function Invoke-RestMethod { return @{ access_token = 'offline-access-token' } }
        function Start-Sleep { }
        function Invoke-StoreApi {
            param([string]$Method, [string]$Path, $Body)
            $script:offlineCalls.Add(@{ Method = $Method; Path = $Path; Body = $Body })
            if ($Method -eq 'Get' -and $Path -eq '/applications/9NN7GSPR8W9R') {
                $script:offlineApplicationReads++
                $pending = if ($script:offlineScenario -in @('pending', 'verify-pending') -or ($script:offlineScenario -eq 'pending-race' -and $script:offlineApplicationReads -gt 1)) { @{ id = 'pending-existing' } } else { $null }
                return @{ id = '9NN7GSPR8W9R'; packageIdentityName = 'apricot-cake.GHJump'; lastPublishedApplicationSubmission = @{ id = 'published-123' }; pendingApplicationSubmission = $pending }
            }
            if ($Method -eq 'Get' -and $Path -match '/submissions/published-123$') {
                if ($script:offlineScenario -eq 'success-new-locale') { return $englishOnly }
                return $published
            }
            if ($Method -eq 'Post' -and $Path -eq '/applications/9NN7GSPR8W9R/submissions') {
                $draft = ConvertTo-TestJson $published | ConvertFrom-Json -AsHashtable
                if ($script:offlineScenario -eq 'success-new-locale') { $draft.listings.Remove('ja-jp') }
                $draft.id = 'draft-456'
                $draft.notesForCertification = 'Fresh draft notes'
                return $draft
            }
            if ($Method -eq 'Put') { return @{ fileUploadUrl = 'https://offline.blob.core.windows.net/fixture?sig=fake' } }
            if ($Method -eq 'Post' -and $Path -match '/commit$') { return @{} }
            if ($Method -eq 'Get' -and $Path -match '/status$') {
                $status = switch ($script:offlineScenario) {
                    'commit-failed' { 'CommitFailed' }
                    'unknown-status' { 'UnknownNewStatus' }
                    'pending-commit' { 'PendingCommit' }
                    default { 'PreProcessing' }
                }
                return @{ status = $status }
            }
            throw "Unexpected offline API request: $Method $Path"
        }
        function Send-StoreImageArchive {
            param([string]$Path, [string]$UploadUrl)
            $script:offlineCalls.Add(@{ Method = 'Upload'; Path = $Path; Body = $null })
            Assert-True (Test-Path -LiteralPath $Path -PathType Leaf) 'The real image ZIP must exist before upload.'
            if ($script:offlineScenario -in @('success-combined', 'success-package-text-only')) {
                $archive = [IO.Compression.ZipFile]::OpenRead($Path)
                try {
                    $expectedCount = if ($script:offlineScenario -eq 'success-package-text-only') { 1 } else { 3 }
                    Assert-True ($archive.Entries.Count -eq $expectedCount -and $null -ne $archive.GetEntry('GHJump_1.0.1.0_Bundle.msixbundle')) 'The actual uploaded ZIP must include the bundle in combined submissions.'
                } finally { $archive.Dispose() }
            }
            if ($script:offlineScenario -eq 'upload-failed') { throw 'Offline upload failure.' }
        }
        foreach ($scenario in @('verify', 'verify-pending', 'verify-combined', 'invalid-package-version', 'missing-package', 'pending', 'pending-race', 'success', 'success-combined', 'success-package-text-only', 'success-text-only', 'success-new-locale', 'upload-failed', 'commit-failed', 'unknown-status', 'pending-commit')) {
            $script:offlineScenario = $scenario
            $script:offlineApplicationReads = 0
            $script:offlineCalls = [Collections.Generic.List[object]]::new()
            $mode = if ($scenario -like 'verify*') { 'listing-verify' } else { 'listing-submit' }
            $testListings = if ($scenario -in @('success-text-only', 'success-package-text-only')) { @{ 'en-us' = @{ description = 'Text only' } } }
                elseif ($scenario -eq 'success-new-locale') { $newJapanese } else { $requested }
            $packageOptions = @{}
            if ($scenario -in @('verify-combined', 'success-combined', 'success-package-text-only', 'invalid-package-version', 'missing-package')) {
                $packageOptions = @{ PackagePath = $bundlePath; PackageVersion = ([version]'1.0.1.0') }
                if ($scenario -eq 'missing-package') { $packageOptions.PackagePath = Join-Path $fixtureRoot 'missing.msixbundle' }
                if ($scenario -eq 'invalid-package-version') {
                    $published.applicationPackages[0].version = '1.0.1.0'
                }
            }
            $operation = { Invoke-StoreListingUpdate -Listings $testListings -ResolvedListingPath $inputPath -Mode $mode -ProductId '9NN7GSPR8W9R' @packageOptions | Out-Null }
            if ($scenario -in @('invalid-package-version', 'missing-package', 'pending', 'pending-race', 'upload-failed', 'commit-failed', 'unknown-status', 'pending-commit')) {
                Assert-Rejected $operation "Scenario $scenario must fail without claiming a successful submission."
            } else { & $operation }
            $mutations = @($script:offlineCalls | Where-Object { $_.Method -in @('Post', 'Put', 'Upload') })
            if ($scenario -eq 'invalid-package-version') { $published.applicationPackages[0].version = '1.0.0.0' }
            if ($scenario -in @('verify', 'verify-pending', 'verify-combined', 'invalid-package-version', 'missing-package', 'pending', 'pending-race')) {
                Assert-True ($mutations.Count -eq 0) "$scenario must not create, update, upload or commit a Store submission."
                continue
            }
            $sequence = @($mutations | ForEach-Object { if ($_.Path -match '/commit$') { 'Commit' } else { $_.Method } }) -join ','
            $expectedSequence = if ($scenario -eq 'upload-failed') { 'Post,Put,Upload' } elseif ($scenario -eq 'success-text-only') { 'Post,Put,Commit' } else { 'Post,Put,Upload,Commit' }
            Assert-True ($sequence -ceq $expectedSequence) 'The submission must create a draft, update metadata, upload images, then commit; upload failure must prevent commit.'
            $put = @($mutations | Where-Object { $_.Method -eq 'Put' })[0]
            Assert-True ($put.Body.notesForCertification -ceq 'Fresh draft notes') 'The PUT must preserve fresh draft fields, not overwrite them with the published snapshot.'
            if ($scenario -in @('success-combined', 'success-package-text-only')) {
                Assert-True ($put.Body.applicationPackages.Count -eq 2 -and $put.Body.applicationPackages[0].fileStatus -ceq 'PendingDelete' -and
                    $put.Body.applicationPackages[1].fileStatus -ceq 'PendingUpload') 'The same draft PUT must replace packages with the listing update.'
            } else {
                Assert-True ((ConvertTo-TestJson $put.Body.applicationPackages) -ceq (ConvertTo-TestJson $published.applicationPackages)) 'The API PUT must preserve existing packages.'
            }
            $newImages = @($put.Body.listings['en-us'].baseListing.images | Where-Object { $_.fileStatus -eq 'PendingUpload' })
            if ($scenario -in @('success-text-only', 'success-package-text-only')) {
                Assert-True ((ConvertTo-TestJson $put.Body.listings['en-us'].baseListing.images) -ceq (ConvertTo-TestJson $published.listings['en-us'].baseListing.images)) 'Text-only API updates must preserve every image without uploading an archive.'
            } elseif ($scenario -eq 'success-new-locale') {
                Assert-True ((ConvertTo-TestJson $put.Body.listings['en-us']) -ceq (ConvertTo-TestJson $englishOnly.listings['en-us'])) 'Adding Japanese through the API must leave every English listing field and image unchanged.'
                $japaneseUploads = @($put.Body.listings['ja-jp'].baseListing.images | Where-Object { $_.fileStatus -eq 'PendingUpload' })
                Assert-True ($japaneseUploads.Count -eq 1 -and $japaneseUploads[0].fileName -ceq 'ja-jp/images/repositories.png') 'The new Japanese API listing must use the uploaded localized archive reference.'
            } else {
                Assert-True ($newImages.Count -eq 2 -and @($newImages | Where-Object { $_.description -eq 'Repositories' }).Count -eq 1) 'The API PUT must include localized image references and captions.'
            }
        }
        Set-Item -LiteralPath Function:Invoke-StoreApi -Value $savedFunctions['Invoke-StoreApi']
        function Invoke-RestMethod {
            param($Uri, $Method, $Headers, $TimeoutSec, $ContentType, $Body)
            Assert-True ($ContentType -eq 'application/json; charset=utf-8') 'Bodyless Store POST requests must explicitly use JSON rather than PowerShell form content type.'
            Assert-True (-not $PSBoundParameters.ContainsKey('Body')) 'Create submission must not send a request body.'
            return @{ id = 'created-test' }
        }
        $createdTest = Invoke-StoreApi -Method Post -Path '/applications/9NN7GSPR8W9R/submissions'
        Assert-True ($createdTest.id -eq 'created-test') 'The bodyless POST response must be preserved.'
        function Invoke-RestMethod {
            $record = [Management.Automation.ErrorRecord]::new([InvalidOperationException]::new('private-secret'), 'offline', [Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $record.ErrorDetails = [Management.Automation.ErrorDetails]::new('{"code":"InvalidRequest","message":"request body includes private-secret https://example.com/?sig=secret"}')
            throw $record
        }
        $diagnosticError = $null
        try { $null = Invoke-StoreApi -Method Post -Path '/applications/9NN7GSPR8W9R/submissions' } catch { $diagnosticError = $_.Exception.Message }
        Assert-True ($diagnosticError -match 'code InvalidRequest' -and $diagnosticError -match 'mentions request body' -and $diagnosticError -notmatch 'private-secret|sig=secret|https://') 'Safe diagnostics must identify the code and cause category without exposing arbitrary messages or URLs.'
        function Invoke-RestMethod { throw 'offline-secret-token-and-signed-upload-url' }
        $sanitizedError = $null
        try { $null = Invoke-StoreApi -Method Get -Path '/applications/9NN7GSPR8W9R' } catch { $sanitizedError = $_.Exception.Message }
        Assert-True ($null -ne $sanitizedError -and $sanitizedError -notmatch 'offline-secret-token-and-signed-upload-url') 'REST failures must hide credentials and signed URLs.'
    } finally {
        foreach ($name in $savedFunctions.Keys) {
            if ($null -ne $savedFunctions[$name]) { Set-Item -LiteralPath "Function:$name" -Value $savedFunctions[$name] }
            else { Remove-Item -LiteralPath "Function:$name" -ErrorAction SilentlyContinue }
        }
        foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
        if ($null -ne $existingAccessToken) { $script:storeAccessToken = $savedAccessToken }
        else { Remove-Variable -Name storeAccessToken -Scope Script -ErrorAction SilentlyContinue }
        foreach ($name in @('offlineScenario', 'offlineApplicationReads', 'offlineCalls')) { Remove-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue }
    }
    Write-Host 'Store listing regression tests passed.'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
