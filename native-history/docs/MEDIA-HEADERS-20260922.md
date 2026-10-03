# 未配置Referer规则的媒体HTTP400兼容

原版播放仅传UA及规则明确配置的Referer。原生媒体发现会补页面/iframe Referer；部分媒体服务拒绝该自动值。

2026-09-22从新鲜播放页取得同一媒体地址，保持UA相同、无Cookie，每次最多读取1024字节后关闭：页面Referer配合Range `bytes=0-1023`、`bytes=0-`或不发送Range，均返回400；仅UA配合Range `bytes=0-1023`返回206、video/mp4及有效ftyp签名。因此本次证据指向自动Referer，不能归因为Range，也不能将全部HTTP400都泛化为该原因。签名地址和响应正文未写入本文。

修复范围：仅规则未明确配置Referer、原探测带非空Referer且响应HTTP400时，移除Referer/Origin额外重试一次。同URL、UA、Range和目标CookieJar保持；仍校验媒体签名/MIME，成功后的PlaybackRequest沿用实际通过的头集合。显式规则Referer、401/403/429不回退；第二次失败不递归，HTML伪成功不能通过。

验证APK为本地code50候选，SHA256 `14f57e35b624bc98c02808803f4d1749df156bc5363154a0822fbe429cdd6b0b`，晚于公开Preview4，未覆盖公开APK。

- 194项单测、release/test构建与lint通过。
- 旧电视及现代TV模拟器均通过8类真实localhost HTTP探测：正常回退、重定向、显式Referer保护、重复400限制、HTML拒绝及401/403/429边界。
- 旧电视aafun第12集原失败线路：实际400触发一次回退后解析为MP4，首帧、推进、拖动、暂停/继续通过。
- 旧电视moonci第12集：原失败线路1以相同机制恢复，线路1–3均通过短测。不是完整观看或全站承诺，也不把该增量和不同构建的17源轮合并成同包验收。
- AGE重新抽测仍为搜索5条、详情SocketTimeoutException，未进入集表解析；没有将它归为XPath或播放器已修复。

本地日志位于 `artifacts/recovery-20260922` 的 `probe-fallback-*`、`headers-aafun-tv.txt`、`headers-moonci-tv.txt` 和 `age-followup-tv.txt`。
