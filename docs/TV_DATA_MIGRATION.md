# 正式身份、签名、版本与数据

## 首版身份与安装关系

首版使用新包 com.znbsf.kazumi.fluttertv、0.4.0-preview.1/base20324 和本机专用长期发布证书。采用并存新装，不覆盖原生、Legacy 或实验应用；不迁移原生收藏、历史或其他旧数据，不开发转换层。原生源码与历史发行保留，建议保留原应用及备份以便切回。

| 方案 | appId / 安装关系 | 签名、版本与数据边界 |
|---|---|---|
| 采用：新正式Flutter包 | com.znbsf.kazumi.fluttertv；与原生compose.tv和当前flutterlab.test并存 | 0.4.0-preview.1/base20324→ARMv7 203241、ARM64 203242、x86_64 203244。本机长期证书签名，公开指纹见实际产物回执。原生不被覆盖；不迁移原生收藏/历史、不开发跨格式转换。Flutter隔离包同格式导出/预览恢复为可选路径，须在新身份另验 |
| 排除：覆盖当前隔离安装 | com.znbsf.kazumi.flutterlab.test | 必须保持同证书fe3f74f8…并递增code，已有Hive数据可沿当前路径使用；但.test身份及开发签名不适合作长期正式品牌，无法仅改显示名就解决长期证书管理。保留为内部验收更合适 |
| 排除：覆盖原生产品 | com.znbsf.kazumi.compose.tv | 必须与原生实际APK兼容的证书及更大code；原生v53源码也用debug signing不证明它和当前隔离证书相同。原生SharedPreferences不会被FlutterHive读取，即使安装保留data目录，用户也看不到原历史。本轮明确不覆盖此应用；模板阻止此身份签名构建，不以补迁移为首版待办 |

源码普通 TV 默认 com.predidit.kazumi.tv 对应 Legacy 身份，不用于本次发行。TV Gradle 配置通过明确的 appId 与签名参数构建新包，不改变普通上游 Android 变体；版本通过 --build-name/--build-number 显式传入。

基础 20324 是本次获准的新 appId 首版编号。不同 appId 的版本序列独立，实验包曾用相同编号不影响新包；同包后续更新须递增版本码并使用兼容证书。

证书只核对公开SHA256指纹。当前隔离ARMv7签名回执为fe3f74f8c6f7bf2af6edffbed9c0293e37cb876beffa6dd5055b8971542892a4；原生实际证书应从授权的公开APK或既有证书回执读取，不能读取用户私钥来猜。新正式证书一旦发布应长期保留；原有Android应用更新依赖兼容签名，不能随意换证书。[Android官方签名说明](https://developer.android.com/studio/publish/app-signing)。

发行使用维护者本机签名流程；CI 只进行无秘密的三 ABI 构建验证，不配置 GitHub 签名 secret 或发布环境。具体流程及产物核验见 [构建与发布](TV_BUILD_AND_RELEASE.md)。

## 数据格式实查（兼容性边界，不是首版开发清单）

| 字段/语义 | 原生24bc | Flutter21233631 | 不兼容原因与数据边界 |
|---|---|---|---|
| 文件format/version | KazumiTV-library / 1 | KazumiFlutter-library / 1 | 不能只替换format字符串；Flutter当前会拒绝原生文件 |
| 收藏数组 | collections：id/title/cover/summary/metadata + collectionType/collectionUpdatedAt | collections：bangumiItem + type/time | 类型1在看、2想看、3搁置、4看过、5抛弃可保持；主题对象需映射与完整校验 |
| 历史数组 | history：key、episode字符串、position/duration、origin、updatedAt、kind | history：bangumiItem、lastWatchEpisode整数、adapterName、lastSrc、lastWatchEpisodeName、episodePageUrl、entryKind、progresses | 多条原生分集记录需按作品/规则/类型聚合，不能覆盖丢集数；必须明确来源与集号 |
| 来源与线路 | origin.rule/sourceTitle/sourceUrl/roadTitle | adapterName、lastSrc、progresses[episode].road整数、episodePageUrl | roadTitle不能猜索引；sourceUrl含义要逐源核验，不把播放直链当节目/集页面 |
| 时间与进度 | position、duration、updatedAt为Long；播放器调用证实毫秒后才能转换 | progressMs/updatedAtMs与DateTime毫秒 | 保持单位；未知时不乘除猜测，不把无时间记录伪装为现在 |
| key | 原生业务key（含分集上下文） | adapterName + Bangumi id + ::online/offline | 必须按Flutter规则重新生成，不直接拷旧key |
| 容量 | 最多200收藏/100历史、4,000,000字符 | 10,000记录、4,000,000字符/16,000,000字节 | 不截断；超限或重复记录提示并停止，保留源文件 |
| 本机储存 | SharedPreferences tv_library | Hive收藏/历史/变更日志 | 不能搬xml文件进Hive目录，也不能仅更换包名指望自动读取 |
| 恢复语义 | 预览后替换、fingerprint防并发覆盖、可撤销 | 同样先预览再整体替换；在当前页面可撤销一次 | 新包先导出自己的空/已有状态；恢复不是合并，必须在用户界面明确确认 |

源码定位：原生app/src/main/java/org/kazumi/tv/data/{LibraryArchive,LibraryCodec,LibraryStore,Collection}.kt；Flutterlib/services/storage/local_library_backup.dart、lib/modules/history/{history_module,history_sync}.dart，以及对应备份页面。此审计未读取用户备份内容。

## 现在能走的导入路径

当前隔离Flutter→新并存Flutter：在设置→同步→收藏与历史备份中“导出到文件”；新包使用同页面“从文件恢复”→预览→确认替换。它不是自动搬家，也不带账号凭据、资源规则、设置、下载文件；来源规则需要单独准备，文件选择器/SAF在目标电视必须实测。退出页面后不能依赖一次性撤销，保留原始导出文件。

原生→Flutter：原生备份页“导出到文件”可保留KazumiTV-library，备份用于原生版本的恢复与回退。当前Flutter不支持直接导入该格式，首版不保证原生收藏/历史继承；按用户决定，不开发转换层，也不把它列为新包preview的发布门禁。新包从独立数据目录开始，用户按需重新配置和收藏。

旧原生下载URI/持久文件权限、账号或WebDAV凭据、规则脚本和设置不由本次首版继承。并存新装需要按需重新配置；原生应用及其备份保持可用，回退时切回原生应用，不卸载、不清空原数据。
