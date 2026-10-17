# Issue 15 手机扫码搜索候选

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
