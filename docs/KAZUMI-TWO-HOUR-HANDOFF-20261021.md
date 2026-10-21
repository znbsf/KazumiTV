# Kazumi 两小时交付：新会话唯一统筹

## 目标与硬期限

直接人类授权：开一个新会话全权做完，允许并行、多路线，用最快办法在两小时内完成做好。用户再次纠正：不要继续围绕保护、流程、工具；要实际来源测试、故障修复、原例播放验证和可用候选。

计时已经开始：2026-10-21 23:51:07 香港时间（UTC15:51:07）；硬截止 2026-10-22 01:51:07 香港时间（UTC17:51:07）。交接、等待、构建都计入，不在新会话重置。到点交实际候选、逐源结果和准确剩余缺口，不伪称外部问题已修好。

新会话是唯一统筹；旧统筹停止派工，旧两会话目前idle。不需要为已授权的QA、普通来源访问、代码修复、构建安装再次问权限。允许新会话用同聊天内子代理并行，不要再建一串用户会话。不预设必须由旧owner做所有事；设备只安排一个明确执行者，网络/规则/代码可同时做。

## 立即执行方法

1. 前5分钟分工并开工，最多三个子代理。统筹同时处理真实QA操作和集成，避免逐包排队等15分钟。
2. 路线A：AGE、sorani、dalvdm的搜索/传输问题；读已有证据后只做能区分新解释的最小真实请求或App观察。有确切拒绝/外部故障就准确归类，不反复同请求。
3. 路线B：aafun、baimao解析/媒体失败；直接用正常网站/现有App链路定位候选到播放器断点。复用现成传输、文件工具和浏览器能力，禁止再用多层shell字符串生成“大一次性工具”。需要写源码用apply_patch。只在结构反例支持时改规则或客户端，不猜编码、不逐个追无关脚本。
4. 路线C：现有候选实际UI验收和必要客户端修复。优先拆清最近首页Bangumi超时：元数据请求失败是否确实阻断进入来源，还是执行者没有点进去。使用既有正常搜索/目录入口，不能把首页等候耗成整轮。能修的产品导航缺陷就修最小处，不修测试框架。
5. 已有11源成功样本不重测扩量。必要改动回归选最少原例。mgnacg第2话、akianime/xfdmneo原失败线路在有可区分证据时处理，优先级低于五个无可播来源。
6. 0–60分钟定位并完成支持的最小修复；60–100分钟集中集成、一次必要QA构建与原例实播；100–120分钟收尾、确认实际候选和逐源结果。不要把前半段全耗在读历史和写计划。
7. 每个子代理交可执行修复/真实结果，而不是建议或新计划。变更只在各自分配文件/独立checkout，统筹组合，设备与播放器不并发争用。最多一轮必要构建，除非首次真实编译错误有明确小修。

完成判据：17源分别给出测试环境、作品/集数、搜索/集表/解析/媒体open/画面/进度结果、修改与原例复验。明确本来可播、QA补救后可播、换线路可播、仍失败、未进入播放。交一个实际APK路径和修订。外部阻塞不得算修复通过；不用测试数量、文档数量或build成功代替播放。

## 当前代码与工具（直接复用）

工作树 C:/Users/hentai/.codex/worktrees/kazumi-rules-parser-integration/Kazumi，当前HEAD在本交接提交之前为9bc6044b。这是交给新统筹的集成树；旧统筹此后不写源码。主项目 C:/Users/hentai/Documents/Kazumi 仅作已有产物/路由，不擅自覆盖其dirty。

作者树 C:/Users/hentai/.codex/worktrees/webview-compat/Kazumi，代码761945149c8ba7d68ec50eae5ab3f4257e1018a9，dirty docs保留。A片作者fb6d4774/root0e0179c2，B片作者76194514/root92ab9731。

已实现：独立debug QA完整首页/VideoPage的Gecko失败补救；普通15秒/换源30秒保持，QA旧WebView资格下10秒primary/25秒总限/一次fallback；先退役、取消迟到、共享租约守卫。B修复selected-plugin头冻结，prepared携不可变headers，提交/失败回滚保留UA/Referer。B代码已root独立读10文件、相关98反例和分析通过；不是网站已修复证明。

最新可用x64 QA20595：
C:/Users/hentai/Documents/Kazumi/artifacts/source-catalog-playback-20261020/app-fallback/full-ui-20595-x64-build-v1/parserqa.apk
SHA256 11b844b2025e040ef9e942557b5dcef4a77a47628d77e21a887b63f3f84787b6，187563233B，0.4.5-parserqa.fullui.x64.2，parserqa/min26/x86_64，源76194514，包含A+B。真实签名/manifest/kernel/B标记已独立核，不需再做全套产物审计。

旧ARM QA20593（仅A，不含B）：app-fallback/full-ui-20593-build-v1/parserqa.apk，SHA00eee6857c145c6e94f60d2417e943ea03ee4672e416c62e2c63bc50994078aa，172465324B。只有需要ARM新代码时才构建新递增版本，不拿旧包冒充B。

固定Flutter C:/Users/hentai/Documents/Codex/2026-10-02/task/toolchain/flutter；同目录pub-cache与gradle-user-home；JDK C:/Program Files/Java/jdk-21。正常Flutter build target tools/qa/full_ui/main.dart，parserQa/debug，双端fullUi真/offline假。不要误用写死batch入口的build.ps1。QA证书SHA24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31。

独立AVD Kazumi_Parser_AB_API36，C:/Users/hentai/.android/avd/Kazumi_Parser_AB_API36.avd，emulator-5588，GoogleTV API36/x64/WebView143.0.7499.24，原read-only/no-snapshot/headless/no-audio。fingerprint google/sdk_google_atv64_amati_x86_64/emu64xa:16/BT2A.260319.001/15058170:user/dev-keys。现在已退出。只读启动和同签install-r正常允许，不卸载清数据。普通QA规则准备可备份固定files/plugins/v2/plugins.json、临时写pinned规则、读回、结束byteexact恢复；避免文件选择器和长文本输入已知失败。正常UI进入，不VM/直达route注入。

ADB C:/Users/hentai/Desktop/platform-tools/adb.exe，SHA b4a6b455702684652cccf7b46258b29e653538904359a58fd4931cf3ef286b3f。最后server111448/5037；现场查实际身份，不要求旧PID复现。服务完全不存在且端口空闲可正常start-server，已有服务不reset。

TV最后18:54正式版正在播放，QA20592停。新授权下如选TV可一次现场确认是否空闲；仍有人使用就转独立AVD，不轮询空闲或打断正式播放。TV192.168.123.217:5555，MiTV-ASTP0/mulan/API28/ARMv7/WebView66；fingerprint Xiaomi/mulan/mulan:9/PPR1.180610.011/2216:user/release-keys。正式包、个人preview和真实数据不改；其它常规QA操作自主推进，不新增审批流程。

## 17源已有真实结论

固定规则目录 ba8e10b35b0c3a56bbb6032a12356b0473844c64；JSON在 C:/Users/hentai/Documents/Kazumi/artifacts/source-inventory-20261020-ba8e10b35b0c/rules。

旧模拟器Android9/WebView66默认原样成功5：7sefun（第01）、DM84（某暗部的少女共栖标签1；标签2有波动）、giriGiriLove（01/03）、mgnacg（第1话成功、第2话仍多环境timeout）、mutefun（01/03）。除DM84外主要作品《学生会也有洞！》。不是整站验收。

原旧默认timeout，经客户端QA补救出现正例4：ezdmw（原首项标签3，另标签1）、moonci（第01/03话）、MXdm（第01/03集）、xfdmnext（原首项非数字标题，不能把六个空label猜成可测集）。现代默认/受控Gecko有对照。电视有效native首帧+完整10秒进度3源：7sefun默认、ezdmw和MXdm补救；moonci电视旧hostunknown加恢复辅助观察不补pass。

正常完整UI真实可见画面：MXdm《学生会也有洞！》第01集，在20594/API36有动画，00:21→01:21，时隔59.111秒。root亲自view两帧。403是api.dandanplay.net弹幕，不是视频。没有声音/AV/长稳，旧episode完整URIhash未出日志不能补造。不重播来补hash。

另外2源只有换现有线路成功，未修原线路：akianime原404，第二线路第1/3集可播；xfdmneo原401，第二线路《葬送的芙莉莲》第01/02可播。

无可播5：AGE搜索传输/TLS失败，电脑另403，旧Android真实peer/trust未配对；sorani搜索失败，电脑TLS EOF无peer/HTTP；dalvdm搜索403但挑战类型未证；baimao原媒体404、新环境同失败、后来selection search_timeout；aafun《葬送的芙莉莲》第01话搜索/集表正常，但TV默认15秒、Gecko总25秒、现代默认15秒均解析timeout，无media/player。LMM实际挑战停，没有播放验收。

没有任何真实来源overlay被证明并安装。不要把换线路、网络200、候选声明或新内核对照说成规则已修。

## 最近失败与不要再踩的坑

最新20595换源包 full-ui-20595-source-switch-v1：安装/两规则准备完成，仅到首页；7sefun与MXdm都未点击/未进入VideoPage。日志Bangumi热门列表connectTimeout不等来源故障。执行者恢复上下文后超时，completion1270.251>900。不能凭它撤销MXdm旧画面或称B实播通过。作者交规则恢复/QA和AVD退出，root只初读completion与stop-restore，图像/日志/退出独立回审未完成。先用实际操作找最短入口，不再次让首页等待吃掉15分钟。

baimao同body包：原详情URL已从app-system-readable.log3316/3317唯一恢复全SHA023bc38b…，但作者生成一次性Dart前多层字符串语法失败，GET0。不要再报告地址缺失或API不支持，不修批测工具。新两小时授权允许选择不同实际诊断方法；旧包仍not_run，不回溯续时。

aafun静态HTML和同源script已取证：url159编码状/encrypt1仅词法，不能猜算法、逐个追script或重复旧矩阵。规则原base同body能选1路28集，候选2路56不证明正确，禁止无反例overlay。新诊断须能区分实际候选链断点，而不是再读相同入口。

原项目唯一状态 docs/PROJECT-STATUS.md，主要证据根 C:/Users/hentai/Documents/Kazumi/artifacts/source-catalog-playback-20261020。优先看本交接和需要的原件，别重读几十屏旧状态。根.dart_tool有独立review：source-switch-B-independent-review.json、full-ui-20595-artifact-independent-review.json、full-ui-20594-direct-mxdm-independent-review.json、aafun-*-independent-review.json。

旧设备执行chat01a14cf7-e176-7cb0-b189-c135d442fcf6 idle，最后cursor86e0fe00-ab7d-40ea-b93d-63add37e744b:76；旧规则chat01a154eb-b07e-7c12-91b7-c1a2696daf3e idle/d9181729。新会话可读取/必要时协调，但不要全串行等旧会话。用户已允许并行及多路线。

## 交付与通知

每约30分钟只报真实结果/重要故障；不要报告“准备中、已派工”充进展。两小时截止输出17源结果表、修复清单、实际原例复验、一个APK路径、未解决的具体原因和还缺什么。留足最后10分钟恢复本任务QA临时数据/关闭自有进程。停止扩实验，到点诚实交付，不能把外部拒绝或未知刷成通过。

现有kazumi heartbeat将迁移到新会话作续接，旧统筹不再做执行。新会话按硬期限完成交付后停止该本次自动化，不无限续跑。
