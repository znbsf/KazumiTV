# FlutterTV 融合版：小米电视实测（2026-10-02）

融合版已覆盖安装到用户后续明确授权的既有小米电视独立测试包。首页横向导航、向下滚动、紧凑详情、来源列表及失败后返回原第 50 项作品通过实测。真实播放验收受阻：实际尝试的 7sefun、baimao、ezdmw 都取得播放列表，但在向 Dart 播放器交付视频地址之前解析超时。首帧、进度推进、暂停、拖动、成功播放中的换集及续播仍未验收通过。

本记录追加于此前电脑/模拟器交付之后；此前模拟器的 580/580 回归与受控媒体验收仍是各自阶段的证据。电视上的网站解析失败未据此改动已交付 UI 或播放器，也未扩大为底层解码专项。

## 安装版本与环境

| 项目 | 实际核验值 |
| --- | --- |
| 项目 / 分支 | `C:/Users/hentai/Documents/Codex/2026-10-02/task/Kazumi` / `codex/flutter-tv-main-ui-fusion-20261002` |
| 已安装产品源码 | `d3033a972f696a891bb39d33a365d5981200c197`；472 个冻结源码文件哈希不变 |
| 设备 | 已连接的 Xiaomi MiTV-ASTP0；Android 9 / API 28；1920×1080；原始地址与序列号只保留在本地私有证据中 |
| WebView | `com.android.webview 66.0.3359.158` |
| 独立测试包 | `com.znbsf.kazumi.flutterlab.test`；`2.3.1-tv-ui-fusion.1` / code `203081` |
| APK | `artifacts/Kazumi-FlutterTV-UI-Fusion-Xiaomi-isolated-armeabi-v7a.apk`；ARMv7；31,641,254 bytes；min SDK 24 |
| APK SHA256 | `23377cd84215bd8fa0ab527204ea9579d66ec77c4c82a6a7b0fca25678899d40` |
| 签名 | 沿用旧独立测试包证书 `fe3f74f8c6f7bf2af6edffbed9c0293e37cb876beffa6dd5055b8971542892a4` |
| 原播放器 | `libmpv.so` 与电视上原独立测试 APK 逐字节相同；未升级媒体依赖或替换 Dart 播放业务 |
| 模型 / 模式 | 父会话显式创建参数 GPT-6.1 Sol / Standard；工具没有模型设置读回证明 |
| Compose | 默认关闭；此次未恢复 Flutter/Compose A/B |

在当前任务目录归档冻结提交，建立仅用于 ARMv7 构建的副本。副本只覆盖独立包名与显示名称，并复用旧测试签名。APK 的 ABI、SDK、证书、Leanback 入口及三个独立 provider authority 先核验，随后只执行一次 `adb install -r`。首次安装完成后，辅助脚本因 `Path` 的 JSON 序列化失败而未写完回执；通过只读查询版本与拉取实际已安装 APK 核对哈希恢复回执，未重复安装。测试包 UID、数据目录和首次安装时间保留，未卸载、清数据或降级。

## 本轮实际观察

| 流程 | 结果与证据 |
| --- | --- |
| 首页同排功能和分类 | 热门→收藏→热门、向右至悬疑再返回热门通过；[首页](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/home.png) |
| 最近观看与目录 | 原 `Fixture 1 · EP8`、`Fixture 12 · EP7` 最近观看记录仍显示；向下进入节目卡、左右移动通过。旧记录只证明显示保留，不证明电视上受控片播放成功 |
| 深层滚动与详情返回 | 滚至第 50 项→详情→Back 恢复同一作品；三条来源尝试后返回仍聚焦第 50 项；[最终返回](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/home-return.png) |
| 详情 UI | 封面、紧凑事实和动作区、折叠简介及五个原 Dart 业务 Tab 正常显示；[详情](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/detail.png) |
| 元数据搜索 | 输入 JOJO 后接口 HTTP 401，错误 UI 显示；明确重试一次后仍失败；[搜索错误](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/metadata-search-error.png) |
| 播放来源检索 | 从首页已有作品详情进入，原 17 条规则检索共返回 11 个结果；未换成 fixture 规则或编辑原规则；[来源列表](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/sources.png) |
| 来源遥控导航 | 方向键能滚动并展开来源；baimao 与 ezdmw 通过方向键和确认进入播放路由。部分标题排除子语义，XML 可能保留上一个结果的焦点标记；[可见 AGE 焦点](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/source-visible-focus.png)及实际展开结果用于交叉核对 |
| 失败后的返回 | Back 先收起选集栏，再回来源，关闭来源后回详情、首页；第 50 项作品身份保留 |

输入由 ADB 注入限定在当前独立测试应用的 DPAD 或点击。实体遥控器长按、人工听声和整屏画面确认未完成。

## 真实来源结果与边界

实际作品为首页第 50 项“飙马野郎 JOJO的奇妙冒险 第一赛段”。

| 来源 | 列表 | 视频地址交付 | 本轮观察 |
| --- | --- | --- | --- |
| 7sefun | 2 集 | 解析超时 | WebView 中有 SSL 握手失败；未观察到 Dart 播放器收到已解析 URL |
| baimao | 2 集 | 解析超时 | 网站 Artplayer 脚本报 `Unexpected token .`，随后 `Artplayer is not defined`。另有 about:blank 的 `_r_text` 重复声明，其对当前超时的影响未建立 |
| ezdmw | 1 集 | 解析超时 | 有 Chromium 媒体活动，但未向 Dart 播放器交付 URL；有限排查内未确定超时根因 |

[解析超时与选集界面](screenshots/flutter-tv-ui-fusion-xiaomi-20261002/source-resolution-timeout.png)。选集上的“正在播放”是当前选择状态的 UI 标签，不能当作首帧或实际播放证据。Chromium 解码器活动属于隐藏 WebView，也不能当作原 Dart/media-kit 播放器的 AV 验收。

当前电视选择 `VideoWebviewImpl` 的旧 WebView fallback 路径；未使用支持 document-start script 时的 `VideoWebviewAndroidImpl`。现有插件在提供 `shouldInterceptRequest` 回调时会设置对应开关，未因猜测开关缺失而修改源码。元数据搜索的 401 与播放规则检索成功分别记录，不能推断整个网络不可用。

三条来源尝试后结束本次有限解析排查，未增加同步 FFI、解码属性轮询或新诊断 build。没有证明当前底层解码失败，也没有证明全来源均不可播放。网站脚本错误与解析超时需要下一步可用路径或明确兼容范围才能补齐播放验收。

## 保护检查与交接

- 电视上 `com.predidit.kazumi.tv`、`com.znbsf.kazumi.tv`、`com.znbsf.kazumi.compose.tv` 的路径、版本、UID、数据目录、首次安装和最后更新时间与安装前完全相同；本轮未启动、覆盖、卸载或清理它们。未读取原应用的私有数据内容。
- 8 个原仓库/工作树的 HEAD、分支、NUL 分隔 Git 状态及脏文件哈希前后相同，包括原生 main 和旧 a5f7bab4 实验；原会话继续暂停，定时检查继续停用。
- 未执行连接/配对、其他设备输入或安装；未改系统网络、代理、功耗、安全设置或系统 WebView。最后成功 UI 观察 `40-final-home-after-source-failures` 为独立测试应用首页、第 50 项聚焦；05:45:16 UTC 再次确认测试包与三个原应用的安装状态。文档推送后进行最终只读核验时，原电视目标已在 ADB 中不可见，未重连、配对或再次启动应用；此后电视当前画面无法确认。
- 7 张代表截图及去除原始设备地址、私有命令和全量日志的 [证据清单](FLUTTER_TV_XIAOMI_UI_ACCEPTANCE_EVIDENCE.json)随当前实验分支保存。原始 XML、日志、安装回执、保护快照与实际已安装 APK 保留在任务根 `evidence/xiaomi-ui-fusion-20261002/`；私有目标记录不提交。
- 剩余额度读取接口未暴露，未使用额度重置卡；本轮没有收到明确的 ≤5% 剩余额度通知。

剩余播放验收需要一条在当前电视上可解析的来源路径，也需先恢复用户认可的既有电视连接。下一步可指定已知能播的来源、作品与集数，或由父会话/用户明确将旧 WebView 解析兼容列入后续范围。届时补首帧与进度、暂停/十秒快进退、成功播放时换集、返回续播及人工 AV 确认；保持原播放器和当前 UI。
