# Set up *this extracted directory* only. Does not download or start processes,
# install Windows services, change the registry, or copy a client/player database.
[CmdletBinding()]
param([string]$JavaPath,[string]$MongodPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if($root -match '["%;\r\n]'){throw 'Choose an installation path without quote, percent, semicolon or line break characters.'}
if(Test-Path -LiteralPath "$root/local-edition.json"){throw 'Refusing to initialize over the original frozen installation.'}
$utf8=New-Object Text.UTF8Encoding($false)
function Write-NewJson($path,$obj){
    $temp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{[IO.File]::WriteAllText($temp,($obj|ConvertTo-Json -Depth 20),$utf8);[IO.File]::Move($temp,$path)}
    finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Find-Tool($provided,$folder,$name){
    if($provided){$f=Get-Item -LiteralPath $provided; if($f.PSIsContainer -or $f.Name -ine $name){throw "Expected $name"};return $f.FullName}
    $dir=Join-Path $root $folder
    $files=@(if(Test-Path -LiteralPath $dir){Get-ChildItem -LiteralPath $dir -Filter $name -Recurse -File})
    if($files.Count -ne 1){throw "Expected exactly one $name under $dir. Or supply its explicit installation path."}
    return $files[0].FullName
}
function Random-Base64(){ $bytes=New-Object byte[] 32; $rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes);return [Convert]::ToBase64String($bytes)}finally{$rng.Dispose()} }
$java=Find-Tool $JavaPath 'runtime/java' 'java.exe'
$mongod=Find-Tool $MongodPath 'runtime/mongodb' 'mongod.exe'
$javac=Join-Path (Split-Path $java) 'javac.exe'
$jar=Join-Path $root 'server/grasscutter.jar'
foreach($f in @($javac,$jar,"$root/scripts/MongoControl.java","$PSScriptRoot/AccountProbe.java")){
    if(-not(Test-Path -LiteralPath $f -PathType Leaf)){throw "Missing required component: $f"}
}
if(Test-Path -LiteralPath "$root/run/state.json"){
    $s=Get-Content -Encoding UTF8 -Raw -LiteralPath "$root/run/state.json"|ConvertFrom-Json
    foreach($idn in @($s.javaPid,$s.mongoPid,$s.supervisorPid)){
        if($s.running -and $idn -and (Get-Process -Id $idn -ErrorAction SilentlyContinue)){throw 'This installation may be running. Stop it before (re)initializing.'}
    }
}
foreach($d in 'database/data','run/commands','run/processed','logs','tmp','cache/java-home','scripts/classes','client-tools/bin','server/plugins','presets','audit'){
    [void][IO.Directory]::CreateDirectory((Join-Path $root $d))
}
# Do not inherit options from a different JDK or user's Java profile.
$env:JAVA_TOOL_OPTIONS=$null;$env:_JAVA_OPTIONS=$null;$env:JDK_JAVA_OPTIONS=$null
& $javac -encoding UTF-8 -proc:none -cp $jar -d "$root/scripts/classes" "$root/scripts/MongoControl.java" "$PSScriptRoot/AccountProbe.java"
if($LASTEXITCODE -ne 0){throw 'JDK compiler could not build the local database helpers.'}
# Gson uses 7.1 defaults for omitted fields; all network-facing addresses and
# shared secrets are explicitly defined here. Never copy an existing keystore.
$configPath=Join-Path $root 'server/config.json'
if(-not(Test-Path -LiteralPath $configPath)){
    $db=@{connectionUri='mongodb://127.0.0.1:27018';collection='astaps_local'}
    $http=@{bindAddress='127.0.0.1';accessAddress='127.0.0.1';bindPort=8088;accessPort=8088;startImmediately=$false;
        encryption=@{useEncryption=$false;useInRouting=$false;keystore='./keystore.p12';keystorePassword=([Guid]::NewGuid().ToString('N'))};
        policies=@{cors=@{enabled=$false;allowedOrigins=@()}}}
    $game=@{bindAddress='127.0.0.1';accessAddress='127.0.0.1';bindPort=22101;accessPort=22101;enableConsole=$true;logPackets='NONE';isShowPacketPayload=$false;isShowLoopPackets=$false;
        watchdog=@{enableDatabaseMonitor=$true;databaseCheckIntervalSeconds=10;enableAutoRestart=$false};
        gameOptions=@{inventoryLimits=@{weapons=2000;relics=2000;materials=2000;furniture=2000;all=30000};questing=@{enabled=$false;triggerAllOnLogin=$false};energyUsage=$true;handbook=@{enable=$false};newAccountIntro=@{enabled=$false};watermark=@{enabled=$false}}}
    $conf=@{version=15;databaseInfo=@{game=$db;server=$db};language=@{language='en_US';fallback='en_US';document='EN'};
        account=@{autoCreate=$false;EXPERIMENTAL_RealPassword=$true;useIntegrationPassword=$false;defaultPermissions=@()};
        server=@{runMode='HYBRID';logCommands=$false;http=$http;game=$game;dispatch=@{regions=@();dispatchUrl='ws://127.0.0.1:1111';encryptionKey=(Random-Base64);dispatchKey=(Random-Base64);logRequests='NONE'}}}
    Write-NewJson $configPath $conf
}
$pathsPath=Join-Path $root 'runtime-paths.json'
$newPaths=[ordered]@{java=$java;mongod=$mongod}
if(Test-Path -LiteralPath $pathsPath){
    $old=Get-Content -Encoding UTF8 -LiteralPath $pathsPath -Raw|ConvertFrom-Json
    if($old.java -ne $java -or $old.mongod -ne $mongod){
        $tmp=$pathsPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
        try{[IO.File]::WriteAllText($tmp,($newPaths|ConvertTo-Json),$utf8);[IO.File]::Replace($tmp,$pathsPath,$pathsPath+'.previous')}
        finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
    }
}else{ Write-NewJson $pathsPath $newPaths }
Write-Host "Local settings and database helpers initialized at: $root. No processes started."
