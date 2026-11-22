param([Parameter(Mandatory=$true)][string]$RequestId,[Parameter(Mandatory=$true)][int]$ItemId,[int]$Level=90,[int]$Refinement=1,[int]$Quantity=1,[switch]$PlanOnly)
# Adds only requested copies via the local server; verifier never writes MongoDB.
# No client, service, registry, network or system configuration changes.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$root=Split-Path -Parent $PSScriptRoot
if($root -ne 'E:\Genshin-Local-Server' -or $RequestId -notmatch '^[a-f0-9]{32}$'){throw 'Unexpected root or request ID'}
$env:TEMP="$root\tmp";$env:TMP=$env:TEMP;$env:JAVA_TOOL_OPTIONS=$null
$paths=Get-Content -LiteralPath "$root\runtime-paths.json" -Raw|ConvertFrom-Json
if(!$PlanOnly){$state=Get-Content -LiteralPath "$root\run\state.json" -Raw|ConvertFrom-Json;$p=Get-Process -Id $state.javaPid -ErrorAction SilentlyContinue;if(!$p -or $p.Path -ne $paths.java -or $p.StartTime.ToUniversalTime().Ticks -ne [long]$state.javaStarted){throw 'Local server is not running'}}
$arguments=@("-Djava.io.tmpdir=$root\tmp","-Duser.home=$root\cache\java-home",'-Dfile.encoding=UTF-8','-Dstdout.encoding=UTF-8','-Dstderr.encoding=UTF-8','-cp',"$root\server\grasscutter.jar;$root\scripts\classes",'WeaponGrant',$root,$RequestId,$ItemId,$Level,$Refinement,$Quantity)
if($PlanOnly){$arguments+='plan'}
& $paths.java @arguments
if($LASTEXITCODE -ne 0){throw 'Weapon copies were not fully confirmed; inspect the request audit before repeating'}
