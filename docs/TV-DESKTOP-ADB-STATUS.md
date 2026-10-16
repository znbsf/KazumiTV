# 电视桌面与ADB调查状态

2026-10-15只读复核。适用边界为本轮Android9/ARMv7电视，不能泛化所有固件。本页只保留可公开结论，不包含设备地址、序列号、个人目录、原始系统日志或用户服务列表。最后回滚状态来自已完成的实测，本次文档整理没有重新操作设备。

| 目标 | 已有证据 | 下一步判断 |
|---|---|---|
| 普通桌面入口 | LTvLauncher手动打开、启动应用及Back返回成功；输入源面板可见，未实际切源 | 保留原小米HOME，通过普通应用入口使用LTv，当前已有可用路径 |
| 开机自动进入LTv | 固定版本BootReceiver只处理BOOT_COMPLETED，读取默认false的start_on_boot；没有依赖无障碍开关的代码 | 有独立验证价值；当前不开开关、不重启。以后用户在场且可恢复时单独验收，不等同待机唤醒 |
| HOME接管 | 原生默认桌面路线未通过；LTv服务实际绑定后ADB HOME仍回小米，未证实先到LTv再被抢回 | 无新证据支持重复失败实验；真实硬件HOME未测，也不能把ADB失败泛化为所有遥控失败 |
| ADB持续可用 | 持久端口配置存在；历史HOME路径发生system_server崩溃及框架重启，缺事故时adbd停止/属性切换日志 | 端口持久化不能保证服务存活；根因未定，不重复写端口、关闭认证、改init或安装守护来掩盖问题 |

## 已完成回滚

LTv安装保留，Home Button Fix已通过系统UI关闭，开机启动未启用；临时启用的Android TV设置包恢复disabled-user，原无障碍服务语义列表及小米HOME保留。系统与ADB进程在后续验收中保持稳定。独立播放器QA已正常退出并停止，临时音量已恢复。没有留下本轮新增的默认桌面或权限改动。此状态不等于今后永不掉线。

## 可复用证据与来源

- [LTv v2026.10.03 BootReceiver](https://github.com/leanbitlab-org/LtvLauncher/blob/v2026.10.03/android/app/src/main/java/com/leanbitlab/ltvL/BootReceiver.java)：仅开机广播触发，不处理SCREEN_ON/USER_PRESENT。源码对Android10+限制的注释不能直接当成本机Android9实测。
- [AOSP Android9 WindowContainer](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-9.0.0_r1/services/core/java/com/android/server/wm/WindowContainer.java#L396)：positionChildAt发现父容器不一致即抛IllegalArgumentException，与现有崩溃类型吻合。支持框架任务栈定位，不证明竞态来源或换桌面即可修复；小米修改实现仍有未知。
- [AOSP Android9 USB init规则](https://github.com/aosp-mirror/platform_system_core/blob/android-9.0.0_r1/rootdir/init.usb.configfs.rc)：config=none/configfs=1可停止adbd，config=adb可启动；这是存在的控制机制，缺事故时对应记录，不能写成已证实断连原因。
- [Android无障碍过滤文档](https://developer.android.com/reference/android/accessibilityservice/AccessibilityServiceInfo#FLAG_REQUEST_FILTER_KEY_EVENTS)与[AOSP Android9输入过滤](https://github.com/aosp-mirror/platform_frameworks_base/blob/android-9.0.0_r1/services/accessibility/java/com/android/server/accessibility/AccessibilityInputFilter.java)：服务能力、请求标志、策略及输入状态均有影响，enabled/bound不能证明每个HOME已送达；不能仅据两个服务同在就断言冲突。
- [Projectivy官方仓库](https://github.com/spocky/miproja1)是配置及问题跟踪，不能当完整源码审计。本轮同型号检索未找到可直接复用的HOME/ADB成功方案；未命中不是不存在的证明。[MiTV 4S #35](https://github.com/spocky/miproja1/issues/35)需Launcher Manager配合应用内默认设置，不是相同固件证据。[Android9 #86](https://github.com/spocky/miproja1/issues/86)是维护者明确在4.53修复的历史黑屏案例，不能指称最新版仍有该故障。[小米另一型号 #537](https://github.com/spocky/miproja1/issues/537)是按键重映射影响手柄的用户报告，未在本机复现。
- [ADB官方文档](https://developer.android.com/tools/adb)区分主机server和设备adbd。通用kill-server建议不适用于本任务共享ADB约束，未执行。

## 后续只读排查规则

自然断连时记录时间、连接状态及TCP连通性；恢复后读取有界crash/events、进程身份、uptime和现有相关属性，区分网络、端口拒绝、授权、adbd及框架重启。无新证据不复现HOME崩溃、不重启或更改安全设置。任何今后的硬件/开机试验均重新核对现场恢复条件与当前授权，不从本页恢复旧授权。

当前不安装替代桌面、不授予新无障碍、不冻结原桌面、不使用工程菜单。桌面和ADB结论与[稳定发布准备](ISSUE11-RELEASE-READINESS.md)分开，相关验收方法统一走[工程经验](ENGINEERING-LESSONS.md)与[TV QA技能](../.agents/skills/android-tv-ui-qa/SKILL.md)。
