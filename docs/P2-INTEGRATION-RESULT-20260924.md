# KazumiTV P2 首页与播放基线集成结果

2026-09-24 · 状态：P2 内部集成验收完成；交付给统筹任务进入 P3。不是正式版放行。

## 候选与源码

- 播放基线：`9bb17ea6e77756428c43a00458efa652f364a2f5`，为 P1 独立工作树已审阅提交。
- 首页快照提交：`8a17f865`；并入播放基线的集成提交：`d2959105`。
- 当前候选代码提交：`6869a394`（`codex/p2-home-playback-20260924`）。包含首页集成、背景请求代次修复和测试诊断改进；P1 基线仍为其祖先。报告只增加文档，不改变应用代码。
- 未合并、推送或发布；P1 原工作树和主目录均未改动。

首页沿用单行双组导航、热门默认焦点、六列海报、最近观看、深处浏览时收起简介，以及详情返回后的焦点/位置恢复。左侧功能组字号较小、分类组字重较高。背景覆盖整窗并在文字/导航周围压暗，目前以焦点海报生成柔化全屏层，快速切换会拒绝过期图像结果。

当前目录没有可靠、稳定映射到 Bangumi 条目的宽幅场景剧照来源，因此**还没有真正的场景剧照**；全屏氛围层是封面回退。候选不会把竖封面拉伸成真实横图。剧照来源、ID 映射和授权需要另行验证。

## 构建产物

| 产物 | 大小 | SHA-256 | 签名 |
| --- | ---: | --- | --- |
| `app/build/outputs/apk/release/app-release.apk` | 10,838,669 bytes | `8D6B229D00FE5B3B1F09766C88A2FBC598F3202A24717EF7731DA8AA3481A22A` | Android Debug；证书 SHA-256 `24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31` |
| `app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk` | 4,491,578 bytes | `C33B1CEBA8E1750625289EE4C75E257CCA6B2779171C1D3C672E818F95D3F5B4` | 内部调试测试包 |

应用版本为 `0.3.3-preview.6`（versionCode 52）。上述 release variant 是本地内部候选，使用 Android Debug 签名，不可当作可升级正式发布包。

## 验收结果

| 检查 | 结果 | 证据与边界 |
| --- | --- | --- |
| 编译与静态检查 | 通过 | `:app:testReleaseUnitTest`、`:app:lintRelease`、`:app:assembleRelease`、`:app:assembleDebug`、`:app:assembleDebugAndroidTest` 均成功。 |
| 首页接受矩阵 | 6 项通过 | `home-ui-acceptance`：热门初始焦点、空目录、详情期间删除当前卡后的最近卡回焦、快速分类切换迟到结果隔离、清缓存刷新、离开首页取消简介请求。使用测试目录，不产生播放记录。 |
| Release 遥控路径 | 通过 | 在自有 `emulator-5584`（Android TV API 36、1920×1080）安装此 release APK；验证首页显示、打开真实目录详情、返回后恢复原海报焦点。截图：`release-home.png`、`release-detail.png`、`release-return.png`。 |
| 首次加载与慢网 | 通过 | 较慢网络下目录加载期间将焦点移到“日常”，完成加载后没有抢回焦点；最终目录成功加载。截图/XML：`slow-success.png`、`slow-success.xml`。 |
| 离线首页 | 通过 | 临时只拦截 Kazumi 应用网络，冷启动仍保留热门焦点，显示错误和重试入口，进程未崩溃。随后恢复应用网络并关闭临时防火墙规则。截图：`offline-valid.png`。 |
| 进程恢复 | 通过 | 首页第 9 张卡聚焦时离开并终止应用，再启动后焦点身份层级哈希与终止前一致；未记录哈希对应的标题值。 |
| 动态背景 | 通过 | 连续聚焦三个目录项目，日志观察到相应新封面与模糊背景加载，迟到结果不会覆盖当前焦点。仍是封面背景，不代表剧照源已接入。 |
| 播放/验证回归 | 本地夹具通过 | `recent-watch-navigation`、`player-controls`、`episode-session`、`verification-layout`、`playback-recovery`。这些覆盖本地路径，不等于同一候选的真实在线播放、真人验证码服务或扬声器听音。 |
| 用户数据与设备状态 | 通过 | `user_data_checkpoint_unchanged stores=3 label=p2-home-20260924`。`tv_settings`、`tv_library`、`search_history` 相对 AVD 检查点未变。慢网、应用防火墙和纯黑模式均恢复。 |

所有设备测试仅使用自建 AVD `emulator-5584`。没有操作实体电视 `192.168.123.217:5555` 或 `emulator-5560`。临时 AVD 结束后保留其 userdata；图片/XML 留在 Git 忽略目录 `app/build/p2-integration-evidence-20260924/`，没有提交目录快照或测试数据。

P1 基线上的真实来源播放证据仍按原 P1 矩阵记录，不会冒充在本 UI 集成候选上重新完成。P3 需要对这份整合候选做真实来源关键路径及目标电视回归，重点复核播放控制、续播、画面/音频和焦点体验。

## 后续平台能力

这次集成没有新增系统 `DreamService` 屏保、Android TV 主屏 Preview/Watch Next 频道，也没有将应用注册为 `ROLE_HOME` 启动器；普通应用启动入口保持现状。它们可以分别复用全屏图片展示、可选节目卡片和一行式桌面视觉，但需要独立阶段实现并在目标固件验证系统入口、用户授权/频道显示、Home/返回语义、其他应用与设置入口、退出恢复及数据更新。设为默认桌面是明确的 Launcher 阶段，不能由应用内首页视觉自动推出。

没有在设备上切换默认桌面、启用屏保或注册内容频道。阶段入口与平台设计见 [首页与系统入口设计交接](UI-DESIGN-HANDOFF-20260923.md)。
