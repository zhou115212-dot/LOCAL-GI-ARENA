# Windows PowerShell 5.1. Read-only assertions against the chosen installation.
# Run after initialize.ps1; never logs secret values, modifies data or starts a listener.
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Assert-True($result,$label){if(-not $result){throw "Preflight failed: $label"};Write-Output "OK $label"}
function Read-Json($rel){Get-Content -Encoding UTF8 -Raw -LiteralPath (Join-Path $root $rel)|ConvertFrom-Json}
$c=Read-Json 'server/config.json'; $p=Read-Json 'runtime-paths.json'
Assert-True (($c.version -eq 15) -and ($c.server.runMode -eq 'HYBRID')) 'pinned server config schema'
Assert-True (($c.server.http.bindAddress -eq '127.0.0.1') -and ($c.server.http.accessAddress -eq '127.0.0.1') -and ($c.server.http.bindPort -eq 8088) -and ($c.server.http.accessPort -eq 8088)) 'HTTP loopback only'
Assert-True (($c.server.game.bindAddress -eq '127.0.0.1') -and ($c.server.game.accessAddress -eq '127.0.0.1') -and ($c.server.game.bindPort -eq 22101) -and ($c.server.game.accessPort -eq 22101)) 'game loopback only'
foreach($part in 'server','game'){ $db=$c.databaseInfo.$part;Assert-True (($db.connectionUri -eq 'mongodb://127.0.0.1:27018') -and ($db.collection -eq 'astaps_local')) "database loopback: $part" }
Assert-True (([Convert]::FromBase64String($c.server.dispatch.encryptionKey)).Length -eq 32 -and ([Convert]::FromBase64String($c.server.dispatch.dispatchKey)).Length -eq 32 -and $c.server.dispatch.encryptionKey -cne $c.server.dispatch.dispatchKey -and $c.server.http.encryption.keystorePassword.Length -ge 24) 'two distinct dispatch keys and per-installation stop credential'
Assert-True (($c.account.EXPERIMENTAL_RealPassword) -and (-not $c.account.autoCreate) -and (-not $c.account.useIntegrationPassword)) 'explicit local test accounts'
Assert-True (($c.server.game.gameOptions.inventoryLimits.relics -gt 0) -and ($c.server.game.gameOptions.inventoryLimits.weapons -gt 0)) 'controller inventory caps'
foreach($f in @($p.java,$p.mongod,(Join-Path (Split-Path $p.java) 'javac.exe'))){Assert-True (Test-Path -LiteralPath $f -PathType Leaf) ([IO.Path]::GetFileName($f))}
foreach($rel in 'scripts/classes/AccountProbe.class','scripts/classes/MongoControl.class','server/grasscutter.jar'){Assert-True (Test-Path -LiteralPath (Join-Path $root $rel) -PathType Leaf) $rel}
Write-Output 'Preflight passed; this is not a successful game login or combat test.'
