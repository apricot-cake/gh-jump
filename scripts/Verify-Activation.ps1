param([switch]$LoadRepositories)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$executable = Join-Path $root 'artifacts/publish/x64/GHJump.exe'
if (!(Test-Path $executable)) { throw 'Run Package.ps1 for x64 first.' }
$server = Start-Process -FilePath $executable -ArgumentList '-RegisterProcessAsComServer' -WindowStyle Hidden -PassThru
Push-Location $root
try {
    $arguments = @('run', '--project', 'tools/GHJump.LiveCheck', '--no-build', '-c', 'Release', '--', '--activate')
    if ($LoadRepositories) { $arguments += '--load' }
    & dotnet @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Extension COM activation validation failed.' }
} finally {
    Pop-Location
    if (!$server.HasExited) { Stop-Process -Id $server.Id }
}
