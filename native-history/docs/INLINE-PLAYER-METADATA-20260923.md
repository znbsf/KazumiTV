# Artplayer 字面量变量引用兼容（2026-09-23）

AGE 第2线实际iframe与第1线采用不同驱动：同一 inline script 中声明 `var Vurl = "媒体地址"`，随后顶层 `new Artplayer({url: Vurl,...})`；脚本还包含 userAgent.match 正则与回调。旧电视播放器库语法错误时地址未被请求，原字面量配置解析器又不支持变量引用及正则，因此本轮补明确的变量关联读取。

## 实现范围

新增变量入口保留原字面量解析器行为，只允许同脚本、顶层、构造器之前的单独 var 字符串声明及唯一直接 Artplayer.url 变量引用；额外用法只允许已观察到的 toLowerCase().indexOf(字面量) 只读表达式。重赋值、重复声明、未知调用、属性改写、嵌套/条件构造器、多个播放器及覆盖属性均拒绝。正则仅支持明确 .match(/.../flags) 场景的词法跳过，其他含糊语法仍交还普通发现，脚本文本不被主机执行。

WebView正常加载结束后等待8秒，再读取当前文档最多64个inline脚本、总计262144字符；解析唯一关联后核对 window 自身数据属性当前值必须与声明一致，拒绝getter/继承属性。文档identity、URL与导航代际均须一致，挑战/加载失败不放行；导航或销毁取消任务。候选走已有7+1 speculative预算与媒体探测，不直接认定成功或绕过人工验证。

不改固定规则、来源存储、主页或观看历史。此记录为实现范围；构建、受控测试及真实线路证据将在实际完成后追加，不能据代码存在推定迁移完成。

初版候选 `29982727e0b4b08942f980d2b197449c3111205e5547abfcb327fcccd6bf2e03`：release 构建、214项单元测试（0失败/0错误）及lint通过；两端本地实际resolver顶层/跨源iframe、8秒门槛、HLS探测、当前值变化/getter/同URL新文档失效回归通过，日志 `inline-metadata-tv.txt`、`inline-metadata-modern.txt`。这批是受控解析测试，没有视频播放或真实来源通过结论。

复核后进一步收紧：候选队列携带文档有效性检查，探测前及成功后再次验证导航/销毁/挑战状态；跨脚本出现额外Artplayer配置（含不支持形式）保守拒绝。额外提及可能造成可选回退拒绝，普通媒体发现仍继续。此收紧晚于上述初版候选，另行验证。

## 本地候选检查

收紧后的候选 APK SHA256 `5d4c87c29455303b35a280743fe3a783d0b75ad12658026c5846e67935dba95c`：release构建、214项单元测试及lint通过。两种WebView的本地解析测试均通过，包括真实probe进行中导航后旧媒体必须拒绝；该负例核实了候选实际入队、恰好一次延迟probe、probe期间替换页实际加载，避免因未触发路径而假通过。日志 `inline-metadata-tv-guard.txt`、`inline-metadata-modern-guard.txt`。

此候选含本地配置，只用于授权设备，不可公开上传。真实AGE线路结果独立记账，不由这些受控测试代替。

## 同候选真实AGE结果

`5d4c87c2…` 在旧电视 WebView66 和现代 WebView143 上，固定AGE规则的第12集五条线路均完成正常解析、首帧、短时推进、拖动与暂停/继续（各5/5，失败0）。旧电视第2–5线日志明确命中 `inline_player_reference depth=1`；第1线继续采用前一轮计算配置入口。现代端沿原捕获通路完成，没有使用变量引用回退。

证据 `artifacts/recovery-20260922/inline-age-roads-tv.txt`、`inline-age-roads-modern.txt`；均已终止完成。此结果把该样本的旧电视AGE从1/5推进到5/5，不代表全站/所有剧集、整集或全部来源迁移验收。没有整集测试，固定规则和用户数据保持。

同候选原有 `web-discovery` 受控回归两端通过，涵盖挑战优先、候选页导航清理、请求上下文、跨域Range、iframe恢复、延迟媒体、取消释放与噪声预算。旧核 document_start 为明确不支持/跳过，现代端 early XHR 与跨域frame通过。证据 `inline-web-discovery-tv.txt`、`inline-web-discovery-modern.txt`。

同候选真机 MXdm 搜索与第12集两条线路短测通过，日志 `inline-mxdm-tv.txt`；这是本轮通用解析改动后的来源回归，不能替代此前跨源切换/历史恢复的独立证据。所有本轮设备测试均已结束，未做整集测试。
