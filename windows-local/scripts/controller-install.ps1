function Get-ArenaExecutable([string]$Root,[string]$Value,[string]$Name) {
    if([string]::IsNullOrWhiteSpace($Value)){throw "Missing runtime-paths.json entry: $Name"}
    if(-not [IO.Path]::IsPathRooted($Value)){$Value=Join-Path $Root $Value}
    $f=Get-Item -LiteralPath $Value -ErrorAction Stop
    if($f.PSIsContainer){throw "Expected a file for $Name"}
    $f.FullName
}
function Read-ArenaUid([string]$Root) {
    $b=[IO.File]::ReadAllText((Join-Path $Root 'run/test-account.json'))|ConvertFrom-Json
    if(-not($b.uid -is [int] -or $b.uid -is [long]) -or $b.uid -le 0 -or $b.uid -gt [int]::MaxValue -or -not($b.username -is [string]) -or [string]::IsNullOrWhiteSpace($b.username)){throw 'Invalid local test-account binding.'}
    [int]$b.uid
}
function Assert-ArenaServerPid([string]$Root,[string]$Java){
    $s=[IO.File]::ReadAllText((Join-Path $Root 'run/state.json'))|ConvertFrom-Json
    $p=Get-Process -Id $s.javaPid -ErrorAction SilentlyContinue
    if(!$p -or $p.Path -ne $Java -or $p.StartTime.ToUniversalTime().Ticks -ne [long]$s.javaStarted){throw 'The local server is not running from this installation.'}
}
