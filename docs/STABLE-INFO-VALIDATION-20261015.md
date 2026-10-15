# 稳定版 INFO 验证记录

状态更新（2026-10-15 16:24 UTC）：用户明确批准远端推送和草稿PR后，同一推送重试成功，已创建 [草稿 PR #13](https://github.com/znbsf/KazumiTV/pull/13)。下文审批阻塞为历史记录，已解除；CI待终态，未合并INFO或发布。没有重复本地构建或设备验收。

2026-10-15 UTC。PR #12 已正常合并到 main，merge SHA `286ab90d7f59279fdd01675002cad4b3eacf6b41`，未发布新版本。INFO 位于独立分支 `feat/stable-playback-info`，产品提交 `b3055c3d424738c9c1e319f422c318ca9de50245`。原纯文档 ed555894 保留，移植提交为 8ca653f4。

## 实现边界

播放器底部新增同风格 INFO 按钮，播放器焦点范围内 INFO/蓝键打开半透明小卡片。显示已有作品名、实际播放集标签、来源、可用海报；仅在相邻普通集编号连续且当前/下一编号均唯一时显示下一集。没有频道、EPG、排期或新节目元数据请求。图片缓存未命中仍可能请求已有 URL，沿用 NetworkImgLayer 的占位/错误处理。

DialogRoute 独立持有，只关闭自己的路由；帧内清理延后至帧结束。捕获调用处主题，默认焦点在返回按钮。Back/INFO/蓝键/返回按钮关闭，恢复原按钮或播放器焦点。开关只持有控制栏，不调用 pause/play/seek。旧设置中的播放诊断保留。

## 本地验证

- Flutter 3.47.3，revision e8113bf45620cbeb8aff64947ee4c93e16adb4cf。
- 全量 `flutter test --no-pub --concurrency=1`：877 项通过，含6项新测试。覆盖缺失/错配资料、歧义下一集、实际 presenter 重复打开、Back/INFO/蓝键/返回、焦点恢复、其他上层路由、帧内清理及明暗主题/640×360/1.5倍字体。
- `flutter analyze --no-pub --no-fatal-infos --fatal-warnings`：exit 0，0 error / 0 warning，58条原有info。
- ARMv7 release QA 构建成功，Gradle workers上限2、parallel=false；无并行本地构建或电源计划更改。pubspec.lock 未变。
- 包名 `com.znbsf.kazumi.fluttertv.stableqa`，版本 `0.4.2-info-qa.1`，versionCode 203271，29,167,539 bytes。
- APK SHA256 `bcf634a92f27fd0f5bba60caab059e2447f612d807066783fc9ef583def3b574`。
- 既有 QA 证书 SHA256 `24f6145444bd07c2db4d3d355692e4dae3dc02cd632a933a9e03a27b9e32aa31`。verify_tv_artifact 的包名/版本/ABI/TV入口/签名/probe absence校验通过。不是正式发布签名。

## Android 9 小米电视

设备 MiTV-ASTP0 / mulan / ARMv7。最初只读核对被自动审批拒绝；补充用户电视验收原始授权后，仅重试一次成功，后续QA安装/测试获准执行。只更新stableqa并保留数据，没有覆盖正式或preview。

- 安装核对为203271 / 0.4.2-info-qa.1。媒体音量由已读取的7暂设为0后测试。
- 从已有最近观看经遥控进入播放；从侧边选集区点击视频区域进入全屏，因此不标成全程纯遥控。
- 有界H.264采样实际读图：标题、02、来源、海报、下一集03正确，浅色主题和半透明表面有效。海报是作品海报，不是剧集截图。采样不等于持续视频观看。
- 播放中开卡及Back后均为PLAYING，位置228165→229166ms，画面/时间有推进。
- 暂停开卡与OK返回均为PAUSED、257403ms。暂停命令后立即采样曾仍见旧PLAYING状态，未把它当稳定暂停基线。
- 控制栏自动隐藏时右键属于快进，导航尝试曾前进40秒；随后按完整下/右序列重建按钮焦点，没有将这次变化归于INFO。稳定基线297401ms：底部INFO按钮OK打开、Back后准确回到INFO按钮，前后PAUSED/297401ms相同。
- 连续INFO开关、Back、蓝键打开及OK返回后仍为PAUSED/297401ms，无残留卡片。文本子节点focused=false时，同边界按钮父节点focused=true，不能误判焦点丢失。
- 正常Back退出后会话inactive/NONE、position0；随后仅停止QA包，恢复音量7并核对原厂桌面。采集自然结束，screenrecord无残留。未重启设备或修改HOME/权限/网络/安全设置。

## 未覆盖及交付状态

实机仅覆盖此Android 9设备、浅色主题与当前已有源；明暗主题、大字、异常资料由widget/数据测试覆盖。未做真实物理遥控器、其他厂商/Android、实机断网海报错误或合法认证弹幕集成验收。全屏外选集区焦点时，播放器快捷键按原范围隔离，不被INFO抢占。

`git push -u origin feat/stable-playback-info` 被自动审批拒绝，命令未执行：可信用户文本尚未明确授权本次远端推送或创建PR。未换途径推送，未创建INFO PR，没有INFO远端CI结果。需要明确授权推送该分支并创建草稿PR；不包含合并INFO或发布。PR #12已合并不受此阻塞影响。

原始日志、APK回执、UI XML、采样帧和媒体状态保留在任务私有 `qa-20261015`，不提交设备地址、用户路径、原始系统日志或媒体画面。入口为[项目状态](PROJECT-STATUS.md)，取舍见[INFO方案](STABLE-INFO-PLAN.md)。
