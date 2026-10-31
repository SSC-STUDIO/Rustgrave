param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    # cold | act1..act4 | mid | give | keep | snuff (comma list)
    [string]$Variants = 'cold,act1,act2,act3,act4,give,keep,snuff',
    # window sizes to render (comma list); 960x540 / 1280x720 / 1920x1080 by default
    [string]$Sizes = '960x540,1280x720,1920x1080',
    # boot,idle,focus,all
    [string]$Shots = 'idle,focus',
    # output folder relative to the workspace
    [string]$OutDir = 'screenshots/acceptance/overhaul-v3/title',
    # skin id to show on the bridge (default: the Ember Knight)
    [string]$Skin = '',
    # hide the UI and capture only the live scene
    [switch]$Bare,
    [switch]$Keyart,
    [switch]$ShadowPair
)
# Window-mode capture of the live title (see tools/title_peek.gd). Saves and settings
# are isolated under $OutDir, and APPDATA is redirected, so a real player save is
# never read or written.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $workspace ($OutDir -replace '/', '\')
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$previousAppData = $env:APPDATA
$previousUpdateCheck = $env:RUSTGRAVE_NO_UPDATE_CHECK
$previousAllowSmall = $env:RUSTGRAVE_ALLOW_SMALL_WINDOW
$resOut = 'res://' + ($OutDir.TrimEnd('/') -replace '\\', '/')
$first = ($Sizes -split ',')[0]
$arguments = @('--path', ('"' + $workspace + '"'), '--windowed', '--position', '-12000,-12000', '--resolution', $first,
    '--rendering-method', 'gl_compatibility', 'res://scenes/tools/TitlePeek.tscn', '--',
    ('--out=' + $resOut), ('--sizes=' + $Sizes), ('--variants=' + $Variants), ('--shots=' + $Shots))
if ($Skin) { $arguments += @('--skin=' + $Skin) }
if ($Bare) { $arguments += @('--bare') }
if ($Keyart) { $arguments += @('--keyart') }
if ($ShadowPair) { $arguments += @('--shadow-pair') }
$stdoutFile = Join-Path $outputDir 'stdout.log'
$stderrFile = Join-Path $outputDir 'stderr.log'
try {
    $env:APPDATA = Join-Path $outputDir 'isolated-userdata'
    $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
    # Diagnostic sizes below 1280x720 stay possible; a real player window is clamped.
    $env:RUSTGRAVE_ALLOW_SMALL_WINDOW = '1'
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
} finally {
    $env:APPDATA = $previousAppData
    $env:RUSTGRAVE_NO_UPDATE_CHECK = $previousUpdateCheck
    $env:RUSTGRAVE_ALLOW_SMALL_WINDOW = $previousAllowSmall
}
if (-not $process.WaitForExit(300000)) {
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    throw 'title_peek timed out'
}
Get-Content -LiteralPath $stdoutFile | Where-Object { $_ -match '^TITLE_PEEK ' }
$errors = @(Get-Content -LiteralPath $stderrFile | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' })
if ($errors.Count -gt 0) { $errors; exit 1 }
if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) { throw 'title_peek failed' }
exit 0
