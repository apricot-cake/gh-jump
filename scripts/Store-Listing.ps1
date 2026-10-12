Set-StrictMode -Version Latest

function Get-StoreFieldKey {
    param([Collections.IDictionary]$Object, [string]$Name)
    foreach ($key in $Object.Keys) { if ([string]::Equals($key, $Name, [StringComparison]::OrdinalIgnoreCase)) { return $key } }
    return $null
}

function Get-StoreImageDimensions {
    param([Parameter(Mandatory)][string]$Path)
    $image = $null
    try {
        $image = [Drawing.Image]::FromFile($Path)
        $format = if ($image.RawFormat.Guid -eq [Drawing.Imaging.ImageFormat]::Png.Guid) { 'PNG' }
            else { throw 'Unsupported image format.' }
        return @{ Width = $image.Width; Height = $image.Height; Format = $format }
    } catch { throw 'Store screenshots must be valid PNG files.' }
    finally { if ($null -ne $image) { $image.Dispose() } }
}
function Resolve-StoreImagePath {
    param([Parameter(Mandatory)][string]$RootDirectory, [Parameter(Mandatory)][string]$FileName)
    if ([IO.Path]::IsPathRooted($FileName) -or $FileName -match '(^|[/\\])\.\.([/\\]|$)|[:\x00]') {
        throw 'Image paths must be relative and must not escape the listing directory.'
    }
    $rootPath = [IO.Path]::GetFullPath($RootDirectory)
    $path = [IO.Path]::GetFullPath([IO.Path]::Combine($rootPath, $FileName))
    if (!$path.StartsWith($rootPath.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Image paths must stay inside the listing directory.'
    }
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Store image was not found: $FileName" }
    $item = Get-Item -LiteralPath $path
    while ($null -ne $item -and $item.FullName -ne $rootPath) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Symbolic links are not allowed in Store image paths.' }
        $item = if ($item -is [IO.FileInfo]) { $item.Directory } else { $item.Parent }
    }
    return $path
}

function Read-StoreListingInput {
    param([Parameter(Mandatory)][string]$Path)
    $listings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($listings -isnot [Collections.IDictionary] -or $listings.Count -eq 0) { throw 'The listing file must contain locale objects.' }
    $allowedFields = @('title', 'description', 'shortDescription', 'features', 'releaseNotes', 'keywords', 'licenseTerms', 'copyrightAndTrademarkInfo', 'images')
    $rootDirectory = Split-Path ([IO.Path]::GetFullPath($Path)) -Parent
    foreach ($locale in $listings.Keys) {
        $archiveNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        if ($locale -notmatch '^[a-z]{2,3}(-[a-z0-9]{2,8})+$') { throw "Invalid Store locale: $locale" }
        $listing = $listings[$locale]
        if ($listing -isnot [Collections.IDictionary] -or $listing.Count -eq 0) { throw "Listing $locale must contain fields." }
        foreach ($field in $listing.Keys) {
            if ($field -cnotin $allowedFields) { throw "Unsupported listing field: $field" }
            if ($field -in @('features', 'keywords')) {
                if ($listing[$field] -isnot [array] -or @($listing[$field] | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
                    throw "$field must be an array of nonempty strings."
                }
                if ($field -eq 'features' -and $listing[$field].Count -gt 20) { throw 'features must contain no more than 20 items.' }
            } elseif ($field -ne 'images' -and $listing[$field] -isnot [string]) { throw "$field must be a string." }
            if ($field -eq 'shortDescription' -and $listing[$field].Length -gt 1000) { throw 'shortDescription must not exceed 1000 characters.' }
        }
        if ($listing.Contains('images')) {
            if ($listing.images -isnot [array] -or $listing.images.Count -eq 0) { throw 'images must be a nonempty array.' }
            if ($listing.images.Count -gt 10) { throw 'A listing must have no more than 10 screenshots.' }
            foreach ($image in $listing.images) {
                if ($image -isnot [Collections.IDictionary] -or $image.Keys.Count -ne 3 -or
                    !$image.Contains('fileName') -or !$image.Contains('description') -or !$image.Contains('imageType')) { throw 'Images require fileName, description and imageType only.' }
                if ($image.fileName -isnot [string] -or [string]::IsNullOrWhiteSpace($image.fileName) -or
                    $image.description -isnot [string] -or $image.imageType -cne 'Screenshot') { throw 'Only Screenshot images are supported.' }
                if ($image.description.Length -gt 200) { throw 'Screenshot descriptions must not exceed 200 characters.' }
                $archiveName = $image.fileName.Replace('\', '/')
                if (!$archiveNames.Add($archiveName)) { throw "Duplicate image fileName: $archiveName" }
                $imagePath = Resolve-StoreImagePath -RootDirectory $rootDirectory -FileName $image.fileName
                if ((Get-Item -LiteralPath $imagePath).Length -gt 50MB) { throw 'Store screenshots must not exceed 50 MB.' }
                $dimensions = Get-StoreImageDimensions -Path $imagePath
                if (!(($dimensions.Width -ge 1366 -and $dimensions.Height -ge 768) -or
                    ($dimensions.Width -ge 768 -and $dimensions.Height -ge 1366))) { throw "Screenshot must be at least 1366 x 768 or 768 x 1366: $archiveName" }
                $extension = [IO.Path]::GetExtension($imagePath).ToLowerInvariant()
                if ($extension -ne '.png') { throw 'Store screenshots must use the .png extension.' }
            }
        }
    }
    return $listings
}

function Read-StorePackageInput {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][version]$Version)
    if ($Version.Major -lt 1 -or $Version.Revision -ne 0) { throw 'Invalid Store package version.' }
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'Validated MSIXbundle was not found.' }
    if ([IO.Path]::GetFileName($Path) -cne "GHJump_${Version}_Bundle.msixbundle") { throw 'The bundle file name does not match the manifest version.' }
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.GetEntry('AppxMetadata/AppxBundleManifest.xml')
        if ($null -eq $entry) { throw 'The bundle manifest was not found.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ($manifest.Bundle.Identity.Name -cne 'apricot-cake.GHJump' -or
            [version]$manifest.Bundle.Identity.Version -ne $Version) { throw 'The bundle identity or version does not match the application manifest.' }
    } finally { $archive.Dispose() }
    return @{ SourcePath = [IO.Path]::GetFullPath($Path); ArchivePath = [IO.Path]::GetFileName($Path); Version = $Version.ToString() }
}

function New-StoreListingPlan {
    param([Parameter(Mandatory)][Collections.IDictionary]$Published,
        [Parameter(Mandatory)][Collections.IDictionary]$Listings,
        [Parameter(Mandatory)][string]$RootDirectory,
        [Collections.IDictionary]$Package)
    $submission = $Published | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
    $listingsKey = Get-StoreFieldKey -Object $submission -Name 'listings'
    if (!$listingsKey -or $submission[$listingsKey] -isnot [Collections.IDictionary]) { throw 'The Store response did not contain listings.' }
    $assets = [Collections.Generic.List[object]]::new()
    foreach ($locale in $Listings.Keys) {
        $localeKey = Get-StoreFieldKey -Object $submission[$listingsKey] -Name $locale
        if (!$localeKey) {
            $newListing = $Listings[$locale]
            foreach ($requiredField in @('title', 'description')) {
                if (!$newListing.Contains($requiredField) -or $newListing[$requiredField] -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($newListing[$requiredField])) { throw "New locale $locale requires an explicit nonempty $requiredField." }
            }
            if (!$newListing.Contains('images') -or $newListing.images -isnot [array] -or
                @($newListing.images | Where-Object { $_.imageType -ceq 'Screenshot' }).Count -eq 0) {
                throw "New locale $locale requires at least one Screenshot image."
            }
            $localeKey = $locale
            $submission[$listingsKey][$localeKey] = @{ baseListing = @{}; platformOverrides = @{} }
        }
        $baseListingKey = Get-StoreFieldKey -Object $submission[$listingsKey][$localeKey] -Name 'baseListing'
        if (!$baseListingKey -or $submission[$listingsKey][$localeKey][$baseListingKey] -isnot [Collections.IDictionary]) { throw 'The Store response did not contain a base listing.' }
        $destination = $submission[$listingsKey][$localeKey][$baseListingKey]
        foreach ($field in $Listings[$locale].Keys) {
            if ($field -eq 'images') { continue }
            $storeField = Get-StoreFieldKey -Object $destination -Name $field
            if (!$storeField) { $storeField = $field }
            $destination[$storeField] = $Listings[$locale][$field]
        }
        if ($Listings[$locale].Contains('images')) {
            $imageTypes = @($Listings[$locale].images | ForEach-Object { $_.imageType } | Select-Object -Unique)
            $images = [Collections.Generic.List[object]]::new()
            $imagesKey = Get-StoreFieldKey -Object $destination -Name 'images'
            if ($imagesKey) {
                foreach ($image in $destination[$imagesKey]) {
                    $typeKey = Get-StoreFieldKey -Object $image -Name 'imageType'
                    if ($image[$typeKey] -in $imageTypes) {
                        $statusKey = Get-StoreFieldKey -Object $image -Name 'fileStatus'
                        if (!$statusKey) { $statusKey = 'fileStatus' }
                        $image[$statusKey] = 'PendingDelete'
                    }
                    $images.Add($image)
                }
            }
            foreach ($image in $Listings[$locale].images) {
                $archivePath = $locale.ToLowerInvariant() + '/' + $image.fileName.Replace('\', '/')
                $images.Add(@{ fileName = $archivePath; description = $image.description; imageType = $image.imageType; fileStatus = 'PendingUpload' })
                $assets.Add(@{ SourcePath = Resolve-StoreImagePath -RootDirectory $RootDirectory -FileName $image.fileName; ArchivePath = $archivePath })
            }
            if (!$imagesKey) { $imagesKey = 'images' }
            $destination[$imagesKey] = $images.ToArray()
        }
    }
    $imageCount = $assets.Count
    if ($null -ne $Package) {
        $packagesKey = Get-StoreFieldKey -Object $submission -Name 'applicationPackages'
        if (!$packagesKey -or @($submission[$packagesKey]).Count -eq 0) { throw 'No published package version was returned.' }
        $packages = [Collections.Generic.List[object]]::new()
        foreach ($existingPackage in $submission[$packagesKey]) {
            $versionKey = Get-StoreFieldKey -Object $existingPackage -Name 'version'
            if (!$versionKey -or [string]::IsNullOrWhiteSpace($existingPackage[$versionKey]) -or
                [version]$Package.Version -le [version]$existingPackage[$versionKey]) {
                throw 'The bundle version must be greater than every published package version.'
            }
            $statusKey = Get-StoreFieldKey -Object $existingPackage -Name 'fileStatus'
            if (!$statusKey) { $statusKey = 'fileStatus' }
            $existingPackage[$statusKey] = 'PendingDelete'
            $packages.Add($existingPackage)
        }
        # 新しいパッケージの詳細はStoreが読み取る。PUTには公式の必須フィールドだけを渡す。
        $packages.Add(@{ fileName = $Package.ArchivePath; fileStatus = 'PendingUpload'; minimumDirectXVersion = 'None'; minimumSystemRam = 'None' })
        $submission[$packagesKey] = $packages.ToArray()
        $assets.Add($Package)
    }
    return @{ Submission = $submission; Assets = $assets.ToArray(); Locales = @($Listings.Keys); ImageCount = $imageCount; PackageIncluded = ($null -ne $Package) }
}

function New-StoreImageArchive {
    param([Parameter(Mandatory)][object[]]$Assets, [Parameter(Mandatory)][string]$Path)
    $archive = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($asset in $Assets) {
            $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $asset.SourcePath, $asset.ArchivePath, [IO.Compression.CompressionLevel]::Optimal)
        }
    } finally { $archive.Dispose() }
    if ((Get-Item -LiteralPath $Path).Length -gt 256MB) { throw 'Store upload archive exceeds the supported 256 MB single-upload limit.' }
}

function Send-StoreImageArchive {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$UploadUrl)
    $uri = [uri]$UploadUrl
    if ($uri.Scheme -ne 'https' -or $uri.Host -notmatch '^[a-z0-9-]+\.blob\.core\.windows\.net$' -or [string]::IsNullOrEmpty($uri.Query)) { throw 'Store returned an unexpected upload destination.' }
    if ((Get-Item -LiteralPath $Path).Length -gt 256MB) { throw 'Store upload archive exceeds the supported 256 MB single-upload limit.' }
    try {
        $null = Invoke-WebRequest -Uri $uri -Method Put -InFile $Path -ContentType 'application/zip' -Headers @{
            'x-ms-blob-type' = 'BlockBlob'; 'x-ms-version' = '2021-12-02'; 'x-ms-date' = [DateTime]::UtcNow.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
        } -TimeoutSec 300
    } catch { throw 'Store archive upload failed. Request details were withheld to protect the signed upload URL.' }
}

function Invoke-StoreApi {
    param([Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Put')][string]$Method,
        [Parameter(Mandatory)][string]$Path, [object]$Body)
    $parameters = @{
        Uri = "https://manage.devcenter.microsoft.com/v1.0/my$Path"
        Method = $Method
        Headers = @{ Authorization = "Bearer $script:storeAccessToken"; TenantId = $env:MSSTORE_TENANT_ID }
        TimeoutSec = 60
        ContentType = 'application/json; charset=utf-8'
    }
    if ($null -ne $Body) {
        $parameters['Body'] = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 100 -Compress))
        $parameters['ContentType'] = 'application/json; charset=utf-8'
    }
    try {
        $response = Invoke-RestMethod @parameters
        if ($null -ne $response) { return $response | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable }
    } catch {
        $responseProperty = $_.Exception.PSObject.Properties['Response']
        $statusCode = if ($null -ne $responseProperty -and $null -ne $responseProperty.Value) { [int]$responseProperty.Value.StatusCode } else { 0 }
        $diagnostic = ''
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            try {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -AsHashtable
                $nodes = @($errorBody) + @($errorBody['error']) + @($errorBody['errors'])
                $codes = @($nodes | Where-Object { $_ -is [Collections.IDictionary] } | ForEach-Object { $_['code'] } |
                    Where-Object { $_ -is [string] -and $_ -cmatch '^[A-Za-z][A-Za-z0-9_.-]{0,79}$' })
                if ($codes.Count -gt 0) { $diagnostic = "; code $($codes -join ', ')" }
                $messages = @($nodes | Where-Object { $_ -is [Collections.IDictionary] } | ForEach-Object { $_['message'] }) -join ' '
                foreach ($phrase in @('request body', 'Content-Type', 'age rating', 'IARC', 'not supported', 'invalid state', 'published', 'pending submission', 'empty', 'tenant', 'permission')) {
                    if ($messages -match [regex]::Escape($phrase)) { $diagnostic += "; mentions $phrase" }
                }
            } catch { }
        }
        throw "Store API $Method request failed (HTTP $statusCode$diagnostic). Raw response and request details were withheld."
    }
}

function Invoke-StoreListingUpdate {
    param([Parameter(Mandatory)][Collections.IDictionary]$Listings,
        [Parameter(Mandatory)][string]$ResolvedListingPath,
        [Parameter(Mandatory)][ValidateSet('listing-verify', 'listing-submit')][string]$Mode,
        [string]$ProductId = '9NN7GSPR8W9R',
        [string]$PackagePath,
        [version]$PackageVersion)
    $packageInput = $null
    if ($PackagePath) {
        if ($null -eq $PackageVersion) { throw 'A package version is required for a combined submission.' }
        $packageInput = Read-StorePackageInput -Path $PackagePath -Version $PackageVersion
    } elseif ($null -ne $PackageVersion) { throw 'A package path is required for a combined submission.' }
    try {
        $access = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$env:MSSTORE_TENANT_ID/oauth2/v2.0/token" -Method Post -Body @{
            grant_type = 'client_credentials'; client_id = $env:MSSTORE_CLIENT_ID
            scope = 'https://manage.devcenter.microsoft.com/.default'
            client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
            client_assertion = $env:MSSTORE_CLIENT_ASSERTION
        } -TimeoutSec 30
        $script:storeAccessToken = $access.access_token
        if ([string]::IsNullOrWhiteSpace($script:storeAccessToken)) { throw 'Missing access token.' }
    } catch { throw 'Could not obtain the Store API access token. Authentication details were withheld.' }
    Write-Output "::add-mask::$script:storeAccessToken"
    $application = Invoke-StoreApi -Method Get -Path "/applications/$productId"
    if ($application.id -ne $productId -or $application.packageIdentityName -ne 'apricot-cake.GHJump') { throw 'Store product identity does not match GH Jump.' }
    $publishedKey = Get-StoreFieldKey -Object $application -Name 'lastPublishedApplicationSubmission'
    if (!$publishedKey -or !$application[$publishedKey]) { throw 'The application has no published submission to preserve.' }
    $published = Invoke-StoreApi -Method Get -Path "/applications/$productId/submissions/$($application[$publishedKey].id)"
    $plan = New-StoreListingPlan -Published $published -Listings $Listings -RootDirectory (Split-Path $ResolvedListingPath -Parent) -Package $packageInput
    $pendingKey = Get-StoreFieldKey -Object $application -Name 'pendingApplicationSubmission'
    $hasPending = $pendingKey -and $application[$pendingKey]
    Write-Host "Listing plan: locales $($plan.Locales -join ', '); $($plan.ImageCount) screenshots; pending submission $([bool]$hasPending)."
    Write-Host "Package replacement: $($plan.PackageIncluded). Unspecified locales, listing fields and image types are preserved."
    if ($Mode -eq 'listing-verify') {
        Write-Host 'Listing plan verified against the published submission. No Store submission was changed.'
        return
    }
    if ($hasPending) { throw 'A pending submission exists. Finish or remove it in Partner Center before submitting a listing update. No draft was overwritten.' }
    $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ('gh-jump-store-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temporaryDirectory
    $createdSubmissionId = $null
    try {
        $archivePath = Join-Path $temporaryDirectory 'submission.zip'
        if ($plan.Assets.Count -gt 0) { New-StoreImageArchive -Assets $plan.Assets -Path $archivePath }
        # 作成直前にも読み直し、審査中の提出を上書きしない。
        $application = Invoke-StoreApi -Method Get -Path "/applications/$productId"
        $pendingKey = Get-StoreFieldKey -Object $application -Name 'pendingApplicationSubmission'
        if ($pendingKey -and $application[$pendingKey]) { throw 'A pending submission appeared before draft creation. No draft was overwritten.' }
        $draft = Invoke-StoreApi -Method Post -Path "/applications/$productId/submissions"
        $createdSubmissionId = $draft.id
        if ([string]::IsNullOrWhiteSpace($createdSubmissionId)) { throw 'Store did not return the created submission ID.' }
        # APIが複製したdraftを基準にすることで、公開済み以外の新しい状態も保持する。
        $plan = New-StoreListingPlan -Published $draft -Listings $Listings -RootDirectory (Split-Path $ResolvedListingPath -Parent) -Package $packageInput
        $updated = Invoke-StoreApi -Method Put -Path "/applications/$productId/submissions/$createdSubmissionId" -Body $plan.Submission
        if ($plan.Assets.Count -gt 0) {
            Send-StoreImageArchive -Path $archivePath -UploadUrl $updated.fileUploadUrl
            Write-Host 'Submission asset archive uploaded.'
        }
        $null = Invoke-StoreApi -Method Post -Path "/applications/$productId/submissions/$createdSubmissionId/commit"
        Write-Host "Listing submission $createdSubmissionId committed."
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            $status = Invoke-StoreApi -Method Get -Path "/applications/$productId/submissions/$createdSubmissionId/status"
            if ($status.status -in @('CommitFailed', 'PreProcessingFailed', 'CertificationFailed', 'PublishFailed', 'ReleaseFailed')) {
                throw "Store rejected listing submission $createdSubmissionId ($($status.status)). Review the submission in Partner Center."
            }
            if ($status.status -in @('PreProcessing', 'Certification', 'PendingPublication', 'Publishing', 'Published', 'Release')) {
                Write-Host "Listing submission status: $($status.status). Certification and publication are separate from this workflow."
                return
            }
            if ($status.status -notin @('CommitStarted', 'PendingCommit')) { throw "Store returned an unexpected submission status ($($status.status)). Check Partner Center before another update." }
            Start-Sleep -Seconds 15
        }
        throw "Store is still processing submission $createdSubmissionId. Check its status in Partner Center before another update."
    } catch {
        if ($createdSubmissionId) { Write-Host "Submission $createdSubmissionId was created. Inspect it in Partner Center; this workflow does not delete drafts or retry commits automatically." }
        throw
    } finally {
        # 生成した一時ディレクトリだけを削除する。
        $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $resolvedTemporaryDirectory = [IO.Path]::GetFullPath($temporaryDirectory)
        if ($resolvedTemporaryDirectory.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedTemporaryDirectory) -match '^gh-jump-store-[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $resolvedTemporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

