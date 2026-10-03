# 来源、依赖与资源

本仓库基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) 的 Flutter/Dart 业务、规则与电视适配，以及本仓库原生 TV 的布局和交互工作。项目遵循 [GPL-3.0](LICENSE)。原生版权与许可原文保留在 [native-history](native-history/THIRD_PARTY_NOTICES.md)。

当前 Flutter/Dart 依赖以 pubspec.lock 为准，声明由 Flutter 收集到应用的许可证页。固定 media-kit/libmpv、FFmpeg 等播放器依赖的原始许可、版本、构建补丁与对应源码见 [播放器依赖来源](docs/NATIVE_DEPENDENCY_SOURCES.md)，该声明区别于历史原生 Media3/Coil 依赖。

本应用使用 Xiaomi Inc. 的 MiSans Fonts，保留原字体且未修改；[官方协议原文](third-party/native/MiSans-License.en.txt)及署名可在应用许可证页查看。字体遵守自身协议，不随项目重新许可。

TV 图标和横幅复用本仓库原生 24bc50ef 的独立几何矢量 kazumitv_mark.xml。TV APK 已移除继承的六份 Flutter 人物 logo 和十份 Android launcher 位图。上游原始人物资源归 Yuquanaaa，其声明完整保存在[历史 README](static/doc/UPSTREAM_FLUTTER_README.md)，不将历史声明解释为新增授权。

节目海报为运行时在线资料，媒体及服务归相应权利人，本项目不托管影视资源。原生自制测试素材、OkHttp Public Suffix List 等历史说明和原文保留在 native-history 及[原生固定提交](https://github.com/znbsf/KazumiTV/tree/24bc50ef47af5e32907ed54413e1eb33c1fb601e)。
