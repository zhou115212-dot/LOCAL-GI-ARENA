$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'local-client-lifecycle.ps1')
$script:Checks=0
function Assert-Result([bool]$Condition,[string]$Name) {
    if (-not $Condition) { throw ('FAILED: '+$Name) }
    $script:Checks++
}
function Step($State,[bool]$Present,[bool]$Success,[double]$Time) {
    return Update-LocalClientLifecycle -State $State -ClientPresent $Present -ProbeSucceeded $Success -NowSeconds $Time -GraceSeconds 30
}
$s=New-LocalClientLifecycle
foreach ($t in @(0,2,30,60,300,86400)) { Assert-Result (-not (Step $s $false $true $t)) "Never-opened client stays idle at $t" }
Assert-Result (-not $s.SeenClient) 'Idle server never armed'
Assert-Result (-not (Step $s $true $true 86401)) 'Actual isolated client arms watcher'
Assert-Result $s.SeenClient 'Client was observed'
foreach ($t in @(86402,86500,87000)) { Assert-Result (-not (Step $s $true $true $t)) 'Running client retained' }
Assert-Result (-not (Step $s $false $true 87002)) 'Exit starts grace period'
foreach ($t in @(87003,87020,87031.9)) { Assert-Result (-not (Step $s $false $true $t)) 'No shutdown before 30 seconds' }
Assert-Result (Step $s $false $true 87032) 'Shutdown at 30-second boundary'
Assert-Result (-not (Step $s $true $true 87032.1)) 'Immediate recheck cancels shutdown on relaunch'
Assert-Result ($null -eq $s.AbsentSinceSeconds) 'Relaunch resets grace timer'
Assert-Result (-not (Step $s $false $true 87034)) 'New exit starts a new timer'
Assert-Result (-not (Step $s $false $false 87065)) 'Failed process probe never stops server'
Assert-Result ($null -eq $s.AbsentSinceSeconds) 'Failed probe resets timer'
Assert-Result (-not (Step $s $false $true 87070)) 'Recovery needs full grace period'
Assert-Result (-not (Step $s $false $true 87099)) 'Still within recovered grace period'
Assert-Result (Step $s $false $true 87100) 'Recovered shutdown deadline'
$s.StopAttempted=$true
foreach ($t in @(87101,87200,90000)) { Assert-Result (-not (Step $s $false $true $t)) 'Never sends duplicate stop request' }
$s=New-LocalClientLifecycle
[void](Step $s $true $true 100)
[void](Step $s $false $true 102)
Assert-Result (-not (Step $s $false $true 90)) 'Backward time resets timer'
Assert-Result (-not (Step $s $false $true 119)) 'Backward-time guard retains grace period'
Assert-Result (Step $s $false $true 120) 'Backward-time guard reaches new boundary'
$expected='E:\ExampleArena\client\Genshin-7.1-CN\YuanShen.exe'
Assert-Result (Test-IsolatedClientPath $expected $expected) 'Exact isolated path matches'
Assert-Result (Test-IsolatedClientPath $expected.ToLowerInvariant() $expected) 'Windows path casing matches'
foreach ($other in @('D:\Official\YuanShen.exe','E:\Other\YuanShen.exe','E:\ExampleArena\client\Other\YuanShen.exe','E:\ExampleArena\client\Genshin-7.1-CN\YuanShen.exe.bak','')) {
    Assert-Result (-not (Test-IsolatedClientPath $other $expected)) 'Other client and invalid paths ignored'
}
$s=New-LocalClientLifecycle
Assert-Result (-not (Step $s $true $false 0)) 'Unreadable probe never arms watcher'
Assert-Result (-not $s.SeenClient) 'Ambiguous presence leaves server alone'
Assert-Result (-not (Step $s $false $true 10000)) 'Failed launcher never triggers shutdown'
foreach ($file in @('local-client-lifecycle.ps1','test-local-client-lifecycle.ps1')) {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
    Assert-Result ($errors.Count -eq 0) ('PowerShell syntax: '+$file)
}
$probe=Get-IsolatedClientPresence -ExpectedPath $expected
Assert-Result ($probe.Present -is [bool] -and $probe.Succeeded -is [bool]) 'Real read-only probe returns booleans'
[pscustomobject]@{Checks=$script:Checks;Passed=$true;PowerShell=$PSVersionTable.PSVersion.ToString();RealClientPresent=$probe.Present;RealProbeSucceeded=$probe.Succeeded} | ConvertTo-Json
