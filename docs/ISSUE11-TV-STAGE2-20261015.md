# #11 第二阶段补充回归

2026-10-15 13:55 UTC。基线 PR #12 head `b90e38498010d8301f160380437fb6ce29336bda`；程序源码仍为 `dae2bbede53f225a3f0c135181f0981f502ddcce`。本轮新增测试和记录，没有修改生产代码、依赖或重建 APK。

## 受控回归

单并发运行 playback_recovery、webview_source_early_event、source_switch、cross_source_resume、tv_player_cancel、tv_player_modal_focus、playback_history_recorder 共七个文件，70 项全部通过。

`flutter analyze --no-pub --no-fatal-infos` exit 0，0 error / 0 warning、58 info；新增测试经 Dart format 整理，git diff --check 通过。完整新 head 的 CI 以远端实际结果为准，不能复用基线的869项及三ABI成功作为新 head 的终态。

新增两个用例：

- 第一次解析超时后重试，在第二次加载中取消，再次重试成功；旧请求迟到失败不能污染新播放，集数及 71 秒恢复位置保持。
- 连续三次提交预解析换源，旧播放器历史回调保留其捕获的来源身份；退出后旧播放错误不能污染状态。

初稿曾错误地要求已接受的旧播放器不能写入最终历史，导致一项失败。检查 `_OwnedPlayer._dispose` 与 PlaybackHistoryRecorder 后，确认最终真实进度允许按捕获身份提交，并由写入队列保持顺序；纠正测试假设后全绿。这不是已经复现并修复的产品缺陷。

## Android 9 电视复核

沿用首轮独立 `com.znbsf.kazumi.fluttertv.stableqa` 203261 / `0.4.2-pr12-qa.2`，设备 MiTV-ASTP0 / mulan、Android 9 / ARMv7。包与程序对应关系见首轮记录；没有覆盖正式版或 preview。

- 从最近观看通过方向键和 OK 进入详情及 giriGiriLove 第 02 集，观察到解析状态后正常播放；本次没有自然发生解析超时。
- 暂停后进入设置并打开换源选择器，Back 取消。MediaSession 前后均 PAUSED，位置精确相同：90444 ms；控件树显示焦点回到“设置”。本次混合按键与坐标操作，不能记为全程纯遥控。
- Back 正常返回作品详情，MediaSession inactive / NONE、position 0。仅停止独立 QA 包，电视音量从临时 0 恢复原值 7；system_server / adbd PID 前后保持 24784 / 29322。
- 未重启电视、未调用 HOME、未修改网络/安全/签名/电源，未启动模拟器或本地 APK 构建。

原始记录在仓库外 `qa-20261015/stage2/`：focused-tests-final.log、before-cancel.txt、after-cancel.txt、after-cancel.xml、exit-check.xml、final-media.txt。媒体画面及原始系统日志不公开上传。

## 尚未覆盖

真实超时后的纯遥控取消/重试、真实硬件遥控、音画同步、验证码及其他电视仍未补足；重复换源的新增覆盖来自受控用例，不冒充新增实机三次换源。初始化永不返回与原生资源最终释放仍不属于当前保证。完整发布验收边界沿用第一阶段报告。PR 保持草稿，不合并、不发布。
