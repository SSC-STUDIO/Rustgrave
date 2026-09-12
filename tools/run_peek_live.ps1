param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$Spots = '',
    [double]$Hold = 4.0,
    [switch]$Lit,
    [switch]$Night,
    [switch]$Active,
    [string]$Weather = '',
    [string]$Level = '',
    # Output folder relative to the workspace (default screenshots/peek). Give each
    # concurrent caller its own folder, e.g. screenshots/peek/level05.
    [string]$OutDir = 'screenshots/peek',
    # Camera centre y (default 220 = the ground floor view). Vertical levels: e.g. -200.
    [double]$CamY = 220.0
)
# Live peek: clock running, one PNG per camera spot in $OutDir.
# Complements run_render_acceptance.ps1 (which freezes time for fixtures).
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $workspace ($OutDir -replace '/', '\')
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$env:APPDATA = Join-Path $outputDir 'isolated-userdata'
$resOut = 'res://' + ($OutDir.TrimEnd('/') -replace '\\', '/')
$arguments = @('--path', ('"' + $workspace + '"'), '--windowed', '--position', '-12000,-12000', '--resolution', '1920x1080', '--rendering-method', 'gl_compatibility', 'res://scenes/tools/PeekLive.tscn', '--', ('--hold=' + $Hold), ('--out=' + $resOut))
if ($Spots) { $arguments += @('--spots=' + $Spots) }
if ($Lit) { $arguments += @('--lit') }
if ($Night) { $arguments += @('--night') }
if ($Active) { $arguments += @('--active') }
if ($Weather) { $arguments += @('--weather=' + $Weather) }
if ($Level) { $arguments += @('--level=' + $Level) }
if ($CamY -ne 220.0) { $arguments += @('--cam_y=' + $CamY) }
$stdoutFile = Join-Path $outputDir 'stdout.log'
$stderrFile = Join-Path $outputDir 'stderr.log'
$process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
if (-not $process.WaitForExit(180000)) {
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    throw 'peek_live timed out'
}
Get-Content -LiteralPath $stdoutFile | Where-Object { $_ -match '^PEEK ' }
$errors = @(Get-Content -LiteralPath $stderrFile | Where-Object { $_ -match '^SCRIPT ERROR:' })
if ($errors.Count -gt 0) { $errors; exit 1 }
Get-ChildItem -LiteralPath $outputDir -Filter 'live_*.png' | ForEach-Object { $_.FullName }
exit 0
