param([string]$GameDirectory = '')
$ErrorActionPreference = 'Stop'
if (Get-Process -Name left4dead2 -ErrorAction SilentlyContinue) {
    throw 'Close Left 4 Dead 2 before installing, then run this script again.'
}
if (-not $GameDirectory) {
    $steam = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam').SteamPath
    $GameDirectory = Join-Path $steam 'steamapps\common\Left 4 Dead 2'
}
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $game 'left4dead2.exe'))) { throw 'Not a Left 4 Dead 2 installation.' }
$addons = Join-Path $game 'left4dead2\addons'
if (-not (Test-Path -LiteralPath $addons -PathType Container)) { throw 'Addons directory missing.' }
$source = Join-Path $PSScriptRoot 'pet_companion.vpk'
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'pet_companion.vpk missing next to this installer.' }
$target = Join-Path $addons 'pet_companion.vpk'
$expected = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $expected) {
    Write-Output 'This exact package is already installed.'
    exit 0
}
$backupDirectory = Join-Path $PSScriptRoot 'backups'
New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$backup = $null
if (Test-Path -LiteralPath $target) {
    $backup = Join-Path $backupDirectory ('pet_companion-before-' + $stamp + '.vpk')
    Copy-Item -LiteralPath $target -Destination $backup
    if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $backup).Hash) { throw 'Backup verification failed.' }
}
$record = @{ target = $target; backup = $backup; installedHash = $expected; installedAt = $stamp }
$record | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDirectory 'last-install.json') -Encoding UTF8
Copy-Item -LiteralPath $source -Destination $target -Force
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $expected) { throw 'Installed package hash mismatch.' }
Write-Output ('Installed and verified: ' + $target)
Write-Output ('Previous version backup: ' + $backup)
Write-Output 'Start a new single-player or LOCAL SERVER campaign. Chat: !pet status'
Write-Output 'No sv_cheats or script_execute is required for normal automatic loading.'
