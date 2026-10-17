param(
    [string]$Window = '1280x720',
    [string]$OutDir = 'screenshots/upgrade-phase2/touch',
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe'
)
# SIMULATED TOUCH: forced on-screen pad + injected InputEventScreenTouch on a desktop
# window. Not a device test. Isolated APPDATA; player saves untouched.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $workspace (($OutDir -replace '/', '\') + '\' + $Window)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$userdata = Join-Path $env:TEMP ('Rustgrave-touch-' + [guid]::NewGuid().ToString('N'))
$arguments = @('--path', ('"' + $workspace + '"'), '--windowed', '--resolution', $Window,
    'res://scenes/tools/TouchPass.tscn', '--', ('--window=' + $Window))
$stdoutPath = Join-Path $runDir 'stdout.log'
$stderrPath = Join-Path $runDir 'stderr.log'
$previous = $env:APPDATA
try {
    $env:APPDATA = $userdata
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $workspace -PassThru `
        -WindowStyle Minimized -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
} finally { $env:APPDATA = $previous }
if (-not $process.WaitForExit(180000)) {
    if (-not $process.HasExited) { $process.Kill() }
    Write-Output '[FAIL] timeout'
}
$gameData = Join-Path $userdata 'Godot\app_userdata\Rustgrave\touch'
Get-ChildItem -LiteralPath $gameData -ErrorAction SilentlyContinue | Copy-Item -Destination $runDir
Get-Content -LiteralPath $stdoutPath | Select-String 'TOUCH'
Get-Content -LiteralPath $stderrPath | Select-String '^(SCRIPT ERROR|ERROR):' | Where-Object { $_ -notmatch 'Texture with GL ID|RID allocations' } | Select-Object -First 10
Write-Output ('Touch shots: ' + $runDir)
