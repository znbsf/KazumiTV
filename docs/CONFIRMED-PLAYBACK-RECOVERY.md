# 确认后尝试软件兼容播放（草稿）

基于稳定版 v0.4.3 / main `ab273c1aca02238cf03d6f523dac7ef259e4830b`。这是独立功能候选，尚未合并、发布。默认 Android TV 输出和持久化设置不变。

## 行为与边界

仅 TV 的 `mediacodec_embed` 会话监听固定原生 mpv 的 `vd` / `Software decoding fallback is disabled.` 证据，并关闭该会话的隐式软件回退。缓冲、卡顿、普通网络错误、完成事件均不触发恢复提示。该证据对应解码初始化用尽可用硬解路径，不覆盖所有运行中硬件异常。

失败后屏蔽该会话的自动下一集。提示默认聚焦“取消”；取消或返回不重试。用户确认只允许一次：等待旧播放器释放，再用原 URL/headers 新建 `gpu` + `hwdec=no` 会话，不复用旧输出。恢复失败保持自动下一集屏蔽并结束加载，用户可手动换源或退出。软件尝试过程中及之后若收到当前播放器的原生 error，也保守地屏蔽自动下一集；不会再自动重试。

保存精确 Duration、明确的播放/暂停意图、倍速，以及保留外部 URI 元数据的音轨/字幕对象。原生 EOF 会把 observed playing 改成 false，因此播放意图由播放器所有者保存，并由明确的 play/pause 更新。恢复不写解码默认值；下一集/新会话仍走原默认。软件解码可能无法实时播放，不承诺兼容所有视频。

会话门控防止重复确认；新初始化/退出使旧令牌失效。每个异步轨道/位置恢复步骤、失败清理后的状态写入均复查所有权。旧播放器的 log/error/debug 订阅随所有者释放；无法确认旧原生播放器成功释放时不启动软件重建。

## 源码入口

- `lib/services/player/confirmed_playback_recovery.dart`：证据分类、会话状态、确认与清理门控。
- `lib/pages/player/controller/player_playback_controller.dart`：原生属性、所有者、订阅、释放顺序和 EOF 屏蔽。
- `lib/pages/player/controller/playback_recovery_snapshot.dart`：typed state 与逐步恢复。
- `lib/pages/player/player_controller.dart`：初始化、确认和退出联动。
- `lib/pages/player/player_item.dart`、`tv_recovery_confirmation.dart`：正式播放器提示、焦点及菜单占用释放。

## 验证（2026-10-16 UTC）

本地全量 **902 项测试通过**；静态检查 **0 error / 0 warning，69 info**。测试覆盖精确失败信号、默认取消/确认焦点、一次确认、取消、新会话/关闭失效、迟到清理、恢复成功后的正常 EOF、毫秒位置/倍速/外部轨道、异步恢复途中切集，以及失败后的播放意图。

API36 Google TV x86_64 原生组件夹具使用本地合成的 40 秒 MJPEG：真实硬解失败触发提示，取消未创建新播放器；确认日志按旧 VideoOutput dispose → 新 create 排序。暂停状态恢复到17秒/1.25倍，画面可见；autoplay 场景确认后 playing=true 且位置持续前进。HTTP 失败原请求和重建请求均带同一合成 header。新会话回到 mediacodec，持久化输出设置不变。

夹具 `tools/qa/confirmed_recovery.dart` 只允许独立 `com.znbsf.kazumi.fluttertv.recoveryqa` debug 身份，使用真实 PlayerController、PlayerItemSurface、TV导航壳和提示管理，下载/弹幕控制器为替身。不是完整正式页面验收；外部音轨/字幕仅自动化验证，合成视频无音轨，不能据截图声称音画同步、全片流畅或实际网站全覆盖。旧 FFV1 素材因精简解码器缺失不可用，不计入恢复通过。原始私人设备日志不提交仓库。

Android9 ARMv7 电视独立 QA 包已核验安装字节，默认 auto 选择 mediacodec，合成 MJPEG 触发真实目标错误并显示提示（低分辨率有界视频取帧及语义树已核对）。电视取消/确认后的实际软件输出、失败恢复及退出尚未完成，不计为通过。首次调试冷启动过早输入产生系统 ANR、shell stdin 传输产生空文件均已定位；就绪后按键与 push/复制后逐字节核验解决了测试输入问题。

API36 的最终导航入口已验证 Back 只取消、焦点回原按钮；快速两次初始化结果 false/true，只有最后一个会话创建；默认取消不重试，正常退出释放旧 VideoOutput。最后增加的软件错误 EOF 保护经过902项全量测试和静态检查，但其原生负向场景尚待补测。完整 PlayerItem 页面、在原生重建等待中快速退出重进、电视软件输出与外部音轨原生恢复仍需补测，草稿不可据此直接合并发布。
