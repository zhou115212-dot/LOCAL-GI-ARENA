# Controller development / 控制器开发

Run scripts/build-local-test-tools.ps1 from a prepared local server distribution (on Windows, .NET Framework 4.5+ and JDK 21). It resolves paths from the script location; runtime-paths.json may use an absolute Java path or one relative to the installation. It reads the local server JAR for compilation. Supply compatible catalog/items.json, catalog/artifacts.json and 7.1 server resources; rebuilding both catalogs also needs a configured Node executable, source and localized name-data. The build compiles both plugins, the desktop manager and Java helpers, and runs offline checks with a disposable synthetic account before deploying plugins. Build in a stopped installation. Temporary compiler output lives under that installation's tmp directory.

首次启动并创建测试账号后，通过 client-tools/bin/IdLookup-v4.exe 打开角色、武器、圣遗物控制器。它读取本安装 run/test-account.json（username + 正整数 uid，没有密码）；没有绑定就停止，不自动选择数据库中的第一个玩家。服务器可以先启用插件、后创建账号。工具读取运行实例的 PID、可执行路径和启动时间，防止把发放送往另一个正在运行的实例。存档、审计、临时编译目录等均不属于发布内容。

The offline suite verifies catalog math, duplicate weapon planning/factory results, edit invariants and binding rejection. These tests are not live game input, live grants or damage parity tests.
