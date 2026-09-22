# 晚间来源与设备验证（2026-09-22）

用户已取消14点停止限制，继续原计划；不做整集测试。

## 同一候选包的17源完整短测

电视：小米 Android9 / WebView66。APK SHA256 `f9786d4fe4edb58854c63cbcd72dcb6952aa408a6dfe33feb0579487f2b2f114`。固定规则仍为 KazumiRules `0d85fc80ab6c208548d9ee9c9e81271b08ff7f39`，17条完整检查；没有修改电视规则、启用/隐藏状态或用户历史。

**9个来源、17条线路短测通过**。每条通过要求首帧、进度推进、拖动（可用时）、暂停和继续，不代表整集或全站节目通过。失败不自动归因于WebView。

|来源|通过线路（从1开始）|未通过或未进入播放|
|---|---|---|
|7sefun|2|线路1 resolve：HTTP 404|
|aafun|—|线路1 resolve：HTTP 400|
|AGE|—|chapters：SocketTimeoutException|
|akianime|1|线路2 resolve：MediaResolutionFailure|
|baimao|1、2、3、4、5|线路6 resolve：MediaResolutionFailure|
|dalvdm|—|search：需人工验证|
|DM84|—|search：HTTP 522|
|ezdmw|1、2|线路3 resolve：MediaResolutionFailure|
|giriGiriLove|1、2|本轮所选线路通过，仍有节目范围限制|
|gugu3|1|本轮所选线路通过，仍有节目范围限制|
|LMM|—|search：需人工验证|
|mgnacg|—|search：需人工验证|
|moonci|2、3|线路1 resolve：HTTP 400|
|mutefun|—|search：需人工验证|
|MXdm|1、2|本轮所选线路通过，仍有节目范围限制|
|sorani|1|本轮所选线路通过，仍有节目范围限制|
|xfdmneo|—|三个关键词均空结果|

## 真实验证码及现代分支

- giriGiriLove：用户读取验证码，实际原生提交按钮提交后，原搜索恢复4条结果；此前 `1de90384…` 包紧接第12集两线短测通过。上表 `f9786d4f…` 再次通过两线。验证码Cookie自然保留，没有人工伪造成功或跳过服务端。
- dalvdm：旧电视与现代WebView实际页面均加载jQuery/MAC.Verify函数。脚本显示在输入获得焦点后才插入验证码图；电视实际点击网页输入框使图片数0→1。固定规则使用旧DS模板XPath，与实际MAC控件不符。诊断等待超时不记验证通过；兼容实现与真实正确输入恢复仍在推进。
- xfdmneo：已保存响应重定向到综合门户且旧搜索列表不存在；AGE实际详情网络超时，尚未进入集表解析。不能据此把它们归为已修复或播放器故障。
- 现代TV模拟器 API36 / WebView143.0.7499.24：通用发现测试通过，含document-start early XHR、跨域iframe、兼容分支、挑战优先级和双页面释放。是受控能力测试，不代替真实来源播放。
- 历史列表详情返回焦点修复，在电视和现代TV均通过真实遥控Back/确认回归，重新确认打开详情而不触发续播。
- 现代验证受控按钮/异步/POST-cookie测试通过；62秒等待、HOME暂停轮询与同一WebView恢复通过；清空网页输入后的按钮状态检测未通过，正在区分可访问性状态与实际控件行为，暂不记完整现代验证通过。

原始日志、私有页面及截图仅在忽略目录 `artifacts/evening-sources-20260922`。没有上传APK或私有凭证。
