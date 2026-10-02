# Kazumi FlutterTV 本机 Agent / Codex 接手手册

更新时间：2026-10-02 UTC。**当前任务仍在实施，root 持有代码/Git/构建/设备控制权；接手前必须协调所有权。** 本手册不依赖云端会话，不包含秘密或私有聊天转录。最新动态状态以本机 `../../..` 的 `evidence/fusion-final-handover.json`、实际 Git 和设备检查为准。

## 目标与已确认取舍

以成熟 FlutterTV 和已审查 `a5f7bab4` 为业务底座，吸收已选择的上游增量，再迁原生 main 新 UI。首页沿用实查布局：同排双组导航、左右滑动分类、向下虚拟滚动、原生柔化背景、深色绿焦点；详情和播放器复用原 Dart 业务。Dart 规则/Hive/同步/历史/选集/原 media-kit/libmpv 是单一来源，不全面重写。Compose 默认关闭，未恢复 A/B 或进一步页面改造。

最初只允许电脑/模拟器；后来用户明确授权同一已核验 Xiaomi 电视和独立测试应用验收，以及卡顿基线、局部优化和播放修复。**后来授权只适用于本轮指定目标；下一接手者不能自动继承。** 不改系统网络代理、电源、安全、证书或全局 WebView，不配对或猜测设备，不操作其他真机。旧暂停会话及定时项目检查保持暂停。父提供 GPT-6.1 Sol / Standard 参数；没有内部模型设置读回或剩余额度接口，未使用重置卡。

## 目录、版本与架构

工作区根：`C:/Users/hentai/Documents/Codex/2026-10-02/task`；独立 Git worktree：`Kazumi`；分支：`codex/flutter-tv-main-ui-fusion-20261002`；origin：`https://github.com/znbsf/KazumiTV.git`。

已推送阶段：产品 UI `d3033a972f696a891bb39d33a365d5981200c197`，电视有限验收文档 `3045e580971af5d2c9a77ccb694aa106937884a0`，连接中断说明 `67c08c980d5e884e34f3d272962df98c04b5772b`，公开搜索与旧WebView修复 `24e341bb503ec71522a82dc07cf1e8ffa292da7a`，默认关闭的探针与失败背景边界候选 `0aa7075a4f7fd09e55ba12b114f54374dd3ab6d3`。本次记录时 HEAD/远端均为最后一项，已只读核验；新异步背景候选正在工作区实现，不能把旧 SHA 当作新包源码。GitHub Actions此前该分支返回空列表，现有workflow使用PR/manual/release触发，无CI通过声明。推送和CI动态状态必须再读取实际回执。

| 路径 | 用途 |
|---|---|
| `lib/pages/popular/`, `lib/bean/widget/tv_artwork.dart` | TV 首页、目录虚拟滚动、背景、焦点 |
| `lib/pages/info/`, `lib/pages/video/` | 原详情与播放器 UI；业务和解码不另建一套 |
| `lib/request/clients/bangumi_client.dart`, `lib/request/core/dio_factory.dart` | 元数据公开搜索、镜像路由 |
| `lib/services/video_source/`, `lib/webview/video/` | 解析任务串行、当前请求、旧 WebView fallback、URL 交接 |
| `lib/services/performance/tv_performance_probe.dart` | 默认关闭的有界 release 帧/输入采样；F10切换开始/结束，F9保留兼容，仅诊断包 |
| `test/`, `test_support/` | 已复用回归、受控合法 fixture 和 Node JS 执行模型 |
| 根 `toolchain/` | 冻结 Flutter/SDK/pub/Gradle 缓存；不升级或改全局工具链 |
| 根 `runtime/xiaomi-build/Kazumi` | 构建副本，不能当作编辑源码或新 worktree |
| 根 `artifacts/`, `evidence/` | APK 与本轮原始证据；大文件未全部进 Git |

源版本及逐页矩阵见 [融合报告](FLUTTER_TV_MAIN_UI_FUSION.md)；45项上游取舍见 [上游索引](FLUTTER_TV_UPSTREAM_DISPOSITION.md)。原生 main 和旧八个工作树仅只读参考，有既有脏文件，禁止 reset/stash/清理/替换。

## 精确本机命令

以下命令从工作区根 PowerShell 执行。工具版本：Flutter 3.47.3 / Dart 3.13.3，SDK frozen revision `e8113bf45620cbeb8aff64947ee4c93e16adb4cf`，Java21，Gradle8.14.5，Android build-tools36.0.0；以 `toolchain/prepared.json` 和实际版本再核实。Python helper 使用当前本机 Python。测试可能因 Flutter 只读访问 Visual Studio 的 vswhere 需要沙箱批准；不得用拒绝绕过权限。

```powershell
Set-Location 'C:\Users\hentai\Documents\Codex\2026-10-02\task'
git -C Kazumi status --short
git -C Kazumi branch --show-current
git -C Kazumi rev-parse HEAD
git -C Kazumi remote get-url origin
python -X utf8 run-fusion-check.py test --full
python -X utf8 run-fusion-check.py analyze
python -X utf8 run-fusion-check.py test --tests test/tv_artwork_transition_test.dart test/tv_home_desktop_test.dart test/tv_popular_scroll_test.dart
```

新模拟器和 fixture 当前已停止，保留 userdata。只有确认本轮进程所有权/端口后再启动；fixture 是受控媒体，不代表公网真实源或物理声音通过。

```powershell
python -X utf8 start-fusion-emulator.py --start
python -X utf8 run-fusion-check.py product-build
python -X utf8 run-fusion-check.py fixture-build
python -X utf8 Kazumi/test_support/emulator_fixture_server.py runtime/assets/tracks-fixture.mp4 evidence/fusion-fixture-server
```

**下面电视命令只供已重新确认目标和权限的控制者运行。** helper 从本地私有目标回执取精确 serial，不在公开手册保存它。`identity`、`versions` 为只读；`start`/`key`、安装更新属于设备动作。

```powershell
python -X utf8 xiaomi-fusion-device.py identity
python -X utf8 xiaomi-fusion-device.py versions
python -X utf8 xiaomi-fusion-device.py start
python -X utf8 xiaomi-fusion-observe.py NEW-UNIQUE-LABEL --shot --logs
```

冻结基线构建只取旧 UI 提交，覆盖已验证的 main/probe 两个文件；**不要用这个命令构建修复后的最终包**。阶段安装回执/测量文件禁止覆盖，不能盲目重复已完成安装。最终/优化阶段需要真实已提交 SHA 和递增版本号，构建脚本会校验旧签名、独立包、ARMv7、原 libmpv 字节及安装门禁。

```powershell
python -X utf8 build-tv-optimization.py baseline-chunks --commit 67c08c980d5e884e34f3d272962df98c04b5772b --version 2.3.1-tv-ui-perf-baseline.4+20312 --probe-overlay
python -X utf8 install-tv-optimization.py baseline-chunks
python -X utf8 measure-tv-optimization.py baseline-chunks settled --label BASELINE-UNIQUE-LABEL
```

性能复现从首页相同分类/作品位置开始，另测 rapid/vertical，先确认前后作品身份和缓存状态。完整步骤、指标边界在根 `evidence/tv-optimization-20261002/PROTOCOL.md`。程序内 Stopwatch 与 FrameTiming 是实际指标，ADB命令耗时不能用作 UI 响应时间。

## 已验证与尚未验证

- 已交付 UI：模拟器 580/580 回归、页面/播放器受控媒体验收；实电视首页/分类/最近观看/详情/向下50号作品/返回焦点通过。原始截图和逐操作回执在根 `evidence/xiaomi-ui-fusion-20261002`，摘要见 [实电视有限验收](FLUTTER_TV_XIAOMI_UI_ACCEPTANCE.md)。
- 第一电视包 `2.3.1-tv-ui-fusion.1` code203081，ARMv7 APK SHA256 `23377cd84215bd8fa0ab527204ea9579d66ec77c4c82a6a7b0fca25678899d40`，实际安装字节匹配，独立包 UID10074及数据/首装时间保留，原三个应用均未改。
- 旧三个真实源进入播放器路由后都在 URL 交接前失败，不能宣称首帧/音画/播放闭环通过。搜索镜像401是构建未含私有镜像凭据的公开请求路由问题；同一匿名请求在电脑官方API200。新代码仅对无凭据的公开搜索精确端点走官方，保留TLS/可选Bearer/所有其他路由，不搜索凭据。
- 新 early-event 订阅、WebView幂等脚本/当前页面session、iframe显式媒体URL和签名字节修复有局部回归；当前源加单变量背景缓存候选完整624/624通过，静态分析0错误/0警告。Node的小DOM模型不等于WebView66，电脑接口200不等于电视搜索或播放通过。
- 后续异步竖图预滤已本机冻结，完整632/632回归通过（`test-20261002T082411090649Z.json`）；非纯色像素与原ImageFiltered/cover在DPR1/2比较通过，保持260ms驻留、600ms交叉淡入、720px源解码、sigma16、.84透明度和原双渐变。只保留一个准备任务和最新待处理选择，缓存限2项/16MiB；该上限不包含仍由淡出/在途任务持有的资源，不能宣称总显存峰值16MiB。超尺寸或准备异常保留原渲染效果。新的电视对照还未执行。
- 修复包203131已在电视将公开搜索精确路由改至官方HTTPS，但两次连接均12秒超时，结果验收未通过；不改网络/代理。原17规则检索返回10结果。baimao已实际交付第1/2集URL并渲染画面，暂停/恢复/时间推进及seek已观察；退出续播、最终包回归与人工听声仍待完成。这是实际技术观察，来源授权/再发布权不因此得到证明。
- 电视连接曾消失；本轮用同一已记录连接恢复并再次核验身份/原包。初始化/监听正常、方向键及F10到达、F9未到Flutter；不推断具体系统拦截原因。诊断日志实测每条1023字节截断，已将完整分片限制900字节。前三基线失败样本保留。203121原UI基线五个窗口完整：首遍settled raster p95 74.735ms，warm 74.973ms，rapid 283.869ms，vertical首遍/暖89.684/89.855ms；build较快，背景合成需优先归因。203131边界候选首遍/暖仅73.811/73.616ms，暖改善1.81%，**未接受为有效优化**。SDK ImageFiltered自身已有重绘边界。相同203131包临时应用内OLED=true后，settled raster p95 36.495ms；10键、焦点1→1、采样边界全0。该开关同时移除图和双渐变，只能归因整个背景合成；已恢复原false（截图52），系统设置未改。异步竖图预滤候选与实际播放验收仍在实施。

原始证据入口：`evidence/fusion-checks`、`evidence/home-perf-diagnosis`、`evidence/metadata-search-401`、`evidence/source-event-race`、`evidence/legacy-webview-playback`、`evidence/tv-optimization-20261002`。以真实存在的文件和时间戳为准；某些诊断路径在最终交付时更新。保护快照 `evidence/optimization-protection-before.json` 和 `capture_protection.py` 对八原树记录 HEAD、NUL状态及脏文件哈希。

## 已知教训、运行任务与恢复

先读旧实验 `融合过程与教训复盘-20261001.md` 及本轮来源索引。同步FFI诊断曾阻塞导致ANR，禁止重新引入；没有数据不要误称卡顿主因。底层解码只在直接阻断当前验收时有界排查，不重开31例深挖。图片clone不是像素复制，Sliver已有虚拟化/边界；背景改动必须基线归因后同场景比较。

Git推送曾因GH007邮箱隐私拒绝，已用先前成功提交的公开noreply身份处理，未改用户隐私或全局Git配置。已发布提交不重写；接手不要重新运行带旧HEAD断言的amend/finalize脚本。设备序列/命令回执、签名密钥、URL可能含token的原始日志仅本机私有保留，不复制进Git/公开报告。

当前运行权：root 独占 TV、构建副本、Git。源码子agent按文件划分，交付冻结后 root 合并；接手者先检查进程/锁/实际dirty状态，避免同时修改。`fusion-check.lock` 是测试runner所有权，不得在进程存活时删除。构建日志的PID只属于该runner；安全退出只停止确认属于本任务的子进程，不按名称杀所有Java/adb/emulator。own TV应用可在确认权限后 `xiaomi-fusion-device.py stop`；不clear/uninstall，不断开其他ADB设备。模拟器/fixture按根runtime/evidence保存的PID核实所有权后停止，保留userdata。

恢复：先只读确认连接、身份、已安装version/code、安装回执和实际APK；失败安装可能已经成功，不能直接重装。没有目标可见不猜地址/配对。需要恢复网络或设备授权时向用户/父说明事实；先完成无关设备的独立代码与文档工作。

## 未完成与优先下一步

1. 获取冻结 release 首页同数据基线，区分raster/build/input反馈；据此最小优化并同场景复测。
2. 在相同电视验证公开搜索、原目录/详情、WebView URL 交接，完成一个可用合法实际源的首帧/暂停/seek/切集/退出/恢复。受控样本另列播放器层。
3. 构建默认关闭诊断的正式同签名ARMv7包，保留数据更新独立测试应用；核对原3包/8树、视觉与焦点回归。
4. 更新手册、SHA/制品/证据/运行状态和精确失败层级；阶段提交推送实验分支，核实remote与实际CI，无用户决策阻塞不停止。

## 技术/资产来源与许可

项目仓库根 [LICENSE](../../LICENSE) 为GPLv3。继承 Kazumi/FlutterTV、media-kit/libmpv 和已列版本；第三方各自许可仍适用，以lockfile、平台二进制来源和既有文档为准，不从项目GPL推断所有依赖许可。UI来自只读原生main源码和已有截图，未新增外部图片素材；真实封面/元数据为既有远程业务内容，不宣称拥有再发布权。受控fixture是本机合成样本（根 `evidence/fusion-fixture-server/fixture-media.json`，SHA256 `03783a50fa160a6dd47f5af0d40ce2a3a679796ad56c90cb9a9be3e568365b90`）；不把真实源可访问当作合法性证明。

## 可直接发给下一 Agent / 本地 Codex 的提示

> 在C46G继续Kazumi FlutterTV融合与当前性能/播放收尾。先只读核实 `C:/Users/hentai/Documents/Codex/2026-10-02/task/START-HERE.md`、项目 `static/doc/FLUTTER_TV_AGENT_HANDOVER.md`、`evidence/fusion-final-handover.json`、Git HEAD/status、锁和进程。原root仍可能持有设备/构建/Git，先协调唯一所有者；不要并发改同文件或操作同一设备。以实际本机源码/证据为准，保留原Dart业务和播放器，Compose默认关闭，保护旧8树和原3TV应用。历史授权不自动继承，请先重新确认当前设备/安装/账号写入权限及目标；只读检查可先完成。不要读取密钥、私有原始聊天或无关历史，不改系统设置。不把电脑200、Node模型、受控fixture或播放器路由进入当作真实源播放PASS。按手册优先项持续完成，更新本机可接手文档和真实SHA/制品/证据。
