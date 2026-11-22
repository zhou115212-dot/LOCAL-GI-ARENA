# LOCAL GI ARENA
[简体中文](README.zh-CN.md) · [Setup](windows-local/distribution/README.md) · [Test record](windows-local/distribution/ACCEPTANCE.md)

LOCAL GI ARENA is a Windows project for testing combat in the Chinese version of Genshin Impact 7.1. Adjust character constellations, weapon refinement and artifact stats to see how they affect damage, energy and buffs. Some constellation effects still have known bugs, so results may differ from the official game.

**Client requirement:** Supply your own Genshin Impact 7.1.0 Windows client for the Chinese region. The game client is not included in this repository.

**What can I use today?** For the offline artifact worksheet, choose **Code → Download ZIP**, extract it, and open `planner.html`. It plans five pieces; it does not put them in a game inventory. For maintainers, use the [Windows assembly guide](windows-local/distribution/README.md) to build a separate localhost server, controllers and an empty account database. **A stock client and this source ZIP are not a playable game bundle.** The control panel checks the client build but does not change or launch it.

| Component | Included | Tested boundary |
|---|---|---|
| Characters and weapons | Windows editor, four-/five-star filtering, constellations, refinement, extra weapon copies and local account binding | Compile, offline rules, GUI controls and live account-targeted previews; no in-world grants verified on a new PC |
| Artifacts | Desktop single-piece and five-piece editors, main/substats, recipes; separate bilingual browser worksheet | Validation and controller builds. Browser worksheet never writes to accounts |
| Combat server | [33-class source patch](windows-local/server-patches/), [pinned build and tests](windows-local/build-server/) and [prebuilt tool components](downloads/) | Fresh server and two plugins running; not an exhaustive damage-parity or client gameplay test |
| Windows runtime | New-instance assembly, vendor archive checksum verification, local account initialization, start/status/stop, portable paths | Clean-directory cold start, local login API, directory relocation and restart, port ownership and clean shutdown |

**Scope:** combat testing only. Story progression, a newer client, official authentication and official damage parity are not supported. No full retail client, game resource mirror, private server JAR, player saves, private credentials or diagnostic logs are included. The original disabled Hydro resonance is a local test preference, not proof of game parity. An optional phlogiston trace still assumes one diagnostic UID.

Server baseline: [AstaPS](https://github.com/MeChen618/AstaPS/tree/0fac870873a35e88b9f969aa1b242a832b602005). This repository contains the local controllers, integration work and combat changes; it does not claim authorship of the upstream server or game. See [LICENSE](LICENSE). The README, setup guide and browser planner are bilingual; the desktop editors are primarily Chinese.
