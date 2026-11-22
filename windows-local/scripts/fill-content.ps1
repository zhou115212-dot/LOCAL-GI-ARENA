param([Parameter(Mandatory=$true)][ValidateSet('fill-all','fill-weapons','fill-missing')][string]$Action)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'controller-install.ps1')
$root=Split-Path -Parent $PSScriptRoot
$paths=[IO.File]::ReadAllText((Join-Path $root 'runtime-paths.json'))|ConvertFrom-Json
$java=Get-ArenaExecutable $root $paths.java java
Assert-ArenaServerPid $root $java
$null=Read-ArenaUid $root
$kind=@{'fill-missing'='avatars';'fill-weapons'='weapons';'fill-all'='all'}[$Action]
& $java "-Djava.io.tmpdir=$root\tmp" "-Duser.home=$root\cache\java-home" -cp "$root\scripts\classes;$root\server\grasscutter.jar" MissingContent $root $kind grant
if($LASTEXITCODE -ne 0){throw 'Grant incomplete; check the request log before retrying.'}
