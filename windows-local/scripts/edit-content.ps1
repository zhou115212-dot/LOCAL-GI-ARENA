param(
    [ValidateSet('avatar','weapon','restore')][string]$Kind='avatar',
    [string]$Selector='stars4',
    [int]$Level=6,
    [switch]$PlanOnly
)
# Uses existing server stdin command queue and plugin receipt. No direct database writes,
# system settings, registry, services, networking changes or client modification.
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
$Root=Split-Path -Parent $PSScriptRoot
$env:TEMP="$Root\tmp";$env:TMP=$env:TEMP
# Windows PowerShell launched by a .NET GUI may inherit another PowerShell edition's
# module search path. Hash with framework APIs instead of an auto-loaded function.
# This does not change any system environment variable or install/modify modules.
function File-Sha256([string]$Path){
    $algorithm=[Security.Cryptography.SHA256]::Create()
    $stream=[IO.File]::OpenRead($Path)
    try{return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}
    finally{$stream.Dispose();$algorithm.Dispose()}
}
$state=Get-Content -LiteralPath "$Root\run\state.json" -Raw | ConvertFrom-Json
$paths=Get-Content -LiteralPath "$Root\runtime-paths.json" -Raw | ConvertFrom-Json
$p=Get-Process -Id $state.javaPid -ErrorAction SilentlyContinue
if(-not $p -or $p.Path -ne $paths.java -or $p.StartTime.ToUniversalTime().Ticks -ne [long]$state.javaStarted){throw 'The local server is not running.'}
if(-not(Test-Path -LiteralPath "$Root\run\local-test-tools-ready.json")){throw 'Restart the local server once to enable LocalTestTools.'}
$ready=Get-Content -LiteralPath "$Root\run\local-test-tools-ready.json" -Raw | ConvertFrom-Json
if($ready.pid -ne $p.Id -or [math]::Abs(([datetimeoffset]$ready.started).UtcDateTime.Subtract($p.StartTime.ToUniversalTime()).TotalSeconds) -gt 1 -or $ready.jarHash -ne (File-Sha256 "$Root\server\plugins\LocalTestTools.jar")){throw 'Restart the local server to load the current LocalTestTools build.'}
if($Kind -eq 'restore'){
    if($Selector -eq 'last'){
        if(-not(Test-Path -LiteralPath "$Root\run\last-edit.json")){throw 'No successful change is available to undo.'}
        $Selector=(Get-Content -LiteralPath "$Root\run\last-edit.json" -Raw | ConvertFrom-Json).backup
    }
    if($Selector -notmatch '^[a-f0-9]{32}$'){throw 'Unexpected backup token.'}
    if(-not(Test-Path -LiteralPath "$Root\backups\edits\$Selector.json")){throw 'Backup is missing.'}
}else{
    if($Selector -notmatch '^(all|stars4|stars5|[0-9]{1,9}(,[0-9]{1,9}){0,399})$'){throw 'Unexpected selector.'}
    if(($Kind -eq 'avatar' -and ($Level -lt 0 -or $Level -gt 6)) -or ($Kind -eq 'weapon' -and ($Level -lt 1 -or $Level -gt 5))){throw 'Expected constellation0..6 or refinement1..5.'}
}
$request=[guid]::NewGuid().ToString('N')
$verb=@{avatar='localconst';weapon='localrefine';restore='localundo'}[$Kind]
$command=if($Kind -eq 'restore'){"$verb @10001 $Selector $request"}else{"$verb @10001 $Selector $Level $request"}
if($PlanOnly){Write-Output $command;return}
$req=[Net.WebRequest]::Create('http://127.0.0.1:8088/api/status');$req.Proxy=$null;$req.Timeout=3000
$response=$req.GetResponse()
try{$reader=New-Object IO.StreamReader($response.GetResponseStream());try{$health=$reader.ReadToEnd() | ConvertFrom-Json}finally{$reader.Dispose()}}finally{$response.Dispose()}
if($health.game.players -lt 1){throw 'Enter the world with localtest UID10001 before editing. No command was queued.'}
$lock=[IO.File]::Open("$Root\run\content-sync.lock",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    # Use the supervisor's existing stdin queue, just like MissingContent.java.
    # The interactive console wrapper writes log tails directly to the host;
    # avoiding that wrapper keeps GUI stdout to exactly one JSON receipt.
    $pending="$Root\run\commands\$request.tmp"
    $queued="$Root\run\commands\$request.txt"
    [IO.File]::WriteAllText($pending,$command,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::Move($pending,$queued)
    $resultPath="$Root\run\edit-results\$request.json"
    $until=[datetime]::UtcNow.AddSeconds(90)
    while(-not(Test-Path -LiteralPath $resultPath)){
        if([datetime]::UtcNow -gt $until){throw 'No server receipt yet. Do not repeat immediately; check logs and whether UID10001 is in the world.'}
        Start-Sleep -Milliseconds 150
    }
    $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if(-not $result.ok){throw $result.error}
    # The server saves asynchronously. Check the persisted values and retained levels/equipment
    # before calling the UI operation complete. The verifier performs Mongo reads only.
    $env:JAVA_TOOL_OPTIONS=$null
    $saved=& $paths.java "-Djava.io.tmpdir=$Root\tmp" "-Duser.home=$Root\cache\java-home" -cp "$Root\server\grasscutter.jar;$Root\scripts\classes" EditSaveCheck $Root $request
    if($LASTEXITCODE -ne 0){throw 'The server edit was acknowledged but its saved state is not confirmed. Inspect logs/backups before repeating.'}
    $result=$saved | ConvertFrom-Json
    if($result.backup){[IO.File]::WriteAllText("$Root\run\last-edit.json",($result | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))}
    $result | ConvertTo-Json -Depth 5 -Compress | Write-Output
}finally{$lock.Dispose()}
