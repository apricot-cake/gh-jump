$ErrorActionPreference = 'Stop'
$package = Get-AppxPackage Microsoft.CommandPalette | Select-Object -First 1
if (!$package) { throw 'Command Palette is not installed for the current user.' }
$executable = Join-Path $package.InstallLocation 'Microsoft.CmdPal.UI.exe'
if (!(Test-Path -LiteralPath $executable)) { throw 'Command Palette executable was not found.' }

$processes = Get-CimInstance Win32_Process -Filter "Name='Microsoft.CmdPal.UI.exe'" |
    Where-Object { $_.ExecutablePath -eq $executable }
foreach ($process in $processes) {
    $running = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    if ($running) {
        Stop-Process -Id $running.Id
        if (!$running.WaitForExit(10000)) { throw 'Command Palette did not stop.' }
    }
}

$started = Start-Process -FilePath $executable -WindowStyle Hidden -PassThru
Write-Host "Command Palette restarted (PID $($started.Id))."
