# Kazumi FlutterTV 本机Agent / Codex接手手册

2026-10-02 UTC：上一轮交付已完成，当前继续[固定背景与大卡片候选](FLUTTER_TV_FIXED_SURFACES_CANDIDATE.md)。候选已完成电脑回归，真机新安装被自动审批拒绝，须取得明确授权后继续；上一轮[最终报告](FLUTTER_TV_OPTIMIZATION_AND_PLAYBACK.md)仅是旧产品基线。动态实际HEAD/远端/运行状态看工作区根evidence/fusion-final-handover.json。本手册不依赖云端会话，不含秘密和私有聊天转录。

## 目标、来源和权限

成熟FlutterTV与已审查a5f7bab4为底座，吸收选择的上游增量，再融合实查的原生main新UI。首页同排双组导航、左右滑分类、向下虚拟滚动、原生柔化背景、深色绿焦点；详情/播放器保留Dart业务。规则、Hive、同步、历史、选集和原media-kit/libmpv是单一业务来源，不全面重写。Compose默认关闭，未恢复A/B或进一步页面改造。源版本、逐页/交互范围、旧实验复用见[融合矩阵](FLUTTER_TV_MAIN_UI_FUSION.md)，45项上游取舍见[索引](FLUTTER_TV_UPSTREAM_DISPOSITION.md)。

最初仅电脑/模拟器，后来用户明确授权同一已核验Xiaomi电视和独立测试应用验收、卡顿基线、局部优化及播放修复。该历史授权不自动授权下一接手者操作设备或账号；先核实当前请求、精确目标和运行所有权，只读可先完成。不改系统网络/代理/功耗/安全/证书/全局WebView，不猜地址/配对，不操作其他真机或原三个应用。原暂停会话和定时项目检查保持暂停。

父最初指定GPT-6.1 Sol / Standard，后因该模型容量失败明确把继续会话切换为Astra。没有内部模型/模式设置读回、剩余额度接口；未用重置卡。创建参数和父明确切换不冒称内部验证。

## 实际目录与版本

工作区C:/Users/hentai/Documents/Codex/2026-10-02/task；源码Kazumi；分支codex/flutter-tv-main-ui-fusion-20261002；origin https://github.com/znbsf/KazumiTV.git。原生main及旧8树只读保护，不reset/stash/清理/替换。

产品源码83752494b2888c3e0338584ef02a3d55b9b00e00；测量源码0fa262183a8da71ed247e22818778759f9f8a231，仅pubspec版本不同。实际安装2.3.1-tv-ui-fusion.3 / code203191，包com.znbsf.kazumi.flutterlab.test，ARMv7，同签名，probe=false/Compose=false。最终APK与实际安装哈希一致，SHA/签名/libmpv见最终报告。文档提交HEAD单独写本机回执，不冒充APK构建来源。

产品UI d3033a97、搜索/旧WebView修复24e341bb、缓存e498a5b3、日志传输0fa26218的阶段提交保留。旧[电视有限验收](FLUTTER_TV_XIAOMI_UI_ACCEPTANCE.md)是当时未获URL的历史记录，已由最终报告推进，不删失败样本。GitHub Actions此前该分支列表为空，现有workflow为PR/manual/release触发，没有CI通过声明。

| 路径 | 作用 |
|---|---|
| lib/pages/popular/ | TV首页、分类、最近观看、虚拟竖滚与焦点 |
| lib/bean/widget/tv_artwork.dart、tv_artwork_preparation.dart、tv_backdrop_overlay.dart | 背景驻留/淡入、异步预滤和静态渐变缓存 |
| lib/pages/info/、video/、player/ | 详情、解析及原播放器UI，业务不另建 |
| lib/request/clients/bangumi_client.dart、core/dio_factory.dart | 精确公开搜索和镜像路由 |
| lib/services/video_source/、lib/webview/video/ | 解析订阅/卸载屏障、WebView66 fallback与session |
| lib/services/performance/tv_performance_probe.dart | 默认关闭、有界诊断；诊断包F10切窗，F9仅兼容 |
| test/、test_support/ | 已复用回归、合成媒体与Node执行模型 |
| 根toolchain/ | 冻结Flutter/SDK/pub/Gradle缓存，不升级全局环境 |
| 根runtime/xiaomi-build/Kazumi | 构建副本，不能编辑为产品源码 |
| 根artifacts/、evidence/ | APK、截图、操作/测试证据；未全部进Git |

## 精确本机命令与复现

从工作区根PowerShell执行。冻结Flutter3.47.3 / Dart3.13.3，SDK e8113bf45620cbeb8aff64947ee4c93e16adb4cf，Java21、Gradle8.14.5、build-tools36.0.0；以toolchain/prepared.json核实。Flutter读取vswhere可能需沙箱批准，不能绕过拒绝。

~~~powershell
Set-Location 'C:\Users\hentai\Documents\Codex\2026-10-02\task'
git -C Kazumi status --short
git -C Kazumi branch --show-current
git -C Kazumi rev-parse HEAD
git -C Kazumi remote get-url origin
python -X utf8 run-fusion-check.py test --full
python -X utf8 run-fusion-check.py analyze
python -X utf8 run-fusion-check.py test --tests test/tv_artwork_transition_test.dart test/tv_artwork_preparation_test.dart test/tv_backdrop_overlay_test.dart
~~~

模拟器/fixture已停止并保留userdata，先核对进程所有权与端口。fixture是合成受控媒体，不代表实际公网源/声音通过。

~~~powershell
python -X utf8 start-fusion-emulator.py --start
python -X utf8 run-fusion-check.py product-build
python -X utf8 run-fusion-check.py fixture-build
python -X utf8 Kazumi/test_support/emulator_fixture_server.py runtime/assets/tracks-fixture.mp4 evidence/fusion-fixture-server
~~~

下面设备动作仅由当前已获授权并独占控制的持有者执行。helper从私有本机目标回执读取精确目标，公开文档不保存地址。identity/versions只读；start/key/安装均为设备动作。方向键必须DPAD前缀。

~~~powershell
python -X utf8 xiaomi-fusion-device.py identity
python -X utf8 xiaomi-fusion-device.py versions
python -X utf8 xiaomi-fusion-device.py start
python -X utf8 xiaomi-fusion-device.py key DPAD_DOWN
python -X utf8 xiaomi-fusion-observe.py NEW-UNIQUE-LABEL --shot --logs
~~~

实际最终构建命令和隔离overlay分别在根evidence/tv-optimization-20261002/final-build.json、final-source-preparation.json。入口build-tv-optimization.py会冻结Git archive、核对包/签名/ABI/原libmpv；pubspec20319经ABI生成code203191。stage final已完成，禁止直接重跑覆盖回执。后续新构建先添加未使用stage、真实已提交SHA、递增版本，再走install-tv-optimization.py门禁；失败安装可能实际成功，先读包状态/实际字节，不盲目重装。

性能流程在根evidence/tv-optimization-20261002/PROTOCOL.md。measure-tv-optimization.py的settled/rapid/vertical脚本需核对相同目录、最近观看与起止卡片1，区分首遍/暖缓存；误起卡片2样本不合格。只在窗口外截图/读日志；F10结束后报告最多18次、间隔2秒累计读取，不调系统logbuffer。最终正式包不能用于开启探针；有新测量需求才创建诊断包。固定脚本记录真实输入间隔；ADB命令耗时不能当UI延迟。

## 当前验证结论与剩余限制

完整639/639回归在渐变缓存源码e498a5b3通过；后续结束报告传输变更另13/13探针测试通过，analysis为0错误/0警告/32info；最终仅版本变更。旧580项为原UI历史阶段测试数。实际正式包关闭诊断，静态二进制和F10日志均验证。

五匹配场景raster p95改善32.34%–45.12%；大部分帧仍超60Hz预算，首横移188.874ms峰值保留。既有UI样式与像素回归通过。两个缓存各16MiB不等于总显存上限，活动/在途/淡出/Flutter缓存额外占用。

203131修复包完成第1/2集URL/实帧/暂停/恢复/seek/切集/退出/历史续播；正式203191再次完成真实第2集、暂停07:28/恢复07:34及退出返回焦点。人工声音/口型同步未确认，源授权未建立；公开元数据电视两次12秒超时，电脑200不可替代。Node模型也不等于WebView66实机，受控fixture不等于真实源合法音画验收。

八旧树HEAD/branch/NUL状态/脏文件SHA完全不变，三个原TV应用完整package_state相同；测试UID10074/数据/首装时间保留。没有clear/uninstall/downgrade。详见[最终摘要](FLUTTER_TV_OPTIMIZATION_AND_PLAYBACK_EVIDENCE.json)。

## 证据、教训与安全退出

细粒度根evidence/fusion-checks、home-perf-diagnosis、metadata-search-401、source-event-race、legacy-webview-playback、tv-optimization-20261002；截图/XML在xiaomi-ui-fusion-20261002。前后保护快照optimization-protection-before/final.json，摘要final-protection-comparison.json。原始日志可能含媒体token，只在本机按最小范围读，禁止复制Git/公开报告。密钥、设备目标、私密聊天无需读取。

先读旧实验融合过程与教训复盘-20261001.md及本轮来源索引；同步FFI诊断曾阻塞ANR，禁止再引入。仅直接阻断当前范围才有界检查解码，不重开31例深挖。图片clone不复制像素，ImageFiltered已有边界；不要把弱候选/无效窗口混成优化成功。GH007用已有公开noreply身份解决，未改用户隐私或全局Git配置；已发布提交不重写，旧amend/finalize脚本带HEAD断言不能复跑。

收尾无本轮运行中的构建、测试、采样和源码子任务，模拟器/fixture已停止、userdata保留；电视独立应用停首页卡片1、播放已退出。root最终交付后释放运行所有权。下次先读最新回执、锁和进程：fusion-check.lock是runner所有权，存活时不得删除；PID可能复用须核对来源，只停确认属于任务的进程，不按名称杀全部Java/adb/emulator，不断开其他ADB设备。设备不可见时不猜地址或配对，先完成无关设备的独立工作。

当前融合和实测优化已交付，不自动重开Compose A/B、页面重写、解码深挖或重复测量。电视搜索连接、人工声音/来源授权、帧预算/单峰值是三个单列限制，后续请求决定是否扩大范围。

## 技术、素材与许可

仓库根[LICENSE](../../LICENSE)为GPLv3。继承Kazumi/FlutterTV、media-kit/libmpv，第三方各自许可仍适用，以lockfile和二进制来源文档为准，不推断所有依赖均GPL。UI来自原生main源码/既有截图，未新加外部美术素材。真实封面和元数据为既有远程内容，不宣称再发布权。本机合成16秒色条/静音AAC fixture：evidence/fusion-fixture-server/fixture-media.json，SHA256 03783a50fa160a6dd47f5af0d40ce2a3a679796ad56c90cb9a9be3e568365b90。

## 可直接发给下一Agent的提示

> 在C46G接手Kazumi FlutterTV。先只读C:/Users/hentai/Documents/Codex/2026-10-02/task/START-HERE.md、本手册、FLUTTER_TV_OPTIMIZATION_AND_PLAYBACK.md和evidence/fusion-final-handover.json，再核实Git HEAD/status、锁与进程。当前已交付融合/播放修复/背景优化，产品源码83752494、独立包203191、probe/Compose默认关闭。不要重复已完成安装或覆盖旧证据。按实际新请求推进，保留原Dart业务/播放器、8旧树/3原TV应用；原会话/定时检查暂停。设备/账号写入授权不从手册继承，核实当前目标与权限，只读可先做。不读密钥、私有聊天或无关历史，不改系统设置。区分639全回归+13后续测试、技术画面闭环、人工声音/来源权利、电视元数据超时和未达60Hz的边界。新改动更新本机入口、真实SHA、制品、证据和退出状态。
