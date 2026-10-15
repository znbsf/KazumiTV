# KazumiTV 当前状态

2026-10-15 最新核对：PR #12 head `ab5ea883a08708cf2a291269c88468273bed7295` 的 [CI 38746978591](https://github.com/znbsf/KazumiTV/actions/runs/38746978591) 于14:12:31 UTC全部成功：871项测试，静态0 error / 0 warning、58 info，三ABI构建与产物校验通过。PR仍为草稿、未合并、未发布。QA生产代码仍对应 `dae2bbede53f225a3f0c135181f0981f502ddcce`；下方869项为旧head结果。验收边界及正式升级/签名/附件待办见[稳定发布准备](ISSUE11-RELEASE-READINESS.md)。

独立设备研究见[桌面/ADB状态与回滚](TV-DESKTOP-ADB-STATUS.md)：LTv普通入口可用，Home Button Fix已关闭，临时设置包状态已恢复，原HOME保留；开机启动、HOME接管与ADB持续可用分别记录，不作为稳定版已修复功能。

2026-10-15 第二阶段补充：新增超时后取消/重试及连续换源历史身份回归，七文件70项通过；Android 9换源取消前后暂停位置90444ms一致、焦点回设置，正常退出后媒体会话清空。没有新增生产代码修复；实际超时与纯遥控取消仍有未测边界，详见[第二阶段记录](ISSUE11-TV-STAGE2-20261015.md)。

2026-10-15 维护验收：PR #12程序head `dae2bbede53f225a3f0c135181f0981f502ddcce` 已通过869项CI及三ABI候选校验，API36模拟器和Android9独立QA核心链路已有实测。纯遥控及长播补充结果见 [第一阶段记录](ISSUE11-TV-STAGE1-20261015.md)，前序范围分别见 [模拟器记录](ISSUE11-EMULATOR-QA-20261015.md) 与 [电视首轮记录](ISSUE11-TV-QA-20261015.md)。候选仍为草稿，未合并、未发布；不能把未测的完整搜索链路、纯遥控加载取消或音画同步写成通过。维护时使用 [项目TV验收技能](../.agents/skills/android-tv-ui-qa/SKILL.md)。

2026-10-14 维护更新：[#10](https://github.com/znbsf/KazumiTV/pull/10) 已以 `ae2d9dab5b036cdde568d6b714ce498fb75a7a3b` 合入 main，显式换源代码已集成，但未发布新版本；其原设备验收边界仍有效。[#11](https://github.com/znbsf/KazumiTV/issues/11) 单独追踪 API 9、设置导航、控制栏动画和 WebView 卡住回收修复，当前为候选分支。规则说明见 [RULES.md](RULES.md)。已发布版本仍是下面的 v0.4.2。

本文件是仓库唯一当前状态入口。历史报告保留原始事实，不从旧结论恢复授权或状态。更新日期：2026-10-15。

## current：已确认的发布

- 正式版：[v0.4.2](https://github.com/znbsf/KazumiTV/releases/tag/v0.4.2)，Latest，非草稿/预发布。
- 标签对应源码：`590001e970e637622422908a9a2e1dcc0d54a999`；0.4.2+20392，三ABI versionCode 203921/203922/203924。
- 正式包名 `com.znbsf.kazumi.fluttertv`，长期证书SHA256 `3225e3b8676eed2d2f28fad6255881120f6335ade615bbb27673d974727ce806`。CI `.candidate` 为独立开发签名包，不是正式附件。
- 11项公开附件已实际匿名下载并逐个通过SHA256，含三ABI APK/验证JSON、精确源码ZIP、许可归档、LICENSE/NOTICE和SHA256SUMS。
- 正式版本地846项全量测试通过，静态0错误0警告58 info；[CI检查和三ABI构建](https://github.com/znbsf/KazumiTV/actions/runs/38404754840)全部成功。
- ARMv7正式包同签名保数据升级、启动、输入法导航/编辑/Back/取消和滑条调值恢复smoke通过。此前同一生产逻辑候选完成代表性电视/模拟器回归；未把所有调用点或所有网站声明为全测通过。
- 发布源码与本地构建提交只差Git作者元数据，完整树一致；各APK验证JSON明确记录对应关系。后续纯文档提交不改变APK源码和标签。

## 本版范围与后续

本次只发布原功能bugfix：#1当前项目入口，#3滑条/seek，#4输入，#5主题，#6焦点/缓存/长说明/设置消费及数字快捷角标，以及#8标准/小播放器跳过秒数输入校验。详见[0.4.2记录](RELEASE-0.4.2.md)。

个人电视、频道、EPG、LCN等新功能（#2）及新频道数字选台不包含在本版，个人电视数字表单亦不包含在本版，开发成果独立保留。#7网站验证码兼容继续跟踪；原有验证能力已继承，不承诺所有来源、多阶段挑战和API/章节验证均可用。

ARM64/x86_64正式包只完成构建、签名和产物校验，未作实机验收。整集长播、全部设置业务分支、登录/同步/评论/建房等没有完整实测结论。源码、配置或设备环境变化后按影响范围重新验证。

## 维护入口

- [构建与发布流程](TV_BUILD_AND_RELEASE.md)
- [工程经验](ENGINEERING-LESSONS.md)
- [数据与迁移](TV_DATA_MIGRATION.md)
- [原生依赖对应源码](NATIVE_DEPENDENCY_SOURCES.md)
- [历史归档](history/README.md)

本次0.4.2授权仅覆盖本次纯修复发布；不恢复旧任务权限，也不自动授权未来版本、新功能或新设备操作。
