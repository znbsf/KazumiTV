# TV 解码停滞与 HTTP 输入复核（Lab5）

本轮保留 Dart 会话、历史、地址解析及 media-kit/libmpv 架构。没有更新依赖、替换播放器或开启 unsafe-playlist。设备范围为隔离 GoogleTV API36 x86_64 AVD；ARM 真机仍未验收。

## 应用层修复

此前 ANR 主线程等待 `mpv_get_property_string`。匹配 AOT Build ID 的符号与反汇编指向 `readDiagnostics`，其二十项同步原生读取在遥控器帮助页初始化时也会执行。返回 Future 不会使同步 FFI 非阻塞，给 Future 加超时无法解除这种等待。

现在帮助和日志页不读取诊断，进入状态页才加载；诊断使用 `Player.state` 的类型化事件快照。已选音视频 codec、像素格式、流标称 fps、输入采样率可以显示。原生硬解状态、输出、丢帧和 A/V 时钟未上报时显示未知，不从配置猜测测量值。

TV 的 `auto` 在冻结视频插件 `Utils.IsEmulator` 判定为模拟器（本次为 goldfish/ranchu） 时采用 `gpu` / `hwdec=no`，对应插件自身已有的模拟器默认保护。物理 TV、移动端及用户明确输出选择沿用既有策略；能力缺失或失败不会猜测设备。切集后的旧会话检测保持原样。帮助/日志/状态五项 widget 回归、能力查询两项及输出选择测试覆盖这些边界。

## 原生 HTTP 故障仍未修复

最小诊断入口 `test_support/decoder_probe_main.dart` 仅使用 Player + Video，没有 Kazumi 的选集、历史、路由或 WebView。受控服务提供合法自制素材，并保留完整请求、字节 SHA 和 native prefix 日志。

| 输入或对照 | 已观测结果 |
| --- | --- |
| 同 SHA 原片 local，ao=null / AudioTrack / 原 scaletempo2 | 三项均 0 stream errors，正常 16 秒 EOF |
| 有声 H264 + AAC local | 0 stream errors，正常 8 秒 EOF；不等于物理扬声器验收 |
| 相同原片，正确 Range HTTP | AAC 与 H264 包错误，7 个 NAL 长度精确匹配源 offset+1 字节 |
| 有效文件缓存目录、默认读取参数 | 50 errors；重复可为 0，但仍有 HTTP 提前 EOF |
| demux buffer 64 KiB | 初次正常，重复出现 77/59 errors，不能默认采用 |
| 显式 short_seek_size=0 | 三次无音频 errors，但实际 ELF 默认已经是 0，不能以此证明改变了读取路径 |
| HTTP/1.1 相同原片 | 53/52 errors；另次 0 仍有提前 EOF，连接方式不是可靠修复 |
| 两音轨、字幕保留，仅 faststart remux | 39/0/0 errors，不能以素材重封装证明播放器已修复 |
| 单轨、索引仍在尾部 | 一次 0，仍有提前 EOF；不能据此归因轨数 |
| ffmpeg:// 包装 URI | 普通 open 的 playlist 安全检查拒绝，0 时长；这是加载失败 |
| embed / mediacodec-copy 冷启动最小本地视频 | open 38 秒未完成，界面 heartbeat 仍运行；GPU/no 确认可销毁并重建 |

宿主 FFmpeg 对原文件与同源 HTTP 完整解码无错误；多个 Range 逐字节 SHA 与文件一致。Dart 下载后同 SHA 本地可播，将问题收敛到捆绑 native HTTP/缓冲/解复用路径。精确首错层与 native 构建 BOM 尚未获得，不能指认一行 C 代码或保证升级解决。

当前 native release 的 [构建提交](https://github.com/Predidit/libmpv-android-video-build/commit/dd2bfba8209bcd22e2d4c79f125b40e619e637ed) 中，两份 [HLS patch](https://raw.githubusercontent.com/Predidit/libmpv-android-video-build/dd2bfba8209bcd22e2d4c79f125b40e619e637ed/buildscripts/patches/ffmpeg/ffmpeg-hls-kazumi-combined.patch) 只修改 `hls.c`；当前普通 MOV 日志没有证明经过该分支。该审查不等于 vendor 全量源码审计。

## 复用诊断与验收口径

以 `--target test_support/decoder_probe_main.dart` 单独构建诊断 APK，配置从模拟器宿主 loopback 的 `10.0.2.2:18792/config.json` 读取。配置支持合法素材名称、local、ao、vo、hwdec、cacheDirectory、单因素 properties 与 reuse/recreate。需要自有服务器和隔离 AVD；不能向已有用户包卸载或清数据。

每例同时检查正时长/位置、真实 completed、原生日志、stream errors 与界面响应。诊断的 result/COMPLETED 表示采集结束，不自动表示 PASS；未选解码器、unsafe URL 或零时长不得通过。Debug log 写出可能延迟，以 JSON 的 utc 和原始命令为准。

应用安全修复和 native 网络失败分别验收。未运行实体声音、长媒体精确续播、默认物理硬解切集、自然后台恢复及不同厂商遥控器；当前 AVD 不支持 PiP。网络 native 修复需要维护库来源和专门输入层回归，不能以静音、隐藏 errors、随机参数或重封装测试素材结束验收。
