# First-run controls. Never opens the game or alters network security settings.
[CmdletBinding()]param([switch]$CheckUI)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$root=$PSScriptRoot
$form=New-Object Windows.Forms.Form
$form.Text='LOCAL GI ARENA · 本机测试 / Local test'
$form.ClientSize=New-Object Drawing.Size(640,360)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$title=New-Object Windows.Forms.Label;$title.SetBounds(18,15,595,32)
$title.Font=New-Object Drawing.Font('Segoe UI',14);$title.Text='LOCAL GI ARENA   /   Windows · 7.1 CN'
$note=New-Object Windows.Forms.Label;$note.SetBounds(20,58,600,67);$note.Text="此工具管理本地服务端，不会启动或修改游戏。选择客户端只检查版本，不代表连接已配置。`r`nManage a local server. Client selection checks the build only; it does not configure routing."
$state=New-Object Windows.Forms.TextBox;$state.SetBounds(20,260,600,84);$state.Multiline=$true;$state.ScrollBars='Vertical';$state.ReadOnly=$true
$form.Controls.AddRange(@($title,$note,$state))
$buttons=@{}
function Button($key,$text,$x,$y){
    $b=New-Object Windows.Forms.Button;$b.SetBounds($x,$y,190,46);$b.Text=$text;$form.Controls.Add($b);$buttons[$key]=$b
}
Button select '检查客户端 / Check client' 20 135
Button start '启动服务端 / Start server' 225 135
Button stop '停止服务端 / Stop server' 430 135
Button account '本机账号 / Local account' 20 195
Button edit '角色与装备 / Equipment' 225 195
Button check '服务状态 / Status' 430 195
$privateFile=Join-Path $root 'run/test-account.private.json'
$binding=Join-Path $root 'run/test-account.json'
$state.Text='就绪 / Ready. 此界面不接触官服账号。'
$buttons.select.Add_Click({
    $dlg=New-Object Windows.Forms.FolderBrowserDialog;$dlg.Description='选择独立的 7.1 测试客户端目录 / Select isolated 7.1 CN client'
    try{if($dlg.ShowDialog() -eq 'OK'){
        $r=& "$root/distribution/check-client.ps1" -ClientFolder $dlg.SelectedPath
        if(-not $r.KnownExecutable){throw 'Unknown client build'}
        $run=Join-Path $root run;[void][IO.Directory]::CreateDirectory($run)
        $path=Join-Path $run client-selection.json;$tmp=[IO.Path]::Combine($run,([Guid]::NewGuid().ToString()+'.tmp'))
        try{[IO.File]::WriteAllText($tmp,(@{executable=(Join-Path $dlg.SelectedPath 'YuanShen.exe')}|ConvertTo-Json))
            if(Test-Path -LiteralPath $path){[IO.File]::Replace($tmp,$path,$null)}else{[IO.File]::Move($tmp,$path)}
        }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
        $state.Text='已识别 7.1.0。仅记录本机路径；下次启动服务时生效。没有启动游戏或验证登录。'
    }}catch{$state.Text=$_.Exception.Message}finally{$dlg.Dispose()}
})
$buttons.edit.Add_Click({try{$p=Join-Path $root 'client-tools/bin/IdLookup-v4.exe';if(-not [IO.File]::Exists($p)){throw '缺少已编译的控制器 / Build the controller first.'};Start-Process -FilePath $p -WorkingDirectory $root}catch{$state.Text=$_.Exception.Message}})
$buttons.account.Add_Click({
    try{if(-not (Test-Path -LiteralPath $binding)){throw '尚无已核验的测试账号。先启动服务端。 / Start this server first.'}
        $b=Get-Content -LiteralPath $binding -Raw -Encoding UTF8|ConvertFrom-Json
        $r=Get-Content -LiteralPath $privateFile -Raw -Encoding UTF8|ConvertFrom-Json
        if($r.username -cne $b.username -or $r.uid -ne $b.uid){throw 'Local account records do not match.'}
        if([Windows.Forms.MessageBox]::Show('在屏幕上显示本机测试密码？ / Show local test password on this screen?', 'LOCAL GI ARENA', 'YesNo') -eq 'Yes'){
            $ss=ConvertTo-SecureString $r.secret;try{[void][Windows.Forms.MessageBox]::Show(($b.username+"`r`n"+([Net.NetworkCredential]::new('',$ss)).Password),'仅限本机测试 / Local test only')}finally{$ss.Dispose()}
        }
    }catch{$state.Text=$_.Exception.Message}
})
$script:jobProc=$null;$script:jobName=''
$timer=New-Object Windows.Forms.Timer;$timer.Interval=400
function Start-JobUI($verb){
    if($script:jobProc){return}
    if($root -match '["\r\n]'){throw 'Unsupported folder name'}
    $script:jobName=$verb
    $argsLine='-NoProfile -NonInteractive -File "'+(Join-Path $root 'distribution/instance-action.ps1')+'" -Action '+$verb
    $script:jobProc=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $argsLine -WorkingDirectory $root -WindowStyle Hidden -PassThru
    $state.Text='处理中 / Working: '+$verb
    foreach($k in 'start','stop','check'){$buttons[$k].Enabled=$false};$timer.Start()
}
foreach($item in @(@('start','start'),@('stop','stop'),@('check','status'))){
    $buttons[$item[0]].Tag=$item[1];$buttons[$item[0]].Add_Click({param($sender,$eventArgs) try{Start-JobUI ([string]$sender.Tag)}catch{$state.Text=$_.Exception.Message}})
}
$timer.Add_Tick({
    if(-not $script:jobProc -or -not $script:jobProc.HasExited){return}
    $timer.Stop();$code=$script:jobProc.ExitCode;$script:jobProc.Dispose();$script:jobProc=$null
    $file=Join-Path $root 'run/panel-result.txt';$state.Text="Exit: $code"
    if(Test-Path -LiteralPath $file){$state.Text=[IO.File]::ReadAllText($file)}
    foreach($k in 'start','stop','check'){$buttons[$k].Enabled=$true}
})
if($CheckUI){if($buttons.Count -ne 6){throw 'Invalid control layout'};Write-Output 'PASS: 6 control-panel actions constructed; no client or server started.'; $form.Dispose();return}
try{[void]$form.ShowDialog()}finally{$timer.Dispose();$form.Dispose()}
