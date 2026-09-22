# Preview 4 发布回读

2026-09-22，已公开Pre-release：[v0.3.3-preview.4](https://github.com/znbsf/KazumiTV/releases/tag/v0.3.3-preview.4)。

- 远端tag及Release target：`4cc52a255ef18edf2dbf7fefe4debbc62a215305`；versionName 0.3.3-preview.4 / versionCode 50。
- 公共APK `KazumiTV-0.3.3-preview.4.apk`，10773133字节。GitHub asset `state=uploaded`，远端digest与本地SHA256均为 `123184ed1d284d77a6434b076672dca2fa3d741425519b5060f0eaf7169fd69a`。随附SHA256SUMS.txt。
- 直接检查公共APK的DEX，DANDAN_APP_ID / DANDAN_APP_SECRET字段均为空。公开包未使用本地配置包或私有配置文件。
- 最终公共包190项单测、lint及构建通过；旧电视与现代TV模拟器无凭证设置/视频专项通过。旧电视MXdm第12集两线首帧、推进、拖动及暂停/继续通过。
- 更广泛17源抽测、giri人工验证、跨源重入和电源恢复证据仍按各自code49候选记录，不冒充全部在最终code50重跑。
- 电视最终安装的是仅供用户本机的code50配置包，SHA256 `bb07e86538e9a69794885f36b0bbccf4e4879bf20b2e4a2d3fa3e7138505d1c0`，已重新打开应用；此包未上传。现代模拟器保留公共包。覆盖安装没有清除应用数据。
- 初次create因缩写target被GitHub以422拒绝，确认Release不存在后使用完整SHA成功。旧Preview3标签未移动或删除。

完整迁移仍未完成。真实人工验证码、来源失败、适用TV功能迁移与更多恢复场景继续按[迁移台账](MIGRATION-STATUS.md)推进，不做整集播放测试。
