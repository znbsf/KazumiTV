# FlutterTV 性能与播放最终交付

2026-10-02 UTC。本轮融合、修复、实测优化及正式独立包更新已完成；外部连接、人工声音与帧预算限制仍然存在。旧模拟器/初次电视验收报告保留为历史阶段，当前结论以本报告和[证据摘要](FLUTTER_TV_OPTIMIZATION_AND_PLAYBACK_EVIDENCE.json)为准。[完整接手手册](FLUTTER_TV_AGENT_HANDOVER.md)提供架构、命令和下一Agent提示。

## 交付版本

- 独立worktree：C:/Users/hentai/Documents/Codex/2026-10-02/task/Kazumi；分支codex/flutter-tv-main-ui-fusion-20261002；origin https://github.com/znbsf/KazumiTV.git。未替换原生main。
- 最终产品源码83752494b2888c3e0338584ef02a3d55b9b00e00；测量源码0fa262183a8da71ed247e22818778759f9f8a231。二者仅pubspec.yaml版本不同，最终包KAZUMI_TV_PERF=false。文档提交SHA另见本机回执，不能冒称APK来自后续文档提交。
- [最终ARMv7 APK](../../../artifacts/Kazumi-FlutterTV-final-Xiaomi-isolated-armeabi-v7a.apk)，31,658,234字节；SHA256：1f49893b42b7efb51fa04e06fd9fed5759c41da91086bea9d51baeba6f0fef4a。
- 包名com.znbsf.kazumi.flutterlab.test；versionName 2.3.1-tv-ui-fusion.3，实际versionCode 203191；pubspec build number20319经ABI后缀生成203191。
- 同签名覆盖更新已完成，拉取实际安装APK后字节哈希相同。测试UID10074、数据目录、首次安装时间保留；原三个应用状态完全相同。Compose默认关闭，原media-kit/libmpv、Skia渲染器和依赖未更换。
- 签名证书SHA256：fe3f74f8c6f7bf2af6edffbed9c0293e37cb876beffa6dd5055b8971542892a4；原libmpv SHA256：6035ab32a2151c404af75417c97646046cbee3d6612365841378635051ba7825。密钥不进Git或文档。

## 性能效果

在后来明确授权的同一Xiaomi MiTV-ASTP0 / Android9 API28 / ARMv7 / 1920×1080 DPR2 / 约60Hz电视上，保留新增真实历史数据，用相同目录、相同起止卡片、同一固定按键脚本及release模式采集五组基线。原UI基线源码67c08c98；优化源码0fa26218。首遍与暖缓存分别列出，进程重启不等于完全相同内存缓存；实际按键间隔和ImageCache计数保存在回执。

| 场景 | 基线raster p95 / ms | 优化raster p95 / ms | 降低 |
|---|---:|---:|---:|
| settled-first | 73.003 | 42.096 | 42.34% |
| settled-warm | 73.133 | 40.134 | 45.12% |
| rapid-warm | 79.311 | 53.665 | 32.34% |
| vertical-first | 87.376 | 54.073 | 38.11% |
| vertical-warm | 87.370 | 52.403 | 40.02% |

五组降低32.34%–45.12%，但仍约90%–95%的采样帧超过16.67ms预算，**不宣称稳定60fps**。首遍横移raster max188.874ms，高于基线75.452ms，原因未建立。暖横移最大值50.095ms，低于基线73.968ms。快速按键窗口只有14个优化帧/21个基线帧，不能外推所有内容或硬件。

快速场景框架内input→focus p95为233.972→36.258ms，totalSpan p95为334.122→93.648ms；latest-event关联存在合并，inputsWithoutFocus为5→3，不代表丢键数。暖竖滚focus p95为420.255→362.588ms，包含原设计滚动等待。ADB耗时、框架回调和FrameTiming都不是遥控器到面板的完整物理延迟。采样上限丢弃计数均为0。

保留原背景来源与样式：260ms驻留、600ms淡入、720px源图解码、sigma16、居中cover、竖图.84透明度/横图1及原双渐变。异步竖图预滤和静态双渐变各生成视口DPR纹理，动画alpha直接作用于RawImage。一个活动准备任务加最新待处理项；过期generation/geometry结果释放，过大或失败走原渲染。图缓存2项/16MiB，渐变缓存1项/16MiB；1080p每张约7.91MiB，三张缓存约23.73MiB。限制不包含淡出、在途、clone仍持有像素和Flutter解码缓存，**不代表总GPU峰值32MiB**。

同卡片真实截图RGB平均绝对差约0.18–0.19、最大3/255；DPR1/2和五个淡入比例的非纯色像素回归通过。静态比较所用早期overlay截图有效，其对应分片缺失性能窗口仍排除。

## 诊断与候选取舍

先复用同步FFI引发ANR的旧教训，使用默认关闭、有界FrameTiming/Stopwatch探针，不增加同步FFI、不深入解码器。窗口内不逐帧打日志，截图/XML及日志读回在窗口外。正式APK的libapp.so中诊断标记缺失，F10后的正式应用日志也为0条探针标记。

弱收益和失败证据均保留：额外RepaintBoundary暖横移只改善1.81%，已移除；单独预滤五组约3%–10%、暖横移4.45%/暖竖滚4.20%，不足以认定卡顿解决；直接alpha只测两组横移，额外收益小；静态双渐变缓存才获得本报告持续收益。临时应用OLED对照移除图片和渐变后36.495ms，只能归因整个背景合成；已恢复false，没有改变系统设置。

900字节分片曾收到155/164片、尾9片丢失，该窗口排除。之后唯一探针代码差异：结束且1500ms drain后，报告回调由debugPrintSynchronously改为SDK debugPrintThrottled；时钟、采样边界、统计、编码不变。基线仍有效，但探针文件哈希并不相同。主机开始前排除旧runId，结束后最多18次、间隔2秒累计片段，仅接受一个新且完整报告，未改系统日志缓冲。误起卡片2的基线、F9未进入Flutter、旧1023字节截断和未安装候选都保留，没有混入有效对比。

## 播放与搜索

公开元数据精确端点/v0/search/subjects仅在缺少镜像凭据时走官方HTTPS，保留原Dio/TLS/可选Bearer/取消/查询/请求体，其他路由不变。电视官方端点两次各12秒连接超时，旧镜像401未重现；没有可见搜索结果通过结论，电脑200不代表电视200。原规则搜索仍能返回结果。没有读取/补造凭据或改变系统网络、代理、证书、WebView。

解析链修复先订阅再load的早到事件竞态、completion gate和await unload屏障；WebView66显式iframe媒体URL fallback保留签名URL字节，注入幂等且以session generation隔离过期页面。未放宽安全策略，未换播放器。

修复阶段203131/0aa7075a的baimao技术闭环已观察第1/2集真实画面、暂停时间稳定、恢复推进、快进/快退、下一集、退出、最近观看与非零续播。7sefun只做一次有界尝试，URL交接前超时伴TLS握手失败，不继续解码器深挖。见[技术闭环回执](../../../evidence/tv-optimization-20261002/playback-technical-loop.json)。

正式203191包另完成首页→最近第2集→详情→URL交接→实际画面，暂停07:28/24:12、恢复07:34、退出详情主按钮和首页原最近条目焦点恢复，再向下卡片2、向左卡片1。加载观察到07:28的间隔小于448秒，说明非零持久化续播，不宣称精确seek误差为0。来源列表后来增加到3集是动态数据。最终首页卡片1聚焦，播放已退出。正式末次smoke日志未见FATAL EXCEPTION、OutOfMemoryError或mpv打开失败；URL交接在111日志，末次有界日志不保证保留早期所有事件。

无人值守画面/日志没有验证人工可听声音或口型同步；可访问来源不证明播放/再发布授权，不能称完整合法音画验收通过。原始媒体URL、目标地址、密钥仅本机私有。DOWN/LEFT错误简写在主机发送前拒绝，116/117标签不能当成功导航；118/119使用DPAD键验证，回执已注明。

## 验证与保护

- 渐变缓存源码e498a5b3829339a3f1348f8b880d42e3ccc23d89：完整639/639测试通过，test-20261002T091717062655Z.json。
- 后续只改窗口结束的日志传输：13/13探针测试通过，test-20261002T093113294378Z.json。静态分析0错误/0警告/32info；没有再跑完整639，不能混称。
- 最终源码仅版本变化，正式release构建成功，安装字节、原libmpv、ABI、包隔离、签名、probe关闭、Compose默认关闭有门禁回执。
- 原八树HEAD/branch/NUL状态/每个脏文件SHA前后完全相同；原三个TV应用完整package_state相同。没有clear/uninstall/downgrade。模拟器userdata保留，原暂停会话/定时检查未恢复。
- 只推送实验分支；最终文档HEAD、remote一致性和CI列表见本机evidence/fusion-final-handover.json。此前Actions列表为空，不宣称CI通过，本机回归与CI分开。
- 无未解决自动审批拒绝。GH007邮箱隐私限制用已有公开noreply身份解决，未改全局配置；构建沙箱OS访问失败获准后重试，原失败证据保留。

细粒度证据根evidence/tv-optimization-20261002：overlay-matched-comparison、background-candidate-dispositions、sampling-exclusions-and-builds、post-window-transport-fix、final-candidate/build/installation/static-gates/product-verification/protection-comparison/background-visual-comparison。原图/XML在evidence/xiaomi-ui-fusion-20261002；不会自动随Git推送。无需重复采样；若另行解决搜索连接、人工声音或帧峰值，建立独立明确范围。
