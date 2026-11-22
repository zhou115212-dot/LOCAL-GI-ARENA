# Create one local account, then verify the saved UID and password via read-only MongoDB access.
# Never overwrite an existing binding/account; retry is safe after a partial first run.
[CmdletBinding()]
param([ValidatePattern('^[A-Za-z0-9_]{3,24}$')][string]$Username='arena',
      [ValidateRange(10001,900000000)][int]$Uid=10001,[switch]$ShowPassword)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$utf8=New-Object Text.UTF8Encoding($false)
function New-File($path,$text){
    $tmp=$path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try{[IO.File]::WriteAllText($tmp,$text,$utf8);[IO.File]::Move($tmp,$path)}finally{if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp}}
}
$run=Join-Path $root 'run';$bind=Join-Path $run 'test-account.json';$private=Join-Path $run 'test-account.private.json'
$paths=Get-Content -Encoding UTF8 -LiteralPath "$root/runtime-paths.json" -Raw|ConvertFrom-Json
$cfg=Get-Content -Encoding UTF8 -LiteralPath "$root/server/config.json" -Raw|ConvertFrom-Json
if(-not $cfg.account.EXPERIMENTAL_RealPassword -or $cfg.account.autoCreate){throw 'Local account requires explicit account creation and real password mode.'}
function Check-Processes{
    if(-not(Test-Path -LiteralPath "$run/state.json" -PathType Leaf)){throw 'Start this local server and wait for it to become ready before creating an account.'}
    $s=Get-Content -Encoding UTF8 -LiteralPath "$run/state.json" -Raw|ConvertFrom-Json
    if(-not $s.running){throw 'Start this server first.'}
    foreach($slot in @(@($s.javaPid,$s.javaStarted,$paths.java,8088),@($s.mongoPid,$s.mongoStarted,$paths.mongod,27018))){
        $p=Get-Process -Id $slot[0] -ErrorAction Stop
        if($p.Path -ne $slot[2] -or $p.StartTime.ToUniversalTime().Ticks -ne [long]$slot[1]){throw 'Different installation/process; stopped without issuing a command.'}
        $ls=@(Get-NetTCPConnection -State Listen -LocalPort $slot[3] -ErrorAction Stop)
        if($ls.Count -ne 1 -or $ls[0].LocalAddress -ne '127.0.0.1' -or $ls[0].OwningProcess -ne $p.Id){throw 'Listener is not owned by this local installation.'}
    }
}
function Probe($mode,$password){
    $args1=@('-cp',"$root/server/grasscutter.jar;$root/scripts/classes",'AccountProbe',$mode,$Username,"$Uid","$root/scripts/mongo-logback.xml")
    if($mode -eq 'verify'){$password | & $paths.java @args1 | Out-Null}else{& $paths.java @args1 |Out-Null}
    return $LASTEXITCODE
}
Check-Processes
$lock=[IO.File]::Open("$run/account-setup.lock",[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    $bound=Test-Path -LiteralPath $bind
    if($bound){
        $old=Get-Content -Encoding UTF8 -LiteralPath $bind -Raw|ConvertFrom-Json
        if($old.username -cne $Username -or $old.uid -ne $Uid){throw 'A different controller binding already exists. It was not changed.'}
        if(-not(Test-Path -LiteralPath $private)){throw 'Private local credential missing; existing account was not touched.'}
    }
    if(Test-Path -LiteralPath $private){
        $record=Get-Content -Encoding UTF8 -LiteralPath $private -Raw|ConvertFrom-Json
        if($record.username -cne $Username -or $record.uid -ne $Uid){throw 'Another account is already configured on this installation.'}
        $secure=ConvertTo-SecureString $record.secret
        $password=([System.Net.NetworkCredential]::new('',$secure)).Password
    }else{
        if((Probe 'available' '') -ne 0){throw 'Username/UID is occupied or database unavailable. No account was changed.'}
        $password=[Guid]::NewGuid().ToString('N')
        $secure=ConvertTo-SecureString $password -AsPlainText -Force
        New-File $private (@{username=$Username;uid=$Uid;secret=($secure|ConvertFrom-SecureString)}|ConvertTo-Json)
    }
    $verified=(Probe 'verify' $password)
    if($verified -ne 0){
        if($bound -or $verified -ne 3 -or (Probe 'available' '') -ne 0){throw 'Existing account did not verify. Refusing to reset its password or replace its UID.'}
        Check-Processes
        $cmd=ConvertTo-SecureString "account create $Username $password $Uid" -AsPlainText -Force
        New-File (Join-Path $run ('commands/'+[guid]::NewGuid().ToString('N')+'.sealed')) ($cmd|ConvertFrom-SecureString)
        $deadline=[DateTime]::UtcNow.AddSeconds(60)
        do{Start-Sleep -Milliseconds 500;$verified=Probe 'verify' $password}while($verified -eq 3 -and [DateTime]::UtcNow -lt $deadline)
        if($verified -ne 0){throw 'Account creation not verified. Retry with the same username/UID; no binding was written.'}
    }
    if(-not $bound){New-File $bind (@{username=$Username;uid=$Uid}|ConvertTo-Json)}
    Write-Host "Verified local test account '$Username', UID $Uid."
    if($ShowPassword){Write-Host "Local test password: $password"}else{Write-Host 'Use -ShowPassword with the same username/UID when you need to see the local test password. Never use official credentials.'}
}finally{$password=$null;$cmd=$null;if($secure){$secure.Dispose()};$lock.Dispose()}
