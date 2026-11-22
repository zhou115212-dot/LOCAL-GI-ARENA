[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ClientFolder)
$ErrorActionPreference='Stop'
$dir=(Get-Item -LiteralPath $ClientFolder -ErrorAction Stop)
if(-not $dir.PSIsContainer){throw 'Select the folder containing YuanShen.exe, not a file.'}
$ini=Join-Path $dir.FullName 'config.ini'
if(-not (Test-Path -LiteralPath $ini -PathType Leaf)){throw 'Missing config.ini'}
$v=@(Get-Content -LiteralPath $ini | ForEach-Object {if($_ -match '^\s*game_version\s*=\s*(\S+)\s*$'){$Matches[1]}})
if($v.Count -ne 1 -or $v[0] -ne '7.1.0'){throw 'Expected exactly one game_version=7.1.0 (CN Windows baseline).'}
$bin=Join-Path $dir.FullName 'YuanShen.exe'
if(-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'YuanShen_Data') -PathType Container)){throw 'Missing game data directory.'}
if(-not (Test-Path -LiteralPath $bin -PathType Leaf)){throw 'Missing YuanShen.exe.'}
$stream=[IO.File]::OpenRead($bin);$sha=[Security.Cryptography.SHA256]::Create()
try{$actual=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
if($actual -ne '7F89938DA606C1281659607D464702CDDB9A09A7D4320A196630F60A811EC38E'){throw 'Unrecognized 7.1 executable. No file has been changed or launched.'}
[pscustomobject]@{ClientVersion='7.1.0';KnownExecutable=$true;LocalRoutingVerified=$false;GameLaunched=$false}
