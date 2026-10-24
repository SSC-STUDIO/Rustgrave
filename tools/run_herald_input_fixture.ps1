param(
    [Parameter(Mandatory=$true)][string]$SourceSave,
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$ArtifactsDir = '',
    [int]$TimeoutSeconds = 180,
    [switch]$Rendered
)

$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$runDir = if ($ArtifactsDir) { [IO.Path]::GetFullPath($ArtifactsDir) } else {
    Join-Path $env:TEMP ('Rustgrave-local-herald-' + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$sourceHash = (Get-FileHash -LiteralPath $SourceSave -Algorithm SHA256).Hash
$userDir = Join-Path $runDir 'userdata'
$saveDir = Join-Path $userDir 'Godot/app_userdata/Rustgrave'
New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
$saveCopy = Join-Path $saveDir 'input_walkthrough_rekindle.cfg'
Copy-Item -LiteralPath $SourceSave -Destination $saveCopy
if ((Get-FileHash -LiteralPath $saveCopy -Algorithm SHA256).Hash -ne $sourceHash) {
    throw 'The isolated checkpoint copy does not match the original bytes.'
}
$stdoutPath = Join-Path $runDir 'stdout.log'
$stderrPath = Join-Path $runDir 'stderr.log'
$arguments = @('--path', ('"' + $projectDir + '"'), '--fixed-fps', '60')
if (-not $Rendered) { $arguments = @('--headless') + $arguments }
$arguments += @('res://scenes/tools/HeraldInputFixture.tscn', '--', '--fast')

# No staged actors/items/flags. Continue loads the copied legal checkpoint.
$originalAppData = $env:APPDATA
$originalNoUpdate = $env:RUSTGRAVE_NO_UPDATE_CHECK
try {
    $env:APPDATA = $userDir
    $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
    $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WorkingDirectory $projectDir `
        -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
} finally {
    $env:APPDATA = $originalAppData
    $env:RUSTGRAVE_NO_UPDATE_CHECK = $originalNoUpdate
}

$started = [DateTime]::UtcNow
$timedOut = $false
$engineError = $false
while (-not $process.WaitForExit(250)) {
    $timedOut = ([DateTime]::UtcNow - $started).TotalSeconds -ge $TimeoutSeconds
    $engineError = (Get-Content -LiteralPath $stderrPath -Raw) -match '(?m)^(?:SCRIPT ERROR|ERROR):'
    if ($timedOut -or $engineError) { break }
}
if ($timedOut -or $engineError) {
    Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
    if (-not $process.HasExited) { $process.Kill() }
    $process.WaitForExit()
}

$stdout = Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8
$stderr = Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8
$engineError = ($stdout + "`n" + $stderr) -match '(?m)^(?:SCRIPT ERROR|ERROR|\[ENGINE ERROR\]):?'
$reports = @(Get-ChildItem -LiteralPath $userDir -Recurse -File -Filter 'herald_input_fixture.json')
$report = if ($reports.Count -eq 1) { Get-Content -LiteralPath $reports[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
$passed = -not ($timedOut -or $engineError) -and $null -ne $report -and $report.passed -eq $true `
    -and $report.full_campaign -eq $false -and $report.herald_dead -eq $true
if ($null -ne $report) {
    $report | Add-Member -NotePropertyName source_save_sha256 -NotePropertyValue $sourceHash
    [IO.File]::WriteAllText((Join-Path $runDir 'result.json'), ($report | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}
Write-Output $stdout
if ($stderr) { Write-Output $stderr }
Write-Output ('Local Herald checkpoint artifacts: ' + $runDir)
if ($timedOut) { Write-Output ('[FAIL] process timeout after ' + $TimeoutSeconds + ' seconds') }
if (-not $passed) { exit 1 }
exit 0
