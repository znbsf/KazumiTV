# 弹弹play 接入

只读接入 [弹弹play开放弹幕网络](https://www.dandanplay.com/)，参考[官方鉴权文档](https://doc.dandanplay.com/open/)与[Swagger](https://api.dandanplay.net/swagger/index.html)。

- 设置填写 AppId 与 AppSecret，本机 Android Keystore AES-GCM 加密保存，关闭系统备份；密钥不回显。
- 播放器按官方 Bangumi ID 映射和明确集数自动获取弹幕；特殊集或映射不唯一时使用“弹幕设置”手动选择。手动结果优先，迟到的自动请求不会覆盖。
- `X-Signature = Base64(SHA256(AppId + Timestamp + Path + AppSecret))`；Path 不带查询参数。只向 API 原站发鉴权头，跟随 CDN 跳转时移除所有鉴权头。
- 响应限制 8M 字符，每集最多解析 30,000 条；最近两集内存缓存 10 分钟。八条互不重叠轨道，保留字幕区域。
- 暂停、跳转与倍速取 Media3 实际时间；±1 秒校准，范围 ±120 秒。没有上传或发送弹幕功能。

调试部署可将 `danmaku-import.json` 放入应用私有 files 目录（键为 `appId`、`appSecret`）。仅 debuggable 构建启动时导入，加密后删除中转文件；不得把真实文件加入仓库、构建资源或日志。常规用户使用设置页面。

当前已验证签名、异常数据过滤、时间查找、密集弹幕轨道限制；指定 Android 9 电视实际读出加密凭证，搜索和弹幕下载成功。独立测试入口仅位于 androidTest，不打进主 APK。0.2.2 真机自动映射第 1 集并显示 7,305 条弹幕通过；长时间同步、不同版本偏移和播完后连续自动切集仍未验收。

## 公开测试包

0.3.0-preview.1的维护者构建通过仓库外properties文件注入应用凭证，设置中的用户凭证优先；清除本地覆盖后使用内置凭证，关闭弹幕可停用。Keystore保护的是用户本地覆盖数据，不能保护APK内置秘密不被提取。公开包不提供防提取承诺，失效后需更新凭证或用户自行配置。编译不配置文件则不带维护者凭证。不要将实际文件放入源码、日志、Issue或Release附件。
