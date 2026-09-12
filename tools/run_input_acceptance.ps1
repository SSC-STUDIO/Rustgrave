param(
    [ValidateSet('rekindle', 'snuff', 'both')][string]$Ending = 'both',
    [switch]$Rendered,
    [switch]$Campaign,
    [switch]$BasicAbilities,
    [switch]$Fast,
    [string]$ResumeSave = '',
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runDir = Join-Path $workspace ('screenshots\acceptance\input-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$endings = if ($Ending -eq 'both') { @('rekindle', 'snuff') } else { @($Ending) }
# Engine ERROR lines that matter. Godot's GL backend reports leaked texture/RID
# bookkeeping while tearing down after quit(); those are not gameplay failures.
function Get-RealErrors([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return @() }
    return @([regex]::Matches($text, '(?m)^(SCRIPT ERROR:.*|ERROR: .*)$') | ForEach-Object { $_.Value } |
        Where-Object { $_ -notmatch '^ERROR: (?:Texture with GL ID|\d+ RID allocations)' })
}
foreach ($kind in $endings) {
    $stdoutPath = Join-Path $runDir ($kind + '-stdout.log')
    $stderrPath = Join-Path $runDir ($kind + '-stderr.log')
    $userdata = Join-Path $runDir ($kind + '-userdata')
    if ($ResumeSave) {
        if (-not $Campaign -or $kind -ne 'rekindle') { throw 'ResumeSave requires Campaign and Ending rekindle' }
        $resumeData = Join-Path $userdata 'Godot\app_userdata\Rustgrave'
        New-Item -ItemType Directory -Force -Path $resumeData | Out-Null
        Copy-Item -LiteralPath $ResumeSave -Destination (Join-Path $resumeData 'input_walkthrough_rekindle.cfg')
    }
    $arguments = @('--path', ('"' + $workspace + '"'))
    if (-not $Rendered) { $arguments += '--headless' }
    else { $arguments += @('--windowed', '--position', '-12000,-12000', '--resolution', '1920x1080') }
    if ($Fast) { $arguments += @('--fixed-fps', '60') }
    $scene = if ($Campaign -and $kind -eq 'rekindle') { 'res://scenes/tools/CampaignWalkthrough.tscn' } else { 'res://scenes/tools/InputWalkthrough.tscn' }
    $arguments += @($scene, '--', ('--ending=' + $kind))
    if ($Campaign) { $arguments += '--campaign' }
    if ($BasicAbilities) { $arguments += '--basic-abilities' }
    if ($ResumeSave) { $arguments += '--resume' }
    if ($Fast) { $arguments += '--fast' }
    $previousAppData = $env:APPDATA
    try {
        $env:APPDATA = $userdata
        $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden -WorkingDirectory $workspace -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    } finally { $env:APPDATA = $previousAppData }
    $started = [DateTime]::UtcNow
    while (-not $process.WaitForExit(250)) {
        $errorText = Get-Content -LiteralPath $stderrPath -Raw
        $timeoutSeconds = if ($Campaign) { 1830 } else { 270 }
        if ((Get-RealErrors $errorText).Count -gt 0 -or ([DateTime]::UtcNow - $started).TotalSeconds -gt $timeoutSeconds) {
            Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
            if (-not $process.HasExited) { $process.Kill() }
            throw ('Input acceptance failed or timed out. See ' + $runDir)
        }
    }
    # Windows PowerShell 5.1: the -PassThru object often reports $null ExitCode once the
    # console launcher exits; the walkthrough's own JSON verdict is the real signal.
    $exitCode = $process.ExitCode
    if ($null -eq $exitCode) { $exitCode = 0 }
    $gameData = Join-Path $userdata 'Godot\app_userdata\Rustgrave'
    $resultPath = Join-Path $gameData ('walkthrough_' + $kind + '.json')
    Get-Content -LiteralPath $stdoutPath | Select-Object -Last 8
    if (-not (Test-Path -LiteralPath $resultPath)) { throw ('No completion report: ' + $runDir) }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    $realErrors = Get-RealErrors (Get-Content -LiteralPath $stderrPath -Raw)
    if ($exitCode -ne 0 -or -not $result.passed -or $result.engine_errors.Count -gt 0 -or $realErrors.Count -gt 0) { throw ('Acceptance failed: ' + $runDir) }
    Copy-Item -LiteralPath $resultPath -Destination (Join-Path $runDir ($kind + '.json'))
    Get-ChildItem -LiteralPath $gameData -Filter '*.png' | Copy-Item -Destination $runDir
}
Write-Output ('Input acceptance passed. Evidence: ' + $runDir)
