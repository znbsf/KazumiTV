# 2026-09-27 首页离屏分类焦点崩溃修复

阶段：修复与本任务回归完成，新候选已交 UI 任务独立复测；未推送或发布。

## 缺陷与修复

UI 任务两次复现旧候选的遥控路径：热门向右9次到热血，下到第6张海报，左5次到第1张，向上进入固定导航，移动到收藏，向右回热门。此时热门已经离开 LazyRow，旧代码直接对未挂载的 FocusRequester 请求焦点，抛出 IllegalStateException 并退出应用。原 P3 APK `32A3F995…` 保留，不再作为放行包。

独立工作树 `C:\Users\hentai\.codex\worktrees\kazumi-focus-fix-20260927\Kazumi`，分支 `codex/home-nav-focus-fix-20260927`，基于 `ba251361`；修复提交 `69f28ba9cb566209f2c89564699a3da3bf33ad9c`。没有修改主目录、P2 或原 P3 工作树。

跨组左右键现在通过首页已有的 `requestHomeFocus` 路径滚动目标入视野，以 `onGloballyPositioned` 和 `DisposableEffect` 记录实际布局/移除状态，等目标已布局才请求焦点。导航意图带当前用户按键代次；后续按键或离开首页取消旧协程，迟到请求不能抢回焦点。没有捕获异常后忽略按键，也没有更改播放/来源/签名逻辑。

## 新最终候选

| 属性 | 值 |
| --- | --- |
| 版本/包名 | `0.3.3` / code53；`com.znbsf.kazumi.compose.tv` |
| 文件 | `artifacts/release-focus-fix-20260927/KazumiTV-0.3.3.apk`，10,838,661 bytes |
| SHA-256 | `84E10D47FC4DA031191371D41DB95ACB194AD5D690F141ED3BBA9EB7EDA5FAFB` |
| 签名证书 SHA-256 | `24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31`，与原候选及公开 Preview6 相同 |
| 测试 APK SHA-256 | `34DF737C2861921EC20473C792BCBD4B049C60A1C397499E7722A6EE6D5E4E0F` |

代码提交后再次构建 release 产物，并在此最终文件覆盖安装后执行以下最终包检查。设备侧 sha256sum 与表中完全一致。版本码不增加新的 Preview；旧 code53 候选可直接覆盖。

## 检查结果

- `:app:testReleaseUnitTest :app:lintRelease :app:assembleRelease :app:assembleDebugAndroidTest --offline` 成功；56份单测报告、229项、失败/错误0。既有 NDK source.properties 缺失警告导致一项库未剥离，工具原样打包，无构建或 Lint 失败。
- 新 `home-navigation-edges` 在最终 APK 通过：原始路径进入收藏时断言热门节点已不在可访问树；向右后焦点真实到热门，截图有焦点边框。普通左右跨组、分类相邻导航、一次UI回合6次Right、Right+Center立即离开首页、历史返回导航身份、详情返回原海报均通过。
- 原有 `home-ui-acceptance` 在最终 APK 六项通过：热门初焦点、空目录、删除卡片的最近卡恢复、迟到分类隔离、清缓存、离开首页取消简介请求。
- 最终 APK 的 baimao 第12集实际搜索/详情/集表入播与60秒无输入短播通过；位置9575→69530ms，测试关闭播放器并恢复原三存储。没有整集、全来源矩阵或重复声画录制。
- 四项存储 `p3four-focusfix-20260927`：测试前备份；临时 baimao 导入后整体 restore，最终 verify unchanged（设置、收藏/历史、搜索历史、规则）。没有修改音量或家庭音频路由。AndroidRuntime错误输出为空。

第一次新回归在“第6海报聚焦”断言失败：同名简介标题在可访问树中先出现，测试只查第一节点；截图确认第6卡实际聚焦。修正为检查所有同名节点后，第二次在假设“Up必到设置”断言失败，截图显示实际到搜索。原复现只要求进入固定导航，故改成检测固定导航焦点后再移到收藏。以上失败日志保留，不是生产崩溃；第三次及最终包复跑通过。

本地私有证据仅在忽略目录 `artifacts/focus-fix-20260927/`：`navigation-edges*.txt`、`final-navigation-edges.txt`、`final-home-ui.txt`、`final-real-short-play.txt`、`final-data-verify.txt`、`final-nav-screens/nav-before-cross.png` / `nav-after-cross.png`；校验文件位于新 APK 同目录 `SHA256SUMS.txt`。

## 证据适用范围与交付

本轮自有 `emulator-5570=Kazumi_P3_Clean_API36`，Android16 Google TV；独立UI任务使用5584，本任务没有碰它。原9月27日声画录制属于旧 `32A3F995…` APK：播放器代码此次未改，可辅助审查，但不能冒充新包的完整声画矩阵或旧电视音频录制。本轮没有连接或扫描旧电视，不能写旧电视上的修复通过。

所有 instrumentation 已结束，5570通过 `adb emu kill` 关闭并从ADB列表消失；AVD和数据保留。只剩UI任务5584。新 APK、修复提交和上述复现步骤已直接交 UI 任务独立复测。

本任务建议：修复后已执行路径通过，未发现新的播放阻断；当前状态是等待独立UI复测/统筹审查放行，不自动发布。Release草稿已更新新hash和焦点修复说明。原 APK 与声画样本完整保留。
