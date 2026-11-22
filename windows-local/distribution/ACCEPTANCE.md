# Verified on Windows / Windows 实测记录

**2026-11-22 — same Windows 11 x64 host, new isolated directories, not a clean OS/VM.** No production client, server process, database or account was reused for these runs. Read-only Git checkouts and vendor archives supplied the inputs. No loopback-capable standalone test client was available; no client was launched.

| Gate | Result |
|---|---|
| Server build from pinned source + 33-class patch | Two builds (including a path with spaces), 107/107 non-integration tests per build; deterministic 50-class combat-only overlay |
| Public build/packaging rules | 7 packaging tests; full server JAR with bundled upstream key material remains private |
| Portable runtime/install | Both vendor ZIP hashes checked; repeat installation leaves verified trees intact; mismatched archive rejected; no Windows service installed |
| Fresh data and database | Immutable source/resource exports, catalog rebuilt (126 characters, 260 weapons, 60 artifact sets); fresh private MongoDB directory, no original player data |
| Controller | Windows PowerShell 5 + .NET Framework builds, offline artifact/weapon/rule/save tests; both server plugins enabled in the real process |
| Actual API login | New randomly generated local test account, loopback login returned HTTP 200, retcode 0. Account was also verified again after directory rename and restart; no token or credential published |
| Isolation and lifecycle | TCP 8088 and UDP 22101 owned by staged Java; TCP 27018 owned by staged MongoDB; all bind only to 127.0.0.1. Both process identities checked and ports released after stop |
| Integrated assembly | An independent, second fresh instance was assembled via distribution/assemble.ps1 using a separately built JAR receipt and clean data. Panel backend started it, created a new account, reported 7.1.0 and two ready plugins, then shut it down |
| Client | Read-only known 7.1 executable/version check passed and a wrong version was rejected. No proof of game login, spawning, damage, applied in-game grants or inventory persistence. Login API and offline grant planning are not substitutes |

首次测试用非默认 UID 验证账号绑定、武器与命座预演；改成带中文和空格的目录后重新启动并核对原账号。第二套目录还完整跑了组装和控制面板的首次启停。均未复制原存档。注意：这是**同机干净目录**验收，不是换电脑实机验收。

Known startup warnings: the pinned resources lack the expected StatuePromote table (upstream fallback exists); one four-star epitomized pool is deferred until first use. Not assessed for gameplay parity. The stock client's region-signature policy remains outside this server-side adaptation. No client modifications, certificate installation, system proxy, hosts changes, firewall changes, or official login were performed.

未验证：战斗客户端进入世界、实际发装备、打木桩和装备存档重登。不把本版本标成可直接玩的整包。
