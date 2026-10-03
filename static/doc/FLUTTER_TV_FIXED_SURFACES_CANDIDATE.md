# 固定主题背景与五列大卡片交付

2026-10-02 UTC。产品源码e06979114d6d0d5447684faef2532a8b70e3b1a5；独立实验分支codex/flutter-tv-main-ui-fusion-20261002。原生main和8个旧工作树未改动。用户在本会话直接确认后，电视、Library和指定GitHub分支的写入已实际完成；此前审批拒绝只是历史记录。

界面按用户最新方向采用原生main的#101611固定主题背景，OLED偏好仍为黑色。首页宽屏六列改五列，行距16→12、列距12→8、卡片高度从可用空间1/2改1/1.65，保留下一行提示。卡片用细边和浅白透明层；无新增BackdropFilter。TV shell不挂载全窗动态背景，不再准备背景图片或运行600ms全窗淡入。普通封面、140ms焦点缩放、焦点边框与阴影、原Cupertino/Hero和180ms封面交接保留，不能说全无动画或阴影。Dart业务、规则/Hive/历史/选集、原media-kit/libmpv不重写，Compose默认关闭。

## 实际制品与保护

最终已安装独立包com.znbsf.kazumi.flutterlab.test，ARMv7、2.3.1-tv-fixed-surfaces.3 / code203231；探针关闭，Compose关闭。APK为工作区artifacts/Kazumi-FlutterTV-cover-final-Xiaomi-isolated-armeabi-v7a.apk，SHA256 1f7709ec73c622a81969a4f89816f43210b838c9a460f0e11e72e1c68c7e48fe。已回拉实际安装字节核验。测试UID10074、数据目录、首次安装时间保留，原三个应用完整package_state不变，没有clear/uninstall/downgrade或系统网络/代理/功耗修改。

同机基准203201（9862ce33加探针字段）→固定背景诊断203211（2d4126fa）→探针关闭隔离验收203231均递增安装，回执在evidence/tv-optimization-20261002/resource-*-installation.json和cover-final-installation.json。基准与候选探针的SHA差已通过内存复原旧哈希证明仅一处dart format换行；测量行为相同。旧203191制品仍保留，不执行降级。文档HEAD与远端回执单列，不冒充APK构建来源。

## 验证与测量

完整640/640测试通过，analyze为0错误、0警告、32项已有info。五列缺列、120项长目录、追加分页、作品身份/视口返回锚点和进入/返回中途实际像素遮挡均有回归。模拟器受控样本完成首页/详情/返回检查；15秒屏录请求产生85个编码帧，最后PTS9.566秒，不能冒充完整15秒连续扫描。

下表是同一电视、目录和原生按键脚本的有限窗口。CPU为有效粗粒度区间占四核容量，包含静止间隙；PSS是片后端点，包含报告/观察开销。五列布局本身改变可见内容与绘制工作量，不能解释成严格同像素渲染微基准。

| 场景 | 产生帧数（旧→新） | raster p95 ms（旧→新） | 进程CPU/四核容量（旧→新） | 片后PSS（旧→新） |
|---|---:|---:|---:|---:|
| 首页横向持键 | 91 → 48 | 42.472 → 44.462 | 10.15% → 5.54% | 128.9 → 100.7 MiB |
| 详情进入/返回（暖） | 199 → 144 | 39.369 → 36.520 | 10.49% → 8.53% | 130.1 → 101.7 MiB |

减少持续背景绘制工作有实测依据；跨版本PSS有缓存/进程年龄混杂，不能声称确定节省约29MiB，但横向单帧p95没有改善，多数运动帧仍超16.67ms，不能宣布卡顿解决或稳定60fps。详情首次缓存准备仍出现253.365ms峰值，该原始窗口保留；暖窗不能掩盖首遍。横向原生down/repeat/up、6次重复、Dart 8次输入及返回节目1均已记录；Dart探针不记录keyup；原生UP只证明注入，不证明app收到释放。松键后的焦点/滚动稳定和真实遥控器硬件仍未验证。纵向旧窗回到“设置”，不满足同焦点对照而排除，不计为通过。

最初2Hz采样同时读取频率的组跨度360–400ms，资源关联被拒绝。收窄版只读进程/最多8线程/proc，先在设备内存缓冲再输出，窗口前后Java墙钟/elapsedRealtime锚定，保留10ms uptime量化与边界余量。有效CPU桶和覆盖率见证据JSON；不把ADB往返、日志抵达或框架post-frame当显示延迟。片内不截图、不dump XML、不读meminfo、不录屏。GPU/温度不可读，GC事件未采；不能因CPU低反推GPU瓶颈。PSS端点不能证明泄漏。同步FFI诊断旧ANR教训仍约束全部诊断。

电视连续转场录像fixed-TV-detail-continuity.mp4单独采集，源版本与实际编码帧PTS在旁边回执。屏录有观测开销，不用于帧性能或面板扫描撕裂判断。原旧页透入详情内容区域的修复由不透明Scaffold及像素回归支持；封面交接的视觉结论见本机accelerated-transition-review.md。

最终probe-off包的真实播放/暂停/恢复/退出和焦点回归见[证据摘要](FLUTTER_TV_FIXED_SURFACES_EVIDENCE.json)中的playback，仅报告实际观测。人工声音/口型同步、来源再发布权未确认；已有电视元数据超时另列，不把电脑请求成功代替电视结果。

## 图像与交接

两张Library图明确是模拟器受控样本，不是真电视实拍：

- 01-fixed-theme-home-EMULATOR-CONTROLLED-SAMPLE.png（已保存至用户Library；私有链接只保存在本机交付回执）
- 02-fixed-theme-detail-EMULATOR-CONTROLLED-SAMPLE.png（已保存至用户Library；私有链接只保存在本机交付回执）

真实电视截图和原始日志保留本机evidence/xiaomi-ui-fusion-20261002，含媒体URL的日志不进Git。独立测量明细/无效窗/时钟与探针证明位于evidence/tv-resource-20261002；GitHub仅发布源码、测试及去私密文档。公开分支的实际HEAD、推送结果、运行终态以本机evidence/fusion-final-handover.json为准；Actions列表为空不是CI通过。

本轮自己的模拟器与fixture已停，userdata保留，构建/采样已结束；正式包留首页，播放已退出。旧会话和定时检查继续暂停。不操作重置卡，不改模型/快速模式；模型创建/切换参数来自父明确指令，不声称内部设置读回。


## 封面交接的最终局部修正

203211电视录像两次显示封面局部亮度短暂下降约17%–20%，其他内容不变。最终e0697911仅在TV专用图片AnimatedSwitcher保持旧封面不透明，直到新图180ms淡入完成，保留Hero、时长和图片生命周期。实际像素中点回归及最新640项完整回归通过。上表性能来自修正之前的2d4126fa/203211，未把该数据归给后续包。203231新录像第二次进入的封面灰度均值196.142/196.100/196.100，未重现旧低谷；两次进退遮挡正常。首进存在206ms编码间隔，仅确认已记录帧，不能声称逐帧穷尽。回执在transition-review-cover-final-tv/review.md。

这里的release是Flutter构建模式，不是公开Release或既有主应用升级包。当前隔离ID、实验签名和版本不能直接代表正式发布身份。远端main仍为原生工程；主线切换、正式应用ID/签名与数据迁移、TV发布流水线及README尚未执行。

暖详情build p95从25.350升至35.228ms（约39%），与raster改善同时列出；首横移292.141ms峰保留。独立输入审计11窗为10项INCOMPLETE、1项FAIL，完整矩阵未通过；只对明确的横向受控repeat接收/最终锚点作有限确认。
