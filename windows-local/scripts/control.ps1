param(
    [ValidateSet('start','supervise','stop','status','command','update','apply-reviewed')]
    [string]$Action = 'status',
    [string]$CommandText = ''
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if ($Action -in @('update','apply-reviewed') -and (Test-Path -LiteralPath (Join-Path $Root 'local-edition.json'))) {
    throw '[LOCAL_EDITION_LOCK] This installation is pinned to its local version. Fetch, pull, build and update deployment were not started.'
}
if ((Test-Path -LiteralPath (Join-Path $Root 'local-edition.json'))) {
    throw 'Use this portable launcher only in a separate initialized installation.'
}
$Server = Join-Path $Root 'server'
$StatePath = Join-Path $Root 'run\state.json'
$env:TEMP = Join-Path $Root 'tmp'
$env:TMP = $env:TEMP
$env:GRADLE_USER_HOME = Join-Path $Root 'cache\gradle'
$Paths = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $Root 'runtime-paths.json') -Raw | ConvertFrom-Json
$Java = $Paths.java
$Mongod = $Paths.mongod
$env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $Java)
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:_JAVA_OPTIONS=$null; $env:JDK_JAVA_OPTIONS=$null
$env:JAVA_TOOL_OPTIONS = '"-Djava.io.tmpdir='+$env:TEMP+'" "-Duser.home='+$Root+'\cache\java-home"'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-State {
    if (Test-Path -LiteralPath $StatePath) {
        return Get-Content -Encoding UTF8 -LiteralPath $StatePath -Raw | ConvertFrom-Json
    }
    return $null
}
function Owned-Process($idNumber, $started, $executable) {
    if (-not $idNumber) { return $null }
    $p = Get-Process -Id $idNumber -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    try {
        if ($p.Path -ne $executable) { return $null }
        if ($p.StartTime.ToUniversalTime().Ticks -ne [long]$started) { return $null }
    } catch { return $null }
    return $p
}
function Game-Process {
    $s = Read-State
    if ($s) { return Owned-Process $s.javaPid $s.javaStarted $Java }
    return $null
}
function Http-Status {
    $req = [System.Net.WebRequest]::Create('http://127.0.0.1:8088/api/status')
    $req.Proxy = $null
    $req.Timeout = 3000
    $response = $req.GetResponse()
    try {
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
}
function Validate-LocalConfig {
    $c = Get-Content -Encoding UTF8 -LiteralPath "$Server\config.json" -Raw | ConvertFrom-Json
    if ($c.server.http.bindAddress -ne '127.0.0.1' -or $c.server.game.bindAddress -ne '127.0.0.1') {
        throw 'Localhost-only binding is required by this installation.'
    }
    if ($c.server.http.accessAddress -ne '127.0.0.1' -or $c.server.game.accessAddress -ne '127.0.0.1') {
        throw 'Localhost-only advertised addresses are required.'
    }
    if ($c.server.http.bindPort -ne 8088 -or $c.server.game.bindPort -ne 22101) { throw 'Unexpected server ports.' }
    foreach ($db in @($c.databaseInfo.server,$c.databaseInfo.game)) {
        if ($db.connectionUri -ne 'mongodb://127.0.0.1:27018' -or $db.collection -ne 'astaps_local') {
            throw 'Unexpected database endpoint or database name.'
        }
    }
    if ($c.version -ne 15 -or $c.server.runMode -ne 'HYBRID' -or $c.server.http.encryption.useEncryption -or $c.server.http.encryption.useInRouting -or $c.server.dispatch.regions.Count -gt 0 -or $c.server.dispatch.dispatchUrl -ne 'ws://127.0.0.1:1111') {throw 'Unexpected run mode, configuration version or remote routing.'}
    if ($c.server.http.accessPort -ne 8088 -or $c.server.game.accessPort -ne 22101) {throw 'Unexpected advertised ports.'}
    if (-not $c.server.game.enableConsole) { throw 'Console must stay enabled for graceful stopping.' }
    return $c
}
function Queue-Command([string]$text) {
    if (-not (Game-Process)) { throw 'Server is not running.' }
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Contains("`n") -or $text.Contains("`r")) {
        throw 'Enter one console command per call.'
    }
    $name = (Get-Date -Format 'yyyyMMddHHmmssfff') + '-' + [guid]::NewGuid().ToString() + '.txt'
    $target=Join-Path $Root "run\commands\$name"
    $secretCmd=($text -match '^(?:/?account\s+(?:create|resetpass)|/?(?:stop|shutdown))\s')
    if($secretCmd){$target=[IO.Path]::ChangeExtension($target,'sealed');$text=ConvertFrom-SecureString (ConvertTo-SecureString $text -AsPlainText -Force)}
    [IO.File]::WriteAllText($target+'.tmp', $text, $Utf8); [IO.File]::Move($target+'.tmp',$target)
}
function New-HiddenProcess([string]$exe,[string]$arguments,[bool]$redirect) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $exe
    $info.Arguments = $arguments
    $info.WorkingDirectory = $Server
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardInput = $redirect
    $info.RedirectStandardOutput = $redirect
    $info.RedirectStandardError = $redirect
    if ($redirect) {
        $info.StandardOutputEncoding = $Utf8
        $info.StandardErrorEncoding = $Utf8
    }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $info
    [void]$p.Start()
    return $p
}
function Mongo-Command([string]$mode) {
    & $Java '-cp' "$Server\grasscutter.jar;$Root\scripts\classes" MongoControl $mode "$Root\scripts\mongo-logback.xml"
    if ($LASTEXITCODE -ne 0) { throw "MongoDB $mode failed." }
}
function Show-Status {
    $s = Read-State
    $p = Game-Process
    if ($p) { Write-Host "AstaPS RUNNING PID=$($p.Id)" } else { Write-Host 'AstaPS STOPPED' }
    if ($s) {
        $db = Owned-Process $s.mongoPid $s.mongoStarted $Mongod
        if ($db) { Write-Host "MongoDB RUNNING PID=$($db.Id)" } else { Write-Host 'MongoDB STOPPED' }
        $ids = @($s.javaPid,$s.mongoPid)
        Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.OwningProcess -in $ids } |
            Select-Object LocalAddress,LocalPort,OwningProcess | Format-Table | Out-Host
        Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
            Where-Object { $_.OwningProcess -in $ids } |
            Select-Object LocalAddress,LocalPort,OwningProcess | Format-Table | Out-Host
        if ($p) { try { Write-Host (Http-Status) } catch { Write-Host 'HTTP status is not ready.' } }
    }
    Write-Host "Log: $Server\logs\latest.log"
}
function Stop-LocalServer {
    $s = Read-State
    $p = Game-Process
    if ($p) {
        $c = Validate-LocalConfig
        Queue-Command ("stop " + $c.server.http.encryption.keystorePassword)
        if (-not $p.WaitForExit(60000)) { throw 'Graceful stop timed out. Check logs; no unrelated process was killed.' }
    }
    if ($s) {
        $db = Owned-Process $s.mongoPid $s.mongoStarted $Mongod
        if ($db) {
            # The supervisor normally shuts MongoDB down after the game process exits.
            if (-not $db.WaitForExit(15000)) { Mongo-Command 'shutdown' }
            if (-not $db.WaitForExit(30000)) { throw 'MongoDB is still stopping. Check its log before backup.' }
        }
    }
    Write-Host 'Local server and its MongoDB are stopped.'
}
switch ($Action) {
    'status' { Show-Status }
    'command' {
        Queue-Command $CommandText
        Write-Host 'Command queued; output below and in server logs.'
        Start-Sleep -Seconds 2
        if (Test-Path "$Server\logs\latest.log") { Get-Content -Encoding UTF8 -LiteralPath "$Server\logs\latest.log" -Tail 25 | Out-Host }
    }
    'stop' { Stop-LocalServer }
    'start' {
        if (Game-Process) { Show-Status; break }
        [void](Validate-LocalConfig)
        $shell = (Get-Process -Id $PID).Path
        $a = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -Action supervise'
        # Detach the long-lived supervisor from the caller's output pipes.
        # Redirect inside the new console so logs still have separate stdout/stderr.
        if (($shell + $Root + $PSCommandPath) -match '["%\r\n]') { throw 'Unsupported character in supervisor path.' }
        $si = New-Object System.Diagnostics.ProcessStartInfo
        $si.FileName = [IO.Path]::Combine([Environment]::SystemDirectory, 'cmd.exe')
        $si.Arguments = '/d /v:off /s /c ""' + $shell + '" ' + $a + ' 1>"' + $Root + '\logs\supervisor.out.log" 2>"' + $Root + '\logs\supervisor.err.log""'
        $si.WorkingDirectory = $Root
        $si.UseShellExecute = $true
        $si.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $hostProcess = [Diagnostics.Process]::Start($si)
        $ready = $false
        for ($i=0; $i -lt 300; $i++) {
            if ($hostProcess.HasExited) { throw "Startup stopped. Read $Root\logs\supervisor.err.log and $Server\logs\latest.log" }
            try {
                $proc=Game-Process
                if ($proc) {
                    $httpOwner=@(Get-NetTCPConnection -LocalAddress '127.0.0.1' -LocalPort 8088 -State Listen -OwningProcess $proc.Id -ErrorAction SilentlyContinue)
                    $udpOwner=@(Get-NetUDPEndpoint -LocalAddress '127.0.0.1' -LocalPort 22101 -OwningProcess $proc.Id -ErrorAction SilentlyContinue)
                    if($httpOwner.Count -and $udpOwner.Count -and ((Http-Status |ConvertFrom-Json).game -ne $null)){ $ready=$true;break }
                }
            } catch {}
            Start-Sleep -Seconds 1
        }
        if (-not $ready) { throw 'Startup is still in progress; inspect logs. No process has been force-stopped.' }
        Show-Status
    }
    'supervise' {
        . (Join-Path $PSScriptRoot 'local-client-lifecycle.ps1')
        $mutex = New-Object System.Threading.Mutex($false, 'Local\AstaPS-E-Localhost')
        if (-not $mutex.WaitOne(0)) { throw 'Another supervisor is active.' }
        $db = $null; $game = $null
        try {
            [void](Validate-LocalConfig)
            $occupied = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -in @(27018,8088) })
            $udp = @(Get-NetUDPEndpoint -ErrorAction SilentlyContinue | Where-Object { $_.LocalPort -eq 22101 })
            if ($occupied.Count -or $udp.Count) { throw 'An installation port is occupied. Existing processes were left untouched.' }
            # Never replay sensitive queued commands after a restart.
            Get-ChildItem -LiteralPath "$Root\run\commands" -Filter '*.sealed' -File | ForEach-Object {Remove-Item -LiteralPath $_.FullName}
            # Archive unconsumed commands from any previous session; never replay stale commands.
            Get-ChildItem -LiteralPath "$Root\run\commands" -Filter *.txt | ForEach-Object {
                Move-Item -LiteralPath $_.FullName -Destination (Join-Path "$Root\run\processed" ('stale-' + $_.Name))
            }
            $dbArgs = '--bind_ip 127.0.0.1 --port 27018 --dbpath "' + $Root + '\database\data" --logpath "' + $Root + '\logs\mongodb.log" --logappend --wiredTigerCacheSizeGB 1'
            $db = New-HiddenProcess $Mongod $dbArgs $false
            $connected = $false
            for ($i=0; $i -lt 60; $i++) {
                if ($db.HasExited) { throw 'MongoDB exited; inspect mongodb.log.' }
                $tcp = New-Object System.Net.Sockets.TcpClient
                try { $tcp.Connect('127.0.0.1',27018); $connected=$true; break } catch { Start-Sleep -Seconds 1 } finally { $tcp.Dispose() }
            }
            if (-not $connected) { throw 'MongoDB startup timed out.' }
            Mongo-Command 'ping'
            $game = New-HiddenProcess $Java ('-Xms512m -Xmx8g -Djava.net.preferIPv4Stack=true -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai -jar "' + $Server + '\grasscutter.jar"') $true
            $state = [ordered]@{
                javaPid=$game.Id; javaStarted=$game.StartTime.ToUniversalTime().Ticks
                mongoPid=$db.Id; mongoStarted=$db.StartTime.ToUniversalTime().Ticks
                supervisorPid=$PID; supervisorStarted=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks; running=$true
            }
            $state | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8
            $streams = @($game.StandardOutput,$game.StandardError)
            $tasks = @($streams[0].ReadLineAsync(),$streams[1].ReadLineAsync())
            $done = @($false,$false)
            $clientLifecycle=New-LocalClientLifecycle
            $clientPath=$null
            $selection=Join-Path $Root 'run/client-selection.json'
            if(Test-Path -LiteralPath $selection){ $clientPath=(Get-Content -Encoding UTF8 -Raw -LiteralPath $selection|ConvertFrom-Json).executable }
            $lifecycleClock=[Diagnostics.Stopwatch]::StartNew()
            $nextClientProbe=0.0
            $autoStopAt=$null
            $autoStopTimeoutLogged=$false
            while (-not $game.HasExited -or -not ($done[0] -and $done[1])) {
                for ($n=0; $n -lt 2; $n++) {
                    for ($j=0; $j -lt 500 -and -not $done[$n] -and $tasks[$n].IsCompleted; $j++) {
                        $line = $tasks[$n].GetAwaiter().GetResult()
                        if ($null -eq $line) { $done[$n]=$true; break }
                        [IO.File]::AppendAllText("$Root\logs\console.log", $line + [Environment]::NewLine, $Utf8)
                        $tasks[$n] = $streams[$n].ReadLineAsync()
                    }
                }
                if (-not $game.HasExited) {
                    Get-ChildItem -LiteralPath "$Root\run\commands" -File | Where-Object {$_.Extension -in '.txt','.sealed'} | Sort-Object Name | ForEach-Object {
                        $text = [IO.File]::ReadAllText($_.FullName, $Utf8).Trim()
                        if($_.Extension -eq '.sealed'){
                            $secure=ConvertTo-SecureString $text
                            try{$text=([System.Net.NetworkCredential]::new('',$secure)).Password}finally{$secure.Dispose()}
                        }
                        if ($text -and -not $text.Contains("`n") -and -not $text.Contains("`r")) {
                            $game.StandardInput.WriteLine($text)
                            $game.StandardInput.Flush()
                        }
                        if($_.Extension -eq '.sealed' -or $text -match '^(?:/?account\s+(?:create|resetpass)|/?(?:stop|shutdown))\s'){
                            Remove-Item -LiteralPath $_.FullName
                        }else{Move-Item -LiteralPath $_.FullName -Destination (Join-Path "$Root\run\processed" $_.Name)}
                    }
                    $now=$lifecycleClock.Elapsed.TotalSeconds
                    if ($clientPath -and $now -ge $nextClientProbe -and -not $clientLifecycle.StopAttempted) {
                        $nextClientProbe=$now+2
                        $presence=Get-IsolatedClientPresence -ExpectedPath $clientPath
                        if (Update-LocalClientLifecycle -State $clientLifecycle -ClientPresent $presence.Present -ProbeSucceeded $presence.Succeeded -NowSeconds $now -GraceSeconds 30) {
                            # Recheck immediately before requesting a graceful save-and-stop.
                            $presence=Get-IsolatedClientPresence -ExpectedPath $clientPath
                            if (Update-LocalClientLifecycle -State $clientLifecycle -ClientPresent $presence.Present -ProbeSucceeded $presence.Succeeded -NowSeconds $now -GraceSeconds 30) {
                                $clientLifecycle.StopAttempted=$true
                                try {
                                    $stopConfig=Validate-LocalConfig
                                    $game.StandardInput.WriteLine('stop '+$stopConfig.server.http.encryption.keystorePassword)
                                    $game.StandardInput.Flush()
                                    $autoStopAt=$now
                                    [IO.File]::AppendAllText("$Root\logs\console.log", '[Local lifecycle] Isolated client absent for 30 seconds; graceful server stop requested. MongoDB stops after server exit.'+[Environment]::NewLine,$Utf8)
                                } catch {
                                    [IO.File]::AppendAllText("$Root\logs\console.log", '[Local lifecycle] Graceful stop request failed; processes left running. Use the manual stop script.'+[Environment]::NewLine,$Utf8)
                                }
                            }
                        }
                    }
                    if ($null -ne $autoStopAt -and $now-$autoStopAt -ge 60 -and -not $autoStopTimeoutLogged) {
                        $autoStopTimeoutLogged=$true
                        [IO.File]::AppendAllText("$Root\logs\console.log", '[Local lifecycle] Server shutdown is taking over 60 seconds; no force-kill and no premature database shutdown.'+[Environment]::NewLine,$Utf8)
                    }
                }
                Start-Sleep -Milliseconds 100
            }
            Write-Host "AstaPS exited: $($game.ExitCode)"
        } finally {
            if ($db -and -not $db.HasExited -and (-not $game -or $game.HasExited)) {
                Mongo-Command 'shutdown'
                [void]$db.WaitForExit(30000)
            }
            $s = Read-State
            if ($s -and $s.supervisorPid -eq $PID) { $s.running=$false; $s | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8 }
            $mutex.ReleaseMutex(); $mutex.Dispose()
        }
    }
    default { throw 'This edition is pinned. Install updates in a separate directory and back up your local save before migrating.' }
}
