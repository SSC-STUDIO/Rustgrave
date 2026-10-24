param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$Level = 'title',
    [string]$Variant = 'cold',
    [string]$Win = '1920x1080',
    [string]$OutDir = 'screenshots/acceptance/overhaul-v3/title-perf/probes',
    [double]$SampleSeconds = 4,
    [switch]$Active,
    [switch]$Keyart
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $workspace ($OutDir -replace '/', '\')
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$tag = $Level + '_' + $Variant + '_' + $Win + $(if ($Keyart) { '_keyart' } else { '_live' })
$stdoutFile = Join-Path $outputDir ($tag + '_stdout.log')
$stderrFile = Join-Path $outputDir ($tag + '_stderr.log')
$resOut = 'res://' + ($OutDir.TrimEnd('/') -replace '\\', '/')
$arguments = @('--path', ('"' + $workspace + '"'), '--windowed', '--position', '-12000,-12000', '--resolution', $Win,
    '--rendering-method', 'gl_compatibility', 'res://scenes/tools/FrameCostProbe.tscn', '--',
    ('--level=' + $Level), ('--variant=' + $Variant), ('--out=' + $resOut), ('--win=' + $Win), ('--sample=' + $SampleSeconds))
if ($Active) { $arguments += '--active' }
if ($Keyart) { $arguments += '--keyart' }
$previousAppData = $env:APPDATA
$previousUpdateCheck = $env:RUSTGRAVE_NO_UPDATE_CHECK
try {
    $env:APPDATA = Join-Path $outputDir 'isolated-userdata'
    $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $workspace -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
} finally {
    $env:APPDATA = $previousAppData
    $env:RUSTGRAVE_NO_UPDATE_CHECK = $previousUpdateCheck
}
if (-not $process.WaitForExit(180000)) {
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    throw 'frame_cost_probe timed out'
}
$stdout = Get-Content -LiteralPath $stdoutFile -Raw
$stderr = Get-Content -LiteralPath $stderrFile -Raw
Write-Output $stdout
if (($stdout + "`n" + $stderr) -match '(?m)^(?:SCRIPT ERROR|ERROR):' -or $stdout -notmatch '(?m)^FRAMECOST ') { throw $stderr }
if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) { throw 'frame_cost_probe failed' }
exit 0
