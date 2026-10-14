# #11 候选验证

2026-10-14 UTC，基于 main `ae2d9dab5b036cdde568d6b714ce498fb75a7a3b`（已包含 #10），未发布。

- Flutter 3.47.3，revision `e8113bf45620cbeb8aff64947ee4c93e16adb4cf`，Dart 3.13.3。
- 单并发以下 8 个测试文件，63 tests passed：`api9_rule_compatibility_test`、`plugin_editor_api9_test`、`tv_settings_navigation_test`、`webview_source_early_event_test`、`source_switch_test`、`playback_recovery_test`、`tv_detail_actions_test`、`tv_unattended_workflow_test`。
- 静态分析 `flutter analyze --no-pub --no-fatal-infos`：exit 0，0 error / 0 warning，58 info（与既有数量一致）。`git diff --check` 通过，pubspec.lock 未变。
- WebView red/green：原实现中 load Future 保持未完成时，20ms 解析期限经过 100ms 后仍无结果；释放测试闸门后断言失败。修复后在短清理宽限下能返回超时，并通过旧 load/unload 卡住后新实例完成下一请求、旧 Future 迟到失败不污染新请求的测试。正常早到解析、取消、复用和关闭行为仍通过。
- API 9 覆盖空模板兼容 API 8、数字/特殊 ID 编码、相邻/重复占位符、无效模板、JSON/分享往返、API 搜索接 XPath 详情、编辑器恢复/校验/保存。导航覆盖保留未保存输入及从子页返回分类。hover 保留原隐藏计时器逻辑，未做独立真机鼠标验证。

本地离线依赖解析完成，Windows 原生插件链接阶段提示开发者模式/符号链接能力不足，未修改系统设置；使用已生成 package config 运行上述 Dart/Flutter 测试和分析成功。未安装工具或创建凭据。

本轮没有启动本地 Android 构建、ADB、模拟器或电视，没有新真机/线上站点/验证码/长时播放结论。WebView 初始化卡住及底层原生资源最终回收不在此次覆盖范围。API 9 官方规则的真实服务连通性、老 Android/WebView 和目标电视仍需后续验收；不要将这些合成与本地夹具测试称为线上全链路通过。完整套件与候选 APK 构建交由草稿 PR 的 CI，须以其实际结果为准。
