# #11 稳定修复发布准备

2026-10-15 15:26 UTC 状态更新：PR #12 已按用户授权正常合并，merge SHA `286ab90d7f59279fdd01675002cad4b3eacf6b41`，未发布版本。以下 draft/未合并描述保留为合并前证据。后续 INFO 进展见 [INFO 方案](STABLE-INFO-PLAN.md)，当前入口见 [项目状态](PROJECT-STATUS.md)。原纯文档记录 ed555894 已保留并移植到 INFO 分支为 8ca653f4。

2026-10-15核对：[PR #12](https://github.com/znbsf/KazumiTV/pull/12) head `ab5ea883a08708cf2a291269c88468273bed7295`，base/main `ae2d9dab5b036cdde568d6b714ce498fb75a7a3b`（含已合并#10），仍open/draft、未合并。正式发布仍v0.4.2。本页是准备清单，不是合并或发布授权。

本轮后续本地提交仅保存七份文档，未推送、未触发新CI。下述CI验证只对应 `ab5ea883`，不代表本地文档提交经过新CI。

## 当前证据

[CI 38746978591](https://github.com/znbsf/KazumiTV/actions/runs/38746978591) 于2026-10-15 14:12:31 UTC completed/success：871项测试通过，静态0 error / 0 warning、58 info；ARMv7、ARM64、x86_64构建、锁文件不变、包名/ABI/TV入口/签名/probe absence校验与产物上传全部成功。没有失败重跑或追加产品代码修复。

已装QA包生产逻辑仍对应 `dae2bbede53f225a3f0c135181f0981f502ddcce`；与当前head比较，lib、android、pubspec.yaml及lockfile无差异。新增测试与文档不冒充新APK实测。对应记录：[模拟器](ISSUE11-EMULATOR-QA-20261015.md)、[电视首轮](ISSUE11-TV-QA-20261015.md)、[第一阶段](ISSUE11-TV-STAGE1-20261015.md)、[第二阶段](ISSUE11-TV-STAGE2-20261015.md)。

## 拟发布内容及边界

- #10显式换源、来源/集数确认与恢复；已在main，未发布。
- #11 API9 sourceTemplate及编辑/序列化兼容、重复设置导航、控制栏hover、WebView load/parser期限及卡住清理。
- 规则教程见[RULES.md](RULES.md)。个人电视、频道、EPG、排序preview、桌面/ADB实验不纳入稳定修复。
- 目标电视官方元数据搜索有连接超时，完整搜索到播放链路未覆盖；不归因为API9解析失败。
- 真实超时后的纯遥控取消/重试未完成；受控Future覆盖load/unload卡住与迟到错误，不能代替实机复现。init永不返回、原生资源最终释放不在保证内。
- 长播为跨源跨集累计31分48.66秒，不是单源无操作30分钟。最新换源取消前后均暂停在90444ms、焦点回设置，退出后媒体会话清空。
- 真实硬件遥控长按、独立鼠标hover、音画同步、验证码/Cookie挑战、全部站点/设置业务未全测；人工选择的来源播放不等于自动作品匹配准确。
- ARM64/x86_64只有CI构建与产物校验；独立QA不代替正式同签名保数据升级验收。

## 发布前顺序

1. 获得当前PR合并授权后，重新执行[main合并检查](MAIN-MERGE-CHECKLIST.md)，核对head/base、有效规则、reviews/checks；不复用旧head绿灯、不修改保护放行。
2. 明确新版本和递增build number，检查远端tag/Release，固定源码SHA。当前v0.4.2为base20392，三ABI code203921/203922/203924；CI的0.4.0-ci/20325不能用作正式更新身份。
3. 按[构建发布流程](TV_BUILD_AND_RELEASE.md)使用正式appId、既有长期证书及合法配置构建；CI `.candidate` 为开发签名，不直接发布。
4. 核对三ABI、签名、版本、TV入口、probe关闭、lockfile及源码对应；生成验证JSON、SHA256SUMS、源码ZIP、LICENSE/NOTICE与原生依赖许可材料。
5. 在获授权设备做同包同签名递增版本保数据升级smoke，核对收藏/历史/规则/设置及播放；不卸载清数据、不覆盖preview。发布评审明确是否接受上述未测边界。
6. 获得发布授权后才创建固定tag/Release及附件，逐个匿名下载校验。记录合并SHA、构建SHA与APK hash，不移动旧tag。

目前是具有代表性设备证据的稳定修复候选，正式发布验收尚未完成。[桌面/ADB调查](TV-DESKTOP-ADB-STATUS.md)是独立设备研究，不作为PR12已修复能力或发布门槛。
