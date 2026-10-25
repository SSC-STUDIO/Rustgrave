param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$Only = '',
    [string]$OutDir = '',
    [switch]$Gate,
    [int]$TimeoutSeconds = 300,
    [string]$ArtifactsDir = ''
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runDir = if ($ArtifactsDir) { [IO.Path]::GetFullPath($ArtifactsDir) } else {
    Join-Path $env:TEMP ('Rustgrave-sprite-audit-' + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stdoutPath = Join-Path $runDir 'stdout.log'
$stderrPath = Join-Path $runDir 'stderr.log'
$arguments = @('--headless', '--path', ('"' + $projectDir + '"'), 'res://scenes/tools/SpriteAuditProbe.tscn')
$userArgs = @()
if ($Only) { $userArgs += ('"--only=' + $Only.Replace('"', '') + '"') }
if ($OutDir) { $userArgs += ('"--out=' + $OutDir.Replace('"', '') + '"') }
if ($Gate) { $userArgs += '--gate' }
if ($userArgs.Count -gt 0) { $arguments += @('--') + $userArgs }

# Child processes inherit this isolated user directory; never touch player saves.
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $runDir 'userdata'
    $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $projectDir `
        -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
} finally {
    $env:APPDATA = $originalAppData
    Remove-Item Env:\RUSTGRAVE_NO_UPDATE_CHECK -ErrorAction SilentlyContinue
}

$started = [DateTime]::UtcNow
$timedOut = $false
$earlyError = $false
while (-not $process.WaitForExit(250)) {
    $timedOut = ([DateTime]::UtcNow - $started).TotalSeconds -ge $TimeoutSeconds
    if (Test-Path -LiteralPath $stderrPath) {
        $earlyError = (Get-Content -LiteralPath $stderrPath -Raw) -match '(?m)^(?:SCRIPT ERROR|ERROR):'
    }
    if ($timedOut -or $earlyError) { break }
}
if ($timedOut -or $earlyError) {
    # The console launcher may own the actual engine process.
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    $process.WaitForExit()
}
$exitCode = $process.ExitCode
if ($null -eq $exitCode) { $exitCode = 0 }
$stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
$stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
Write-Output ('Audit artifacts: ' + $runDir)

# Completion marker + engine error scan matter more than the advisory exit code.
$hasErrors = ($stdout + "`n" + $stderr) -match '(?m)^(?:SCRIPT ERROR|ERROR|\[ENGINE ERROR\]):?'
$completed = $stdout -match '(?m)^\[SPRITE AUDIT\] DONE'
if ($timedOut -or $hasErrors -or -not $completed) {
    if ($timedOut) { Write-Output ('[FAIL] process timeout after ' + $TimeoutSeconds + ' seconds') }
    if (-not $completed) { Write-Output '[FAIL] audit did not finish (no [SPRITE AUDIT] DONE marker)' }
    exit 1
}
if ($Gate -and $exitCode -ne 0) { exit 1 }
exit 0
