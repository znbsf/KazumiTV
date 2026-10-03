# 0.3.3 正式发布核验

发布于 2026-09-27 02:24:49 Asia/Hong_Kong（GitHub 时间 `2026-09-26T18:24:49Z`）。

- [正式 Release](https://github.com/znbsf/KazumiTV/releases/tag/v0.3.3)，GitHub `releases/latest` 返回 `v0.3.3`，`draft=false`、`prerelease=false`。
- 源码与注释 tag 原子推送成功；`v0.3.3` 解引用为 `c5d3c62edf76c8cbcbc0fbc11650a9794a517cfd`，包含最终生产修复 `69f28ba9` 和验收文档。
- [APK](https://github.com/znbsf/KazumiTV/releases/download/v0.3.3/KazumiTV-0.3.3.apk)：10,838,661 bytes，GitHub asset digest 与本地重新下载 SHA-256 均为 `84e10d47fc4da031191371d41db95acb194ad5d690f141ed3bba9eb7eda5fafb`。
- 同时下载的 `SHA256SUMS.txt` 内容与 APK 相等，校验文件 asset digest 为 `3e2bfcd44b49167759ebf65c00f4706334c14b52c545cf0ddf3bcee8db00586f`。
- 对重新下载的 APK 执行 `apksigner verify --print-certs` 成功，证书 SHA-256 `24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31`，与验收包及公开 Preview6 一致。
- 原失败候选未上传，未新增 Preview，未删除旧发布或 tag。Release 附件只有正式 APK 与校验文件，没有录制、用户数据、原始设备日志或测试 APK。

放行依据见[最终验收](RELEASE-ACCEPTANCE-20260927.md)，复用方法见[应用声画录制](AV-ACCEPTANCE-20260927.md)。首次发布成功后，此核验记录作为文档增量推送 main，不移动 `v0.3.3` tag，不重建或替换已验收 APK。

本机主目录的未提交工作保留，发布从隔离工作树执行，没有重置或覆盖主目录。测试任务分别恢复四项存储后关闭 5570/5584，保留各自 AVD 数据；本次未操作无法连接的旧电视。
