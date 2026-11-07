[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$OutDir = '',
    ## Godot user-args after --, e.g. -ExtraArgs '--sequence=all','--frames=10','--step=0.5'
    [string[]]$ExtraArgs = @(),
    ## '' = the project setting (forward_plus). 'gl_compatibility' reproduces the
    ## pre-switch baseline for A/B comparisons.
    [string]$Renderer = ''
)
# Windowed stills of the live title, storyboards, journal and ember recap.
# Takes the shared Godot lock ($env:TEMP\rustgrave_godot.lock) and refreshes it so a
# long run is not treated as stale. Isolated APPDATA; the player save is not touched.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP 'rustgrave_shots' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$lock = Join-Path $env:TEMP 'rustgrave_godot.lock'
$waitUntil = (Get-Date).AddMinutes(40)
while (Test-Path -LiteralPath $lock) {
    $ageMin = ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalMinutes
    if ($ageMin -gt 20) {
        Remove-Item -LiteralPath $lock -Force
        break
    }
    if ((Get-Date) -gt $waitUntil) { throw 'timed out waiting for rustgrave_godot.lock' }
    Start-Sleep -Seconds 3
}
Set-Content -LiteralPath $lock -Value ("story_shots pid=$PID " + (Get-Date -Format o)) -Encoding ascii
$touch = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
    '-NoProfile', '-Command',
    "while (Test-Path -LiteralPath '$lock') { (Get-Item -LiteralPath '$lock').LastWriteTime = Get-Date; Start-Sleep -Seconds 20 }"
)
$stdout = Join-Path $OutDir 'stdout.log'
$stderr = Join-Path $OutDir 'stderr.log'
$resOut = ($OutDir -replace '\\', '/')
$previousAppData = $env:APPDATA
$previousUpdate = $env:RUSTGRAVE_NO_UPDATE_CHECK
try {
    $env:APPDATA = Join-Path $OutDir 'userdata'
    $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
    $arguments = @(
        '--path', ('"' + $workspace + '"'),
        '--windowed', '--position', '-12000,-12000', '--resolution', '1280x720',
        'res://scenes/tools/StoryShots.tscn', '--',
        ('--out=' + $resOut)
    )
    if ($Renderer) { $arguments = @('--rendering-method', $Renderer) + $arguments }
    if ($ExtraArgs) { $arguments += @($ExtraArgs) }
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $workspace `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(240000)) {
        Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) |
            ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        if (-not $process.HasExited) { $process.Kill() }
        throw 'story_shots timed out'
    }
} finally {
    if ($null -ne $previousAppData) { $env:APPDATA = $previousAppData }
    if ($null -eq $previousUpdate) { Remove-Item Env:\RUSTGRAVE_NO_UPDATE_CHECK -ErrorAction SilentlyContinue }
    else { $env:RUSTGRAVE_NO_UPDATE_CHECK = $previousUpdate }
    if ($touch -and -not $touch.HasExited) { Stop-Process -Id $touch.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
}
Get-Content -LiteralPath $stdout | Where-Object { $_ -match '^STORY_SHOT' }
$errors = @()
if (Test-Path -LiteralPath $stderr) {
    $errors = @(Get-Content -LiteralPath $stderr | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' })
}
if ($errors.Count -gt 0) {
    $errors | Select-Object -First 40
    exit 1
}
exit 0
