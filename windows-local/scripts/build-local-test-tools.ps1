param([switch]$GuiOnly,[switch]$RebuildCatalogs)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'controller-install.ps1')
$root=Split-Path -Parent $PSScriptRoot
$paths=[IO.File]::ReadAllText((Join-Path $root 'runtime-paths.json')) | ConvertFrom-Json
foreach($dir in 'tmp','catalog','audit','client-tools/bin','scripts/classes','server/plugins'){[void][IO.Directory]::CreateDirectory((Join-Path $root $dir))}
$env:TEMP="$root\tmp";$env:TMP=$env:TEMP
$java=Get-ArenaExecutable $root $paths.java java
$jdk=Split-Path -Parent $java
$serverJar="$root\server\grasscutter.jar"
$classes="$root\scripts\classes";$cp="$classes;$serverJar"
$build=Join-Path $root ('tmp\controller-build-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($build)
function Execute([string]$exe,[string[]]$arguments){& $exe @arguments;if($LASTEXITCODE -ne 0){throw "$([IO.Path]::GetFileName($exe)) failed (exit $LASTEXITCODE)"}}
$guiSources=@('IdLookup.cs','ArtifactModels.cs','ArtifactDesigner.cs','ArtifactSetDesigner.cs')|ForEach-Object {Join-Path $PSScriptRoot $_}
$csc="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$cflags=@('/nologo','/optimize+','/codepage:65001','/nowarn:0649','/reference:System.dll','/reference:System.Core.dll','/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll')
Execute $csc ($cflags+@('/target:winexe',"/out:$build\IdLookup-v4.exe")+$guiSources)
if($GuiOnly){Copy-Item -LiteralPath "$build\IdLookup-v4.exe" -Destination "$root\client-tools\bin\IdLookup-v4.exe";return}
foreach($catalog in 'id','artifact'){
    $dest=if($catalog -eq 'id'){'items'}else{'artifacts'}
    if($RebuildCatalogs -or !(Test-Path -LiteralPath "$root\catalog\$dest.json")){
        $node=Get-ArenaExecutable $root $paths.node node
        Execute $node @("$PSScriptRoot\build-$catalog-catalog.cjs")
    }
}
$jflags=@('-encoding','UTF-8','-proc:none')
$helpers=@('ArenaAccount.java','ArtifactGrant.java','WeaponGrant.java','EditSaveCheck.java','MissingAvatars.java','MissingContent.java','MongoControl.java')|ForEach-Object {Join-Path $PSScriptRoot $_}
Execute "$jdk\javac.exe" ($jflags+@('-cp',$serverJar,'-d',$classes)+$helpers)
$tests="$build\tests";[void][IO.Directory]::CreateDirectory($tests)
$plugin="$root\client-tools\local-test-plugin"
foreach($pkg in @(@('local-test-plugin','LocalTestTools','localtools'),@('energy-diagnostics-plugin','LocalEnergyDiagnostics','localenergy'))){
    $src="$root\client-tools\$($pkg[0])";$out="$build\$($pkg[1])";[void][IO.Directory]::CreateDirectory($out)
    $files=@(Get-ChildItem -LiteralPath "$src\src\$($pkg[2])" -Filter *.java -File)|ForEach-Object {$_.FullName}
    Execute "$jdk\javac.exe" ($jflags+@('-cp',$serverJar,'-d',$out,"$PSScriptRoot\ArenaAccount.java")+$files)
    Copy-Item -LiteralPath "$src\plugin.json" -Destination "$out\plugin.json"
    Execute "$jdk\jar.exe" @('--create','--file',"$out.jar",'-C',$out,'.')
}
Execute "$jdk\javac.exe" ($jflags+@('-cp',"$cp;$build\LocalTestTools",'-d',$tests,"$PSScriptRoot\ArenaBindingTests.java","$PSScriptRoot\ArtifactGrantTests.java","$PSScriptRoot\WeaponGrantTests.java","$plugin\tests\EditRulesTest.java","$plugin\tests\EditSaveCheckTest.java"))
Execute $csc ($cflags+@('/target:exe',"/out:$tests\ArtifactMathTests.exe","$PSScriptRoot\ArtifactModels.cs","$PSScriptRoot\ArtifactMathTests.cs"))
# Sample account exists only in the test fixture; building never registers an account in the real save.
$fixture="$build\fixture";foreach($dir in 'run','catalog','server/resources/ExcelBinOutput'){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $dir))}
[IO.File]::WriteAllText("$fixture\run\test-account.json",'{"username":"fixture","uid":783014}')
foreach($file in 'catalog/items.json','catalog/artifacts.json','server/resources/ExcelBinOutput/WeaponExcelConfigData.json'){Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $fixture $file)}
Push-Location -LiteralPath $fixture
try{
    Execute $java @('-cp',"$tests;$cp",'ArenaBindingTests',$fixture,$root)
    foreach($test in 'ArtifactGrantTests','WeaponGrantTests','EditRulesTest','EditSaveCheckTest'){Execute $java @('-Dfile.encoding=UTF-8',"-Duser.home=$fixture","-Djava.io.tmpdir=$build",'-cp',"$tests;$cp;$build\LocalTestTools",$test,$fixture)}
    Execute "$tests\ArtifactMathTests.exe" @($fixture)
}finally{Pop-Location}
# Do not overwrite loaded plugins. Never terminate a process here.
if(Test-Path "$root\run\state.json"){$s=[IO.File]::ReadAllText("$root\run\state.json")|ConvertFrom-Json;if($s.javaPid -and (Get-Process -Id $s.javaPid -ErrorAction SilentlyContinue)){throw 'Stop the local server before deploying rebuilt plugins.'}}
foreach($name in 'LocalTestTools','LocalEnergyDiagnostics'){Copy-Item -LiteralPath "$build\$name.jar" -Destination "$root\server\plugins\$name.jar"}
Copy-Item -LiteralPath "$build\IdLookup-v4.exe" -Destination "$root\client-tools\bin\IdLookup-v4.exe"
Write-Host 'Controller and plugins built; offline tests passed.'
