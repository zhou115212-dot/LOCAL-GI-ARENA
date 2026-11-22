# First use / 首次使用

**Users:** the working browser worksheet needs only `planner.html`. The compiled [tool components](../../downloads/) are not a game installer. Selecting a client only inspects its local build. The current upstream [client compatibility note](https://github.com/MeChen618/AstaPS/blob/0fac870873a35e88b9f969aa1b242a832b602005/README.md) explains why a stock client does not accept a private region by default. This project does not alter that check, change Windows networking or start a retail client.

**普通用户：** 网页规划器解压即可用。预编译组件不等于完整游戏。选择客户端只进行本地识别；不配置连接。原版客户端默认不接受非官方区服，本项目不改游戏、代理、hosts、证书或系统服务。

## Build a private instance / 组装到新的空目录

**Maintainers only.** Windows x64, Windows PowerShell 5.1, .NET Framework with CSC, Git, Python 3.9+ and a current Node.js. Use enough free disk for Gradle caches, source, resource sets and the database. Run as a normal user. Stop if an input cannot be obtained from a trusted source you are entitled to use.
构建者需准备上述工具及以下输入。程序只导入固定提交的静态数据，不导入旧数据库、账号、日志。目标必须是**尚不存在**的新目录。

| Input | Source / pinned version |
|---|---|
| Source clone | [AstaPS](https://github.com/MeChen618/AstaPS/tree/0fac870873a35e88b9f969aa1b242a832b602005), `0fac870873a35e88b9f969aa1b242a832b602005` |
| Compatible server resources, separate from the stock client | Local Git checkout at `402e95270010df5929f51cca8652362ca3e5c07a`; six directories listed in [build notes](../build-server/README.md). No resource mirror in this project. |
| Chinese item labels | [genshin-db](https://github.com/theBowja/genshin-db/tree/49a6544a6c6ae36089cb42fa591fc46f01de8bcf), working checkout of characters, weapons, artifacts and LICENSE at that revision |
| Tools | Official Gradle 8.5 binary ZIP; Temurin JDK 21.0.12.1+1 and MongoDB Community 8.0.32 Windows x64 archives. The runtime installer checks pinned SHA-256 before extracting. No MongoDB Windows service, Compass or system Java installation. |

In **windows-local/distribution**, replace every example path. First-time Gradle may download declared Java dependencies. Use only trusted source clones and dependency caches. If you have the official runtime archives, replace `-DownloadRuntimes` with `-JavaArchive "..." -MongoArchive "..."` for offline extraction. Gradle offline mode additionally requires `-OfflineModules "path to trusted modules-2"`.

在本目录的 PowerShell 中执行，路径换成自己的。下载开关只用于两个官方运行库；不会下载游戏或自动获取游戏资源。

```powershell
.\assemble.ps1 -Destination "D:\My Arena" -SourceRepo "D:\Sources\AstaPS" -ResourceRepo "D:\Sources\ArenaResources" -NamesRepo "D:\Sources\genshin-db" -GradleZip "D:\Downloads\gradle-8.5-bin.zip" -BuildWork "D:\Arena Private Build" -DownloadRuntimes
```

If you already ran [the verified build recipe](../build-server/), replace the GradleZip/BuildWork arguments with `-TrustedBuild "D:\Arena Private Build"`. The assembler checks its receipt, test counts and JAR digest. The receipt is not a signature: only use a build you made yourself. A failed assembly leaves an incomplete **private** directory for inspection; choose another unused path for a retry.

## After assembly / 组装后

1. Open **Open-Arena.cmd** in the **new instance**, not the source checkout. Start server also creates a new random-password local account on first launch. Local account shows it on request. Never enter official account credentials. / 双击新目录的启动面板，点“启动服务端”，首次会创建测试账号。
2. Start the editor with **Equipment**. Actual inventory operations require the bound account to be in the world; an offline plan is not a grant. / “角色与装备”打开管理器，实际发放要求该账号已进入世界。
3. **Status** shows service status. For strict checks run `.\portable-server\health.ps1 -RequirePlugins -Json` from the instance after startup. / 可验证 HTTP、游戏 UDP、数据库和两种插件。
4. **Stop server**, then `.\portable-server\health.ps1 -Stopped -Json`. Back up private state only after shutdown. To relocate, move the entire stopped instance on the same computer and use the control panel; it rediscovers bundled runtimes. Stored credentials are protected by Windows for that user; moving an existing account to another computer is not a supported save migration. / 停服后再迁移，勿把私人运行目录公开。新电脑应创建新账号。
5. To update, assemble a new directory and test it separately. To uninstall, first verify stopped, preserve any saves you want and remove only your own instance directory. No service, system proxy or certificate to uninstall. / 更新另建目录，卸载前先停服并保留需要的存档。

The setup does **not** launch a game or claim an in-world test. See [tested vs. outstanding](ACCEPTANCE.md).
