# KazumiTV 0.4.0-preview.1

Flutter TV 融合预览：固定深色背景、五列大卡片、遥控器导航，继续使用 Dart 业务和 media-kit/libmpv 播放器。修复详情过渡透出旧页面、封面闪暗，以及长按取消误快进、分页焦点丢失、长按确认跨页重复激活。

## 下载与安装

| ABI | 安装包 | versionCode |
|---|---|---|
| ARMv7 | [KazumiTV-0.4.0-preview.1-armeabi-v7a.apk](https://github.com/znbsf/KazumiTV/releases/download/tv-fusion-v0.4.0-preview.1/KazumiTV-0.4.0-preview.1-armeabi-v7a.apk) | 203241 |
| ARM64 | [KazumiTV-0.4.0-preview.1-arm64-v8a.apk](https://github.com/znbsf/KazumiTV/releases/download/tv-fusion-v0.4.0-preview.1/KazumiTV-0.4.0-preview.1-arm64-v8a.apk) | 203242 |
| x86_64 | [KazumiTV-0.4.0-preview.1-x86_64.apk](https://github.com/znbsf/KazumiTV/releases/download/tv-fusion-v0.4.0-preview.1/KazumiTV-0.4.0-preview.1-x86_64.apk) | 203244 |

需要 Android 7.0+。新包名 `com.znbsf.kazumi.fluttertv`，使用本机专用长期证书，与原生、Legacy 和实验应用并存。不迁移旧原生收藏、历史或其他数据；保留原应用与导出备份即可切回。应用内 TV 自动更新暂未启用。

## 验证与限制

- 产品源码通过 663 项本地回归，分析 0 错误、0 警告、58 项 info。三 ABI 配置构建通过；ARMv7 有 Android 9 电视有限控制/播放/返回证据，x86_64 有模拟器保数据更新证据。
- **ARM64 仅完成构建，未实机验证。** 既有隔离包测试不冒充正式包或全部设备验收，正式产物信息以随附回执为准。
- 元数据搜索在测试电视上曾连接超时；已测规则搜索可返回结果。首页横向滚动 raster p95 仍约 43ms，不承诺 60fps。
- 长期播放、声音同步及全部站点未全面验收。既有稀疏位置样本不证明原生变速确认或 250ms 恢复上界。

随附三个 ABI 的 APK、产物核验 JSON、SHA256SUMS、对应源码 ZIP、GPL 与第三方 NOTICE；公开证书指纹、源码 SHA 和 APK SHA256 以这些实际产物记录为准。原生与 Legacy 历史发行继续保留。
