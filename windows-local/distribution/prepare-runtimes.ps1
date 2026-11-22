[CmdletBinding()]
param([string]$Root=(Split-Path -Parent $PSScriptRoot),[string]$JavaArchive,[string]$MongoArchive,[switch]$Download)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Root=(Get-Item -LiteralPath $Root).FullName
$rt=Join-Path $Root runtime
[void][IO.Directory]::CreateDirectory($rt)
function GuardPath([string]$path) {
    $d=Get-Item -LiteralPath $path
    while ($d) { if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Reparse point not allowed: $($d.FullName)"}; $d=$d.Parent }
}
GuardPath $rt
$artifacts=@(
    @{Name='java'; Archive=$JavaArchive; Dir='jdk-21.0.12.1+1'; Bin='bin/java.exe'; Hash='f9d6e191ab098c0d416e7d588a24420a8621cd2f4720dab2459b8b7b2d2d8b4e'; Url='https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip'},
    @{Name='mongodb'; Archive=$MongoArchive; Dir='mongodb-win32-x86_64-windows-8.0.32'; Bin='bin/mongod.exe'; Hash='5a0675fdec49b544cd5d374ad50a9a594cf5b3278b5ace658aa51cbb4df17177'; Url='https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-8.0.32.zip'}
)
foreach($a in $artifacts){
    $parent=Join-Path $rt $a.Name; [void][IO.Directory]::CreateDirectory($parent); GuardPath $parent
    $dest=Join-Path $parent $a.Dir; $marker=Join-Path $dest '.arena-archive.sha256'
    if(Test-Path -LiteralPath $dest){GuardPath $dest; if((Test-Path -LiteralPath $marker -PathType Leaf) -and [IO.File]::ReadAllText($marker).Trim() -eq $a.Hash -and (Test-Path -LiteralPath (Join-Path $dest $a.Bin) -PathType Leaf)){Write-Host "Already installed: $($a.Name)"; continue};throw "Existing runtime was not created by this installer. No overwrite: $dest"}
    $work=Join-Path $parent ('.prepare-'+[guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($work)
    try {
        if($a.Archive){$archive=(Get-Item -LiteralPath $a.Archive -ErrorAction Stop).FullName}
        elseif($Download){$archive=Join-Path $work 'vendor.zip'; (New-Object Net.WebClient).DownloadFile($a.Url,$archive)}
        else {throw "Provide the official $($a.Name) ZIP or pass -Download. No download attempted."}
        $sha=[Security.Cryptography.SHA256]::Create();$stream=[IO.File]::OpenRead($archive)
        try{$hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
        if($hash -ne $a.Hash){throw "SHA-256 mismatch for $($a.Name); archive not extracted."}
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try{foreach($entry in $zip.Entries){
            $n=$entry.FullName.Replace('\','/')
            if(-not ($n.StartsWith($a.Dir+'/',[StringComparison]::Ordinal)) -or $n -match '(^|/)\.\.(/|$)|:'){throw 'Unexpected vendor archive path'}
            if($n.EndsWith('/')){continue}
            if($a.Name -eq 'mongodb' -and ($n -match '(?i)\.pdb$|/bin/(?!mongod\.exe$)')){continue}
            $p=Join-Path $work $n;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p));[IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$p,$false)
        }}finally{$zip.Dispose()}
        $tree=Join-Path $work $a.Dir
        if(-not (Test-Path -LiteralPath (Join-Path $tree $a.Bin) -PathType Leaf)){throw 'Missing expected executable'}
        [IO.File]::WriteAllText((Join-Path $tree '.arena-archive.sha256'),$a.Hash)
        [IO.Directory]::Move($tree,$dest);Write-Host "Installed from verified archive: $($a.Name)"
    }finally{
        $full=[IO.Path]::GetFullPath($work)
        if(([IO.Path]::GetDirectoryName($full) -eq $parent) -and ([IO.Path]::GetFileName($full) -match '^\.prepare-[a-f0-9]{32}$') -and (Test-Path -LiteralPath $full)){Remove-Item -LiteralPath $full -Recurse -Force}
    }
}
