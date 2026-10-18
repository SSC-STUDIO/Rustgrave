param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$CaseFilter = '',
    [int]$TimeoutSeconds = 180,
    [string]$ArtifactsDir = ''
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runDir = if ($ArtifactsDir) { [IO.Path]::GetFullPath($ArtifactsDir) } else {
    Join-Path $env:TEMP ('Rustgrave-tests-' + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stdoutPath = Join-Path $runDir 'stdout.log'
$stderrPath = Join-Path $runDir 'stderr.log'
$arguments = @('--headless', '--path', ('"' + $projectDir + '"'), 'res://tests/run_tests.tscn')
if ($CaseFilter) { $arguments += @('--', ('"--case-filter=' + $CaseFilter.Replace('"', '') + '"')) }

# Child processes inherit this isolated user directory; never touch player saves.
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $runDir 'userdata'
    # The suite runs with the update check disabled: no case may hang on the
    # network. update_service_test re-arms it itself against a local server.
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
# Windows PowerShell 5.1 hands back a -PassThru object without the start handle,
# so ExitCode is often $null once the console launcher exits. $null -ne 0 used to
# flag every green run as a failure; treat the code as advisory and rely on the
# runner's completion marker plus the error scan below.
$exitCode = $process.ExitCode
if ($null -eq $exitCode) { $exitCode = 0 }
$stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 } else { '' }
$stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 } else { '' }
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
Write-Output ('Test artifacts: ' + $runDir)

# Also catch errors before the scene/logger could load, and require completion.
$hasErrors = ($stdout + "`n" + $stderr) -match '(?m)^(?:SCRIPT ERROR|ERROR|\[ENGINE ERROR\]):?'
$completed = $stdout -match '(?m)^OK .+\d+/\d+ passed; 0 engine errors'
$passed = -not ($timedOut -or $exitCode -ne 0 -or $hasErrors -or -not $completed)
$summary = [ordered]@{
    passed = $passed
    timed_out = $timedOut
    exit_code = $exitCode
    engine_errors = $hasErrors
    completed = $completed
    case_filter = $CaseFilter
}
[IO.File]::WriteAllText((Join-Path $runDir 'summary.json'), ($summary | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
if ($timedOut -or $exitCode -ne 0 -or $hasErrors -or -not $completed) {
    if ($timedOut) { Write-Output ('[FAIL] process timeout after ' + $TimeoutSeconds + ' seconds') }
    exit 1
}
exit 0
