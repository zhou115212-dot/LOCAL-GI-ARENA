# Build the 7.1 combat server / 从源码构建战斗服务端

For maintainers, not a player installer. This builds the 33 reviewed combat source changes against the exact upstream revision in a new directory. It does not start a server, acquire a client, install services, change system settings, or read a player database.

面向维护者：在全新目录里从固定源码编译服务端、运行上游非集成测试，另外输出只含战斗改动类的覆盖包。此步骤不会启动游戏或服务，不会安装系统依赖，不会读取存档。

## Inputs / 准备

- Windows, [Git](https://git-scm.com/download/win), Python 3.9+ and a locally installed or extracted **JDK 21** (not just a JRE).
- A Git clone containing the [upstream AstaPS commit](https://github.com/MeChen618/AstaPS/tree/0fac870873a35e88b9f969aa1b242a832b602005). The working tree may be elsewhere: only the immutable Git commit is used, not local edits.
- The official [Gradle 8.5 binary ZIP](https://services.gradle.org/distributions/gradle-8.5-bin.zip), left zipped. The script checks the [official distribution hash](https://gradle.org/release-checksums/) before extraction. The source Gradle wrapper is not executed.
- A new private build directory **outside this public repository**. Budget several GB of disk and enough memory for the upstream 6 GiB javac worker. The build uses its own Gradle cache and temporary directories; it never writes to the source clone. The upstream non-integration tests do not require MongoDB.

## Build / 构建

In this directory, replace the example locations with your own. The source clone must contain the exact commit above. No extra clone is required if you already have one.

```powershell
python -B build.py --source "D:\Sources\AstaPS" --jdk "D:\Tools\jdk-21" --gradle-zip "D:\Downloads\gradle-8.5-bin.zip" --work "D:\Arena Build"
```

The default build downloads declared dependencies through Gradle's upstream repositories. For an offline build add `--offline-modules "D:\TrustedGradleCache\caches\modules-2"` from a trusted, populated Gradle 8.5 cache. Only module artifacts and resolution metadata are copied, not init scripts or build outputs. The dependency cache is **not** a cryptographically locked dependency manifest. Never use a cache from an untrusted PC. The offline path was exercised here; a first-time online dependency download was not tested.

需自行准备可信的 JDK、Gradle ZIP 及源码；示例中的盘符和目录都可替换。默认模式由 Gradle 解析上游依赖。离线模式仅复制已有可信依赖缓存，不使用已经编译好的服务端或补丁类。失败时不会删除工作目录；排查后可指定一个新的目录重试。

## What gets produced / 产物

| File in the private work directory | Purpose |
|---|---|
| `src/arena-server.jar` | **Private local runtime**, including upstream's embedded defaults and protocol/auth material. Not a public Release asset. |
| `src/data`, `src/lua`, `src/webstatic` | Upstream static directories from the pinned checkout. They are separate from 7.1 server resources. Do not substitute a live server directory with accounts or mutable state. |
| `combat-classes.jar` | Only compiled classes owned by the patched Java units, including their nested classes. **Not a standalone JAR, plugin, or game client**. If you built the full JAR above, it already includes those fixes; no second application is needed. |
| `build-result.json` | Pinned revision/patch hash, test counts, emitted class count and SHA-256 digests for this build. |

Do not publish the private work directory. It contains the full source checkout, caches and private-use runtime material. Keep source and attribution with any published combat changes (see the repository [license](../../LICENSE), [patch](../server-patches/combat.patch) and [source inventory](../server-patches/README.md)). The full JAR is not expected to be byte-identical across builds: archives contain timestamps. The class-only overlay is sorted with fixed timestamps.

## Resources / 单独的服务端资源

The pinned server expects a **separate 7.1 resource pack**. Its [upstream README](https://github.com/MeChen618/AstaPS/blob/0fac870873a35e88b9f969aa1b242a832b602005/README.md) identifies the companion repository. The observed [resource revision](https://github.com/MeChen618/AstaPS-Resource/tree/402e95270010df5929f51cca8652362ca3e5c07a) contains 65,462 Git files (2,478,073,686 uncompressed bytes, including notices). The six runtime directories are `BinOutput`, `ExcelBinOutput`, `Scripts`, `ScriptSceneData`, `Server`, `TextMap`. This is not the retail client. Its root has a [project MIT notice](https://github.com/MeChen618/AstaPS-Resource/blob/402e95270010df5929f51cca8652362ca3e5c07a/LICENSE); that notice alone does not document the provenance of every underlying game-derived asset. The public source archive and combat overlay contain none of those files.

只有零售客户端而没有兼容服务端资源，不足以通过服务端验收。资源目录与玩家数据库是两回事：前者是启动输入；后者应由新环境自行建立。本构建脚本不分发或转换游戏本体，也不运行客户端补丁。固定资源来源与构建成功都不等于已经进游戏验证。

## Checks / 验证

```powershell
python -B test_build.py
```

Packaging tests cover patch integrity for LF/CRLF, exact overlay membership, deterministic ordering, failure on missing or invalid classes, preserving prior outputs, Gradle checksum rejection, and rejecting failed/empty/all-skipped test reports. The real build uses Gradle `jar test -PexcludeTags=integration`; the integration-tagged test suite needs a running environment and is not counted. No claim of gameplay parity follows from these tests.

A comparison of the installed 7.1 server and its unpatched local baseline found 44 differing JAR entry names (per-entry SHA-256, including duplicate-entry order). The 43 changed class entries were all owned by the 33 source units; the other entry was an announcement JSON, not a combat class. This comparison covers these two JARs, not independently installed plugins, external resources, game files or player saves.

### Verification record (Windows, 2026-11-22)

Two independent source checkouts were built with JDK 21 and Gradle 8.5 using the pinned patch and trusted offline dependency metadata. One build path contained spaces. Both ran **107 non-integration tests: 107 passed, 0 skipped**. The unit allowlist and packaging checks additionally passed 7/7. Both full JARs contained 50 classes belonging to the 33 patched source units; the two generated class-only JARs were byte-identical, SHA-256 `7a8e240feb6cee346a84026abd1ecd961b61d763e0dd9581095bd72b0a3208a9`. Whole runtime JAR digests differed as expected. No live login, equipment or damage assertion is part of these results. The optional phlogiston diagnostic trace still filters on the historical fixture UID; that restriction is not used to apply gameplay fuel snapshots.

实测：两个新目录（其中一个路径含空格）分别从源码构建成功；每次 107 个非集成测试通过，另有 7 项打包测试通过。两次生成的纯战斗类覆盖包逐字节相同。该验收不包含登录、客户端兼容性或实战伤害。
