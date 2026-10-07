param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'apricot-cake/gh-jump',
    [string]$ActivationShortcut = 'alt+space',
    [ValidateSet('All', 'Top', 'Issues', 'Actions', 'PullRequests', 'CreateIssue', 'CreatePullRequest')]
    [string]$Scenario = 'All',
    [ValidateRange(1000, 60000)][int]$TimeoutMilliseconds = 15000
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$palette = 'Microsoft.CmdPal.UI'
$reportDirectory = Join-Path $root 'artifacts/e2e'
New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
$reportPath = Join-Path $reportDirectory ('ui-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.json')
$results = [System.Collections.Generic.List[object]]::new()
$events = [System.Collections.Generic.List[object]]::new()
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$script:step = 'Preflight'
$browserAddressSelectors = @{}
$script:repositorySelectionChecked = $false
$startedAt = [DateTime]::UtcNow.ToString('o')
$previousWorkflow = $env:WINAPP_UI_WORKFLOW_ID
$env:WINAPP_UI_WORKFLOW_ID = [guid]::NewGuid().ToString()

function Invoke-Winapp([string[]]$Arguments, [switch]$AllowNoMatches) {
    $output = & winapp @Arguments --json 2>&1
    $parsed = $output -join "`n" | ConvertFrom-Json
    if ($AllowNoMatches -and $Arguments[1] -eq 'search' -and $parsed.matchCount -eq 0) { return $parsed }
    if ($LASTEXITCODE -ne 0) { throw "winapp $($Arguments[1]) $($Arguments[2]) failed: $($output -join ' ')" }
    return $parsed
}

function Write-Step([string]$Name) {
    $script:step = $Name
    $events.Add(@{ Step = $Name; ElapsedMilliseconds = $timer.ElapsedMilliseconds })
    Write-Host "[$($timer.ElapsedMilliseconds) ms] $Name"
}

function Save-PaletteState([string]$ExpectedItem = '', [string]$ExpectedQuery = '') {
    $front = Get-ForegroundWindow -AllowMissing
    $state = @{ Step = $script:step; ElapsedMilliseconds = $timer.ElapsedMilliseconds; ForegroundProcess = $front.processName }
    try {
        $search = Invoke-Winapp @('ui', 'get-property', 'MainSearchBox', '-a', $palette, '--property', 'Name')
        $state.Page = $search.properties.Name
        $value = Invoke-Winapp @('ui', 'get-value', 'MainSearchBox', '-a', $palette)
        if ($PSBoundParameters.ContainsKey('ExpectedQuery')) { $state.QueryMatches = $value.text -eq $ExpectedQuery }
        $items = @(Get-Items)
        $state.VisibleCandidateCount = $items.Count
        if ($PSBoundParameters.ContainsKey('ExpectedItem')) {
            $state.ExpectedItemCount = @($items | Where-Object { $_.name -eq $ExpectedItem }).Count
            $state.FirstItemMatches = $items.Count -gt 0 -and $items[0].name -eq $ExpectedItem
        }
        if ($items.Count -gt 0) {
            $selection = Invoke-Winapp @('ui', 'get-property', $items[0].selector, '-a', $palette, '--property', 'IsSelected')
            $state.FirstItemSelected = $selection.properties.IsSelected -eq 'True'
        }
    } catch { $state.StateReadError = $_.Exception.Message }
    $events.Add($state)
    Write-Host ($state | ConvertTo-Json -Compress)
}

function Get-ForegroundWindow([switch]$AllowMissing) {
    $window = Invoke-Winapp @('ui', 'list-windows') | Where-Object isForeground | Select-Object -First 1
    if (-not $window) {
        if ($AllowMissing) { return $null }
        throw 'No foreground window is available. Use an unlocked interactive desktop.'
    }
    if ($window.processName -in @('LockApp', 'LogonUI')) { throw 'The Windows desktop is locked. Unlock it before running UI tests.' }
    return $window
}

function Send-PaletteKey([string]$Key) {
    Invoke-Winapp @('ui', 'send-keys', $Key, '--via', 'send-input', '--target', 'MainSearchBox', '-a', $palette) | Out-Null
}

function Wait-PalettePage([string]$Name, [switch]$Different) {
    $limit = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $search = Invoke-Winapp @('ui', 'get-property', 'MainSearchBox', '-a', $palette, '--property', 'Name')
        $actual = $search.properties.Name
        if (($Different -and $actual -ne $Name) -or (-not $Different -and $actual -eq $Name)) { return }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $limit)
    throw "The palette did not reach the expected page: $Name"
}

function Set-PaletteQuery([string]$Query) {
    Send-PaletteKey 'ctrl+a'
    # Backspace on an empty CmdPal search box navigates to the parent page.
    Send-PaletteKey 'delete'
    if ($Query) {
        Invoke-Winapp @('ui', 'send-keys', $Query, '--verbatim', '--via', 'send-input', '--target', 'MainSearchBox', '-a', $palette) | Out-Null
    }
    Invoke-Winapp @('ui', 'wait-for', 'MainSearchBox', '-a', $palette, '--value', $Query, '--timeout', "$TimeoutMilliseconds") | Out-Null
    Save-PaletteState -ExpectedQuery $Query
}

function Wait-Item([string]$Name) {
    $limit = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        if (@(Get-Items | Where-Object { $_.name -eq $Name }).Count -gt 0) { return }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $limit)
    $page = Invoke-Winapp @('ui', 'get-property', 'MainSearchBox', '-a', $palette, '--property', 'Name')
    $matches = @(Get-Items | Where-Object { $_.name -like "*$Name*" } | ForEach-Object name)
    throw "The expected list item did not appear: $Name; page: $($page.properties.Name); matching names: $($matches -join ', ')"
}

function Get-Items {
    $tree = Invoke-Winapp @('ui', 'inspect', '-a', $palette, '--depth', '12')
    function Read-Items($Node) {
        if ($Node.type -eq 'ListItem' -and $Node.isEnabled -and -not $Node.isOffscreen) { $Node }
        foreach ($child in $Node.children) { Read-Items $child }
    }
    foreach ($window in $tree.windows) { foreach ($node in $window.elements) { Read-Items $node } }
}

function Assert-FirstItem([string]$Expected, [string]$Identity = '') {
    Wait-Item $Expected
    $items = @(Get-Items)
    if (-not $items -or $items[0].name -ne $Expected) { throw "Expected first item: $Expected" }
    $selection = Invoke-Winapp @('ui', 'get-property', $items[0].selector, '-a', $palette, '--property', 'IsSelected')
    if ($selection.properties.IsSelected -ne 'True') { throw "Expected selected item: $Expected" }
    Save-PaletteState -ExpectedItem $Expected
    if ($Identity) {
        $command = Invoke-Winapp @('ui', 'search', $Identity, '-a', $palette, '--root', $items[0].selector)
        if (-not ($command.matches | Where-Object { $_.automationId -eq $Identity })) { throw "Expected extension command: $Identity" }
    }
}

function Test-RepositorySelectionReset {
    Write-Step 'Repository selection: find owner'
    $ownerQuery = $Repository.Split('/')[0]
    Set-PaletteQuery $ownerQuery
    Wait-Item ($Repository.Split('/')[1])
    $items = @(Get-Items)
    if ($items.Count -lt 2) {
        $results.Add(@{ Scenario = 'RepositorySelectionReset'; Skipped = $true; Reason = 'The owner search has fewer than two visible repositories.' })
        Write-Host 'RepositorySelectionReset: skipped (fewer than two visible owner matches)'
        return
    }
    Assert-FirstItem $items[0].name
    Write-Step 'Repository selection: select second candidate'
    Send-PaletteKey 'down'
    $limit = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $selection = Invoke-Winapp @('ui', 'get-property', $items[1].selector, '-a', $palette, '--property', 'IsSelected')
        if ($selection.properties.IsSelected -eq 'True') { break }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $limit)
    if ($selection.properties.IsSelected -ne 'True') { throw 'The second repository was not selected by the Down key.' }
    $events.Add(@{ Step = $script:step; ElapsedMilliseconds = $timer.ElapsedMilliseconds; SecondItemSelected = $true })
    Write-Step 'Repository selection: append slash and reset to first candidate'
    # Append without clearing: both owner/repo matches remain, including the previously selected second item.
    # Clearing first would reset the selection and hide the regression being tested.
    Invoke-Winapp @('ui', 'send-keys', '/', '--verbatim', '--via', 'send-input', '--target', 'MainSearchBox', '-a', $palette) | Out-Null
    Invoke-Winapp @('ui', 'wait-for', 'MainSearchBox', '-a', $palette, '--value', "$ownerQuery/", '--timeout', "$TimeoutMilliseconds") | Out-Null
    $limit = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        $updatedItems = @(Get-Items)
        if ($updatedItems.Count -gt 0 -and $updatedItems[0].name -eq $items[0].name) {
            $selection = Invoke-Winapp @('ui', 'get-property', $updatedItems[0].selector, '-a', $palette, '--property', 'IsSelected')
            if ($selection.properties.IsSelected -eq 'True') { break }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $limit)
    Assert-FirstItem $items[0].name
    Wait-PalettePage 'Search owner/repository'
    Save-PaletteState -ExpectedItem $items[0].name -ExpectedQuery "$ownerQuery/"
    $results.Add(@{ Scenario = 'RepositorySelectionReset'; Passed = $true; SecondItemSelectedBeforeTyping = $true; FirstItemSelectedAfterTyping = $true; StayedOnRepositoryPage = $true })
    Write-Host 'RepositorySelectionReset: passed'
}

function Open-Repository {
    Write-Step 'Open palette'
    $front = Get-ForegroundWindow
    $searchBox = Invoke-Winapp -Arguments @('ui', 'search', 'MainSearchBox', '-a', $palette, '--type', 'Edit') -AllowNoMatches
    $isOpen = @($searchBox.matches | Where-Object { $_.automationId -eq 'MainSearchBox' -and -not $_.isOffscreen }).Count -gt 0
    if (-not $isOpen) {
        Invoke-Winapp @('ui', 'send-keys', $ActivationShortcut, '-w', "$($front.hwnd)", '--via', 'send-input', '--allow-system-keys') | Out-Null
    }
    Invoke-Winapp @('ui', 'wait-for', 'MainSearchBox', '-a', $palette, '--timeout', "$TimeoutMilliseconds") | Out-Null
    # GH Jump pages have distinct placeholders; Escape returns to the root without executing a command.
    for ($back = 0; $back -lt 3; $back++) {
        $search = Invoke-Winapp @('ui', 'get-property', 'MainSearchBox', '-a', $palette, '--property', 'Name')
        if ($search.properties.Name -notin @('Search owner/repository', 'Issues, Pull requests, Actions, Create…', 'Create issue or pull request')) { break }
        Send-PaletteKey 'esc'
        Wait-PalettePage $search.properties.Name -Different
    }
    Write-Step 'Find GH Jump'
    Set-PaletteQuery 'gh'
    Assert-FirstItem 'GH Jump' 'gh-jump.repositories'
    Write-Step 'Enter GH Jump'
    Send-PaletteKey 'enter'
    Wait-PalettePage 'Search owner/repository'
    if (-not $script:repositorySelectionChecked) {
        Test-RepositorySelectionReset
        $script:repositorySelectionChecked = $true
    }
    Write-Step 'Find repository'
    Set-PaletteQuery $Repository
    Assert-FirstItem ($Repository.Split('/')[1])
    # The single repository remains a list item until Enter, rather than auto-navigating.
    $repositoryItem = @(Get-Items)[0]
    $owner = Invoke-Winapp @('ui', 'search', $Repository, '-a', $palette, '--type', 'Text', '--root', $repositoryItem.selector)
    if (-not ($owner.matches | Where-Object { $_.name -eq $Repository })) { throw 'Repository owner/repo subtitle is missing.' }
    Write-Step 'Enter repository'
    Send-PaletteKey 'enter'
    Wait-PalettePage 'Issues, Pull requests, Actions, Create…'
    Invoke-Winapp @('ui', 'wait-for', 'MainSearchBox', '-a', $palette, '--value', '', '--timeout', "$TimeoutMilliseconds") | Out-Null
    Assert-FirstItem 'Repository top'
}

function Get-BrowserUrl($Browser) {
    $tree = Invoke-Winapp @('ui', 'inspect', '-w', "$($Browser.hwnd)", '--depth', '12')
    function Read-Address($Node) {
        if ($Node.type -eq 'Edit' -and $Node.name -match 'アドレス|Address|Search or enter address') { $Node }
        foreach ($child in $Node.children) { Read-Address $child }
    }
    $addresses = @(foreach ($window in $tree.windows) { foreach ($node in $window.elements) { Read-Address $node } })
    if ($addresses.Count -ne 1) { throw 'Could not uniquely identify the browser address bar.' }
    $browserAddressSelectors[$Browser.hwnd] = $addresses[0].selector
    $value = (Invoke-Winapp @('ui', 'get-value', $addresses[0].selector, '-w', "$($Browser.hwnd)")).text
    if (-not $value) { return $null }
    if ($value -notmatch '^[A-Za-z][A-Za-z0-9+.-]*:') { $value = 'https://' + $value }
    $uri = $null
    if ([uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri)) { return $uri }
    throw 'Could not read a valid browser URL.'
}

function Test-BrowserUrl([uri]$Actual, [uri]$Expected) {
    return $Actual -and $Actual.Scheme -eq $Expected.Scheme -and $Actual.Host -eq $Expected.Host -and (
        $Actual.AbsolutePath.TrimEnd('/') -eq $Expected.AbsolutePath.TrimEnd('/') -or
        ($Expected.AbsolutePath.EndsWith('/issues/new') -and $Actual.AbsolutePath -eq $Expected.AbsolutePath + '/choose'))
}

function Set-DistinctBrowserBaseline([string]$Expected) {
    Get-ForegroundWindow | Out-Null
    $browsers = Invoke-Winapp @('ui', 'list-windows') | Where-Object {
        $_.processName -in @('chrome', 'msedge', 'firefox') -and $_.ownerHwnd -eq 0 -and $_.width -gt 0 -and $_.height -gt 0
    }
    foreach ($browser in $browsers) {
        if (Test-BrowserUrl (Get-BrowserUrl $browser) ([uri]$Expected)) {
            Invoke-Winapp @('ui', 'focus', $browserAddressSelectors[$browser.hwnd], '-w', "$($browser.hwnd)") | Out-Null
            Invoke-Winapp @('ui', 'send-keys', 'ctrl+l', '-w', "$($browser.hwnd)", '--via', 'send-input') | Out-Null
            Invoke-Winapp @('ui', 'send-keys', 'about:blank', '--verbatim', '-w', "$($browser.hwnd)", '--via', 'send-input') | Out-Null
            Invoke-Winapp @('ui', 'send-keys', 'enter', '-w', "$($browser.hwnd)", '--via', 'send-input') | Out-Null
            Wait-BrowserUrl 'about:blank' | Out-Null
        }
    }
}

function Wait-BrowserUrl([string]$Expected) {
    $limit = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    do {
        Get-ForegroundWindow -AllowMissing | Out-Null
        $browsers = Invoke-Winapp @('ui', 'list-windows') | Where-Object {
            $_.processName -in @('chrome', 'msedge', 'firefox') -and $_.ownerHwnd -eq 0 -and $_.width -gt 0 -and $_.height -gt 0
        }
        foreach ($browser in $browsers) {
            $uri = Get-BrowserUrl $browser
            if (Test-BrowserUrl $uri ([uri]$Expected)) { return $uri.GetLeftPart([UriPartial]::Path) }
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $limit)
    throw "The browser did not show the expected URL: $Expected"
}

$scenarios = @(
    @{ Name = 'Top'; Query = ''; Item = 'Repository top'; Path = ''; Create = $false },
    @{ Name = 'Issues'; Query = 'i'; Item = 'Issues'; Path = '/issues'; Create = $false },
    @{ Name = 'Actions'; Query = 'a'; Item = 'Actions'; Path = '/actions'; Create = $false },
    @{ Name = 'PullRequests'; Query = 'p'; Item = 'Pull requests'; Path = '/pulls'; Create = $false },
    @{ Name = 'CreateIssue'; Query = 'i'; Item = 'Issue'; Path = '/issues/new'; Create = $true },
    @{ Name = 'CreatePullRequest'; Query = 'p'; Item = 'Pull request'; Path = '/compare'; Create = $true }
)
$success = $false
try {
    Get-Command winapp -ErrorAction Stop | Out-Null
    $version = (& winapp --version).Trim()
    Get-ForegroundWindow | Out-Null
    foreach ($case in $scenarios | Where-Object { $Scenario -eq 'All' -or $_.Name -eq $Scenario }) {
        Write-Step "$($case.Name): browser baseline"
        $expectedUrl = "https://github.com/$Repository$($case.Path)"
        Set-DistinctBrowserBaseline $expectedUrl
        Open-Repository
        if ($case.Create) {
            Write-Step "$($case.Name): open Create"
            Set-PaletteQuery 'c'
            Assert-FirstItem 'Create'
            Send-PaletteKey 'enter'
            Wait-PalettePage 'Create issue or pull request'
            Wait-Item 'Issue'
            Wait-Item 'Pull request'
            $childItems = @(Get-Items)
            if ($childItems.Count -ne 2) { throw 'Create must show exactly two actions.' }
        }
        Write-Step "$($case.Name): find action"
        Set-PaletteQuery $case.Query
        Assert-FirstItem $case.Item
        Write-Step "$($case.Name): execute action"
        Send-PaletteKey 'enter'
        Invoke-Winapp @('ui', 'wait-for', 'MainSearchBox', '-a', $palette, '--gone', '--timeout', "$TimeoutMilliseconds") | Out-Null
        $actualUrl = Wait-BrowserUrl $expectedUrl
        $results.Add(@{ Scenario = $case.Name; Passed = $true; Url = $actualUrl; PaletteDismissed = $true })
        Write-Host "$($case.Name): passed"
    }
    $success = $true
} catch {
    Save-PaletteState
    $failedScenario = if ($case) { $case.Name } else { 'Preflight' }
    $results.Add(@{ Scenario = $failedScenario; Passed = $false; Error = $_.Exception.Message })
    throw
} finally {
    @{ Passed = $success; StartedAt = $startedAt; CompletedAt = [DateTime]::UtcNow.ToString('o'); WinappVersion = $version; Repository = $Repository; Results = @($results.ToArray()); Events = @($events.ToArray()) } |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding utf8
    $env:WINAPP_UI_WORKFLOW_ID = $previousWorkflow
    Write-Host "E2E report: $reportPath"
}
