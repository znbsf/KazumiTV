# TV 构建与发布维护

0.4.0 正式版沿用包名 `com.znbsf.kazumi.fluttertv`，从本版起固定使用新的长期发布证书，基础版本号递增为 `20325`。preview 需卸载后重新安装；后续正式版保持同一证书。main 已保留原生与 Flutter 两条历史，preview 和原生归档继续保留。发行由维护者在本机完成，CI 不接收签名秘密。

## 工具链与无秘密 CI

固定 Flutter 3.47.3 / `e8113bf45620cbeb8aff64947ee4c93e16adb4cf`、JDK 21、Android SDK 36 / Build Tools 36.0.0、NDK 28.2.13676358；依赖锁文件不升级。先 `flutter pub get --enforce-lockfile`，构建使用 `--pub` 重新生成插件注册，构建后检查 pubspec.lock 未变。

分析与全部测试使用 Windows runner，与现有四张非 TV 像素基线的生成/验收平台一致，保持原基线和严格逐像素比较。首轮 Linux 运行其余 659 项通过，四张截图有 0.39–0.47% 跨平台差异；不更新基线或跳过测试。三 ABI Android 构建仍使用 Ubuntu。

唯一启用工作流为 `.github/workflows/tv-ci.yml`，响应 main 的 PR/push、指定融合/集成分支 push 及手动触发。它运行分析和测试，并分别构建 ARMv7、ARM64、x86_64；候选身份为 `com.znbsf.kazumi.fluttertv.candidate`，开发证书、probe 关闭，只上传 Actions artifact。权限限当次任务的 `contents:read`，checkout 不保留凭据；不使用 secret、发布环境、长期令牌或 Release 写权限。

旧通用 pr.yaml/release.yaml 的原文保留于 native-history/upstream-flutter-workflows，集成时移除旧触发入口。未配置的签名工作流移至 [workflow-reference/tv-release.yml.reference](workflow-reference/tv-release.yml.reference)，不在 active workflows 中；它只是未来方案参考，不能当作可用 CI，也不需要为本次发行配置 GitHub secret/environment。

## 本机签名与三个 ABI

使用审阅后的精确提交构建。0.4.0 的长期证书及随机密码已按维护者要求固定在本机；密码使用 Windows 当前用户 DPAPI 加密保存，目录仅当前用户和 SYSTEM 可访问。后续签名自动复用，不再次询问密码、不自动生成替代证书。完整保留签名目录及当前 Windows 用户配置，不能只复制加密密码到另一账户后假定可解密。凭据由本机受控流程提供给签名进程，使用现有 `TV_KEYSTORE_PATH`、`TV_KEYSTORE_PASSWORD`、`TV_KEY_ALIAS`、`TV_KEY_PASSWORD` 环境接口，材料不进入仓库或制品。构建命令不包含密码值：

```sh
flutter pub get --enforce-lockfile
flutter build apk --release --pub --flavor tv --split-per-abi \
  --target-platform android-arm,android-arm64,android-x64 \
  --android-project-arg=kazumiTv=true \
  --android-project-arg=kazumiTvSigned=true \
  --android-project-arg=kazumiTvApplicationId=com.znbsf.kazumi.fluttertv \
  --android-project-arg=kazumiTvLabel=KazumiTV \
  --build-name=0.4.0 --build-number=20325 \
  --dart-define=KAZUMI_TV_PERF=false --dart-define=KAZUMI_TV_FIXED_SURFACES=true
git diff --exit-code -- pubspec.lock
```

输出为 `build/app/outputs/flutter-apk/app-<ABI>-tv-release.apk`。本次本机发行使用等价的分步流程：先省略 `kazumiTvSigned` 构建 release 模式中间包，再由本机签名脚本解锁固定凭据，用 Android Build Tools 36.0.0 的 `apksigner` 替换中间签名。签名前后逐项比较 ZIP 非签名内容，并复核对齐、发布证书及不可调试状态；中间包不安装、不发布。

本版程序构建于 `678d00379eef2299b296a1ff8478ce7bdb7df8d0`；正式标签在此基础上只修订 README、CHANGELOG 和本维护文档的签名说明。已核对其余全部 Git 文件内容一致，复用相同程序构建；源码包保留最终说明，核验 JSON 同时记录程序构建提交与发行提交。

基础编号乘 10 后按 ABI 加 1/2/4：ARMv7 203251、ARM64 203252、x86_64 203254。新 appId 的版本序列独立于原生或实验包，后续同包升级须保持兼容证书并递增编号。

每份包用 `tools/verify_tv_artifact.py` 核验明确 appId、ABI、基础编号 20325、版本 0.4.0、完整 source SHA 和实际公开证书 SHA256。核验器同时检查 TV 入口、不可调试、probe 关闭及 libmpv 哈希，并输出 JSON。三个 ABI 必须都纳入，不以两个 ARM 包替代完整发行清单。

## 产物、发布与回退

将三份 APK 命名为 `KazumiTV-0.4.0-{armeabi-v7a,arm64-v8a,x86_64}.apk`，附上各 ABI 核验 JSON、SHA256SUMS、精确构建提交的对应源码 ZIP、GPL 与第三方 NOTICE。正式证书/源码/产物哈希从实际回执获取，不预填开发证书或用文档提交冒充来源。

签名 artifact 可先本地审阅，不要求 main 已切换或 tag 已存在。随后普通推送 main，保留现有双父历史、原生归档及 `tv-fusion-v0.4.0-preview.1`；核验正式 tag `v0.4.0` 指向已验产物源码，再发布非 prerelease 的 GitHub Release。CI 不自动建 tag、不创建或发布 Release。

原生代码与历史 Release 保留。源码回退使用新分支上的 `git revert -m 1 <MERGE_SHA>` 后普通合入，不重写历史；应用采用并存包，用户可直接切回原生，不卸载或清数据。首版不迁移原生收藏/历史，不开发转换层。

## 证据边界

产品源码 e767 已有 663/663 测试、0 错误/0 警告/58 项 info；同源四文件配置覆盖的三 ABI 开发证书包已构建，x86_64 已完成保数据升级。ARMv7 有 Android 9 电视有限验证；ARM64 仅构建未实机，不能写成同等验收。正式签名构建、实际安装和远端 CI 各按后续回执记录，不靠重复旧测试补结论。

测试电视元数据搜索曾连接超时，已测规则搜索可返回结果；首页横向 raster p95 仍约 43ms，不承诺 60fps。长期播放、声音同步和全部站点未全面验收，发行说明应保留这些简短限制。
