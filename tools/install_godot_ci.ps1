param(
    [string]$Destination = (Join-Path $env:TEMP 'Rustgrave-Godot-4.7.1')
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$version = '4.7.1-stable'
$asset = 'Godot_v4.7.1-stable_win64.exe.zip'
$releaseUrl = 'https://github.com/godotengine/godot-builds/releases/download/' + $version
$destinationPath = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null
$archive = Join-Path $destinationPath $asset
$manifest = Join-Path $destinationPath 'SHA512-SUMS.txt'
Invoke-WebRequest -UseBasicParsing -Uri ($releaseUrl + '/' + $asset) -OutFile $archive
Invoke-WebRequest -UseBasicParsing -Uri ($releaseUrl + '/SHA512-SUMS.txt') -OutFile $manifest
$pattern = '^([a-fA-F0-9]{128})\s+\*?' + [regex]::Escape($asset) + '$'
$entries = @(Get-Content -LiteralPath $manifest | Where-Object { $_ -match $pattern })
if ($entries.Count -ne 1) { throw 'Expected exactly one Godot Windows checksum entry' }
$expectedHash = [regex]::Match($entries[0], $pattern).Groups[1].Value
$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash
if ($actualHash -ine $expectedHash) { throw 'Godot SHA512 checksum mismatch' }
Expand-Archive -LiteralPath $archive -DestinationPath $destinationPath -Force
$engine = Join-Path $destinationPath 'Godot_v4.7.1-stable_win64_console.exe'
$actualVersion = & $engine --version
if ($LASTEXITCODE -ne 0 -or $actualVersion -notmatch '^4\.7\.1\.stable\.official\.') {
    throw 'Downloaded Godot does not report the pinned official version'
}
Write-Output ('Verified Godot: ' + $actualVersion)
