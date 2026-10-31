$ErrorActionPreference = 'Stop'
if (Get-Process -Name left4dead2 -ErrorAction SilentlyContinue) { throw 'Close Left 4 Dead 2 first.' }
$recordPath = Join-Path $PSScriptRoot 'backups\last-install.json'
if (-not (Test-Path -LiteralPath $recordPath)) { throw 'No installer backup record found.' }
$record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json
if (-not $record.backup -or -not (Test-Path -LiteralPath $record.backup)) { throw 'No previous package exists to restore. Disable Trail Pet in the game Add-ons menu instead.' }
if ([IO.Path]::GetFileName($record.target) -ne 'pet_companion.vpk') { throw 'Unexpected restore target.' }
if ((Get-FileHash -LiteralPath $record.target).Hash -ne $record.installedHash) { throw 'The installed package changed since installation. Refusing to overwrite it.' }
Copy-Item -LiteralPath $record.backup -Destination $record.target -Force
if ((Get-FileHash -LiteralPath $record.backup).Hash -ne (Get-FileHash -LiteralPath $record.target).Hash) { throw 'Restore verification failed.' }
Write-Output 'Previous pet_companion.vpk restored and verified.'
