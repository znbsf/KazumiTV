# 同域章节 GET 传输回退

AGE 固定规则的站点和搜索使用 HTTPS，但实际搜索结果中的绝对详情链接使用 HTTP。旧电视多次搜索得到 5 条结果，随后 HTTP 详情 SocketTimeoutException；电脑端同一路径的 HTTP 与 HTTPS 都返回 200，因此不能泛化为站点 HTTP 全面失效。

2026-09-22 在电视做显式诊断，只将同一详情路径改为 HTTPS，得到 5 条线路及第 12 集播放页。该诊断没有写入规则存储或固定规则 JSON。

## 修复边界

仅非 API 章节 GET 读取启用 `ChapterGetTransport`。原地址必须为 HTTP 默认端口或 80，无 userinfo；规则 base 必须为同一主机的 HTTPS 默认端口或 443。首次请求出现 I/O 传输异常时，最多以 HTTPS 再请求一次；路径、查询及 fragment 的原始编码保持。原地址本来成功时保持原行为。

HTTP 状态、验证码及节流的分类位于回退外部，不触发改协议；任何响应一旦返回，就消耗该次读取的升级机会。取消及被包装为 IOException 的取消不会发起第二请求。发生升级后，原有验证/节流重放沿用实际 HTTPS 请求。API、POST、跨主机及非默认端口不采用该策略，也不修改全局 HTTP 客户端。

## 证据

- 本地候选 SHA256 `2137caa9c0556657a8d33488f42e23103eb41a931a7f74c5577b90200d1282e5`：204 项单元测试与 release lint 通过，包含新增 10 项传输策略、编码、响应分类及取消测试。
- 旧电视使用原 AGE 规则、没有诊断地址替换：`chapter_transport` 记录 requestedScheme=http、responseScheme=https、HTTP 200；获得 5 条线路及第 12 集页面。
- 同一轮第一条线路的媒体解析仍为 MediaResolutionFailure，未到实际播放。这项修复只证明集表通路恢复，不代表 AGE 播放通过。
- 本地日志：`artifacts/recovery-20260922/age-page-followup-tv.txt`、`age-https-details-tv.txt`、`age-fallback-resolve-tv.txt`。电脑端协议对照为辅助证据，不能替代电视结果。

固定上游规则保持不变。该改动晚于公开 Preview 4；额外请求仍受原 HttpText 超时约束，失败时最多增加一次请求的等待，不做无限重试。
