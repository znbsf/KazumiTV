# 已有工具及验证边界

当前回滚与设备研究边界见[桌面/ADB状态](../../../../docs/TV-DESKTOP-ADB-STATUS.md)，稳定验收边界见[发布准备](../../../../docs/ISSUE11-RELEASE-READINESS.md)。下文为分阶段观察，不能把早期故障当当前状态或恢复历史授权。换源取消对照前后暂停/位置/焦点；受控超时取消重试不替代实机自然超时。

本轮复用了任务环境已有的 `adb-lowres-prototype` 引擎（`capture.py` 和 `latest_frame.py`）。使用前从当前任务的工具记录定位目录并读其 README，再通过 `--tool-root` 传入；本仓库不捆绑该外部引擎。使用环境已有 Python、adb 与 FFmpeg，工具位置不构成设备操作授权。

```powershell
python scripts/observe.py --tool-root <已有工具目录> --serial <本次设备> --model <实测型号> --device <实测device> --package <授权包名> --out <工作区证据目录> --seconds 15
```

启动自动取首帧；采集期间在输出目录创建 `REQUEST`，确认 `latest.json` 的 `received_unix` 更新后读 `latest.jpg`。创建 `STOP` 后等进程终态，并核对 owned recorder 消失。15 秒到时自动停止。引擎编码目标 960×540/500 kbps、内存上限 2 MB、FFmpeg 单线程；没有设备端帧率保证。

旧证据仅验证 API36 模拟器：连续 H.264 在运行中两次按需取帧成功；scrcpy 限时 MKV 可录制但文件缓冲使其不能直接 tail 为实时画面。Android 9 的编码器、raw screenrecord 和 Flutter 树完整性须真机逐项验证，不沿用模拟器结论。

2026-10-15 本轮 Android 9 实机：独立包安装成功，但休眠时及报告 Awake/ON 后均无窗口焦点；wrapper 实际执行并按前台保护拒绝，未启动 recorder。uiautomator 多次返回 null root；高清 screencap 实际为黑帧。这不能证明 Flutter semantics 本身缺失，也不能称为连续捕获成功。KEYCODE_WAKEUP 未解除该机休眠；确认 Asleep 后单次 POWER 得到 Awake/ON，但没有有效画面。随后 window 服务不可用、ADB offline，再连接被拒绝；未发送重启命令。系统恢复前不继续按键或改 HOME，不能通过放宽前台保护掩盖不可观测状态。

wrapper `--help` 已运行，frontmatter、相对链接和脚本语法已检查。初次 quick_validate 因缺PyYAML未运行；后续获准后在任务隔离venv从官方PyPI安装PyYAML 6.0.3，以UTF-8模式执行原验证器得到 `Skill is valid!`。成功采集见下节，早期拒绝路径不再代表当前结论。

## 同日恢复后的成功验证

用户打开ADB后，系统桌面与控件树恢复。小米桌面15秒采集首帧1.37秒、960×540、47KB，模型实际读图；修正QA包使用约定页面首帧0.82秒，REQUEST后5.91秒得到第二帧，两次 `capture_running=true`，模型读图与XML的“同意并继续”焦点相符。静态页两次同图，不能推出动态延迟或严格帧率。15秒自动退出后 `pidof screenrecord` 为空。原始指标在任务证据 `tv/stream-home/`、`tv/stream-qa2/`。

本机一次PNG截图为0字节，pull成功不代表图片有效；检查文件长度并实际解码。小米设置浮层存在文本但子节点focused均false，应结合画面和祖先节点，不盲用文本节点判断焦点；`am start -W` 对该浮层等待未及时返回，普通启动后读窗口及树有效。

独立工作树首次直接 `build --no-pub` 缺少 GeneratedPluginRegistrant；单独pub get后再 `--no-pub` 又误注册仅dev使用的splash插件。按现有CI `flutter build ... --pub` 重新生成release插件后构建、同证书递增升级成功，应用正常到首屏。不要把这种本地无效产物的黑屏作为业务回归；先核对注册文件/日志。此经验不要求每次重建或手改生成代码。

首屏条款确认初次被自动审批拒绝后停止；核对条款与稳定版及两份APK一致，收到用户明确同意后重试一次成功。随后完成API9导入、详情至源搜索与播放、换源取消保持26714ms、再换源继续26秒、第二集加载取消重试、分类保留滚动与硬件解码器嵌套返回。参见 [真机验收](../../../../docs/ISSUE11-TV-QA-20261015.md)；混合遥控/坐标输入，不扩大为纯遥控或全部兼容性通过。

## 纯遥控复测经验

搜狗电视键盘的按键布局在画面中可见，但uiautomator没有键盘节点。实际用方向键/OK拼出fate，并用Back隐藏键盘；不能用 `input text` 代替后声称全程纯遥控。

播放器控制栏会自动隐藏。间隔数秒再按上，可能只是重新显示并聚焦选集；不能把它误判为进度条导航失败。先确认控制栏可见，短间隔显控→进度条→左右操作；本轮观察到进度增加10000ms、随后减少10000ms。精确时钟和音画同步仍需独立证据。

页面持续显示0/0或MediaSession标成PLAYING不能单独证明实际视频在播放；结合有效画面、稳定时长、位置推进及缓冲状态。加载取消必须看到明确提示；本轮纯遥控切集后几次按键错过解析阶段，不计取消通过。
