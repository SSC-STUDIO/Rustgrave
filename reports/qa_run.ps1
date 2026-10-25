# qa_run.ps1 — QA helper: run one test suite headless, evaluate pass criteria.
# Unlike tools/run_tests.ps1, this treats Godot's benign
# "ERROR: Failed to read the root certificate store." line as non-fatal and
# avoids Get-CimInstance (blocked in this environment) when killing on timeout.
# Usage: powershell -File qa_run.ps1 -CaseFilter <suite> [-TimeoutSeconds 300] [-Label <name>]
param(
    [string]$CaseFilter = '',
    [int]$TimeoutSeconds = 300,
    [string]$Label = ''
)
$ErrorActionPreference = 'Stop'
$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe'
$projectDir = 'C:\Users\Administrator\OneDrive\Documents\My-Program\Rustgrave'
if ($Label -eq '') { $Label = $CaseFilter }

$runDir = Join-Path $env:TEMP ('rg-qa-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stdoutPath = Join-Path $runDir 'stdout.log'
$stderrPath = Join-Path $runDir 'stderr.log'

$originalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $runDir 'userdata'
    $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
    $argList = @('--headless', '--path', "`"$projectDir`"", 'res://tests/run_tests.tscn')
    if ($CaseFilter -ne '') { $argList += @('--', "--case-filter=$CaseFilter") }
    $proc = Start-Process -FilePath $GodotExe `
        -ArgumentList $argList `
        -WorkingDirectory $projectDir -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
} finally {
    $env:APPDATA = $originalAppData
    Remove-Item Env:\RUSTGRAVE_NO_UPDATE_CHECK -ErrorAction SilentlyContinue
}

$started = [DateTime]::UtcNow
$timedOut = -not $proc.WaitForExit($TimeoutSeconds * 1000)
if ($timedOut) {
    # Console build runs the engine in-process; direct kill is sufficient.
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    $proc.WaitForExit()
}

$stdout = if (Test-Path $stdoutPath) { Get-Content $stdoutPath -Raw -Encoding UTF8 } else { '' }
$stderr = if (Test-Path $stderrPath) { Get-Content $stderrPath -Raw -Encoding UTF8 } else { '' }

# Filter the known-benign cert-store line before error evaluation.
$stderrClean = ($stderr -split "`r?`n" | Where-Object { $_ -notmatch 'Failed to read the root certificate store' -and $_ -notmatch 'get_system_ca_certificates' }) -join "`n"

$completed = $stdout -match '(?m)^OK .+\d+/\d+ passed; 0 engine errors'
$failedLine = [regex]::Match($stdout, '(?m)^FAILED .+$').Value
$engineErr = ($stdout + "`n" + $stderrClean) -match '(?m)^(?:SCRIPT ERROR|ERROR|\[ENGINE ERROR\]):?'
$passed = -not ($timedOut -or -not $completed -or $engineErr)

Write-Output $stdout
if ($stderrClean.Trim()) { Write-Output "--- stderr (benign cert lines filtered) ---"; Write-Output $stderrClean }
Write-Output ("Artifacts: " + $runDir)
Write-Output ("=== QA-RESULT [{0}] passed={1} timed_out={2} completed={3} engine_errors={4} duration={5:N1}s ===" -f `
    $Label, $passed, $timedOut, $completed, $engineErr, ([DateTime]::UtcNow - $started).TotalSeconds)
if ($failedLine) { Write-Output $failedLine }
exit $(if ($passed) { 0 } else { 1 })
