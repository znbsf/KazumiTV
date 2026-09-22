# 播放优先迁移续作（2026-09-22）

工作目录为主目录 Kazumi，起点 `d80e9743`。公开版为 0.3.2-preview.1；本轮修复候选 0.3.3-preview.1 / 47。既有主页方向与用户数据保留。

## 本轮验收范围调整

用户明确要求不再做整集完整播放测试。后续采用针对性短时验收：真实来源搜索/验证、选集入播、播放推进、快进/暂停、换源换线、返回续播、错误重解析，以及系统杀进程、网络/待机恢复。各项单独记证据；不以首帧、组件重建或受控测试代表全部迁移完成，也不再把等待整集作为本轮退出条件。

原公开版 Sorani 实时整集用例已按用户要求中止。终止后通过测试 APK 的恢复入口，将测试前持久快照中的 `tv_settings` 与 `tv_library` 恢复并逐项比较相等。该运行仅标记用户取消，不算整集或自动下一集通过。原始快照仅本地保存。

## 固定基线与来源保护

- 本日远端 KazumiRules HEAD 仍为 `0d85fc80ab6c208548d9ee9c9e81271b08ff7f39`，目录 17 条。
- 电视来源盘点 17/17 已安装；执行先备份后仅补缺失项的流程，本次无缺失，保留启用/隐藏状态。备份已拉回本地。
- Kazumi 上游 HEAD 已更新至 `4fed48b527768782d66b127f171d96babd7c427b`；相对前次 `285fa01b` 的 `lib/services/plugin`、`lib/webview`、`lib/plugins` 与 `lib/utils/media.dart` 无差异。
- 物理电视 Android 9 / 旧 WebView，测试由主代理串行执行；本次未启动其他模拟器。

## 发现与修复候选

1. MXdm 第12集两条线路在原公开版仍失败于媒体发现。私有 console 将错误定位到 Artplayer bundle 的新语法，随后顶层页面 `Artplayer is not defined`；页面没有 iframe，但内联播放器配置有明确媒体 URL。增加受限静态配置提取，拒绝动态表达式/属性覆盖等不确定值；沿用媒体地址校验、请求头及 HTTP/content probe，不执行抓取的脚本。单测与电视结果分别补记。
2. 换线手选子页保存的是目录索引，恢复时目录尚未重新加载可能越界。子选择跟随目录生命周期重置，空目录提供返回路径。
3. 搜索原先仅在点击时保存焦点，滚动位置没有进入 SavedState。改为保存焦点、首个可见节目锚点和偏移，并重载最多五页的原窗口；恢复期间不自动翻页覆盖锚点。仍需组件及系统进程恢复分别验收。
4. 新增仅测试 APK 使用的持久用户数据检查点，支持宿主主动终止进程后恢复设置、历史和搜索历史；不将快照或值输出到公共日志。

## 真实系统恢复发现

正常主页编号进入既有 baimao 第13集历史，真实视频与弹幕可见。HOME 后执行 `am kill`，确认原 PID 21495 消失，再以 Launcher 语义恢复保留任务。09-22 10:08:57 的新进程 21858 崩溃：`Parcelable encountered ClassNotFoundException reading a Serializable object (name = org.kazumi.tv.data.Subject)`，栈经过 Compose `ParcelableSnapshotMutableState` 与 Android `Parcel.readSerializable`。这是实际系统恢复失败，不是来源错误。早期探索中有额外 Activity 的运行不作为验收，以清理活动任务后的这次独立复现为准；未清除应用数据。

该失败说明 Serializable 对象能通过组件 SaveableStateRegistry 并不能证明 Android 9 进程恢复安全。已改为明确字符串Saver，覆盖节目、历史入口、关联作品路径和人物路径。

最终APK正常入口复测：既有baimao第13集实际播放且6134条弹幕可见；HOME后确认Launcher处于前台，`am kill`后PID 24825为空；恢复原任务88，新PID 25196成功进入同集约01:06并保持暂停。显式确认后推进至01:17，真实画面与弹幕继续显示，Back可返回首页。这里只验证这条正常入口的系统回收路径，未将搜索/人物等所有页面或待机/网络恢复一并标为通过。

新增Parcel组件测试最终`navigation-parcel-47-final3.txt`通过四类编解码与真正的Parcel marshall/unmarshall重挂载。前两次失败为测试同步/注册项计数假设：Compose SideEffect未确认，以及一个registry key可含多个状态值；修复测试后通过，没有掩盖成生产修复。正常入口OS实测与此组件测试分别保留。测试结束将设置、历史、搜索历史三份检查点恢复并比较相等，电视返回正常首页。

## 最终构建与专项结果

- `build47-parcel.txt`：release、androidTest、188项单测与lint通过；之后仅修订测试装配并重编androidTest，发布APK未变。
- 发布APK SHA256：`83d8a7bd65ab09b29684aca6342d0e05f3ea94960cb5e5df7a5a9b22b2d2da48`，版本0.3.3-preview.1 / 47。
- `MXdm-47-final.txt`：最终静态提取器下两线第12集首帧、推进、拖动、暂停/继续均通过。此前完整17源轮7源14线结果和构建边界见[本日来源表](SOURCE-VALIDATION-20260922.md)。
- `road-selection-47-final.txt`：空目录/重排、长列表手选、歧义集数从零、返回及库数据保留通过。
- `s4-search-47-final.txt`：搜索返回、浏览焦点、锚点/偏移、窗口重建、恢复失败重试和空结果通过；受控结果不等于所有搜索来源。
- `playback-restore-47-final.txt`：会话重建、换源上下文、暂停位置、缺失来源、选集返回与隐身通过。
- `release-danmaku-47-final.txt`：不可调试发行APK内置凭证匹配并取得7310条真实评论；独立于上述真实baimao画面的6134条评论。

## 未关闭项

dalvdm 的实际验证 DOM 无图片且与固定 XPath 不符；mgnacg/giri 的电视验证、其他来源 HTTP/集表问题继续保留。系统回收仅上述真实路径通过，网络/待机及其他页面恢复未因新增组件测试自动变为通过。画质、同步、下载等其他迁移表项目保持原状态。

原始页面、签名 URL、Cookie、用户快照与 console 仅放本地忽略目录 `artifacts/source-audit-20260922`，公开记录只列阶段和脱敏结论。
