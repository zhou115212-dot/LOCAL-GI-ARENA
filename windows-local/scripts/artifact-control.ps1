param([Parameter(Mandatory=$true)][string]$RequestId,[switch]$PlanOnly)
# Read-only validation/Mongo confirmation; actual grants go through server stdin.
# No client/registry/service/security/network configuration changes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'controller-install.ps1')
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$Root=Split-Path -Parent $PSScriptRoot
$env:TEMP="$Root\tmp";$env:TMP=$env:TEMP;$env:JAVA_TOOL_OPTIONS=$null
if($RequestId -notmatch '^[a-f0-9]{32}$'){throw 'Invalid artifact request token.'}
$paths=Get-Content -Encoding UTF8 -LiteralPath "$Root\runtime-paths.json" -Raw | ConvertFrom-Json
$paths.java=Get-ArenaExecutable $root $paths.java java
if(-not $PlanOnly){
    $state=Get-Content -Encoding UTF8 -LiteralPath "$Root\run\state.json" -Raw | ConvertFrom-Json
    $p=Get-Process -Id $state.javaPid -ErrorAction SilentlyContinue
    if(-not $p -or $p.Path -ne $paths.java -or $p.StartTime.ToUniversalTime().Ticks -ne [long]$state.javaStarted){throw 'The local server is not running.'}
}
$arguments=@("-Djava.io.tmpdir=$Root\tmp","-Duser.home=$Root\cache\java-home",'-cp',"$Root\server\grasscutter.jar;$Root\scripts\classes",'ArtifactGrant',$Root,$RequestId)
if($PlanOnly){$arguments+='plan'}
& $paths.java @arguments
if($LASTEXITCODE -ne 0){throw 'Artifact request was not confirmed. Inspect the detailed error/audit before repeating.'}
