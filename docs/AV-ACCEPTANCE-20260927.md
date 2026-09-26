# 2026-09-27 应用声画录制验收方法与结果

本阶段依据用户要求，实际录制应用输出并做自动分析，替代仅等待用户现场听音的做法。此记录属于播放任务；统筹另审生产代码，UI 任务独立审录制与焦点问题。未推送或发布。

## 身份与采集边界

- 正式 APK 锁定 `0.3.3` / code53，SHA-256 `32A3F9950B5DF05FD23B1A06A3334C0794DAE2A50082237B31C6470E076A3A77`。本轮设备侧 `sha256sum` 再次相等。没有重建、修改或换签名正式 APK。
- 实际采集设备为自有 `Kazumi_P3_Clean_API36` / `emulator-5570`，Android16 Google TV。它不是旧电视。
- 旧电视既有地址的 ADB 连接返回 Windows10061主动拒绝。本轮没有取得其当前包、音量、路由或新录制，不能沿用9月24日状态作当前测量。没有反复重连、扫描新地址或启用家庭麦克风。
- [Android 官方](https://developer.android.com/media/platform/av-capture)说明 AudioPlaybackCapture 从 Android10 引入；[scrcpy 官方](https://github.com/Genymobile/scrcpy/blob/master/doc/audio.md)要求内部音频采集 Android11+。旧电视历史记录为Android9；这只能说明标准接口不适用，不证明厂商所有私有接口均不可用。
- scrcpy 官方v4.1，发布ZIP由统筹校验SHA-256。`--audio-source=playback --audio-dup` 捕获模拟器内正在播放的音频；没有拉取源视频、录电脑混音或麦克风。`--require-audio` 防止退化成仅视频。样本不上传，只在忽略目录保存。

## 可复跑方式

1. 串行核对设备名、已安装正式包hash、音频状态及设备占用；先以新标签 `p3four-...` 备份 `tv_settings`、`tv_library`、`search_history`、`tv_rules`。
2. 仅临时导入既有固定规则中的 baimao，记录规则hash；不更新整个目录，不执行验证码识别或提交。
3. 开始 scrcpy 录制，再运行真实播放测试。此轮测试工具为 `real-road-switch -e captureOnly true`：沿既有来源搜索、详情/集表和生产播放器进入第12集；首次真实渲染且历史位置超过6秒后，保持60秒不输入，每10秒记录播放位置，然后关闭播放器并恢复三项存储。该参数只修改测试代码，不替换生产播放器或音视频数据。测试APK SHA-256 `CF76CAC62F9A2A393F11F8C2D25DA8E68A156B260711A6BBCA8C53B1ED4C83B1`。
4. 等 scrcpy 正常输出 `Time limit reached / Recording complete` 后才读文件、运行其他 instrumentation。切线/暂停/seek 验收放另一段；不能把人为暂停当音频中断。
5. ffprobe 检查实际音视频双轨，FFmpeg 实际解码、电平/静音及时间轴分析；抽取帧检查真实画面。双轨存在与时间戳相近均不能单独证明内容同步。无音频感知工具时，不能写听清对白或听感正常。
6. 所有测试结束后恢复四项检查点并verify；比较音量/静音/路由。闲置自有模拟器关闭，保留AVD和数据。实体电视依用户要求可亮屏，不为回退而卸载或清数据。

实际采集命令（通过 `Start-Process -WindowStyle Hidden`，stdout/stderr写忽略目录；环境变量 `ADB` 指向既有ADB）：

```text
scrcpy -s emulator-5570 --no-control --no-playback --no-window --require-audio
  --audio-source=playback --audio-dup --audio-codec=flac
  --max-size=1280 --max-fps=30 --time-limit=125 --record=<原始MKV绝对路径>
adb -s emulator-5570 shell am instrument -w -e mode real-road-switch
  -e sourceName baimao -e captureOnly true -e maxMs 150000
  com.znbsf.kazumi.compose.tv.test/org.kazumi.tv.TvNetworkInstrumentation
ffmpeg -ss 25 -i <原始MKV> -t 50 -vn
  -af volumedetect,astats=metadata=0:reset=0,silencedetect=noise=-50dB:d=0.3
  -f null NUL
```

## 本轮原始样本与时间线

绝对根目录：`C:\Users\hentai\.codex\worktrees\p3-kazumi-20260924\Kazumi\artifacts\av-continuous-20260927\`。

- `continuous-real-playback.mkv`：124.898秒、49,354,000bytes；H264 1280×720 + FLAC48kHz双声道；SHA-256 `6C7343E9FAE5A5EDA679776985C17D5E7AEEFC63A2AAC5A96910E1EC1AA9F5EF`。这是应用真实输出录制。
- `continuous-25-75.mp4`：原始样本25–75秒转码方便审阅，SHA-256 `7890EC5D22CF59D521DB74CD1D8AFF72A0C187E789650151F690C3D77D3B211A`；原始证据仍为MKV。该50秒段全部位于无输入的60秒播放区间。
- `continuous-test.log`、`capture-start.txt`、scrcpy双日志、`streams.json`、`audio-analysis.log`、`timeline-analysis.txt`、`continuous-contact-sheet.png` 为本地证据。
- scrcpy进程启动wall时间1790441649302ms；连续区间开始1790441668198ms，播放位置9450ms；10/20/30/40/50/60秒位置为19453/29450/39453/49459/59463/69469ms；区间结束1790441728217ms，随后测试关闭播放器、恢复存储。连续等待实测60021ms，期间没有暂停、seek或遥控输入。

## 自动分析与定向发布审查

| 项目 | 观察 | 能证明的范围 |
| --- | --- | --- |
| 连续内部音频 | 50秒段均值-28.7dB、峰值-7.8dB；`-50dB / 0.3秒` 静音检测未检出长静音；FFmpeg实际解码完成 | 音频不是全静音、未见超过该阈值的明显断音；不等于亲耳清晰度、无爆音或实体扬声器声学证明。 |
| 视频 | 实际抽帧可见多段对话、字幕和近景变化；真实历史进度持续推进 | 不是仅菜单或首帧；可见推进，未见整段停住。动画静止镜头不能一概当卡顿。 |
| 采集时间轴 | 25–75秒中视频1195包、最大相邻PTS间隔0.092秒；FLAC586包、最大0.100秒（常规包时长约0.085秒） | 没有秒级采集时间戳缺口；这些数不是内容声画同步误差。 |
| HOME恢复 | `playback-background`通过：真实HOME使Activity停止、播放器暂停/session断开，返回同Activity仍暂停，明确Play后推进 | 最终APK的受控媒体/生产播放器生命周期路径；不是本轮实体电视结果。 |
| 切线取消/验证恢复 | `playback-recovery`通过：保暂停或继续意图，保进度；验证后恢复原POST请求 | 本地受控夹具，没有真人验证码。真实换线/返回另见统筹录制及9月24日记录。 |
| 验证后台与焦点 | `verification-layout`及带`waitBeforeInputMs=1000`复跑通过：实际Back回工具栏焦点；HOME停止轮询count2→2、done=false；回前台同WebView恢复 | 本地受控验证页，无后台完成或自动提交证据；不能代表所有实站验证页。 |
| 失效媒体退出与重试 | `playback-expired`通过：真实本地HTTP403后重新解析、保暂停/继续意图和位置、退出取消在途解析 | 最终APK的有限失败恢复路径；没有扩展断网矩阵。 |

以上播放侧没有发现新的已确认阻断缺陷。独立UI/生产代码审查及内容级同步分析由统筹汇总后决定放行；不因有音轨而自动放行。本工具集合未提供音频感知能力，播放任务不报告听清对白或精确口型同步，实际扬声器结果仍不能由模拟器样本代替。

## 恢复结果

`p3four-av-continuous-20260927`四存储已restore并verify unchanged；临时baimao规则恢复未导入状态。全部安全夹具后再次verify仍一致。STREAM_MUSIC前后均未静音、3/15、speaker路由，没有改音量。设备侧正式APKhash最终仍为锁定值。AndroidRuntime错误缓冲输出为空。scrcpy已正常结束，所有instrumentation退出；5570已关闭并从ADB列表消失，AVD与数据保留。
