param(
    [switch]$Touch,
    [switch]$Headless,
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$mode = if ($Touch) { 'touch' } else { 'keyboard' }
$runDir = Join-Path $workspace ('screenshots/acceptance/combat-' + $mode + '-' + (Get-Date -Format yyyyMMdd-HHmmss-fff))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$arguments = @('--path', ('"' + $workspace + '"'), '--fixed-fps', '60')
if ($Headless) { $arguments += '--headless' }
else { $arguments += @('--windowed', '--position', '-12000,-12000', '--resolution', '1280x720') }
$arguments += 'res://scenes/tools/CombatInputAcceptance.tscn'
if ($Touch) { $arguments += @('--', '--touch') }
$oldAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $runDir 'userdata'
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $runDir 'stdout.log') -RedirectStandardError (Join-Path $runDir 'stderr.log')
} finally { $env:APPDATA = $oldAppData }
$deadline = [DateTime]::UtcNow.AddSeconds(90)
$runtimeError = $false
while (-not $process.WaitForExit(250)) {
    $runtimeError = (Get-Content (Join-Path $runDir 'stderr.log') -Raw) -match '(?m)^(SCRIPT ERROR|ERROR):'
    if ($runtimeError -or [DateTime]::UtcNow -gt $deadline) { break }
}
if (-not $process.HasExited) {
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    Get-Content (Join-Path $runDir 'stderr.log') -Tail 20
    throw ('Combat acceptance failed or timed out: ' + $runDir)
}
$gameData = Join-Path $runDir 'userdata/Godot/app_userdata/Rustgrave'
$reportPath = Join-Path $gameData 'combat_input.json'
if (-not (Test-Path -LiteralPath $reportPath)) {
    Get-Content (Join-Path $runDir 'stderr.log') -Tail 20
    throw ('No combat report: ' + $runDir)
}
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
$errorLog = Get-Content (Join-Path $runDir 'stderr.log') -Raw
$engineFailed = $errorLog -match '(?m)^(SCRIPT ERROR|ERROR):'
$exitCode = $process.ExitCode
if ($null -eq $exitCode) { $exitCode = 0 }
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $runDir 'report.json')
Get-ChildItem -LiteralPath $gameData -Filter '*.png' | Copy-Item -Destination $runDir
Get-Content (Join-Path $runDir 'stdout.log') -Tail 12
Write-Output ('Combat evidence: ' + $runDir)
if (-not $report.passed -or $engineFailed -or $exitCode -ne 0) { exit 1 }
