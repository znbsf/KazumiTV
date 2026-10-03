# 版本记录

## 0.4.0-preview.1 — Flutter TV 预览

发布身份为 `com.znbsf.kazumi.fluttertv`，使用本机专用长期证书；基础版本号 20324，对应 ARMv7 203241、ARM64 203242、x86_64 203244。标签为 `tv-fusion-v0.4.0-preview.1`。

- 保留成熟 Flutter TV 的 Dart 业务与 media-kit/libmpv 播放器，融合原生电视布局；Compose 实验默认关闭。
- 首页采用固定深色背景、单排导航、五列大卡片；修复详情过渡透出旧页面及封面闪暗，保留 Hero 与淡入动画。
- 修复播放器长按取消误提交快进、分页加载期间丢失待显示焦点、长按确认跨页再次激活按钮。
- 复用旧 WebView 兼容和解析修复；Android 9 ARMv7 隔离包完成有限续播、持键/取消及退出返回验证。
- 产品源码通过 663 项本地回归，分析 0 错误、0 警告、58 项 info；三 ABI 配置构建通过，x86_64 完成模拟器保数据升级。正式签名产物的来源和哈希随 Release 提供。
- CI 仅执行无秘密的分析、测试和三 ABI 候选构建；正式发行在本机签名，不配置 GitHub 签名 secret。
- 新包并存安装，不迁移旧原生收藏、历史或其他数据；原生源码、历史 Release 与许可保留。

已知限制：测试电视的元数据搜索曾连接超时，已测规则搜索可返回结果；首页横向滚动 raster p95 仍约 43ms，不承诺 60fps。ARM64 仅构建、未实机验证；长期播放、声音同步及全部站点未全面验收。

## 0.3.3 — 原生 Kotlin/Compose/Media3

包名 `com.znbsf.kazumi.compose.tv`，versionCode 53。历史功能和验收范围见[原始发行记录](https://github.com/znbsf/KazumiTV/blob/24bc50ef47af5e32907ed54413e1eb33c1fb601e/docs/RELEASE-0.3.3-STABLE.md)。

## 2.3.1-tv-legacy.1 — Flutter Legacy

保留[原始标签与制品](https://github.com/znbsf/KazumiTV/releases/tag/v2.3.1-tv-legacy.1)。本预览采用不同包名，不是 Legacy 的覆盖升级。
