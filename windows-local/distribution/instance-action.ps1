[CmdletBinding()]param([Parameter(Mandatory=$true)][ValidateSet('start','status','stop')][string]$Action)
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot
$run=Join-Path $root run;[void][IO.Directory]::CreateDirectory($run);$out=Join-Path $run panel-result.txt
try{
    if(-not(Test-Path -LiteralPath "$root/server/grasscutter.jar" -PathType Leaf)){throw '缺少服务端构建产物 server/grasscutter.jar。仅下载源码或选择客户端不会自动提供它。 / Server JAR missing.'}
    if($Action -eq 'start'){
        foreach($p in 'server/resources/ExcelBinOutput/AvatarExcelConfigData.json','catalog/items.json','catalog/artifacts.json','server/plugins/LocalTestTools.jar','client-tools/bin/IdLookup-v4.exe'){if(-not(Test-Path -LiteralPath "$root/$p" -PathType Leaf)){throw "缺少文件 / Missing component: $p"}}
        $pathsFile=Join-Path $root 'runtime-paths.json'
        $init=-not (Test-Path -LiteralPath $pathsFile)
        if(-not $init){$paths=Get-Content -LiteralPath $pathsFile -Raw -Encoding UTF8|ConvertFrom-Json;$rt=[IO.Path]::GetFullPath((Join-Path $root runtime))+[IO.Path]::DirectorySeparatorChar
            $init=@(@($paths.java,$paths.mongod)|Where-Object {-not (Test-Path -LiteralPath $_ -PathType Leaf) -or -not ([IO.Path]::GetFullPath($_).StartsWith($rt,[StringComparison]::OrdinalIgnoreCase))}).Count -gt 0
        }
        if($init){& "$root/portable-server/initialize.ps1"}
    }
    if($Action -eq 'status'){
        $summary=& "$root/scripts/control.ps1" -Action status 6>&1 |Out-String
        [IO.File]::WriteAllText($out,$summary);return
    }
    & "$root/scripts/control.ps1" -Action $Action
    if($Action -eq 'start'){
        $b=Join-Path $root 'run/test-account.json';$u='arena';$id=10001
        if(Test-Path -LiteralPath $b){$saved=Get-Content -LiteralPath $b -Raw -Encoding UTF8|ConvertFrom-Json;$u=$saved.username;$id=$saved.uid}
        & "$root/portable-server/new-account.ps1" -Username $u -Uid $id
        [IO.File]::WriteAllText($out,'服务端就绪，本机账号已验证。游戏未启动。 / Local server and test account ready; no game launched.')
    }else{[IO.File]::WriteAllText($out,'本机服务已停。 / Local server stopped.')}
}catch{[IO.File]::WriteAllText($out,$_.Exception.Message);exit 1}
