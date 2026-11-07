param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [switch]$Quick,
    [switch]$Supplement,
    # '' = the project setting (forward_plus). 'gl_compatibility' reproduces the
    # pre-switch baseline for A/B comparisons.
    [string]$Renderer = ''
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$outputDir = Join-Path $workspace 'screenshots\acceptance\display'
if ($Supplement) { $outputDir = Join-Path $outputDir 'supplement' }
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$reportPath = Join-Path $outputDir 'report.json'
if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath }
$env:APPDATA = Join-Path $outputDir 'isolated-userdata'
$arguments = @('--path', ('"' + $workspace + '"'), '--windowed', '--position', '-12000,-12000', '--resolution', '1920x1080', 'res://scenes/tools/RenderAcceptance.tscn')
if ($Renderer) { $arguments = @('--rendering-method', $Renderer) + $arguments }
if ($Supplement) { $arguments += @('--', '--supplement') }
elseif ($Quick) { $arguments += @('--', '--quick') }
$stdoutFile = Join-Path $outputDir 'stdout.log'
$stderrFile = Join-Path $outputDir 'stderr.log'
$process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
$started = [DateTime]::UtcNow
while (-not $process.WaitForExit(250)) {
    $runtimeStderr = Get-Content -LiteralPath $stderrFile -Raw
    $errorsFound = $runtimeStderr -match '(?m)^(SCRIPT ERROR:|ERROR:)' -and $runtimeStderr -notmatch '(?m)^(ERROR: (?:Texture with GL ID|\d+ RID allocations)|WARNING: (?:\d+ RIDs|\d+ ObjectDB instances))'
    if ($errorsFound -or ([DateTime]::UtcNow - $started).TotalSeconds -gt 330) {
        Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
        if (-not $process.HasExited) { $process.Kill() }
        $process.WaitForExit()
        Get-Content -LiteralPath $stderrFile | Select-Object -Last 15
        throw 'Render acceptance failed or timed out before completion.'
    }
}
# Windows PowerShell 5.1: the -PassThru object often has no ExitCode once the console
# launcher exits ($null). The report's own passed/completed flags are the real signal.
$exitCode = $process.ExitCode
if ($null -eq $exitCode) { $exitCode = 0 }
if (Test-Path -LiteralPath $reportPath) {
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    $exitErrors = @(Get-Content -LiteralPath $stderrFile | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: (?:Texture with GL ID|\d+ RID allocations)' })
    $exitErrors += @(Get-Content -LiteralPath $stdoutFile | Where-Object { $_ -match '^(SCRIPT ERROR:|ERROR:)' -and $_ -notmatch '^ERROR: (?:Texture with GL ID|\d+ RID allocations)' })
    $report | Add-Member -NotePropertyName engine_exit_errors -NotePropertyValue $exitErrors -Force
    # Supplement: 4 main-loop captures + 7 places x 3 weathers + 5 UI/pit extras (see render_acceptance.gd).
    $expectedCaptureCount = if ($Supplement) { 30 } elseif ($Quick) { 8 } else { 36 }
    $expectedTitleCount = if ($Supplement) { 1 } else { $expectedCaptureCount / 4 }
    $report.passed = [bool]$report.passed -and $exitErrors.Count -eq 0 -and $exitCode -eq 0 -and [bool]$report.completed -and $report.resolutions.Count -eq $expectedCaptureCount -and $report.title_screens.Count -eq $expectedTitleCount
    [IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 14), (New-Object Text.UTF8Encoding($false)))
}
else {
    Write-Error 'Rendering stopped before report.json was produced; no completed acceptance result exists.'
    exit 1
}
Get-Content -LiteralPath $stdoutFile | Select-Object -Last 8
Get-Content -LiteralPath $stderrFile | Select-Object -Last 12
if ($null -ne $report -and -not $report.passed) { exit 1 }
exit $exitCode
