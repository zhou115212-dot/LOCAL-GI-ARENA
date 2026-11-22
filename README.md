# LOCAL GI ARENA
[Windows controller and server scripts / Windows 控制器与服务端脚本](windows-local/)

[简体中文](README.zh-CN.md)

LOCAL GI ARENA is a Windows project for testing Genshin Impact combat locally on a fixed 7.1 baseline. Its only supported use is combat testing: hold the party and target constant, change one build variable, then compare damage, energy or buffs.

**Quick start:** Download and extract the source ZIP, then open [planner.html](planner.html) in your browser. The GitHub file viewer only shows its source. In the planner, switch between English and Chinese, pick a set, rarity and main stat for each slot, then export a JSON worksheet. A fictional example is included; compatible local artifacts.json catalogs retain their original labels. The page runs locally and never grants items or connects to an account.

## Feature inventory

| Area | Local 7.1 installation | In this repository draft |
|---|---|---|
| Characters | Search names and IDs; filter by rarity; fill missing characters; set C0–C6 individually or in batches; undo eligible recent edits | [Windows controller sources](windows-local/); no standalone installer |
| Weapons | Set refinement by filter or max out refinable four-stars; add multiple independent copies with a chosen level and refinement | [Windows controller sources](windows-local/); no standalone installer |
| Artifacts | Generate a single piece or a five-piece set; select main stats per slot; tune substat rolls, match a target value, save/load recipes, choose standard or unrestricted budgets | Bilingual main-stat planner; original C# calculation and validation code and catalog-specific tests. No inventory writes or full recipe editor in the web version |
| Combat | Server training target and DPS measurement; targeted fixes to particle counts and coordinates, recharge, HP sync, constellation state and talent notifications | A special-passive partitioning example, not the full combat engine or patch set |
| Runtime | Local server and database, update lock and critical-file checks. After the client exits, the supervisor waits 30 seconds before requesting an orderly server and database shutdown; observed in a real session | Exit decision logic and tests only; this helper alone does not start or terminate any process |

## Limits and open work

- Story progression, questing and general world exploration are outside the supported scope.
- There is no exhaustive live parity test for phlogiston, constellation follow-up hits, party buffs or final damage. Use DPS results for comparisons within this build, not as an official damage benchmark. Disabled double-Hydro resonance is a local preference, not a correctness fix.
- Cold start: the local supervisor now writes independent logs instead of holding open the output pipes of the caller. The [Windows regression](runtime-tests/test_wait.py) reproduces the former delay with a harmless timer and verifies that the caller returns before the timer finishes. In one real cold start, the server became ready at 14:33:46 and the game process started at 14:33:49. The client reached the login flow. Foreground window visibility and entry into the world were not verified.
- Newer clients are outside the 7.1 baseline. Full disconnected play and relocation to another drive or PC have not been validated; the local installation uses fixed paths.
- The README and browser planner are bilingual; the full Windows controllers are not yet fully translated.
- This source collection is not an installer. No game binaries or assets, accounts, saves, secrets or private logs are distributed.

## Code and credits
[Artifact math](planner/) · [Exit watcher and tests](lifecycle/) · [Server reference](server-reference/). The C# tests require a compatible 7.1 catalog and .NET Framework with System.Web.Extensions. The browser example does not. The server baseline is [AstaPS](https://github.com/MeChen618/AstaPS) revision 0fac870873a35e88b9f969aa1b242a832b602005. We credit upstream separately from the tools, integration and fixes developed here. This project is not affiliated with miHoYo or endorsed by upstream. See [LICENSE](LICENSE).

[Settings and first use](SETTINGS.md)
