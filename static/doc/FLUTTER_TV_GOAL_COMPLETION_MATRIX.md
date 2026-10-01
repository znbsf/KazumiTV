# Flutter TV 整体目标核验矩阵（2026-10-01）

实验分支沿用官方 Dart 业务、Hive 与 media-kit/libmpv。原生对照固定在 `24bc50ef47af5e32907ed54413e1eb33c1fb601e`，Flutter 起点为 `c54b2fd492a4baa4f5e8d604a2b2c83593ce0cda`，官方业务基线为 `1b395a501f7712d17adbe77a95af65743bf736f9`。本矩阵逐项核验用户流程；原生项目的历史测试结果不计作本分支通过。

## 用户流程与 UI/UX 对照

| 流程 | Flutter 的实现与证据入口 | 与原生的差异、完成判定 |
|---|---|---|
| 首次安装、规则准备 | TV onboarding 四步、遥控器继续/返回；`tv_settings_navigation_test`、`tv_defaults_preview_test`；独立 API36 x86_64 AVD 冷安装及引导截图 | 沿用官方引导及规则编辑；TV 禁用应用内更新。Google TV 系统账户登录不属于应用引导，也不绕过。 |
| 首页、搜索、分页、详情 | `tv_home_return_focus_test`、`tv_search_return_test`、`tv_popular_scroll_test`、`tv_unattended_workflow_test` | 返回以番剧 ID 定位并保留视口，重排/删除有相邻回退；保留 Flutter 卡片密度、菜单与热门/时间表。原生首页直接“最近观看”频道目前由历史入口承接，并未实现首页同款频道；是否增设须产品选择。 |
| 多源查询与章节 | 真实规则引擎、HTTP、XPath/API 规则；`rule_engine_test`、`api_rule_engine_test`、`cross_source_resume_test`、`tv_unattended_workflow_test` | 不复制原生抓取内核；异常、取消、旧请求迟到由 Dart 会话边界控制。模拟器两源 fixture 查询、取章节实际运行；公网提供商可用性、登录验证码不由本地 fixture 证明。 |
| 详情简介、相关条目、画面连续性 | `info_page.dart` 背景图片/渐变；卡片 Hero；`info_tabview.dart` 长简介折叠；`tv_detail_actions_test` | 原生固定简介高度、六列首页布局没有逐像素移植；Flutter 简介在标签内容区域，保留自身布局。避免突然黑背景与返回视口跳转已有实现，实际外观需截图评估。 |
| 真实播放、音频与解码 | 生产 `VideoPage`→WebView 视频地址解析→`PlayerController`→MediaKit/MPV；`player_bridge_ownership_test`、`pip_entry_request_test`；API36 x86_64 合成 MP4 实测 | 默认 TV `mediacodec_embed` 首次播放成功、切集 ANR，尚未通过完整设备验收。独立测试入口软件解码连续切集成功，不能替代默认路径。虚拟 AudioTrack/MediaSession 有状态，未验收物理声音；AVD 不声明 PiP feature。 |
| 同源换线路、下一集 | `episode_identity_test`、`online_history_resume_test`、`cross_source_resume_test` | 正片/OVA/SP/预告类型及 URL 身份隔离，唯一匹配映射到新列表真实位置；歧义不自动续播，跨源明确确认，不用数字位置冒充同一集。 |
| 长列表选集、当前/已看 | Flutter 数字定位及独立 Compose Activity（每段50、倒序）；`tv_native_episode_flow_test`、`episode_browser_same_input_test`、Kotlin `EpisodeBrowserSameInputTest` | 同一 CSV 八种输入输出逐项对照。默认 Compose 关闭，可运行时切换，缺组件自动回到 Flutter。两界面的业务结果相同，不声称完全相同布局或性能。 |
| 历史、最近观看、收藏 | `tv_history_return_focus_test`、`tv_collection_return_focus_test`、`history_repository_test`、`playback_history_recorder_test` | 历史持续写入由单 Dart 协调者串行化；退出/重启保存真实来源/集身份和位置。收藏三状态保留官方交互；原生“最近观看”单独首页频道属于上文决定点。 |
| 遥控器焦点、Back、视口 | `tv_focus_regression_test`、上述三类返回测试、`tv_channel_input_test`；选集取消焦点修复 | 返回按钮禁用期间不请求焦点；重新启用后仅在相同会话且当前路由恢复。后来一次方向键移动取消旧恢复意图。实体遥控器键码和厂家兼容仍需设备。 |
| 本地备份、导入预览、撤销 | `local_library_backup_test`（39项）；`tv_settings_navigation_test` 的3条真实备份预览返回测试；模拟器保存/预览/确认/撤销截图 | 修复 TV 双栏设置直接移除子路由、绕过 PopScope 的缺陷，系统及两处工具栏返回先取消预览。确认前检查修订，写三个库串行化、失败回滚；5个轮换副本。撤销为当前页内存会话，离页/进程重启失效；与原生3副本及 Activity 保留方式不同。原生 JSON 明确拒绝，不宣称跨实现迁移。 |
| 规则失败、挑战与诊断 | 非2xx挑战判定、规则错误重试与取消；`rule_engine_test`、`api_rule_engine_test`、`search_failure_state_test`、`player_diagnostics_test` | 保留官方恢复界面；诊断展示白名单 MPV 属性，不暴露完整播放 URL/凭据。原生特定诊断文件导出与失败规则报表未逐项搬入。 |
| 弹幕、屏蔽词、繁简 | 类型化屏蔽 WebDAV 同步/删除墓碑，转换模式实际传到请求；`upstream_blocklist_sync_test`、`danmaku_conversion_request_test`、`webdav_service_test` | 已接纳确定上游增量；在线弹幕服务/账户会话由设备网络决定，模拟器合成播放不证明公网弹幕响应。 |
| 下载、离线播放 | 原有下载管理、后台任务和离线路由保留；本轮未增加下载平台专项测试 | 未迁移原生 Media3 下载器；SAF/通知权限弹窗及后台长时间存活未在模拟器运行，需平台实测。 |
| 跨设备同步 | 官方收藏/历史/WebDAV 服务；类型化屏蔽同步扩展 | 不迁移原生私有同步格式；没有使用用户账户进行线上写入。双端真实服务验收需要用户已有配置。 |
| 更新、发布、安装覆盖 | TV flavor、ABI拆分、Leanback manifest、APK签名检查；分支发布证据 | 实验签名与 Legacy 不同，不能证明原地覆盖；不卸载旧包。GitHub token 无 workflow 权限，工作流提案仅本地保存，远程没有检查不等于通过。 |
| 图像、着色器与系统增强 | 沿用 Flutter 内置 shader 和设置入口；media-kit 提交及依赖锁冻结 | 不复制原生系统增强、厂家设置或 QuickSR 构建任务。虚拟机软件 GPU 无法判定真机 GPU/内存/功耗收益。 |

## Compose 的单一业务所有权

Dart 创建只读显示快照：会话 ID、修订、匿名集 ID、截短标签、当前/已看状态、初始位置。完整播放地址、规则、历史库、播放器和业务回调均留在 Dart。Kotlin 只展示并返回一次 selected/cancelled；重复结果、过期修订、旧路由结果一律不执行。Activity Back、停止、销毁、宿主解绑有取消边界。打开组件前由 Dart 暂停播放器，取消不偷偷自动续播，以便 HOME 后保持安全生命周期。

同输入 CSV 位于 `android/app/src/test/resources/episode_browser_cases.csv`；Dart 覆盖 native、fallback 以及缺组件降级，Kotlin 覆盖实际解析/窗口/单次协调结果。八项包含50/51分段边界、倒序、151集、201末尾、5000上限和 Back。对照证明的是原始集身份与业务动作一致。旧四列浏览第151集约40键，新数字定位约5键，两种新实现都有数字定位；未测量同设备输入延迟、帧时间或内存，因此不宣称 Compose 更快，也不默认开启。

## 上游截止与取舍

截至本轮观察，官方审计上限为 `0ea0bbd455a4ce4d30927f84cd50d1d2b2308a18`，相对业务基线的45个提交已逐项读取实际差异。完整 SHA、采纳/保留 TV 差异/暂缓理由见 [上游逐项表](FLUTTER_TV_UPSTREAM_DISPOSITION.md)。已采纳启动历史同步尊重开关、搜索历史去重、非2xx挑战、类型化屏蔽同步和繁简转换请求链路。media-kit/新SDK包、21文件全屏所有权、ECH新依赖、图库/SAF截图和25宿主公共菜单改造均有具体兼容/范围理由；本实验版本不能称为整套最新官方版本。

## 可复现构建与设备验证

使用 Flutter 3.47.3 / Dart 3.13.3、JDK21、Android SDK36 和锁定依赖，Gradle最多2 worker、不开并行、堆2GiB，单次只跑一个构建。TV 的手机/桌面入口保持原有边界。

```powershell
flutter test --no-pub --concurrency=2
flutter analyze --no-pub --no-fatal-infos --fatal-warnings
flutter build apk --release --flavor tv --android-project-arg=kazumiTv=true --target-platform android-arm --split-per-abi
flutter build apk --release --flavor tv --android-project-arg=kazumiTv=true --target-platform android-x64 --split-per-abi
# 仅设备测试入口：受控目录元数据+真实规则/解析/播放器，不能当产品 APK 发布
flutter build apk --release --flavor tv --android-project-arg=kazumiTv=true --target-platform android-x64 --split-per-abi --target test_support/emulator_main.dart
# 仅隔离虚拟 MediaCodec 问题的软件解码 fixture，不改变产品默认设置
flutter build apk --release --flavor tv --android-project-arg=kazumiTv=true --target-platform android-x64 --split-per-abi --target test_support/emulator_main.dart --dart-define=KAZUMI_FIXTURE_SOFTWARE_OUTPUT=true
```

设备 fixture 服务只监听宿主 `127.0.0.1:18791`，模拟器通过 `10.0.2.2` 访问。运行 `test_support/emulator_fixture_server.py <自生成MP4> <证据目录>`；使用明确隔离的新 AVD，只指定其 serial 安装和发送按键。先验证产品 APK 冷安装/引导，再用同签名 fixture APK覆盖该新测试包；真实数据持久化、规则/WebView/MPV和 Compose 不替换。force-stop/restart 验证进程级历史恢复。全过程保存命令、APK哈希、HTTP请求、截图、Activity状态、日志与结果。设备结果以实施记录为准，不能把 fixture 元数据等同公网服务验收。

本轮自动化516项、Kotlin23项通过；同 CSV8项结果一致。设备实测证明真实取流、软件解码切集、历史落盘/重启、Compose 数字定位/倒序/当前已看、Back/HOME取消与备份交互。元数据受控且部分准备步骤使用触摸/ADB输入，不能称全程实体遥控器验收。默认解码 ANR 的主线程在 `libmpv.so mpv_get_property_string` 等待，虚拟 MediaCodec 线程在 `native_dequeueOutputBuffer`；没有把这次失败转记为通过，也没有升级冻结的 media-kit 依赖。ARMv7 APK 构建成功仅证明产物有效。

剩余步骤：先在可用实体 TV 验证默认解码切集、声音、厂商按键、PiP/后台恢复，并据此判断 ANR 是否限于虚拟 MediaCodec；如果真机也复现，应在独立播放器问题中修复和回归后再验收。Legacy 覆盖需原签名构建流程；分支 CI需维护者的 workflow 权限。首页最近观看频道、原生备份格式迁移和同款外观仍是明确产品选择。总体设备验收尚未完成。
