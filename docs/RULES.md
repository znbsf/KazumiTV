# 自定义规则与 TV 适配

## 2026-10-20：本地 TV 数据覆盖 v1（候选，未发布）

这项候选在独立分支 codex/rules-overlay-minimal-20261020 开发，基于 main
410ca4a2a35195c3306aca012997eb4750c34cfe。它不改默认规则仓库、WebView、媒体发现、
播放器或正式包。上一轮规则研究的“按引擎能力匹配的播放 profile”仍是后续设计，
本版不实现或宣称支持这些 profile，也不根据 Android 系统版本自动启用覆盖。

Android 版本与 WebView 引擎版本需分别识别。Android10不能单独保证播放；
Android9设备也不必然使用WebView66。已观察的旧核JS语法和来源策略问题可按实际
provider、版本、功能及失败条件适配，源站间接HTML、网络或原生输出问题仍需独立
处理。平台诊断依据见[Android WebView Version API](https://developer.android.com/develop/ui/views/layout/webapps/managing-webview#version-api)。

最小闭环为：导出基础规则 → 离线生成覆盖文件 → 原有剪贴板/JSON 文件入口导入 →
以有效规则执行搜索和集表 → 保存/分享时保留基础与覆盖 → 菜单“还原基础规则”。
还原会移除覆盖记录，重新导入原覆盖文件可再次启用。存在覆盖时编辑器拒绝保存，
避免把修改与基础身份混在一起；请先还原再编辑。

### 文件格式与摘要

JSON 根对象包含 kind=kazumi-tv-rule-overlay、schemaVersion=1、
upstream（repository 和完整 commit）、baseSha256、baseRule、overrides。
v1 只接受 Predidit/KazumiRules 来源标签；标签是待审查的来源记录，不会联网验证该
提交是否含有所附基础规则，也不是签名或可信发布证明。导入者仍需核实来源。

baseRule 必须是当前客户端导出的单条完整规则（包含默认值，不带已有覆盖）。
baseSha256 为该对象按所有层级键名排序后，紧凑 UTF-8 JSON 的 SHA-256；
不是原始上游文件的字节摘要。不同字段顺序不影响它，任何基础内容变化会失配。
规则身份 name、version、api 不可由覆盖改变；普通规则和上游 API 级别维持原语义。

overrides 是扁平的字段到值映射，仅允许：

- 文本：baseURL、searchURL、searchList、searchName、searchResult、
  chapterRoads、chapterResult、userAgent、referer、
  searchApiConfig.sourceTemplate（要求已有 API 搜索）。
- 布尔：usePost、useLegacyParser、adBlocker。

不接受任意 JS、验证码脚本、未知字段/必需能力、API 对象替换、解析服务、引擎匹配
或网络安全开关；超过 256 KiB、嵌套覆盖、类型不符和摘要失配均拒绝。
文本上限 8192 字符，请求头拒绝换行，地址覆盖只接受无内嵌凭据的 HTTP(S) URL。
顶层 UA/Referer 仍仅作用于原播放器/下载请求，不能修复网页 fetch 来源策略。

### 生成与导入

先核对上游提交和对应规则，再从候选客户端导出该基础规则为 base.json；
也可使用只含一条基础规则的导出数组。不要导出当前已应用覆盖的规则作为基础。
overrides.json 的教学示例（保留域名，不是实际站点修复）：

~~~json
{
  "referer": "https://example.invalid/",
  "chapterResult": ".//li/a"
}
~~~

在已有依赖配置的开发环境中执行，四个参数依次为基础、覆盖、上游完整提交和输出：

~~~powershell
dart --packages=.dart_tool/package_config.json tools/rules/create_overlay.dart base.json overrides.json ba8e10b35b0c3a56bbb6032a12356b0473844c64 tv-overlay.json
~~~

工具仅离线读写指定文件，输出已存在则拒绝覆盖，不连接站点或导入应用。
把 tv-overlay.json 通过原有规则导入入口导入候选客户端；也支持规则数组、现有分享
链接。分享后的本地记录保留有效规则及覆盖信息，仅本候选及兼容版本支持该元数据；
旧客户端可能将分享内容当普通规则并丢弃覆盖身份，不承诺跨版本往返兼容。

### 更新、冲突和撤回

有覆盖的规则不自动重定位到上游新版本。单条和批量更新遇到更高版本会报告
“保留 TV 覆盖”，不替换当前规则；普通规则仍正常更新。远端规则下载不能激活覆盖
文档，覆盖必须经用户显式导入。处理上游变化时，核实新基础后重新生成/导入覆盖，
或先还原基础规则再更新；不通过虚增版本号阻止上游更新。

本版保留现有按名称的单一上游目录模型，没有自定义远程仓库订阅、多仓库命名空间、
签名发布、自动三方合并或通用兼容适配器。上述能力不因 v1 格式存在而自动具备。
测试使用合成规则与响应，不改变已安装规则；不代表线上来源或电视播放验收通过。

核对日期：2026-10-14 UTC。已发布 v0.4.2 支持 API 8；本文的 API 9 `sourceTemplate` 是 #11 候选改动，未发布。实际 schema 以 [plugins.dart](../lib/plugins/plugins.dart)、[api_rule_config.dart](../lib/plugins/api_rule_config.dart) 为准。

## 最小 XPath 示例

以下是可反序列化的教学规则，不是可播放的站点；`example.invalid` 是保留域名。使用自己有权访问的公开站点替换 URL 与 XPath，不能直接复制本例声称验证成功。

```json
{
  "api": "8",
  "type": "anime",
  "name": "MyPublicDemo",
  "version": "1.0",
  "baseURL": "https://example.invalid",
  "searchMode": "xpath",
  "chapterMode": "xpath",
  "searchURL": "https://example.invalid/search?q=@keyword",
  "searchList": "//div[@class='result']",
  "searchName": "//a",
  "searchResult": "//a",
  "chapterRoads": "//ul[@class='episodes']",
  "chapterResult": "//li/a"
}
```

| 字段 | 意义 |
| --- | --- |
| api | 所需规则 API 版本，不能高于客户端支持值 |
| type/name/version | 类型、规则身份、作者维护的版本；同名导入会替换，先备份 |
| baseURL | 站点根地址，用于相对地址归一化 |
| searchMode/chapterMode | 搜索和详情各自选择 `xpath` 或 `api`，允许混用 |
| searchURL | 搜索请求地址；`@keyword` 由客户端编码替换 |
| searchList | 搜索结果条目节点集合 |
| searchName | 每条结果中取名称的节点 XPath，读取文本 |
| searchResult | 每条结果中取详情地址的元素 XPath，读取 `href`，不要写 `/@href` |
| chapterRoads | 详情页中的线路容器节点集合 |
| chapterResult | 每个线路内的集数链接节点 XPath，读取文本与 `href` |

`Plugin.fromJson` 对许多缺失字段有默认值，“JSON 能导入”不等于能搜索/播放。XPath 要匹配实际 HTML，不能用浏览器执行脚本后才出现的 DOM 假定静态请求也能找到。

## 请求和播放链路

1. [RuleEngine](../lib/services/plugin/rule_engine.dart) 按搜索模式准备请求、执行请求，返回名称与来源地址/ID。
2. 选中搜索结果后，根据详情模式调用 XPath 或 API 解析线路、集数和播放页地址。
3. 用户选集，将规范化的播放页交给视频源解析服务。WebView 可监听播放器解析事件取得媒体 URL；规则“测试”按钮不会替你验证到实际媒体播放。
4. 播放器使用媒体 URL；换源、历史、遥控焦点由应用负责，规则不定义 TV UI。

XPath 模式 `usePost` 将搜索 URL 查询参数用于表单请求。顶层 `userAgent`、`referer` 是请求/播放 header 配置入口。`muliSources` 是代码中的既有拼写；不要擅自改成 `multiSources`。`useWebview`、`useLegacyParser`、`adBlocker` 控制已有解析行为；`useNativePlayer` 属于兼容历史字段，不能当成跨平台播放器能力保证。

API 模式使用 `searchApiConfig` / `chapterApiConfig`。其 `request` 支持 `method`（GET/POST）、`url`、`headers`、`query`、`bodyType` 与 `body`；结构见 schema，不能把这些嵌套字段随意放到顶层。JSONPath 只支持受限的属性、下标、通配和引号键路径，不支持任意脚本过滤。API 8 已有详情变量和 `episodePage` 二次请求机制。

API 9 新增的是 **搜索**配置里的可选 `sourceTemplate`：搜索返回 ID 时，将编码后的 ID 替换其中每一个 `@source`，构成详情 URL；例如 `https://example.invalid/GV@source/` 加 ID `123`。留空完全保留旧的原始来源语义，非空必须包含 `@source`。随后 URL 仍经过现有归一化（例如移除尾斜线）。不要给原本返回完整 URL 的规则盲目增加模板。

## Cookie、JavaScript 和验证码边界

代码没有通用 `searchJS` / `playJS` 字段。`antiCrawlerConfig` 的确支持 `enabled`、`captchaType`、`captchaImage`、`captchaInput`、`captchaButton`、`captchaDetectType`、`captchaDetectValue`、`captchaScript`，但这是验证码流程配置，不是任意阶段注入脚本。只对公开可访问、允许使用的内容测试，不规避访问控制。

验证服务的 Cookie 是按插件保存的内存状态；请求端会重建域名/路径作用域，存在 Cookie 时会使用验证 UA。不能声称 Cookie 已端到端贯穿所有路径：现有 XPath 详情请求和媒体/下载请求的传递边界不同，媒体 `buildHttpHeaders` 主要来自顶层 UA/referer。某站搜索成功但详情或播放仍失败，应分别核对请求，不能靠重复验证推断全部生效。

## 创建、导入和测试

1. 设置 → 规则管理，先导出原规则；新建规则或打开编辑器，填基础地址，再选搜索/详情模式。
2. 也可从剪贴板或 JSON 文件导入，支持单规则、规则数组及既有 `kazumi` 分享链接。规则名大小写不敏感的替换行为意味着测试时宜使用独立名称。
3. 用固定公开关键词测试。内置测试流程取首个搜索结果继续解析详情，因此还要人工检查多个结果、空结果、线路、普通集与特别篇。
4. 实际播放一集，再测试下一集、返回、换源取消和失败重试；在 Android TV 上用遥控器完成输入、结果选择和退出。开发者可运行 `flutter test --concurrency=1 test/api9_rule_compatibility_test.dart test/plugin_editor_api9_test.dart` 验证本次模板行为；这是合成数据测试，不代表某个线上站点可用。

## 哪些需要 TV 适配

XPath/API 数据规则本身通常跨平台；差异主要在网站按 UA 返回的内容、WebView 版本、JS/跳转行为、验证码 UI、Cookie、媒体解码与网络能力。相同 JSON 不能保证每个平台都有同样结果。

应用已有 TV 焦点/遥控导航、输入与 Back 行为，且 #10 已加入显式换源入口。验证码的点击、文字输入、弹窗与回退仍须逐设备验证；老 Android 系统 WebView、电视厂商 WebView 与桌面实现不可视为等价。网页全屏与应用播放器全屏也不是同一个通道。规则作者不应把 TV 焦点逻辑写进 JSON；需要专门 UI 支持时应改应用。

#11 的 WebView 改动只覆盖初始化后的加载/解析和清理卡住：默认解析期限覆盖 load 与 parser，清理宽限为 2 秒；超时实例退出复用并尝试释放，下一请求使用新实例。初始化本身和底层原生资源最终释放不在此次保证范围内。尚无此次改动的真机、验证码或老 Android 验收。

## 上游策略

审查上游为 [Predidit/Kazumi](https://github.com/Predidit/Kazumi)，核对头 `025dcb5c2f62db881382c72f191d08b49a9feb41`；规则仓库 [Predidit/KazumiRules](https://github.com/Predidit/KazumiRules) 核对头 `2fa4d28659f94e1eb52e7a38d79b7b9a5dcd605b`。官方 README 的旧 API 介绍不覆盖所有当前代码能力。

TV 与上游 fork 点为 `1b395a501f7712d17adbe77a95af65743bf736f9`，审查时两侧分别有 124/66 个独有提交。此 fork 有大量 TV 与稳定发布改动，适合逐项移植并回归；直接 rebase 会重写已共享历史，整仓 merge 会一次引入不相关功能与依赖。`4960f9c` 只是此前文件审查目标，不能当作已经完整合并的基线。

#11 选择 [ff859472](https://github.com/Predidit/Kazumi/commit/ff8594727d9d157d23f9c2b26759f943ebb35936) 的 API 9、[eb53fcb8](https://github.com/Predidit/Kazumi/commit/eb53fcb8e2cba36eb0d6b7789295ff426f1b83b8) 的重复设置导航修复、[de6ab4f6](https://github.com/Predidit/Kazumi/commit/de6ab4f696ba8cbc3d83038783b64118bc23fd17) 的重复 hover 动画修复；按 TV 代码结构适配，不整仓 cherry-pick。截图面板、删除内置规则和依赖升级未纳入。WebDAV 历史开关、搜索去重排序及已有验证码机制已具备等价实现，不能再当新增修复。
