# 自定义规则与 TV 适配

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
