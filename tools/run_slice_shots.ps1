param(
    [string]$Window = '1280x720',
    [ValidateSet('rekindle', 'snuff')][string]$Ending = 'rekindle',
    [switch]$BasicAbilities,
    [switch]$GodotVerbose,
    [string]$OutDir = 'screenshots/upgrade-phase1',
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe'
)
# Real windowed run of title -> opening -> chapter 1 -> combat -> boss -> chapter 2,
# driven by the normal-input walkthrough, photographing each beat. The window is
# placed on the desktop (not off-screen). Isolated APPDATA; player saves untouched.
# This is scripted keyboard-action input, not a human playthrough or device test.
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $workspace (($OutDir -replace '/', '\') + '\' + $Window)
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$userdata = Join-Path $env:TEMP ('Rustgrave-shots-' + [guid]::NewGuid().ToString('N'))
$size = $Window.Split('x')
$arguments = @('--path', ('"' + $workspace + '"'), '--windowed', '--resolution', $Window,
    'res://scenes/tools/InputWalkthrough.tscn', '--', ('--ending=' + $Ending), '--shots', '--onscreen', ('--window=' + $Window))
if ($BasicAbilities) { $arguments += '--basic-abilities' }
if ($GodotVerbose) { $arguments = @('--verbose') + $arguments }
$stdoutPath = Join-Path $runDir 'stdout.log'
$stderrPath = Join-Path $runDir 'stderr.log'
$previous = $env:APPDATA
try {
    $env:APPDATA = $userdata
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $workspace -PassThru `
        -WindowStyle Minimized -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
} finally { $env:APPDATA = $previous }
if (-not $process.WaitForExit(600000)) {
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    Write-Output '[FAIL] timeout'
}
$gameData = Join-Path $userdata 'Godot\app_userdata\Rustgrave'
Get-ChildItem -LiteralPath (Join-Path $gameData 'shots') -Filter '*.png' -ErrorAction SilentlyContinue | Copy-Item -Destination $runDir
$result = Join-Path $gameData ('walkthrough_' + $Ending + '.json')
if (Test-Path -LiteralPath $result) { Copy-Item -LiteralPath $result -Destination (Join-Path $runDir 'walkthrough.json') }
Get-Content -LiteralPath $stdoutPath | Select-String 'WALKTHROUGH|MILESTONE' | Select-Object -Last 4
Get-Content -LiteralPath $stderrPath | Select-String '^(SCRIPT ERROR|ERROR):' | Where-Object { $_ -notmatch 'Texture with GL ID|RID allocations' } | Select-Object -First 10
Write-Output ('Shots: ' + $runDir)
