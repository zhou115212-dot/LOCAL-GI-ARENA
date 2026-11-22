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
if ($Action -in @('start','supervise') -and (Test-Path -LiteralPath (Join-Path $Root 'local-edition.json'))) {
    . (Join-Path $PSScriptRoot 'local-edition-check.ps1')
    [void](Test-LocalEdition -Root $Root)
}
$Server = Join-Path $Root 'server'
$StatePath = Join-Path $Root 'run\state.json'
$env:TEMP = Join-Path $Root 'tmp'
$env:TMP = $env:TEMP
$env:GRADLE_USER_HOME = Join-Path $Root 'cache\gradle'
$Paths = Get-Content -LiteralPath (Join-Path $Root 'runtime-paths.json') -Raw | ConvertFrom-Json
$Java = $Paths.java
$Mongod = $Paths.mongod
$env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $Java)
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:JAVA_TOOL_OPTIONS = "-Djava.io.tmpdir=$env:TEMP -Duser.home=$Root\cache\java-home"
$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-State {
    if (Test-Path -LiteralPath $StatePath) {
        return Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
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
    $c = Get-Content -LiteralPath "$Server\config.json" -Raw | ConvertFrom-Json
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
    if (-not $c.server.game.enableConsole) { throw 'Console must stay enabled for graceful stopping.' }
    return $c
}
function Queue-Command([string]$text) {
    if (-not (Game-Process)) { throw 'Server is not running.' }
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Contains("`n") -or $text.Contains("`r")) {
        throw 'Enter one console command per call.'
    }
    $name = (Get-Date -Format 'yyyyMMddHHmmssfff') + '-' + [guid]::NewGuid().ToString() + '.txt'
    [IO.File]::WriteAllText((Join-Path $Root "run\commands\$name"), $text, $Utf8)
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
function Git-Local([string]$repo,[string[]]$arguments) {
    $proxy = [System.Net.WebRequest]::DefaultWebProxy.GetProxy([uri]'https://github.com/').AbsoluteUri
    if ($proxy -ne 'https://github.com/') {
        & $Paths.git -c "http.proxy=$proxy" -c http.version=HTTP/1.1 -C $repo @arguments
    } else { & $Paths.git -C $repo @arguments }
    if ($LASTEXITCODE -ne 0) { throw 'Git command failed.' }
}
switch ($Action) {
    'status' { Show-Status }
    'command' {
        Queue-Command $CommandText
        Write-Host 'Command queued; output below and in server logs.'
        Start-Sleep -Seconds 2
        if (Test-Path "$Server\logs\latest.log") { Get-Content -LiteralPath "$Server\logs\latest.log" -Tail 25 | Out-Host }
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
            try { $status = Http-Status; if (Game-Process) { $ready=$true; break } } catch {}
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
            $game = New-HiddenProcess $Java ('-Xms512m -Xmx8g -Dfile.encoding=UTF-8 -Duser.timezone=Asia/Shanghai -jar "' + $Server + '\grasscutter.jar"') $true
            $state = [ordered]@{
                javaPid=$game.Id; javaStarted=$game.StartTime.ToUniversalTime().Ticks
                mongoPid=$db.Id; mongoStarted=$db.StartTime.ToUniversalTime().Ticks
                supervisorPid=$PID; running=$true
            }
            $state | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8
            $streams = @($game.StandardOutput,$game.StandardError)
            $tasks = @($streams[0].ReadLineAsync(),$streams[1].ReadLineAsync())
            $done = @($false,$false)
            $clientLifecycle=New-LocalClientLifecycle
            $clientPath=Join-Path $Root 'client\Genshin-7.1-CN\YuanShen.exe'
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
                    Get-ChildItem -LiteralPath "$Root\run\commands" -Filter *.txt | Sort-Object Name | ForEach-Object {
                        $text = [IO.File]::ReadAllText($_.FullName, $Utf8).Trim()
                        if ($text -and -not $text.Contains("`n") -and -not $text.Contains("`r")) {
                            $game.StandardInput.WriteLine($text)
                            $game.StandardInput.Flush()
                        }
                        # Command content is archived locally; this may include locally created test passwords.
                        Move-Item -LiteralPath $_.FullName -Destination (Join-Path "$Root\run\processed" $_.Name)
                    }
                    $now=$lifecycleClock.Elapsed.TotalSeconds
                    if ($now -ge $nextClientProbe -and -not $clientLifecycle.StopAttempted) {
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
            if ($db -and -not $db.HasExited) {
                Mongo-Command 'shutdown'
                [void]$db.WaitForExit(30000)
            }
            $s = Read-State
            if ($s -and $s.supervisorPid -eq $PID) { $s.running=$false; $s | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8 }
            $mutex.ReleaseMutex(); $mutex.Dispose()
        }
    }
    'update' {
        $review = [ordered]@{}
        foreach ($name in @('source','server\resources')) {
            $repo = Join-Path $Root $name
            Git-Local $repo @('fetch','origin','main')
            $sha = (& $Paths.git -C $repo rev-parse origin/main).Trim()
            $review[$name]=$sha
            $label=$name.Replace('\','-')
            & $Paths.git -C $repo diff HEAD origin/main | Set-Content -LiteralPath "$Root\audit\update-$label.diff" -Encoding UTF8
            & $Paths.git -C $repo diff HEAD origin/main -- '*.bat' '*.cmd' '*.ps1' '*.sh' '*gradle*' '*.yml' '*.yaml' '*README*' | Set-Content -LiteralPath "$Root\audit\update-$label-scripts.diff" -Encoding UTF8
            & $Paths.git -C $repo log --oneline HEAD..origin/main | Out-Host
        }
        $review | ConvertTo-Json | Set-Content -LiteralPath "$Root\audit\update-reviewed-refs.json" -Encoding UTF8
        Write-Host 'Fetched only; running server unchanged. Read audit\update-*.diff before applying.'
        Write-Host 'After reviewing changed scripts and source, run: update-server.bat apply-reviewed'
    }
    'apply-reviewed' {
        # Binary-local fixes must be migrated/replayed, never silently overwritten by upstream.
        if (@(Get-ChildItem -LiteralPath "$Root\run" -Filter '*-deployed.json').Count -gt 0 -and
                -not (Test-Path -LiteralPath "$Root\run\local-patch-registry.json")) {
            throw 'Local fixes are installed but no tested patch registry is active. Preserve/review them before updating; running server unchanged.'
        }
        # Never interrupt a live test session to update, and never replace or wipe its database.
        $clientStatePath=Join-Path $Root 'run\client-state.json'
        if(Test-Path -LiteralPath $clientStatePath){
            $cs=Get-Content -LiteralPath $clientStatePath -Raw | ConvertFrom-Json
            if(Owned-Process $cs.pid $cs.startedTicks (Join-Path $Root 'client\Genshin-7.1-CN\YuanShen.exe')){throw 'Exit the isolated game before applying updates. Server and saved data are unchanged.'}
        }
        $remoteConstants=& $Paths.git -C "$Root\source" show 'origin/main:src/main/java/emu/grasscutter/GameConstants.java'
        $versionMatch=[regex]::Match(($remoteConstants -join "`n"),'String\s+VERSION\s*=\s*"([^"]+)"')
        if(-not $versionMatch.Success-or $versionMatch.Groups[1].Value -ne '7.1.0'){
            throw 'Upstream requires a different or unrecognized client version. Keep this working 7.1.0 installation and database; review a matching isolated client and patch first.'
        }
        $review = Get-Content -LiteralPath "$Root\audit\update-reviewed-refs.json" -Raw | ConvertFrom-Json
        foreach ($name in @('source','server\resources')) {
            $repo = Join-Path $Root $name
            if ((& $Paths.git -C $repo rev-parse origin/main).Trim() -ne $review.$name) { throw 'Fetched ref differs from reviewed ref; run update again.' }
            $dirty = & $Paths.git -C $repo status --porcelain
            if ($dirty) { throw "Local changes in $repo; preserve and review them first." }
        }
        Stop-LocalServer
        $backup = Join-Path $Root ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $backup | Out-Null
        Copy-Item -LiteralPath "$Server\config.json","$Server\grasscutter.jar" -Destination $backup
        Copy-Item -LiteralPath "$Root\database" -Destination "$backup\database" -Recurse
        foreach ($name in @('source','server\resources')) {
            $repo=Join-Path $Root $name
            (& $Paths.git -C $repo rev-parse HEAD) | Set-Content -LiteralPath "$backup\$($name.Replace('\','-'))-old-commit.txt"
            Git-Local $repo @('pull','--ff-only','origin','main')
            if ((& $Paths.git -C $repo rev-parse HEAD).Trim() -ne $review.$name) { throw 'Remote changed during pull. New source remains stopped; run update and review again.' }
        }
        $proxy = [System.Net.WebRequest]::DefaultWebProxy.GetProxy([uri]'https://plugins.gradle.org/').AbsoluteUri
        $gradleArgs=@('jar','-PskipHandbook=1','-PjarFilename=grasscutter','-Dorg.gradle.jvmargs=-Xmx4g','--no-daemon','--console=plain')
        if ($proxy -ne 'https://plugins.gradle.org/') {
            $pu=[uri]$proxy
            $gradleArgs += @("-Dhttps.proxyHost=$($pu.Host)","-Dhttps.proxyPort=$($pu.Port)","-Dhttp.proxyHost=$($pu.Host)","-Dhttp.proxyPort=$($pu.Port)")
        }
        Push-Location "$Root\source"
        try {
            $oldPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference='Continue'
                # Combine native stdout/stderr inside cmd so Windows PowerShell does not
                # mislabel Java's JAVA_TOOL_OPTIONS notice as a NativeCommandError.
                $quotedArgs = @($gradleArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
                $buildLine = '"' + $Root + '\source\gradlew.bat" ' + $quotedArgs + ' 2>&1'
                & $env:ComSpec /d /c $buildLine | Tee-Object -FilePath "$Root\logs\update-build.log"
                $buildExit=$LASTEXITCODE
            } finally { $ErrorActionPreference=$oldPreference }
            if ($buildExit -ne 0) { throw "Build failed; previous deployed jar retained. Backup: $backup" }
        } finally { Pop-Location }
        $incomingJar = "$Root\source\grasscutter.jar"
        if (Test-Path -LiteralPath "$Root\run\local-patch-registry.json") {
            $patchedJar = "$Root\run\update-with-local-fixes.jar"
            & "$Root\scripts\preserve-local-patches.ps1" -InputJar $incomingJar -OutputJar $patchedJar
            & "$Root\scripts\test-unified-candidate.ps1" -Jar $patchedJar -LogDir "$Root\audit\update-local-fix-regressions"
            $incomingJar = $patchedJar
        }
        Copy-Item -LiteralPath $incomingJar -Destination "$Server\grasscutter.jar" -Force
        foreach ($d in @('data','lua','webstatic')) { Copy-Item -Path "$Root\source\$d\*" -Destination "$Server\$d" -Recurse -Force }
        $upstreamThai = & $Paths.git -C "$Server\resources" ls-files TextMap/TextMapTH.json
        if (-not $upstreamThai -and (Test-Path "$Server\resources\TextMap\TextMapTH_1.json") -and (Test-Path "$Server\resources\TextMap\TextMapTH_2.json")) {
            & $Paths.node "$Root\scripts\merge-textmap.cjs"
            if ($LASTEXITCODE -ne 0) { throw 'Thai map overlay requires review. Server remains stopped.' }
        }
        Write-Host "Updated, still stopped. Backup: $backup. Run start-server.bat to verify."
        if((Test-Path -LiteralPath "$Root\scripts\build-id-catalog.cjs")-and(Test-Path -LiteralPath "$Root\name-data\src\data\ChineseSimplified\characters")){
            & $Paths.node "$Root\scripts\build-id-catalog.cjs"
            if($LASTEXITCODE -ne 0){throw 'Server update deployed, but the local ID catalog needs repair before using missing-content grants. Backup is retained.'}
        }
        if(Test-Path -LiteralPath "$Root\scripts\build-local-test-tools.ps1"){
            & "$Root\scripts\build-local-test-tools.ps1"
            if($LASTEXITCODE -ne 0){throw 'Updated server remains stopped; rebuild LocalTestTools before using editor commands.'}
        }
    }
}
