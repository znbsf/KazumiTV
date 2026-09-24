# KazumiTV P3 正式候选验收交接

2026-09-24。P3 通过已执行的播放、首页、安装和数据保护检查；交付 P4 审核发布。此记录不是已公开发布的声明。

## 候选身份

- 代码基于 P2 集成提交 `76af6349`，其中 P1 播放基线 `9bb17ea6` 是祖先。本阶段只改版本号及测试隔离/诊断代码，没有改生产播放或首页逻辑。
- 正式候选 `0.3.3` / versionCode `53`，包名 `com.znbsf.kazumi.compose.tv`。忽略目录中的 APK：`artifacts/p3-release-candidate/KazumiTV-0.3.3.apk`，10,838,661 bytes，SHA-256 `32A3F9950B5DF05FD23B1A06A3334C0794DAE2A50082237B31C6470E076A3A77`。
- `apksigner verify --print-certs` 证书 SHA-256 为 `24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31`。公开 `v0.3.3-preview.6` APK 从 GitHub Release 下载、核对其发布 digest `e385e1f8be5087e6e363de26a7084bd36d2ea9ae368ad0ef1f19483b17c19278` 后，证书指纹相同。当前项目 release 变体仍使用本机 Android Debug 签名；这次确认的是与现有公开 Preview6 的实际升级兼容性，P4 应维持同一签名身份。
- `:app:testReleaseUnitTest :app:lintRelease :app:assembleRelease :app:assembleDebugAndroidTest --offline` 成功。NDK 缺 `source.properties` 导致 `libandroidx.graphics.path.so` 未剥离，构建工具将其原样打包；没有编译、测试或 Lint 失败。

## 设备结果

| 设备与包 | 路径 | 结果 |
| --- | --- | --- |
| API36 自有播放模拟器，P2 集成 APK | baimao 第 12 集真实同源换线、下一集、历史续播、首页最近观看返回；baimao→MXdm 第 12 集跨源；首页六项回归 | 全部 PASS；播放有画面时间推进与音频解码器建立，非整集/亲耳听音证明。原三项用户数据检查点相等，原主包与测试包已恢复。 |
| 小米旧电视 Android9 / WebView66，P2 集成 APK | baimao 第 12 集真实换线、下一集、历史续播、首页最近观看返回；首页六项回归 | 全部 PASS；AAC 使用 `OMX.google.aac.decoder`。首页夹具在临时清空最近观看、完成初始化后运行，结束恢复原设置和最近记录。 |
| 同一旧电视，正式候选 `0.3.3` | baimao→MXdm 第 12 集真实跨源，取消换源保持暂停、进度迁移、目标继续推进、返回目标来源/线路；首页六项回归 | 全部 PASS。跨源切换前 32 秒、目标首次 37.753 秒、继续到 42 秒。每次测试后以及最终恢复测试包前，`tv_settings`、`tv_library`、`search_history`、`tv_rules` 四项检查点相等。真实首页截图确认热门、最近观看、目录和海报在旧电视可见。 |
| 新建干净 Google TV API36 AVD，公开 Preview6→正式候选 | Preview6 首次设置 1–4 步，进入旧首页；安装正式 APK 覆盖升级 | 安装成功、包回读 `0.3.3` / 53，升级前后三项应用数据检查点相等，无需重进初始设置，进入新首页。随后仅在这台自有 AVD 清应用数据，正式候选重新完成首次设置并进入新首页。 |

以上真实来源结果仅限记录的两来源、单集和短时路径；没有整集播放、异片头时长、返回后二次入播、实体扬声器亲耳确认。音频解码链可见，但实际扬声器声音和画音同步仍待人耳确认。没有再执行验证码自动识别或提交。

## 状态与交接

- 旧电视始终保持亮屏，最后 `dumpsys power` 为 `mWakefulness=Awake`。四项用户数据核对后恢复了原测试 APK。原主 APK 是 versionCode 52；尝试 `adb install -r -d` 被系统以 `INSTALL_FAILED_VERSION_DOWNGRADE` 拒绝，因此**旧电视当前保留 versionCode 53 的正式候选**。没有卸载或清除电视应用数据；原包备份仍在忽略目录 `artifacts/p3-preserve/tv-before/main.apk`。若必须回退，需要专门的数据安全迁移方案，不能直接卸载重装。
- 自有播放模拟器的原主包、测试包已恢复，三项数据检查点在恢复前后均相等。新建的干净 AVD 仅用于安装/升级试验，最后安装正式候选。
- 私有日志和截图在忽略目录 `artifacts/p3-preserve/`，包括 `tv-final-real-source-switch.txt`、`tv-final-home-ui.txt`、`tv-home-ui-pass/`、`tv-final-real-home2.png`、`clean-public-home2.png`、`clean-upgraded-home.png`、`clean-final-home.png`；不提交个人观看内容、请求正文或截图。
- P4 须核对提交、APK SHA-256 与签名、发布目标 tag `v0.3.3` 是否仍空闲，再发布同一 APK。P3 没有创建 tag、推送或公开 Release。用户之前已授权在播放和界面通过后发布，声音亲耳核验是尚未得到的独立事实，发布说明不得写成已验证。

## 拟用 Release 摘要

`0.3.3` 整合播放恢复和电视首页：真实来源换线/换源、选集、续播与返回路径的修复及六列电视首页；支持从 `0.3.3-preview.6` 直接覆盖升级并保留设置与观看记录。测试范围包括 Android9 小米电视与 Android16 Google TV 模拟器。第三方站点可用性会变化，本次未验证所有来源或整集播放。

P4 已备好独立的 [Release 文案草稿](RELEASE-0.3.3-DRAFT.md)及忽略目录 `artifacts/p3-release-candidate/SHA256SUMS.txt`。交接后只读重查 `origin` 的 `v0.3.3` tag 得到空结果，GitHub 对应 Release API 得到 404；发布时仍须再查一次。完整候选提交 `26a17fb60b4808a471daffd265b99471dfbfc2d0`，工作树干净时交接。新增干净模拟器 `emulator-5570` 已通过 `adb emu kill` 关闭并从 `adb devices` 消失，AVD 与测试数据保留；预先运行的 `emulator-5560` 保持原状态。
