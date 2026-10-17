# 外部轨道恢复验收

本清单保留验收步骤；已执行范围与仍缺项见末尾最新证据，未列通过的步骤不推定完成。复用 `docs/CONFIRMED-PLAYBACK-RECOVERY.md`；结果由集成负责人写回既有记录。仅使用独立 recoveryqa 身份，构建/服务/ADB/采集由设备 owner 串行调度。

## 输入与入口

运行 `python tools/qa/generate_external_recovery_fixture.py <ffmpeg绝对路径> <新的空输出目录>`，生成40秒MJPEG、两个独立PCM音频、两个独立SRT和SHA256清单。无内嵌音轨/字幕，不能误将内嵌轨道通过记作外部URI通过。白色闪烁与100ms音频脉冲位于整数秒，A/B音频分别440/880Hz，字幕显示外部A/B及秒数。生成器不启动服务、不改变网络配置。

`recovery_page.dart` 支持 `--dart-define=RECOVERY_QA_BASE=http://受控地址:端口`，仅验证完整失败恢复链。外部轨道另用 `--target tools/qa/external_snapshot.dart`，同BASE以及可选 `RECOVERY_QA_AUDIO`/`RECOVERY_QA_SUBTITLE`（默认BASE下external-a.wav/external-b.srt）。独立入口先建立GPU/no可播放会话，加载外部轨道，核验URI状态，保存真实snapshot，dispose旧播放器，再创建新播放器调用生产restorer；整个实验30秒截止。按Run，等待typed restore PASS，检查字幕后按Play听音频。此项只证明原生snapshot/restorer，不证明硬解失败UI全链。

完整失败链在onDirectDecoderFailure即捕获snapshot，不能等pendingRecovery后选择外部轨道再声称已恢复。外部原生恢复与完整失败链证据必须分别记录。

## 执行顺序及判据

1. 记录源码SHA、APK SHA/包名/ABI/版本/证书、实际安装字节、素材manifest与设备身份。先API36模拟器，再Android9 ARMv7。保持正式包、收藏、规则与设置。
2. 独立外部A音频+B字幕入口：记录URI、位置17秒、暂停意图、1.25倍。运行仅一次；核对旧输出dispose先于新create、首帧可见、暂停不前进、URI保留及字幕“EXTERNAL B SECOND 17”。再播放，音频440Hz、字幕秒数与画面持续推进。声音需要真实音频观察，不能以Track状态通过。
3. 外部B音频+A字幕、播放意图true重复一次；确认后继续播放而非永久暂停。允许帧/音频启动误差，但记录实际测量方法与阈值，不把日志到达时间当AV时间。
4. 外部URI返回404、延迟超过30秒、损坏SRT分别单因素测试。首帧仍为15秒截止，后续状态恢复新增独立30秒总截止；到期返回失败并阻止迟到命令继续seek/play，不代表底层原生命令被取消。每项观察到截止立即正常Back退出，确认旧会话不能改变新会话。不无限等待或重复试探。
5. 在外部轨道请求中退出、立即重新打开；旧响应到达后新会话URI、集数、提示与焦点不改变。确认恢复失败仍有手动重试/换源入口，无自动跳集/循环重建。
6. 有声AV验证以正常低音量记录脉冲与闪帧的同一采集时基，或用户现场听觉确认；无有效音频采集时标记inconclusive。不得凭MediaSession/截图宣称同步。同步素材证明仅为合成40秒输入，不证明自然影片口型/长播全覆盖。
7. 正常Back退出，检查输出释放及本任务服务/录制进程结束；恢复音量/前台/电源状态，不卸载或清数据。

## 历史边界与停止条件

- 新增30秒截止只约束 `restoreRecoveredPlayer` 的返回及后续命令；调用者 `recoverWithSoftware` 的 finally 仍经 `recovery.settle` 等待 `playback.stop`。原生命令锁或dispose不返回时清理仍可等待，不能声称loading必在30秒消失或完整链已解决。可控Future回归证明的是上层截止和迟到隔离。建议后续以独立issue跟踪原生命令卡死时的退出/清理上限，不在缺乏安全释放证据时并发重建播放器。

- `static/doc/TV_DECODER_REPRO_AND_LIMITS.md`：AVD embed/mediacodec-copy曾38秒open不返回；GPU/no可释放重建。不因缺口重新试copy或同步FFI诊断。
- 2026-10-16 Android9结果属于历史；本轮20515完整页面及20510独立外部轨道补测分别记证，不能跨入口替代。
- 历史907项与本轮955项自动化不代替原生输出；本轮原生外部轨道已补，物理音频及校准AV同步仍未验收。
- 输入不可解码、URI未实际选中、设备身份不符、服务/设备不归本任务时停止该项，记environment_invalid或not_run，不记产品fail。

## 2026-10-17 准备证据（非设备通过）

本机生成目录为根Kazumi的 `artifacts/four-stream-20261017/external-fixture`，未提交媒体二进制。FFmpeg完整解码sample.mkv无错误；五个文件SHA256复核通过，两条PCM均40秒/48kHz，首秒100ms有声及900ms静音通过程序检查。sample.mkv SHA256为 `48fd058cf14590123af25da3c4e03c59154a886264f0728ee691f6e81a6ddfad`。生成检查当时尚未覆盖设备；后续原生设备结果见末尾，物理音频和校准声画同步仍未测。

本次 `flutter test --no-pub test/playback_recovery_snapshot_test.dart test/recovery_readiness_test.dart` 11/11通过；四文件analyze为0 error/0 warning，recovery_page原构造器1条use_super_parameters info。离线pub get依赖已解析，Windows symlink尾步骤受开发者模式限制而非依赖缺失，未修改系统设置。测试仅覆盖上层Future截止/迟到隔离与既有首帧逻辑，未执行原生设备。

2026-10-17 入口断言修正：`external-run.log` 旧样本在首帧/外部字幕可见时过早打印typed PASS，日志position为0；该PASS不能用于位置恢复验收。现仅在恢复后的轨道、位置距snapshot≤500ms、1.25倍、暂停、未完成持续500ms均满足后报告PASS，使用单调计时且仍受整体30秒/退出代次限制。旧样本保留原始观察，不回写成新版通过；后续新构建20506/20510重验见下。

## 最新实证与剩余范围（2026-10-17）

集成负责人执行设备操作；本记录离线核对日志。A=`artifacts/four-stream-20261017`（私人证据，不上传原件）。全量955项通过对应head606593f1，播放生产修复7595a9ad。

| 范围 | 本轮证据与结论 |
| --- | --- |
| 原生外部A音轨/B字幕snapshot恢复 | 模拟器20506 `external-asserted.log` 和电视20510 `tv-external-pass.log`：17秒、1.25倍、playing=false、externalTracks=true、stableMs=500；旧播放器释放再重建。独立GPU/no入口通过，不冒充完整失败链外部轨道通过。 |
| 模拟器内部音频/画面 | AV2 23个音频脉冲均440.19Hz；三抽样帧字幕B的17→24→37秒推进。音频录制内晚159–224ms，中位205.5ms；报告 `external-av-analysis.json/.md`。完整解码exit0但有4条null输出DTS警告，不能写无警告。 |
| 完整VideoPage恢复 | 模拟器20514真实firstFrameNotify后17秒暂停；电视20515恢复、位置27.7→39秒、EOF至第2集默认mediacodec。详见原CONFIRMED记录。 |
| 软件恢复负向 | 模拟器受控FFV1失败显示三个操作入口，无自动重试；内部loading=true但错误页有效。 |
| 仍缺 | 物理音频/人工听感、校准AV同步、自然影片长播；B音频/A字幕交换组合及每个外部URI异常步骤未逐项取得本轮设备证据。原生旧响应与新会话并发重叠未测，只有并发回调隔离单元证据。 |

20503旧入口曾在position=0时过早报PASS；后续严格断言的新包结果独立记录，不覆盖或修改旧事实。第一次静音AV录制排除成功，第二次AV2仅证明内部音频存在及上述录制时序。没有校准基线，不能把约0.2秒偏移直接归因播放器或宣称同步合格。

在途退出补测：media-requests.jsonl于12:03:12.914记录delay12请求，旧控制器12:03:14.728退出；新控制器12:03:28.093进入（旧请求预计返回之后），12:03:37.418首帧，12:03:39恢复17秒暂停、blocked/loading=false。证据recovery-delay-inflight-exit及recovery-delay-final。该结果支持在途退出和随后恢复，不支持旧响应/新会话并发重叠原生结论；第一轮未建立请求的立即退出未计入此通过。
