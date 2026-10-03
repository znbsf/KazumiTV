# 原生首个公开测试版

2026-09-16，0.3.0-preview.1 / versionCode43。

- Release构建、134项单元测试、lint通过；APK v2签名验证通过，不可调试，保留测试安装签名以支持现有开发包覆盖。
- 小米Android9电视实际覆盖安装成功，使用隔离的空凭证配置验证包内默认凭证，Bangumi映射及7309条弹幕下载通过。
- 同一Release包运行downloads-adaptive通过：条件续传拒绝变化资源、从头重下、HLS/DASH缓存内容与断网实际视频画面及删除。
- APK未捆绑Flutter/libmpv，通用包10.11 MiB；源码标签与该发布对应。自制测试素材和instrumentation不进入主APK。
- 首页/详情截图取自同一发布准备期间的实机界面，播放器截图是自制视频的控制栏/外播返回测试，不冒充实际影视播放。
- 本次不是所有来源、整集连续播放、全部遥控与重启路径的全量验收。详细未完成项见MIGRATION-STATUS与ROADMAP。
- 公开包按维护者选择内置弹幕凭证，已说明可被提取；源码、日志和Release附件不提供明文凭证文件。用户本地覆盖优先。

旧FlutterTV路线独立标签v2.3.1-tv-legacy.1，326项测试通过，双ARM APK构建完成。旧版并不与原生版数据互通，之后主力维护原生main。

发布前根据实机启动器反馈，为同一MainActivity补充普通LAUNCHER类别，并将应用名称标明KazumiTV 原生。电视上另有两条历史Flutter路线，并非原生版重复安装。
