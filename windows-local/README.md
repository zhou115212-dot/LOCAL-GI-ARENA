# Windows local components / Windows 本地组件

The scripts, Windows Forms controllers, editor plugin and energy diagnostics in this directory come from the local 7.1 combat environment. The server-only start, stop and status entries are included as source. This is not a portable installer: the original scripts assume local paths, a separate compatible catalog and resources, a built server JAR, a local Java/MongoDB installation and runtime configuration. Do not point these tools at a production database. No player database or game data is supplied.

对应本机的角色命座、武器精炼与副本、五件套圣遗物编辑器、服务端插件和服务端独立启停入口。保留原工程布局供移植，不代表解压就能运行。部分路径和测试 UID 是原版的固定假设；不附账户、存档或密钥。

Server baseline / 服务端源码基线: [AstaPS at 0fac870](https://github.com/MeChen618/AstaPS/tree/0fac870873a35e88b9f969aa1b242a832b602005). The upstream tree alone does not include the local combat fixes.
