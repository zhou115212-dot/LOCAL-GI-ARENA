$ErrorActionPreference='Stop'
$line=Read-Host 'Local server console command'
if([string]::IsNullOrWhiteSpace($line)){return}
& "$PSScriptRoot/control.ps1" -Action command -CommandText $line
