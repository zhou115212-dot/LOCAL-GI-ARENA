# Read-only runtime acceptance. Never starts/stops a process or prints an account, secret or log line.
[CmdletBinding()]
param([string]$InstallRoot,[string]$ExpectedVersion='7.1.0',[switch]$RequirePlugins,[switch]$Stopped,[switch]$Json)
$ErrorActionPreference='Stop'
if($InstallRoot){$root=(Get-Item -LiteralPath $InstallRoot -ErrorAction Stop).FullName}else{$root=Split-Path -Parent $PSScriptRoot}
function Read-Json($p){Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $root $p)|ConvertFrom-Json}
function Must($ok,$message){if(-not $ok){throw "Health check failed: $message"}}
function Matches-Start($p,$ticks,$exe){
    if(-not $p){return $false}
    return $p.Path -ieq $exe -and $p.StartTime.ToUniversalTime().Ticks -eq [long]$ticks
}
$paths=Read-Json 'runtime-paths.json'
Must (Test-Path -LiteralPath "$root/run/state.json" -PathType Leaf) 'no previous server session recorded'
$state=Read-Json 'run/state.json'
$java=Get-Process -Id $state.javaPid -ErrorAction SilentlyContinue
$db=Get-Process -Id $state.mongoPid -ErrorAction SilentlyContinue
$javaMatches=Matches-Start $java $state.javaStarted $paths.java
$dbMatches=Matches-Start $db $state.mongoStarted $paths.mongod
$tcp=@(Get-NetTCPConnection -State Listen)
$udp=@(Get-NetUDPEndpoint)
if($Stopped){
    Must (-not $javaMatches -and -not $dbMatches) 'Java or database from this session is still running'
    Must (-not $state.running) 'supervisor did not finish marking this session stopped'
    Must (-not @($tcp|Where-Object {$_.LocalPort -in @(8088,27018)}).Count -and -not @($udp|Where-Object {$_.LocalPort -eq 22101}).Count) 'one or more local ports are still occupied'
    $report=[ordered]@{result='stopped';recordedJavaExited=$true;recordedMongoExited=$true;portsReleased=$true}
}else{
    Must ($state.running -and $javaMatches -and $dbMatches) 'recorded Java/Mongo executable or creation time does not match a live process'
    $supervisor=Get-Process -Id $state.supervisorPid -ErrorAction SilentlyContinue
    Must ([bool]$supervisor) 'supervisor is not running'
    if($state.supervisorStarted){
        Must ($supervisor.StartTime.ToUniversalTime().Ticks -eq [long]$state.supervisorStarted) 'supervisor creation time differs'
    }
    $jHttp=@($tcp | Where-Object {$_.LocalPort -eq 8088})
    $mTcp=@($tcp | Where-Object {$_.LocalPort -eq 27018})
    $jUdp=@($udp | Where-Object {$_.LocalPort -eq 22101})
    foreach($item in @(@($jHttp,$java.Id),@($mTcp,$db.Id),@($jUdp,$java.Id))){
        $rows=@($item[0]);Must ($rows.Count -eq 1 -and $rows[0].LocalAddress -eq '127.0.0.1' -and $rows[0].OwningProcess -eq $item[1]) 'missing or unexpected interface/owner on a required port'
    }
    # Extra listening TCP endpoints, including wildcard sockets on other ports, must be local.
    $foreign=@($tcp|Where-Object {$_.OwningProcess -in @($db.Id,$java.Id) -and $_.LocalAddress -notin @('127.0.0.1','::1')})
    Must ($foreign.Count -eq 0) 'server or database also has a non-loopback TCP listener'
    $req=[Net.HttpWebRequest]::Create('http://127.0.0.1:8088/api/status')
    $req.Proxy=$null;$req.AllowAutoRedirect=$false;$req.Timeout=5000
    $response=$req.GetResponse()
    try{
        Must ([int]$response.StatusCode -eq 200) 'non-success HTTP status'
        $reader=New-Object IO.StreamReader($response.GetResponseStream())
        try{$health=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
    }finally{$response.Dispose()}
    Must ($null -ne $health.game -and $null -ne $health.game.players -and $null -ne $health.retcode -and $health.retcode -eq 0) 'application status response was incomplete'
    if($ExpectedVersion){Must ($health.game.gameVersion -ceq $ExpectedVersion) 'application game version does not match expected baseline'}
    # Ping through the local installation's driver. Its output is not published.
    & $paths.java -cp "$root/server/grasscutter.jar;$root/scripts/classes" MongoControl ready "$root/scripts/mongo-logback.xml" | Out-Null
    Must ($LASTEXITCODE -eq 0) 'MongoDB driver ping failed'
    if($RequirePlugins){
        $tool=Read-Json 'run/local-test-tools-ready.json'
        $diag=Read-Json 'run/local-energy-diagnostics-ready.json'
        $difference=[math]::Abs(([DateTimeOffset]$tool.started).UtcDateTime.Subtract($java.StartTime.ToUniversalTime()).TotalSeconds)
        $hash=(Get-FileHash -LiteralPath "$root/server/plugins/LocalTestTools.jar" -Algorithm SHA256).Hash
        Must ($tool.pid -eq $java.Id -and $difference -le 1 -and $tool.jarHash -ieq $hash) 'editor readiness does not match the live JVM and installed plugin'
        Must ($diag.pid -eq $java.Id -and $diag.readOnly -and ((Get-Item -LiteralPath "$root/run/local-energy-diagnostics-ready.json").LastWriteTimeUtc -ge $java.StartTime.ToUniversalTime())) 'diagnostic readiness is stale'
    }
    $report=[ordered]@{result='running';version=$health.game.gameVersion;onlineCount=$health.game.players;databasePing=$true;loopbackHttp=$true;loopbackGameUdp=$true;loopbackDb=$true;pluginsChecked=[bool]$RequirePlugins}
}
if($Json){$report|ConvertTo-Json -Compress}else{[pscustomobject]$report}
