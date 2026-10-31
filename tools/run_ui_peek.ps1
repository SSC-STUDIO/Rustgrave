param(
    [string]$GodotExe = 'C:\Program Files\Godot\Godot_v4.7.1-stable_win64_console.exe',
    [string]$Sizes = '960x540,1280x720,1920x1080',
    [string]$Only = 'title,menus',
    [string]$OutDir = 'screenshots/peek/ui-upgrade/menus-final'
)

# Real render-target screenshots with disposable saves/settings for every size.
$ErrorActionPreference = 'Stop'
$projectDir = Split-Path -Parent $PSScriptRoot
$previousAppData = $env:APPDATA
$previousUpdateCheck = $env:RUSTGRAVE_NO_UPDATE_CHECK
try {
    foreach ($size in ($Sizes -split ',')) {
        if ($size -notmatch '^\d+x\d+$') { throw "Invalid size: $size" }
        $relativeOutput = $OutDir.TrimEnd('/') + '/' + $size
        $outputDir = Join-Path $projectDir $relativeOutput
        New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
        $stdout = Join-Path $outputDir 'stdout.log'
        $stderr = Join-Path $outputDir 'stderr.log'
        $env:APPDATA = Join-Path $outputDir 'isolated-userdata'
        $env:RUSTGRAVE_NO_UPDATE_CHECK = '1'
        $arguments = @('--path', ('"' + $projectDir + '"'), '--windowed',
            '--position', '-12000,-12000', '--resolution', $size,
            '--rendering-method', 'gl_compatibility', 'res://scenes/tools/UiPeek.tscn',
            '--', ('--out=res://' + $relativeOutput), ('--size=' + $size), ('--only=' + $Only))
        $process = Start-Process -FilePath $GodotExe -ArgumentList $arguments -WindowStyle Hidden `
            -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $started = [DateTime]::UtcNow
        $failed = $false
        while (-not $process.WaitForExit(250)) {
            $failed = ([DateTime]::UtcNow - $started).TotalSeconds -gt 180
            if (Test-Path -LiteralPath $stderr) {
                $failed = $failed -or ((Get-Content -LiteralPath $stderr -Raw) -match '(?m)^(SCRIPT ERROR|ERROR):')
            }
            if ($failed) { break }
        }
        if ($failed) {
            Get-CimInstance Win32_Process -Filter ('ParentProcessId=' + $process.Id) |
                ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
            if (-not $process.HasExited) { $process.Kill() }
            throw "UI capture failed or timed out; inspect $stderr"
        }
        $outText = Get-Content -LiteralPath $stdout -Raw
        $errorText = Get-Content -LiteralPath $stderr -Raw
        if ($errorText -match '(?m)^(SCRIPT ERROR|ERROR):' -or
            $outText -notmatch 'UI_PEEK shots=\d+' -or $outText -match 'saved=false') {
            throw "UI capture did not complete; inspect $outputDir"
        }
        $outText -split "`r?`n" | Where-Object { $_ -match '^UI_PEEK ' }
    }
} finally {
    $env:APPDATA = $previousAppData
    $env:RUSTGRAVE_NO_UPDATE_CHECK = $previousUpdateCheck
}
