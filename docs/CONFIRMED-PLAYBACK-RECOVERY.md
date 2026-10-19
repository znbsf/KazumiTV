# 确认后尝试软件兼容播放（草稿）

## 当前补救路径：失败后补试一层，仍失败才取确认缓存

2026-10-19候选已在Android TV跑通“正常解析超时→明确HTML候选→真实MP4→原生首帧”，完整版本、一次未成功尝试与成功对照见[当前状态](PROJECT-STATUS.md)。第三方规则保持原样：不把HTML直接交给播放器、不从任意链接爬取、不递归多层。候选不唯一/回到原页/已知广告则停止；下一层最多10秒且受整轮预算和取消约束。此路径也可能因上游慢加载而失败，不能用一次成功撤销已有的第二层超时记录。

失败仍记录原页和额外页各自结果及nested_page关联；超时前最多等待既有cleanupTimeout取得只读DOM readyState、iframe/video数量、解析脚本状态与iframe地址指纹，不获取页面正文/存储/凭据。快照获取失败或卡住不能延长为无界等待。后续同集确认缓存仅在超时/未找到时消费，首帧确认前不缓存，原生失败清除。下文“尚未修复/未安装”为各阶段历史事实，不代表当前候选状态。

## 2026-10-19：500具体请求已匹配，撤回其为视频失败主因的猜测

在原授权下进一步对照同源第2/3集，宿主隔离Chrome记录了4次有界网页加载（不运行Kazumi解析脚本，不下载整集；媒体请求截获后中止）。第3集 `GET https://dp.no3acg.com/index.php/index/dm?ac=dm&id=be140d7cf92a6db1` 的URL SHA256前12位正是电视日志的 `321c99f4d2a6`。对照响应500，正文是网站通用错误页“你所浏览的页面暂时无法访问”，没有后端异常栈；网页播放器配置明确将该路径列为 danMu_api。可播放的第2集对同类弹幕接口也返回500，因此撤回上一节“重复500为主要视频失败嫌疑”的推断。这里取得的是宿主对同一URL的新请求/响应，不能冒充电视历史响应体原件。

实际差异：第2集网页播放器请求QQ MP4；第3集却把 `www.lmm85.com/play/8308_1_3.html` 作为media请求，响应200/text-html，内容为对应第03集播放页。新浏览器直接打开第3集、以及第2集后切第3集都如此，故未支持sessionStorage切集污染假设。直接作为网页打开该lmm85页面，则经过另一层播放器解析到不同的QQ MP4；此时两集最终地址各自Range请求均返回206/video-mp4、2048字节且含ftyp。结论为上游交出间接播放页，而当前App不会将该非媒体地址继续作为新页面解析；不应把HTML放宽成视频直链。本次未做嵌套地址电视播放验收，也没有修复二次解析，不能把缓存试验称为第3集故障修复。

原始网络请求、对应响应、页面配置、媒体小范围读取、结论JSON保存在原 failure-snapshot 目录；其中 request-response-conclusion.json 为本轮结论。带签名URL仅本地保留。地址含dis_k/dis_t，尚未确认有效期；同地址在两组UA/Referer组合下曾分别返回404/206，未隔离具体header的影响，缓存保留实际播放成功时的请求头。4次浏览器任务正常关闭，未操作正式电视或QA包，未改系统代理/证书/调试设置。取证完成后停止原logcat，核验所属两个采集进程已退出；保留日志，不改变电视应用状态。

缓存本地候选：内存最多20条、首帧确认后5分钟，按完整规则配置+番剧+线路+集数+页面URL隔离；仍先正常解析，仅超时/未找到时取同键地址及原请求头一次。取消/过期/更换集数不回退，回退不续期，原生播放失败作废；文件、下载、未出帧和预解析回滚地址不写入。它只能容错曾成功播放的同集，不能用第2集缓存替代从未成功解析的第3集；未安装到电视或发布。测试结果跟随PROJECT-STATUS。

## 2026-10-19：0.4.4 正式电视再次失败，已定位解析阶段

用户主动操作后报告失败；只保存日志、当前错误界面及包身份，不点击重试、不改解码配置。正式包 0.4.4/205571、PID13450；证据为根 artifacts/tv-stable-044-live-20261019/122241/failure-snapshot（原始日志与用户内容仅本地）。12:23:05 切至第03集，session1792383785198318-4 在15002ms后 outcome=timeout，界面为“视频解析超时，请重试”；此请求没有 resolved、原生播放器创建或首帧，因此本次不是已进入原生解码后失败。

12:21:27、12:21:49、12:23:20 三次同剧集地址指纹解析超时，都含 dp.no3acg.com#321c99f4d2a6 的 HTTP500/mainFrame=false。先前12:20:39的另一剧集地址成功解析到 groupvideo.photo.qq.com，12:20:41出现实际首帧；成功请求也有 union.maccms.la 连接重置，不能以该警告认定主因。失败时图片418/连接重置也不能替代视频链路证据。

同现场console及另存公开 EcPlayer1.js 确认 dp.no3acg.com 承载来源网页播放器；重复500是主要关联异常。尚缺500的具体请求路径/响应体，不能断言是媒体文件500、网站服务端自身故障、参数错误、设备网络或特定缓存问题；电脑只读获取网页/脚本不算电视复现。最新单条 PlaybackTrace 在logcat被截断，前两次同指纹记录完整；应用私有持久日志尚未导出，已保存可取得的系统日志。明确阶段后不重开copy/GPU/软解实验，下一步若继续定位，应优先获取完整失败请求与响应及参数对照，不盲目加超时或自动重试。原有有界被动采集维持原截止条件，未启动第二个采集器。

## 后续诊断补齐（0.4.4候选）

针对下节现场留下的证据缺口，新增 PlaybackTrace 关联解析与原生会话：错误详情先脱敏，再保留有限上下文；通过强制写入既有kazumi_logs.log，在普通模式和重试后仍保留。WebView同时记录资源错误的域名/请求指纹、平台错误码、HTTP状态与mainFrame；取消和替换单独记结果。未知原生错误不会自动变成硬解结论。查看入口为设置→存储与日志→错误日志；下次现场先保留该文件及logcat，再重试，按同会话、同地址指纹和时间关联。

本地覆盖脱敏、未知错误在同步释放前记录、限长/限条、取消后重试隔离、真实文件持久化。不会开启全量HTTP头或脚本console持久化，也不改现有解码策略。日志不保证追溯到平台未上报的内部原因；进程崩溃或WebView init永不返回仍需系统日志。0.4.4候选实际安装后的取证以项目状态为准，r7旧原生错误无法由新代码补回。

## 2026-10-18 14:30：r7 当前源间歇失败，旧日志已保留

用户确认剩余电视 UI/遥控验收通过，同时另报当前源失败；允许点击当前源一次。实机 MiTV-ASTP0 / mulan，remoteqa 0.4.3-qa6-r7 / 205551。新证据目录为根 artifacts/four-stream-20261017/tv-r7-failure-20261018-143043：before-logcat.txt 在操作前完整保存，before.png/xml 确认当前焦点是「学生会也有洞！」7sefun；原始日志含媒体签名地址，仅本地保留。prior-app-redacted.log 为脱敏旧应用日志。

- 13:45:15 与13:46:00，7sefun 剧集页 HTTP200；13:45:16/13:46:01 进入第03集，WebView 出现 SSL handshake failed / net_error -101，尚无相应 resolved video URL 或 native VideoOutput 创建。13:45:55 同时有 SourceSheet 的15秒 VideoSourceTimeoutException。只能确认解析阶段曾失败及同期连接异常；握手日志没有具体失败资源，不能断言主媒体域名、证书、DNS或路由根因，不能把 SourceSheet 超时等同所有 VideoPage 请求的精确终态。
- 13:49:01 是另一来源 mgnacg 第1话；13:49:06 已解析到带签名的 .mknvideo URL，direct 输出 handle2271706984 已完成1×1预挂。13:49:08 session102588664 只有 category=unknown / signal=native_error，随即 dispose；无本会话 hardwareUnavailable 证据。未知错误不可改写为硬解不可用、格式错误或网络错误。
- 本次14:31:22点击7sefun，第03集在14:31:25.901解析完成；14:31:26 direct预挂，14:31:28选择 OMX.amlogic.avc.decoder.awesome，14:31:29.923尺寸1920×1080，14:31:30.207真实首帧回调；attempt.png 有画面，after-media 位置99974ms，后续170002ms。本次成功与用户“好像又好了”一致，不能证明间歇问题已修复。成功会话仍有 ACodec setPortMode/nBufferCountActual 警告，故单凭这些警告不可归因失败。
- 弹幕403同时出现在失败和成功会话；该日志不是视频流403证据。

源码复核发现观测缺口：VideoWebviewImpl._log 仅流向页面日志流；VideoPage 的解析超时只改UI，未持久记录请求终态。PlayerErrorMapper 只保留安全分类，unknown 没有原始错误详情；MPV详细日志仅 playerDebugMode 时写入文件，普通 playerLog 每次新建播放清空。因此当前系统日志不能追补已消失的旧原生错误内容。后续优先补可脱敏、带会话关联的解析阶段/失败原因有限日志，再在同源复发时观测；不根据本次未知错误调整解码或扩大重试。

本轮未新增功能修改、换源对照、安装或重开copy/GPU实验。取证后正常Back停播，media_session inactive/state0；音量保持8/100、配对不变。所有采集均为已完成的单次命令，无持续录制。即时 dumpsys cpuinfo 含过去播放窗口，不作为停后安静证明；另保存短时 top 采样观察实际负载。

## 2026-10-18 QA6 用户现场：Surface 初始化互锁修复候选

### 当前路由：先按现场输出路径判断，copy/GPU不阻塞本轮

2026-10-18用户再次明确复用既有copy/GPU结论、明天自行验收电视。本轮仅回读既有qa6-user-regression-app.log：第484行session=574978520与第772行session=95887251均明确output=mediacodec_embed、hardwareUnavailable、mpv_no_software_fallback；对应创建后约6.8秒及1.2秒，无前置实际尺寸Resize。当前对应源码android_video_output.dart对mediacodec_embed固定hardwareAcceleration=true、hardwareDecoder=mediacodec，故可确定故障请求的是direct MediaCodec路径，不是mediacodec-copy/GPU；这些失败会话没有证明成功选中了某个具体OMX解码器。较早其他会话的OMX.amlogic.avc.decoder.awesome警告不得跨会话归因。

此前20547模拟器copy基线失败仅保留历史环境证据；没有本次用户故障相关的新证据，不满足重开门槛，不再作为本轮交付阻塞，也不执行下方旧的拟议copy诊断。当前播放器保持1037a14e已验证的direct有界预挂修复，不增加新的播放器修改。原视频、外部轨道与真实声画由用户明天验收；本轮不连接/唤醒/安装/卸载电视，不重复模拟器播放。

现场仅离线读取负责人保存的 `qa6-user-regression-app.log/media.txt/screen.png`，本分工未操作设备。23:37:20 和 23:39:56 两次解析已完成，创建 SurfaceTexture 后没有 SetSurfaceSize/Resize，分别约6.8秒和1.2秒出现 `mpv_no_software_fallback`，紧接输出释放；不是30秒首帧超时。ACodec警告属于其他时间段，不能归为这两次失败根因，也不能由此断言设备损坏或网络问题。

对比正式版 `70c3769`、固定上游 media-kit `994465d9` 与 QA4/QA6：默认 direct MediaCodec 和 `androidAttachSurfaceAfterVideoParameters:false` 保持；但上游实际没有消费这个参数，直到解码后的 videoParams 才请求 Surface 尺寸并发布 wid。兼容恢复新增 `hwdec-software-fallback=no` 后，未附着 Surface 的初始化无法再依靠软件解码先产生尺寸。这是与现场吻合的源码互锁路径；尚缺本次原生对照，不能把推断写成已验证的视频恢复。

修复候选兑现显式 false：先请求1×1占位 Surface，等实际回调及 wid/vo/vid 属性安装完成，才放行 VideoController 初始化和 open；初始阶段不 seek（seek 本身等待 VideoController，会造成新的互锁）。保留既有属性顺序、direct 默认、禁止隐式软解、手动一次恢复、旧 owner 失效和真实 consumed-frame 首帧判据；占位尺寸不代表首帧。等待有10秒上限，取消/属性错误终止初始化。后续真实尺寸仍更新 Surface。

本地聚焦19项测试通过（Surface挂载门控、输出所有权、确认恢复、当前输出失败）；实际Android controller/helper/test静态检查0 error / 0 warning，2项既有文件头info。测试验证请求接受不等于属性安装、安装不等于首帧、退出取消、错误和超时；不替代原生Surface联调。

后续边界复查发现：若原生 SetSurfaceSize 请求本身未返回，仅给 wid 回调计时会漏掉请求的等待，cancel 也会被 Future.wait 拖住。先补两个反例均失败，再把整个请求与安装等待纳入同一10秒期限，并独立竞争取消信号。最终5个文件 **32项通过**，包括既有 direct、GPU/GPU-next + mediacodec-copy、手动 no 的配置保持测试；helper和测试静态检查无问题。生产路径均显式预挂，未改renderer或decoder选择。负责人先前模拟器direct首帧和位置推进结果对应此取消边界补丁之前；最终fixture需带上本补丁，不能把之前的全量/设备结果改写成最终版本验收。

边界：media-kit NativePlayer.dispose 本身先等待 VideoController 初始化，故极端平台请求完全不返回时，应用层退出仍可能等待本10秒期限后才执行原生输出 dispose；helper 的取消即时完成测试不能当作完整原生退出即时完成的证据。迟到平台响应不改变新门控，既有 owner/token 隔离继续约束旧输出。

### 20544 GPU 紫屏反例与同 Surface 尺寸更新

负责人20544模拟器实际截图中 GPU + mediacodec-copy 和 GPU + no 均整屏紫色，虽有首帧通知和位置推进仍判失败；此前20543 direct色条结果不能代替GPU验收。`qa6-regression-gpu-software.log` 中1×1和640×360两次Resize的wid同为14378。源码确认callback仅赋wid.value，ValueNotifier对同值不通知，导致mpv `android-surface-size` 保持1×1，而native缓冲区和Flutter rect已变640×360。这是本次预挂引入的实质回归，不能归因模拟器，也不能把consumed-frame单信号当正确画面证明。

修复改为按(wid,width,height)整体变化排队更新mpv，独立于Flutter rect；完全重复事件不重配。回调不await重入锁，继续受输出owner/token门控，退休队列不访问mpv。新增同指针尺寸更新及退休队列测试，本轮23项聚焦通过。后续20545须重测direct/copy-GPU/手动软解真实截图和连续推进；本条不提前声明紫屏已修复验收。

### 20545 后收敛：仅 direct 预挂，GPU 保持原路径

20545负责人观察 GPU + no 实际色条通过，但 GPU + mediacodec-copy 出现黑屏与UI/状态timer停止；日志在16:13:24.058同wid的640×360 Resize后无进一步Dart timer，并出现新一轮CCodec初始化。新增同wid刷新执行了vo=null→size→wid→vo=gpu→seek，扩大了活跃GPU重建行为。缺少原生栈，不能断言具体属性调用死锁。既有 `SOURCE-HEALTH-IMPLEMENTATION-20261017.md` 仅记录GPU硬解无响应及配置差异，也不能作为模拟器根因证明。

按最小范围收敛：仅 `mediacodec_embed` 且显式 `androidAttachSurfaceAfterVideoParameters:false` 预挂，并允许同wid尺寸刷新；GPU/GPU-next（含copy和手动软解）恢复原来尺寸事件后首次挂载、仅wid变化重配。未修改硬解选项、全局async或首帧判据。补模式边界测试；20546需与同素材/配置旧逻辑作实际画面对照，20544紫屏、20545copy无响应继续保留失败身份。

### 最终20548候选收敛（取代上段同wid刷新方案）

20546 direct 在16:17:56.027仍playing=true/17000ms，16:17:56.034实际尺寸Resize后状态timer停止；负责人20547使用旧controller作同环境同素材copy对照也无响应，故copy问题不能仅归因本轮预挂，也不能在无线程栈时断言模拟器根因。按负责人决定停止重复copy探测。

最终仅保留direct显式false预挂及有界门控，恢复原wid.addListener/removeListener触发机制，不给同wid尺寸事件新增vo重建或seek。删除本轮未提交的surface_state helper及对应测试；预挂模式判定和测试移入surface_attachment文件。GPU/copy/software仍走原尺寸后首次挂载。首帧、owner/token隔离和既有释放修复保持；此前20543 direct色条是该最小方向的已有证据，20548仍需最终direct两次、software一次实际画面验证，不将源码收敛当通过。

本次需要原生验证：首次 direct 打开在解码前已有非零 wid；正常首帧、尺寸更新后连续播放；退出时挂载等待取消；旧输出迟到回调不影响新会话；无真实视频帧不能通过首帧等待。模拟器由负责人执行，Android9本轮不安装新包，真实用户媒体回归仍待后续允许的验收。

## 2026-10-17 新发现：首帧信号语义（进行中）

源健康集成审查确认固定 media-kit `994465d9` 的 Android `android_video_controller/real.dart` 在视频尺寸事件后即完成 `waitUntilFirstFrameRenderedCompleter`，该 Future 单独不能证明真实纹理帧已消费。Java 输出端未实现相应 first-frame notify。旧模拟器/电视截图仍是其原始可见画面证据，但仅凭该 Future 的自动首帧判断需修正，不能把旧907测试或尺寸通知当新健康探测验收。当前正准备以实际 SurfaceTexture 帧消费回调替代；未构建/原生验证前不宣称解决。

新问题建议单独追踪为“Android首帧Future被视频尺寸提前完成”，复现判据是仅尺寸事件而无输出帧时Future不应完成。本次尚未向远端创建issue。

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

## 2026-10-17 首帧等待期间的视频挂载修复

20511完整页面出现replacement Resize640x360但未收到真实firstFrameNotify；相同GPU/no的独立external_snapshot入口可首帧。源码确认两层门控：VideoPage在loading时不挂PlayerItem，PlayerItemSurface又在loading时不挂Video；原尺寸推断通知曾掩盖首帧与挂载之间的互锁。现在加载期间在原加载/取消UI下单独挂Surface，VideoController非空即可渲染；controller赋值/置空改用Observable，Video按controller身份重建订阅。加载和调试遮罩alpha .99，避免完全不透明遮挡；不放宽首帧完成条件，不提前挂载完整播放器交互层。

真实media-kit Video/Texture widget回归确认loading仍true时TextureLayer存在，旧/新controller及null更新可观察，加载取消覆盖按钮可操作。测试只替代原生输出元数据，不伪造首帧完成；它不是原生解码/显示验收。后续20514/20515已补真实firstFrameNotify与恢复状态，见下方最新验收；该widget结果本身仍不替代设备证据。独立QA补rootScaffoldMessengerKey使toast有合法宿主，该遗漏不归为生产缺陷。

20512首次设备复验在真实stop→videoController=null触发MobX严格写入断言，原widget回归的外层runInAction掩盖了该调用边界。已将action封装到生产setter本身（getter仍可追踪），改回归为ReactiveWritePolicy.always下直接??=发布、await后直接替换、调用真实playback.stop清空，禁止测试外包action；该定向回归通过。QA定时日志在decoder尚未初始化时显示not_initialized，避免在原错误后增加LateInitializationError。该修复的后续新包复验见下，不把20512失败改写为通过。

## 2026-10-17 最新验收（集成负责人设备执行，离线核对）

### 用户反馈整改后的补证据（13:38–13:41 UTC）

最新生产修复 `b44276ed` 全量1017项通过；只改QA初始化的后续 `82277968` 定向实际构造测试另通过1项。播放QA20528（源码含上述提交）安装回读SHA256 `c3b53fe02ea616de7ce7a8595d999bdae3c9fafa92cb96203325badd4aecafd8`。20527曾因QA重赋late final danmaku红屏，已修为QA专属getter并加入真实Controller构造测试；这是失败样本，不计播放验收，也未改变生产初始化。

- 首帧上限：本机服务立即给合法头、每秒flush一个真实媒体字节；13:38:34.884请求，13:39:04.563安全诊断 `firstFrameTimeout`，错误页明确等待画面超时，pending=false，无软解确认或循环重试。证据A/lifecycle-final-drip-result与media-requests.jsonl。此前delay40在约5.5秒失败只能对应底层网络超时可能性，不算本项通过。
- 原生重叠：13:40:10.241旧sample请求delay12，旧播放器13:40:11.390释放；新H264请求13:40:11.798，新控制器878472694于13:40:11.836进入，13:40:12.238真实首帧。旧响应预计13:40:22.241返回后，新会话继续至11291ms正常EOF，13:40:42仍blocked=false/nativeError=false/pending=false。无Unhandled Exception。证据A/rapid-overlap-events.json、lifecycle-rapid-overlap与lifecycle-rapid-after-old-return；此项补足下方旧记录明确未覆盖的原生时间重叠，不扩大为所有原生竞态证明。
- 完整生产main20529（非fixture）安装回读SHA256 `7ae97cc1d31ba249df2751767b1d5f9913a8d0468a62efa40b36bf8a73395a29`，正常启动使用约定首屏（A/main-final-smoke）。未代同意或绕过既有审批限制，后续生产引导/首页人工验收未完成。未操作用户电视。

实际硬件方法故障的正例、Android9外部轨道恢复与物理扬声器/校准声画仍是现场边界；明确方法日志分类有自动正负例，不能当成真实硬件故障验收。正常下载包仍为lib/main，不含本地故障fixture。

全量 **955项测试通过**，测试head `606593f1`，本播放生产修复为 `7595a9ad`。完整页面模拟器20514与Android9 ARMv7电视20515使用独立recoveryqa身份，不等同正式版发布/合入。私人证据根目录为 `artifacts/four-stream-20261017`，下文简称A；原始设备日志不提交。

- 模拟器20514完整VideoPage：`A/recovery-emu-action-restored.log` 中11:54:00.779真实firstFrameNotify，随后恢复17秒暂停，blocked=false、loading=false、pending=false、decoder=no，焦点回当前剧集。与此前20511仅Resize、20512MobX异常分别保留。
- 电视20515完整VideoPage：`A/tv-recovery-restored`（log/png/xml）确认恢复17秒暂停；`A/tv-recovery-playing` 记录位置27.7→39秒持续推进，并正常EOF至第2集，下一集回默认mediacodec。只覆盖本受控素材与此设备，不扩展到所有站点/长片。
- 模拟器FFV1负向：`A/recovery-emu-failed-visible` 显示明确软件播放失败及重试、选集/换线路、换源三个入口，无自动重试或跳集。日志内部loading仍true，错误页有效；**不写成loading=false**，也不将不可解码素材算作成功。
- 外部轨道独立入口：模拟器20506 `A/external-asserted.log` 与电视20510 `A/tv-external-pass.log` 均记录先捕获17秒/1.25倍/暂停，再重建后轨道一致及同状态持续500ms的typed restore PASS。该入口验证原生snapshot/restorer，不是完整硬解失败提示链携带外部轨道的证明。
- `A/external-emulator-av2.mkv` 离线分析确认外部音频A约440.19Hz、外部字幕B推进；录制内22组脉冲音频晚159–224ms、中位205.5ms。这是模拟器内部录制，未校准采集链路；物理扬声器、自然影片口型与校准后的AV同步仍缺证据。第一次静音录制为失败样本，不计成功。详见 `A/external-av-analysis.json/.md`。

delay12最终证据：`A/media-requests.jsonl` 12:03:12.914记录sample请求mode=delay12；旧控制器471688714于12:03:14.728离开（约1.8秒，`A/recovery-delay-inflight-exit`），证明请求在途时退出。新控制器3555623于12:03:28.093进入，已晚于旧请求预计返回；12:03:37.418真实firstFrameNotify，12:03:39恢复17秒暂停、blocked=false/loading=false（`A/recovery-delay-final`）。只声明“在途请求退出+随后新会话恢复”，**不声明旧响应与新会话并发重叠的原生实证**；并发回调隔离仍由单元测试覆盖。首轮请求未建立即退出只证明立即退出，未用作该结论。既有2026-10-16延迟案例保留历史范围。当前不新增合并、正式发布或全部验收完成声明。

## 20548 最终最小候选原生结果（2026-10-17 UTC）

后续只读定位：固定依赖公开NativePlayer.setProperty直接同步调用mpv_set_property_string，不受内部_setProperty的configuration.async分支控制。下一步仅允许同20547条件的一次临时诊断：记录输出锁、vo=null、android-surface-size、wid、vo=gpu、seek的BEGIN/END及session/序列/单调时间，不记录URL；timer停止超过5秒后对该模拟器QA进程最多一次有界debuggerd -b。缺END须结合线程栈，不能仅凭时序断言死锁；权限拒绝不提权改系统，最多30秒观察，恢复临时代码并停止QA进程。此诊断尚未执行，当前不再试跑组合。

仅direct预挂，原wid listener机制保持。最终1060全量测试通过。20548 direct实际色条、持续推进和rapid replace [false,true]通过；software实际色条及推进通过。20546copy与20547改动前controller严格基线均黑屏/状态timer停止，具体原生阻塞点未证实；这不是copy通过记录。20544纯色和20545/20546新增同wid重建失败保留，相关新增重建代码已经撤回。最终APK哈希与完整验收边界见PROJECT-STATUS顶部。本轮未重装或操控电视，Android9原视频与真实AV仍待验收。
