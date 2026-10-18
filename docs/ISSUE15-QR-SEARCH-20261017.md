# Issue 15 手机扫码搜索候选

## 2026-10-17 最新要求：应用级临时手机键盘（候选）

旧版一次性搜索服务与以下历史设备证据仅作历史参照，不代表本次需求完成。新工作树 phone-keyboard 从 31769f00 开始；尚未构建、推送或设备验收。

- 用户显式开启前台 LAN 临时会话，关闭二维码控制弹窗不关闭连接；任一普通 TV 编辑框按 OK 真正打开后可接收，多次修改、清空、确认及切换字段无需重扫。DPAD 路过预览不成为目标；覆盖编辑框的控制弹窗期间也不投递。
- 每次编辑目标随机 ID，切换 generation、本地/远程变更 revision，POST 全部核对；无目标或旧目标/旧版本拒绝。128 条有界请求回执保持幂等，过期回执仍受 revision 隔离。上传限制 16 KiB、绝对 5 秒，字段最长默认 2048 字、搜索 120 字。
- 手机确认只写入草稿并回到 TV，不触发 onSubmitted；搜索、下载/安装仍由 TV 用户另行执行。密码和 Token 字段显式禁用，包括切换为可见文本时。所有字段已有文本均不发送给手机，规则 URL 中已有凭据也不会回显。
- 完整可手打 LAN URL 与二维码同屏，显式断开按钮可达。闲置 10 分钟停服，轮询不延长闲置；应用 paused/detached 停服。重新开启创建新随机短会话，无永久凭据、云中转、防火墙或持久访问变更。HTTP 临时 LAN 连接只适用于可信局域网，不能宣称加密或防窃听。
- 当前自动测试证据在根 artifacts/four-stream-20261017/phone-keyboard-*；设备与真实手机浏览器仍须验收。安装包与版本必须绑定集成后精确提交。

### 后续遥控和长期配对：仅设计，当前不启用

可在同一连接切换键盘/标准遥控面板，动作必须映射应用真实处理逻辑，DPAD/OK/Back、数字、颜色、Info/Menu、播放按上下文显示实际功能。频道键不能无提示当下一集；HOME、电源、系统音量、输入源不是 MVP，不采用 ADB、无障碍或扩展权限。Android 键码及电视控制器资料见 [KeyEvent](https://developer.android.com/reference/android/view/KeyEvent)、[TV controllers](https://developer.android.com/training/tv/get-started/controllers)，Sony 色键说明见 [官方帮助](https://www.sony.com/electronics/support/televisions-projectors-lcd-tvs-android-/xbr-49x900f/articles/00157696)。

长期配对需另获用户对保存长期控制凭据/持续访问的明确确认。候选架构为一次配对、短会话重连、设备列表逐个撤销及总开关；二维码仅短期 bootstrap，不能装永久密钥。当前 HTTP/WS 同网可窃听篡改，CORS、随机二维码或自制加密不能修复不可信 JavaScript bootstrap。长期设计须有稳定 origin 和可信 TLS/WSS 或可信客户端；DHCP/IP/端口变化会改变浏览器 origin，NSD 不保证手机浏览器解析。不得把长期凭据放明文 URL/localStorage 后称为安全配对。参考 [Android cleartext](https://developer.android.com/privacy-and-security/risks/cleartext-communications)、[same-origin](https://web.dev/articles/same-origin-policy)、[NSD](https://developer.android.com/develop/connectivity/wifi/use-nsd)。此阶段只保留设计和合成测试门槛，不拖入本次 bugfix 或宣称已实现。

2026-10-17，基线 main 70c3769a，独立工作树 workstreams/qr-search。

实现：TV 搜索栏提供带文字的“手机输入”按钮，打开弹窗后绑定本机一个 RFC1918 IPv4 地址及随机端口。192-bit 随机会话路径，3 分钟有效；手机浏览器的本地 HTML 表单发送关键词，电视立即显示已收到内容，遥控“搜索”确认后使用既有搜索路径。退出、Back、应用后台、到期关闭监听，返回后恢复入口焦点。无需第三方中转，无凭据存储，不修改网络权限、防火墙或全局设置。

限制：120 Unicode 字符、2 KiB 请求体、5 秒请求总时限，空输入/控制字符/错误编码拒绝；同一会话仅接受一次，并发和重复提交返回 409；跨 Origin 提交拒绝。手机页面禁缓存、禁框架嵌入及外部资源。仅选择第一个私网接口，多网卡/VPN 地址选择与手机实际可达性仍需现场验收。局域网使用 HTTP，页面只传搜索关键词。

依赖：qr_flutter 4.1.0 / qr 3.0.2，lock 已固定。pub get 下载及解析成功，Windows 插件链接尾步提示未开启开发者模式；未改系统设置。使用 --no-pub 可执行测试。

验证：指定 Flutter 工具链，`flutter test --no-pub test/qr_search_session_test.dart test/qr_search_dialog_test.dart` 9 项通过；新增持续慢流总时限与退出期间上传回归；真实 loopback HTTP 表单/中文/随机路由/错误输入/过长输入/跨 Origin/并发重复/退出/过期关闭；widget 覆盖收到回显、确认、关闭、过期、Escape 与入口焦点恢复。测试发现二维码 LayoutBuilder intrinsic 布局异常及超大请求流提前取消，均已修复并回归通过。

当前验收范围：真实 Edge 浏览器提交到模拟器、设备端回显、退出焦点及电视端三分钟过期已完成，详见下方设备证据。设备运行的是独立 FeatureQA 入口及生产二维码弹窗，专用 loopback 与 ADB forward 不能证明生产搜索页遥控入口、真实 Wi-Fi 扫码、实际 LAN 多网卡连接或系统后台关闭已验收。未操作 12T 手机、未重置数据；设备与构建由集成负责人统一协调。

验收步骤：启动候选→遥控进入搜索→手机输入→同网浏览器扫码→输入中文→发送→TV 回显→确认搜索→检查关键词及入口焦点；另测空/超长、重复提交、等待 3 分钟、Back 退出后旧链接不可达、重开生成不同链接、Home 进入后台后旧链接不可达，以及断网错误提示。

## 真实浏览器补充

2026-10-17 11:11:59 UTC，Edge 真实表单 E2E：通过 tools/qa/qr_browser_server.dart 调用生产 QrSearchSession，绑定127.0.0.1，3分钟自动结束。浏览器GET输入“二维码浏览器测试”并点击发送，显示“已发送，请查看电视。可以关闭此页。”；浏览器Back重复提交显示“Already submitted”。本地 artifacts/four-stream-20261017/qr-browser/receipt.jsonl 只有一条接收记录。不是curl模拟，也不代表Android局域网实扫通过。

首轮真实浏览器发现 no-referrer 与 Origin校验冲突，正常表单返回403；Referrer-Policy改为same-origin后成功，跨站仍不发送referrer并仍拒绝陌生Origin。增加响应头回归断言。QA脚本不进入App，不改变生产监听范围。

## 模拟器与电视补充（2026-10-17）

证据根目录为本地 `artifacts/four-stream-20261017`。本节浏览器操作由二维码工作线直接执行；设备画面、端点时间与焦点结果由集成负责人采集并提供，不能当作该工作线独立操作设备的记录。使用独立 `com.znbsf.kazumi.fluttertv.featureqa`，通过 QA 注入的 loopback 地址及专用 ADB forward 连通，生产私网绑定策略未改变。

- 模拟器 `20501`：真实 Edge 打开设备表单，空输入点击发送出现“请填写此字段。”并留在表单；输入 `Clannad 模拟器` 后提交成功。集成负责人确认设备即时回显该关键词，退出后入口 `focus=true`。浏览器记录为 `qr-browser/emulator-browser-e2e.txt`。
- 电视 `20507`：会话起点为设备时间 19:43:01（UTC+8），即 11:43:01 UTC；11:44:31 与 11:45:53 UTC 的端点检查均为 HTTP 200，11:46:04 UTC 返回 `RemoteDisconnected`。`tv-qr-after180` 画面显示“会话已过期”，退出后入口 `focus=true`。这些离散观察支持三分钟会话到期后不可继续访问，不将最后一次成功与首次断开的间隔解释为毫秒级过期精度。
- 清理：集成负责人确认本轮专用监听/forward 已移除；未留下常驻输入服务。

尚待现场验收：真实手机扫描二维码、真实 Wi-Fi/LAN 可达性、多网卡或 VPN 下地址选择、生产搜索页入口与后台关闭链路。本轮受控 loopback 验收不能替代这些项目。

### 本次候选验证与 PR 说明

PR 描述应将二维码项更新为「应用级临时手机键盘」，说明旧版只能向搜索提交一次，新版保持临时连接并向明确打开的普通编辑框输入；目标切换、版本校验和敏感字段排除是边界。长期配对和完整遥控不在实现范围，也不能复用旧版 3 分钟一次性服务的设备通过结论。

本地自动验收：phone-keyboard-regression.log 为 7 文件 35 项，覆盖真实 HTTP、多次输入/清空、幂等/改载荷重放、并发、慢上传绝对超时、迟到请求切字段、闲置轮询不续期、退出、敏感字段、字段原值不外传、手机确认不触发业务提交、控制层遮盖、返回焦点与搜索/规则既有回归。网页脚本另做可重复的合成异步测试；合成 IME 事件不能替代真实手机输入法验收。静态分析见 phone-keyboard-analyze.log。

设备复验入口为 tools/qa/phone_keyboard_navigation.dart：只允许隔离 featureqa debug/TV 模式，独立 Hive，显式 loopback 启动；两普通编辑框、一可见但明确敏感的排除字段、独立业务执行计数。fixture 日志仅字段 ID 和字符长度，不记录输入值。此入口未由本工作线构建或运行；设备负责人需绑定提交/包并验证真实输入、焦点、生命周期和 LAN。手机确认不得增加业务执行计数，电视另点执行才增加。
网页回归：运行 node tools/qa/phone_keyboard_page_test.cjs，7 个合成场景通过（未知结果禁止确认、跨目标确认隔离、在途 IME 切目标及尾 input、轮询/输入串行、普通组合输入、断线状态保持/重连、请求绝对 5 秒超时）。日志为 phone-keyboard-script-final.log；源码严格 UTF8 解码与替换字符检查通过。真实移动浏览器/输入法仍待独立验收。

### 连续键盘真实浏览器复验（2026-10-17 13:24–13:30 UTC）

生产实现 b3808c0e 已集成至 83f5eee0；API36 模拟器 featureqa 20525，APK SHA256 `28aaa03d83502705d2b5095ef2e454d304976e5e90428bd4348f21c1fe25810c`，安装后回读一致。真实 Edge 通过临时 loopback 转发连接生产 PhoneKeyboardSession：无编辑目标时禁用；打开搜索编辑器后中文实时回显、连续改写、清空、确认均通过；确认后电视执行及提交回调仍为0。切换规则 URL 后同一手机页更新目标且清空旧草稿，保存测试地址仍不触发业务。敏感字段不可输入；重开已有文字字段，手机为空。主动断开后手机显示失联且禁用，转发已删除。证据在本地 artifacts/four-stream-20261017/phone-nav-*.png/.xml/.log。

明确使用限制：**所有普通字段均为手机本次草稿整体替换电视草稿**，不回传已有内容、不追加到电视光标位置、不支持手机直接修改已有原文；页面已明示替换行为。目标变更清空草稿，target/generation/revision 拒绝旧字段迟到请求，不能自动串写。敏感字段则完全排除。下一阶段可设计 selection/编辑操作，但本轮不擅自扩大远程读取已有值的范围。连续文本输入不等同于完整遥控器或长期配对。

以上不覆盖物理手机扫码/Wi-Fi、真实手机中文组合输入、实际后台关闭与10分钟闲置设备计时；生命周期与过期由自动测试覆盖，不能借用旧一次性服务3分钟实测结论。独立只读审查 b44276ed 未发现新增阻塞。
