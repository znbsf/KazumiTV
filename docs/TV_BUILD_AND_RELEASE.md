# TV构建与发布维护

## 固定公开测试签名（QA6-r2起）

仅测试包remoteqa使用[公开测试夹具说明](../tools/testing/README.md)及kazumiTvPublicTestSigning=true；证书指纹固定为131f00a5a75f3e587ece7ef86a96a21c5971db5717123890121dc55363523ea1。该密钥和android密码有意公开，不是身份凭据，不得用于正式包、签名权限或任何信任关系。CI每ABI校验证书，禁止每次生成临时debug key作为交付签名；正式签名流程保持不变。

QA6-r2建立固定测试签名序列，未来同包名/同证书/递增versionCode可覆盖该序列。旧QA6及r1临时证书不同，仍无法直接覆盖；用户已完成授权的测试序列替换，r2至r7的安装和数据边界见项目状态。不要把旧的“待次日安装”记录当成当前状态。无需新GitHub Secret或传输私密凭据。

当前稳定修复候选的精确head、CI终态、设备边界和正式发布待办见[#11发布准备](ISSUE11-RELEASE-READINESS.md)，执行前仍以[项目状态](PROJECT-STATUS.md)与当前授权为准。[桌面/ADB研究](TV-DESKTOP-ADB-STATUS.md)不混入稳定版发布范围。

当前版本、状态和验收范围只在[项目状态](PROJECT-STATUS.md)维护。[旧0.4.0构建与签名记录](history/2026-10-10/TV_BUILD_AND_RELEASE.md)保留历史复现信息。

## 工具链与检查

Flutter3.47.3 / e8113bf45620cbeb8aff64947ee4c93e16adb4cf，JDK21、SDK36、BuildTools36.0.0、NDK28.2.13676358。精确像素回归使用既有Windows基线，不因换平台而改基线。先确认Git状态、工作树与其他写入活动，保护未提交工作。

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-fatal-infos --fatal-warnings
flutter test --concurrency=2
git diff --exit-code -- pubspec.lock
```

纯文档清理只检查链接、差异、事实及归档恢复，不重复APK构建/设备验收。若既有CI自动触发，跟踪到终态并区分程序构建与文档提交。

## 正式产物

使用TV flavor、`kazumiTv=true`、正式applicationId、probe关闭，版本/构建号按当前目标明确传入；Android ABI拆包号为基础号×10加1/2/4。通过正常受控方式传入合法应用配置，不公开原始JSON或secret。

复用长期签名流程与证书，不生成替代证书、不打印凭据。`tools/verify_tv_artifact.py`逐ABI校验appId、版本、source SHA、证书、TV入口、probe和libmpv；再核对zipalign。源码包与真实构建快照关联，附许可证/NOTICE、验证JSON和SHA256SUMS。

CI `.github/workflows/tv-ci.yml`当前产出独立`remoteqa`固定公开测试签名包，不能当正式包上传；更早的`.candidate`包属历史候选。已发布正式附件不重签、不替换，tag不移动。

## 交付与恢复

发布前先查远端tag/Release，避免覆盖。需要发布时遵循该次用户目标和授权：固定精确程序提交，核对公开附件白名单，公开后实际下载验hash；文档提交与APK源码分开记录。本次0.4.1许可不构成下一版本自动发布许可。

升级前核对正式包身份，覆盖升级并检查真实用户数据；不同实验包不自动迁移。恢复代码优先正常revert/归并，产物归档有manifest和哈希；不reset/clean或永久删除来清理现场。

详细方法：[工程经验](ENGINEERING-LESSONS.md)、[数据说明](TV_DATA_MIGRATION.md)、[原生依赖源码](NATIVE_DEPENDENCY_SOURCES.md)。
