param([string]$GameDirectory = '')
$ErrorActionPreference = 'Stop'
if (-not $GameDirectory) {
    $steam = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam').SteamPath
    $GameDirectory = Join-Path $steam 'steamapps\common\Left 4 Dead 2'
}
$vpk = Join-Path $GameDirectory 'bin\vpk.exe'
if (-not (Test-Path -LiteralPath $vpk)) { throw 'L4D2 vpk.exe not found.' }
$source = Join-Path $PSScriptRoot 'pet_companion_src'
& $vpk $source
if ($LASTEXITCODE -ne 0) { throw 'vpk.exe failed.' }
$built = Join-Path $PSScriptRoot 'pet_companion_src.vpk'
Copy-Item -LiteralPath $built -Destination (Join-Path $PSScriptRoot 'pet_companion.vpk') -Force
Write-Output 'Build finished. Use Install.ps1 only after closing the game.'
