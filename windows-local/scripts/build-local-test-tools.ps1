param([switch]$GuiOnly)
# Compiles only local readable sources, runs pure rules tests, deploys a plugin JAR and
# Windows Forms EXE under E:. No download or system/registry/service/client modification.
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$env:TEMP="$Root\tmp";$env:TMP=$env:TEMP
$java=(Get-Content -LiteralPath "$Root\runtime-paths.json" -Raw | ConvertFrom-Json).java
$bin=Split-Path -Parent $java
$build="$Root\client-tools\local-test-plugin\build"
New-Item -ItemType Directory -Force "$build\classes","$build\tests","$Root\server\plugins" | Out-Null
if(Test-Path -LiteralPath "$Root\scripts\build-artifact-catalog.cjs"){
    & 'D:\node.exe' "$Root\scripts\build-artifact-catalog.cjs"
    if($LASTEXITCODE -ne 0){throw 'Artifact catalog build failed.'}
    & "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$Root\server\grasscutter.jar" -d "$Root\scripts\classes" "$Root\scripts\ArtifactGrant.java"
    if($LASTEXITCODE -ne 0){throw 'Artifact grant verifier compilation failed.'}
    & "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$Root\server\grasscutter.jar;$Root\scripts\classes" -d "$build\tests" "$Root\scripts\ArtifactGrantTests.java"
    if($LASTEXITCODE -ne 0){throw 'Artifact backend tests compilation failed.'}
    & $java -cp "$build\tests;$Root\scripts\classes;$Root\server\grasscutter.jar" ArtifactGrantTests $Root
    if($LASTEXITCODE -ne 0){throw 'Artifact backend tests failed.'}
    if(Test-Path -LiteralPath "$Root\scripts\WeaponGrant.java"){
        & "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$Root\server\grasscutter.jar;$Root\scripts\classes" -d "$Root\scripts\classes" "$Root\scripts\WeaponGrant.java"
        if($LASTEXITCODE -ne 0){throw 'Weapon copies verifier compilation failed.'}
        & "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$Root\server\grasscutter.jar;$Root\scripts\classes" -d "$build\tests" "$Root\scripts\WeaponGrantTests.java"
        if($LASTEXITCODE -ne 0){throw 'Weapon copies tests compilation failed.'}
        & $java -cp "$build\tests;$Root\scripts\classes;$Root\server\grasscutter.jar" WeaponGrantTests $Root
        if($LASTEXITCODE -ne 0){throw 'Weapon copies tests failed.'}
    }
    $testCsc="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    & $testCsc /nologo /target:exe /optimize+ /codepage:65001 /nowarn:0649 /reference:System.dll /reference:System.Core.dll /reference:System.Web.Extensions.dll "/out:$build\tests\ArtifactMathTests.exe" "$Root\scripts\ArtifactModels.cs" "$Root\scripts\ArtifactMathTests.cs"
    if($LASTEXITCODE -ne 0){throw 'Artifact model tests compilation failed.'}
    & "$build\tests\ArtifactMathTests.exe" $Root
    if($LASTEXITCODE -ne 0){throw 'Artifact model tests failed.'}
}
if(-not $GuiOnly){
& "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$Root\server\grasscutter.jar" -d "$Root\scripts\classes" "$Root\scripts\EditSaveCheck.java"
if($LASTEXITCODE -ne 0){throw 'Saved-state verifier compilation failed.'}
$sources=Get-ChildItem -LiteralPath "$Root\client-tools\local-test-plugin\src\localtools" -Filter *.java | ForEach-Object FullName
& "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$Root\server\grasscutter.jar" -d "$build\classes" @sources
if($LASTEXITCODE -ne 0){throw 'Plugin compilation failed.'}
& "$bin\javac.exe" -encoding UTF-8 -proc:none -cp "$build\classes;$Root\scripts\classes;$Root\server\grasscutter.jar" -d "$build\tests" "$Root\client-tools\local-test-plugin\tests\EditRulesTest.java" "$Root\client-tools\local-test-plugin\tests\EditSaveCheckTest.java"
if($LASTEXITCODE -ne 0){throw 'Test compilation failed.'}
& $java -cp "$build\classes;$build\tests" EditRulesTest
if($LASTEXITCODE -ne 0){throw 'Rules tests failed.'}
& $java -cp "$build\tests;$Root\scripts\classes;$Root\server\grasscutter.jar" EditSaveCheckTest
if($LASTEXITCODE -ne 0){throw 'Saved-state/invariant tests failed.'}
Copy-Item -LiteralPath "$Root\client-tools\local-test-plugin\plugin.json" -Destination "$build\classes\plugin.json"
& "$bin\jar.exe" --create --file "$build\LocalTestTools.jar" -C "$build\classes" .
if($LASTEXITCODE -ne 0){throw 'JAR creation failed.'}
# Running JVM retains a loaded JAR: stop it normally before replacing an existing build.
$dest="$Root\server\plugins\LocalTestTools.jar"
if(Test-Path -LiteralPath $dest){
    $state=Get-Content -LiteralPath "$Root\run\state.json" -Raw | ConvertFrom-Json
    if(Get-Process -Id $state.javaPid -ErrorAction SilentlyContinue){throw 'Plugin rebuilt; stop the local server normally before replacing its loaded JAR.'}
}
Copy-Item -LiteralPath "$build\LocalTestTools.jar" -Destination $dest
}
$guiSourceHash=(@('IdLookup.cs','ArtifactModels.cs','ArtifactDesigner.cs','ArtifactSetDesigner.cs')|ForEach-Object{
    $sha=[Security.Cryptography.SHA256]::Create()
    try {([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes("$Root\scripts\$_")))).Replace('-','')}
    finally {$sha.Dispose()}
})-join ':'
$guiStamp="$build\gui-source.sha256"
if(-not(Test-Path -LiteralPath "$Root\client-tools\bin\IdLookup-v4.exe") -or -not(Test-Path -LiteralPath $guiStamp) -or (Get-Content -LiteralPath $guiStamp -Raw).Trim() -ne $guiSourceHash){
    $csc="$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    & $csc /nologo /target:winexe /optimize+ /codepage:65001 /nowarn:0649 /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.Web.Extensions.dll "/out:$Root\client-tools\bin\IdLookup-v4.exe" "$Root\scripts\IdLookup.cs" "$Root\scripts\ArtifactModels.cs" "$Root\scripts\ArtifactDesigner.cs" "$Root\scripts\ArtifactSetDesigner.cs"
    if($LASTEXITCODE -ne 0){throw 'GUI compilation failed. Close the role/weapon manager before recompiling its EXE.'}
    [IO.File]::WriteAllText($guiStamp,$guiSourceHash)
}
if($GuiOnly){Write-Host 'Silent management GUI rebuilt. Running game and server were left unchanged.'}
else{Write-Host 'LocalTestTools plugin and silent GUI built successfully.'}
