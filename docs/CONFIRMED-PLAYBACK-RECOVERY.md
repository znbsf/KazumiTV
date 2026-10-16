# 确认后尝试软件兼容播放（草稿）

基于稳定版 v0.4.3 / main `ab273c1aca02238cf03d6f523dac7ef259e4830b`。这是独立功能候选，尚未合并、发布。默认 Android TV 输出和持久化设置不变。

## 行为与边界

仅 TV 的 `mediacodec_embed` 会话监听固定原生 mpv 的 `vd` / `Software decoding fallback is disabled.` 证据，并关闭该会话的隐式软件回退。缓冲、卡顿、普通网络错误、完成事件均不触发恢复提示。该证据对应解码初始化用尽可用硬解路径，不覆盖所有运行中硬件异常。

失败后屏蔽该会话的自动下一集。提示默认聚焦“取消”；取消或返回不重试。用户确认只允许一次：等待旧播放器释放，再用原 URL/headers 新建 `gpu` + `hwdec=no` 会话，不复用旧输出。软件恢复需要 media-kit 首帧通知才能成功，最长等待15秒；原生错误或退出立即终止等待。恢复失败保持自动下一集屏蔽，展示失败操作或结束恢复加载，用户可手动换源或退出。软件尝试过程中及之后若收到当前播放器的原生 error，也保守地屏蔽自动下一集；不会再自动重试。

保存精确 Duration、明确的播放/暂停意图、倍速，以及保留外部 URI 元数据的音轨/字幕对象。原生 EOF 会把 observed playing 改成 false，因此播放意图由播放器所有者保存，并由明确的 play/pause 更新。恢复不写解码默认值；下一集/新会话仍走原默认。软件解码可能无法实时播放，不承诺兼容所有视频。

会话门控防止重复确认；新初始化/退出使旧令牌失效。每个异步轨道/位置恢复步骤、失败清理后的状态写入均复查所有权。旧播放器的 log/error/debug 订阅随所有者释放；无法确认旧原生播放器成功释放时不启动软件重建。

## 源码入口

- `lib/services/player/confirmed_playback_recovery.dart`：证据分类、会话状态、确认与清理门控。
- `lib/pages/player/controller/player_playback_controller.dart`：原生属性、所有者、订阅、释放顺序和 EOF 屏蔽。
- `lib/pages/player/controller/playback_recovery_snapshot.dart`：typed state 与逐步恢复。
- `lib/pages/player/player_controller.dart`：初始化、确认和退出联动。
- `lib/pages/player/player_item.dart`、`tv_recovery_confirmation.dart`：正式播放器提示、焦点及菜单占用释放。

## 验证（2026-10-16 UTC）

最终本地全量 **907 项测试通过**；静态检查 **0 error / 0 warning，71 info**。测试覆盖精确失败信号、默认取消/确认焦点、一次确认、取消、新会话/关闭失效、迟到清理、恢复成功后的正常 EOF、毫秒位置/倍速/外部轨道、异步恢复途中切集、失败后的播放意图，以及首帧等待、取消、超时和迟到软件错误提示。

API36 Google TV x86_64 原生组件夹具使用本地合成的 40 秒 MJPEG：真实硬解失败触发提示，取消未创建新播放器；确认日志按旧 VideoOutput dispose → 新 create 排序。暂停状态恢复到17秒/1.25倍，画面可见；autoplay 场景确认后 playing=true 且位置持续前进。HTTP 失败原请求和重建请求均带同一合成 header。新会话回到 mediacodec，持久化输出设置不变。

夹具 `tools/qa/confirmed_recovery.dart` 只允许独立 `com.znbsf.kazumi.fluttertv.recoveryqa` debug 身份，使用真实 PlayerController、PlayerItemSurface、TV导航壳和提示管理，下载/弹幕控制器为替身。不是完整正式页面验收；外部音轨/字幕仅自动化验证，合成视频无音轨，不能据截图声称音画同步、全片流畅或实际网站全覆盖。旧 FFV1 素材因精简解码器缺失不可用，不计入恢复通过。原始私人设备日志不提交仓库。

Android9 ARMv7 电视独立 QA 包已核验安装字节，默认 auto 选择 mediacodec，合成 MJPEG 触发真实目标错误并显示提示（低分辨率有界视频取帧及语义树已核对）。电视 Back 取消保持17秒暂停且没有重建；新会话仍走原硬解默认。明确确认后日志显示旧 VideoOutput dispose → 新 create，软件解码恢复17秒暂停/1.25倍，低分辨率有界取帧确认实际画面；继续播放后位置推进。持久化输出仍为 auto，正常退出释放 VideoOutput，前台、音量和电源状态已恢复。当时尚未覆盖软件恢复本身失败；后续模拟器补测见下。首次调试冷启动过早输入产生系统 ANR、shell stdin 传输产生空文件均已定位；就绪后按键与 push/复制后逐字节核验解决了测试输入问题。

API36 的原组件入口已验证 Back 只取消、焦点回原按钮；快速两次初始化结果 false/true，只有最后一个会话创建；默认取消不重试，正常退出释放旧 VideoOutput。完整页面的后续补测如下；外部音轨原生恢复仍未覆盖。

## 完整页面原生补测（2026-10-16 12:08 UTC）

新增 `tools/qa/recovery_page.dart` 使用真实 VideoPage、PlayerItem、coreModule 和路由所属控制器，仅媒体解析返回受控本机 URL，评论请求替换为空。独立 debug 身份检查仍生效。此测试的弹幕 ID 为合成0，其后台403不计为播放器失败，也不扩展站点排查。

实际发现并修复：原生 open 返回只代表命令接受，FFV1 的解码错误可能稍后到达。旧实现会先认定恢复成功，随后只拦截 EOF 而未提供失败入口。现等待首帧通知（15秒上限，退出/错误即时取消），并将软件尝试的原生错误交给正式页面现有失败处理，释放输出并显示重试/换线路/换源。普通会话的错误分类不变。

- 真实页面硬解失败提示默认取消；Back 后焦点回当前剧集，控制栏和设置菜单可再次打开、返回。
- 明确确认后先 dispose 旧输出再 create 新输出，保持17秒暂停和1.25倍；继续播放可见画面与位置推进。最终成功播完自动进入第2集，并回到 mediacodec 默认。
- 硬解失败后将同 URL 的受控响应切换为 FFV1，真实原生错误触发可操作失败页面，软件输出已释放；仍停第1集，无自动重试或跳集。
- 受控 HTTP 延迟30秒；在日志确认 software/no、loading=true、completed=false 的首帧等待中经 Back 退出，旧输出释放；立即重新进入新控制器，新会话走原硬解默认。旧响应到达后，新会话仍能确认恢复并正常播放。

最终原生包为20408，SHA-256 8b09d1eac12ef12503cf75d1ce65c226bb12590c57f343d0a5b318400b173dbf，安装后拉回逐字节核验。采集为3秒有界 H.264 后取帧并人工查看，不能解释为全片音画同步验证；素材无音轨。外部 URI 音轨/字幕仍只有自动化验证，仓库现有生成器生成的是内嵌轨道，不能替代外部轨道原生验收。新增变更未重新跑 ARMv7 真机；既有电视证据对应本次首帧/失败提示修复前。维持草稿，不合并发布。

私人证据保存在任务工作区 recovery-qa：final-negative(.log/.xml)、final-negative-observe、race-during、race-exited、race-reentered、final-success、final-menu、final-play、final-eof、final-closed、final-recovered-observe 和 page-install.json。模拟器、受控HTTP服务和限时采集均已停止。
