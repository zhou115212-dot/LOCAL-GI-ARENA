[CmdletBinding(DefaultParameterSetName='Build')]
param(
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$SourceRepo,
    [Parameter(Mandatory=$true)][string]$ResourceRepo,
    [Parameter(Mandatory=$true)][string]$NamesRepo,
    [Parameter(Mandatory=$true,ParameterSetName='UseTestedBuild')][string]$TrustedBuild,
    [Parameter(Mandatory=$true,ParameterSetName='Build')][string]$GradleZip,
    [Parameter(Mandatory=$true,ParameterSetName='Build')][string]$BuildWork,
    [Parameter(ParameterSetName='Build')][string]$OfflineModules,
    [string]$JavaArchive,[string]$MongoArchive,[switch]$DownloadRuntimes
)
# Maintainer action: read committed source/data, assemble only into a fresh private directory.
$ErrorActionPreference='Stop';$from=Split-Path -Parent $PSScriptRoot
function Exec([string]$exe,[string[]]$A){& $exe @A; if($LASTEXITCODE){throw "Component build failed ($LASTEXITCODE): $exe"}}
$py=(Get-Command python -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$node=(Get-Command node -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
$dest=[IO.Path]::GetFullPath($Destination)
if((Test-Path -LiteralPath $dest) -or $dest -match '["%;\r\n]'){throw 'Specify a new directory (no quote, percent, semicolon or line break). No overwrite.'}
foreach($p in @($from,$SourceRepo,$ResourceRepo,$NamesRepo)){ $parent=(Get-Item -LiteralPath $p).FullName.TrimEnd('\')+'\';if(($dest+'\').StartsWith($parent,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must not be under a source checkout.'} }
if(!$DownloadRuntimes -and (!$JavaArchive -or !$MongoArchive)){throw 'Supply both official ZIP files, or explicitly select -DownloadRuntimes.'}
[void][IO.Directory]::CreateDirectory($dest)
$files=Get-Content -LiteralPath "$PSScriptRoot/instance-files.txt" -Encoding UTF8
foreach($rel in $files){
    if($rel -notmatch '^[a-zA-Z0-9_./-]+$' -or $rel -match '(^|/)\.\.(/|$)|^/'){throw 'Invalid instance file list'}
    $target=Join-Path $dest $rel;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    [IO.File]::Copy((Join-Path $from $rel),$target,$false)
}
& "$PSScriptRoot/prepare-runtimes.ps1" -Root $dest -JavaArchive $JavaArchive -MongoArchive $MongoArchive -Download:$DownloadRuntimes
if($PSCmdlet.ParameterSetName -eq 'Build'){
    $j=(Get-ChildItem -LiteralPath "$dest/runtime/java" -Directory -Filter 'jdk-*'|Select-Object -First 1).FullName
    $a=@('-B',"$from/build-server/build.py",'--source',$SourceRepo,'--work',$BuildWork,'--jdk',$j,'--gradle-zip',$GradleZip)
    if($OfflineModules){$a+=@('--offline-modules',$OfflineModules)}
    Exec $py $a;$TrustedBuild=$BuildWork
}
# Receipt must be from the operator's own trusted build, never an arbitrary download.
$receipt=Get-Content -LiteralPath "$TrustedBuild/build-result.json" -Raw -Encoding UTF8|ConvertFrom-Json
$jar=(Get-Item -LiteralPath "$TrustedBuild/src/arena-server.jar").FullName
if($receipt.base -ne '0fac870873a35e88b9f969aa1b242a832b602005' -or $receipt.patch_sha256 -ne '55270d2155699201d385e1c65d5a15e3b86cf0556473df9fe2281b917a9e32c0' -or $receipt.tests.tests -lt 107 -or $receipt.tests.failures -ne 0 -or $receipt.tests.errors -ne 0 -or $receipt.tests.skipped -ne 0 -or (Get-FileHash -LiteralPath $jar).Hash -ne $receipt.private_runtime_sha256){throw 'Unexpected build receipt or JAR; stopped.'}
Exec $py @('-B',"$PSScriptRoot/stage-data.py",'--root',$dest,'--source',$SourceRepo,'--resources',$ResourceRepo,'--name-data',$NamesRepo)
Copy-Item -LiteralPath $jar -Destination "$dest/server/grasscutter.jar"
[void][IO.Directory]::CreateDirectory((Join-Path $dest audit))
foreach($s in 'merge-textmap','build-id-catalog','build-artifact-catalog'){Exec $node @("$dest/scripts/$s.cjs")}
& "$dest/portable-server/initialize.ps1"
& "$dest/scripts/build-local-test-tools.ps1"
Write-Host "Built private instance: $dest. Double-click Open-Arena.cmd there. No service or client started. Do not publish the private instance directory."
