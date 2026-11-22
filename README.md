# LOCAL GI ARENA
[简体中文](README.zh-CN.md) · [Setup](windows-local/distribution/README.md) · [Test record](windows-local/distribution/ACCEPTANCE.md)

LOCAL GI ARENA is a Windows project for **comparing team compositions and team DPS (average damage per second)** in a local Genshin Impact 7.1 CN test environment. Compare teams against the same training dummy over the same time window. To test a build, keep the team and rotation fixed and change one variable at a time: a character constellation, weapon refinement, artifact set, main stat, or substat. Compare burst damage, full-rotation DPS, and energy recovery. Some constellation effects have known bugs, so results may differ from the official game.

**Client requirement:** Supply your own Genshin Impact 7.1.0 Windows client for the Chinese region. The game client is not included in this repository.

**Client download:** [Quark Drive: 7.1.0 Windows base client for the Chinese region (Chinese voice-over included)](https://pan.quark.cn/s/c92a08de4fd5). Download all four ZIP files and extract each into the same empty folder, separate from your official installation. This is the client only; extracting it does not connect it to a local server.

**Disclaimer:** LOCAL GI ARENA is an unofficial local test build for learning and discussion only. It is not affiliated with miHoYo or HoYoverse. The game and its assets belong to their respective rights holders; the project’s open-source license does not cover the game client. Some constellation effects have known bugs, so test results should not be treated as official game values.

**What can I use today?** For the offline artifact worksheet, choose **Code → Download ZIP**, extract it, and open `planner.html`. It plans five pieces; it does not put them in a game inventory. For maintainers, use the [Windows assembly guide](windows-local/distribution/README.md) to build a separate localhost server, controllers and an empty account database. **A stock client and this source ZIP are not a playable game bundle.** The control panel checks the client build but does not change or launch it.

| Component | Included | Tested boundary |
|---|---|---|
| Characters and weapons | Windows editor, four-/five-star filtering, constellations, refinement, extra weapon copies and local account binding | Compile, offline rules, GUI controls and live account-targeted previews; no in-world grants verified on a new PC |
| Artifacts | Desktop single-piece and five-piece editors, main/substats, recipes; separate bilingual browser worksheet | Validation and controller builds. Browser worksheet never writes to accounts |
| Combat server | [33-class source patch](windows-local/server-patches/), [pinned build and tests](windows-local/build-server/) and [prebuilt tool components](downloads/) | Fresh server and two plugins running; not an exhaustive damage-parity or client gameplay test |
| Windows runtime | New-instance assembly, vendor archive checksum verification, local account initialization, start/status/stop, portable paths | Clean-directory cold start, local login API, directory relocation and restart, port ownership and clean shutdown |

**Scope:** combat testing only. Story progression, a newer client, official authentication and official damage parity are not supported. No full retail client, game resource mirror, private server JAR, player saves, private credentials or diagnostic logs are included. The original disabled Hydro resonance is a local test preference, not proof of game parity. An optional phlogiston trace still assumes one diagnostic UID.

Server baseline: [AstaPS](https://github.com/MeChen618/AstaPS/tree/0fac870873a35e88b9f969aa1b242a832b602005). This repository contains the local controllers, integration work and combat changes; it does not claim authorship of the upstream server or game. See [LICENSE](LICENSE). The README, setup guide and browser planner are bilingual; the desktop editors are primarily Chinese.
