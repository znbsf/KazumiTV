# KazumiTV

面向电视遥控器的动画浏览与播放应用，基于 Flutter 和 media-kit。
首页提供横向分类、向下浏览和五列大卡片，支持收藏、历史记录及分集续播。

## 下载

当前版本：**0.4.0-preview.1** · [发行说明](https://github.com/znbsf/KazumiTV/releases/tag/tv-fusion-v0.4.0-preview.1)

| 安装包 | 适用系统 |
|---|---|
| [ARMv7](https://github.com/znbsf/KazumiTV/releases/download/tv-fusion-v0.4.0-preview.1/KazumiTV-0.4.0-preview.1-armeabi-v7a.apk) | 32 位 ARM 电视 |
| [ARM64](https://github.com/znbsf/KazumiTV/releases/download/tv-fusion-v0.4.0-preview.1/KazumiTV-0.4.0-preview.1-arm64-v8a.apk) | 64 位 ARM Android 系统 |
| [x86_64](https://github.com/znbsf/KazumiTV/releases/download/tv-fusion-v0.4.0-preview.1/KazumiTV-0.4.0-preview.1-x86_64.apk) | x86_64 Android / 模拟器 |

需要 Android 7.0 或更新版本，请按系统 ABI 选择安装包。
电视应用内自动更新暂未启用，更新包从本仓库 Release 获取。

## 安装与已知限制

- 新包名为 `com.znbsf.kazumi.fluttertv`，与原生版、Legacy 和实验版并存。
- 不迁移原生收藏、历史或其他旧数据；建议保留原应用与导出备份，便于切回。
- ARMv7 已有 Android 9 电视有限验证，x86_64 已有模拟器验证；ARM64 仅完成构建，未实机验证。
- 元数据搜索在测试电视上曾连接超时；已测规则搜索可返回结果。
- 部分首页滚动仍有长帧，不承诺 60fps；长期播放与全部站点尚未全面验证。

[版本记录](CHANGELOG.md) · [构建说明](docs/TV_BUILD_AND_RELEASE.md) · [数据说明](docs/TV_DATA_MIGRATION.md)

## 原生版本

[原生 0.3.3](https://github.com/znbsf/KazumiTV/releases/tag/v0.3.3)及其
[完整源码](https://github.com/znbsf/KazumiTV/tree/24bc50ef47af5e32907ed54413e1eb33c1fb601e)继续保留。
原生工程的文档与许可原文见 [native-history](native-history/README.md)。

## 致谢与许可

基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 及本仓库原生 TV 工作，感谢上游贡献者。
本项目不是上游官方 TV 版本，遵循 [GPL-3.0](LICENSE)；第三方声明见 [NOTICE](THIRD_PARTY_NOTICES.md)。
节目资料与媒体由相应服务提供，本项目不托管影视资源。
