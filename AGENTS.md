# 本地维护入口

开始前读取 [项目状态](docs/PROJECT-STATUS.md) 与 [工程经验](docs/ENGINEERING-LESSONS.md)，核对当前授权、工作树和设备归属。

Android TV 界面、遥控焦点、返回、弹窗或播放恢复验收使用 [android-tv-ui-qa](.agents/skills/android-tv-ui-qa/SKILL.md)：先复用低清连续采集与控件树，必要时高清截图；区分实际观测方式和未测范围。设备地址与授权每次重新确认，不操作其他任务设备，不重置共享 ADB。

播放速度/模拟器墙钟问题先读已有播放排障经验，不因截图或 MediaSession 再开重复性能实验。构建与安装按 [构建说明](docs/TV_BUILD_AND_RELEASE.md) 和 [数据边界](docs/TV_DATA_MIGRATION.md) 执行，保护正式包与预览数据。
