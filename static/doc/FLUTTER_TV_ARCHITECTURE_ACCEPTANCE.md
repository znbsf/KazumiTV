# Flutter TV 架构迭代验收

日期：2026-10-01。版本 `2.3.1-tv-lab.2+20304`。本机自动化关卡完成；真机验收和签名迁移仍待完成。

## 架构与有限里程碑

| 里程碑 | 实现与验收边界 | 结果 |
| --- | --- | --- |
| 唯一业务状态 | Dart repository/同步为数据所有者，路由持有 VideoPageController/PlayerController；原生桥只分派平台事件 | 完成边界记录；未新建第二业务库 |
| 查找→详情→Back | 按稳定作品 ID 返回焦点；结果重排、目标删除、空列表、新查询及屏外目标保护 | 首轮真实 widget 用例 4 PASS，完整回归保留 |
| 观看→历史续播 | native session recorder 捕获实际进度；历史恢复按页面 URL 映射当前播放列表，来源一致才使用旧 offset | 重排、缺页、重复 URL、非法索引、legacy、关闭跳转开关等用例通过 |
| 持久化与失败恢复 | 本地 put 失败向 recorder 传播，成功后才去重；非 TV 周期调用消费异常并继续 | 真实 repository 首次 put 故障→相同快照重试→flush/close/reopen、新 repository 读取 PASS |
| 返回与平台生命周期 | TV remote/PIP 每页面持有租约，旧 dispose 只释放自身；最近 owner 接收回调，存活前页可恢复 | 实际平台消息双 widget、最后/重复释放、旧请求失效 PASS |
| 可交付与回滚 | 锁定依赖，限量构建 TV ARMv7，保留首轮 APK/源码/证据与独立回滚点 | APK 构建、manifest/ABI/签名验证 PASS；不覆盖 native main |

## 三项修复

1. `VideoPage` 的统一在线入口调用 `resolveOnlineHistoryResume`。已保存的 `episodePageUrl` 经现有源站 URL 归一化后匹配当前道路；旧 road 优先，跨道路找同一页。已知页面缺失返回新播放的零偏移；仅 legacy 空 URL 可以使用合法旧索引。新来源不借旧来源进度，负进度归零，数据/标题长度均检查。Hive schema 和既有 progress map 保持兼容。
2. `HistoryRepository.updateHistory` 记录错误后传播失败；`PlaybackHistoryRecorder` 不把失败快照标为保存成功。真实 Hive 底层 put 注入一次故障，经过生产 HistoryController/recorder 重试，并关闭重开验证持久化。TV session 捕获路径已有错误消费，补齐手机周期路径。
3. `OwnedMethodChannel` 只保存回调租约；播放状态继续留在既有 Dart controller/media-kit。当前租约回退时重同步 PIP 参数；Android active 只在首个订阅/最后释放改变。异步 PIP 请求捕获激活 revision，每次等待后核验，失去后重获 owner 也不能复活旧请求；取消/失败/异常清页面 entering 标记，重复请求受页面 in-flight 保护。

## 测试与构建

| 检查 | 通过/失败/未运行 |
| --- | --- |
| 固定 Legacy 基线 | 326 PASS / 0 FAIL / 0 SKIP |
| 首轮结果 | 336 PASS / 0 FAIL / 0 SKIP |
| 三边界旧逻辑 RED | 11 PASS / 12 FAIL / 0 SKIP，实际断言失败与 RangeError；续播原判断等价抽取后复现 |
| PIP 旧异步流程 RED | 1 PASS / 2 FAIL / 0 SKIP；可控 Future 复现取消不清标记/旧请求继续 enter |
| 最终完整 suite | 366 PASS / 0 FAIL / 0 SKIP |
| Flutter CLI analyze | exit 0；0 error / 0 warning，5 项既有 avoid_print info |
| release TV ARMv7 APK | PASS，普通用户工具；测试并发 2、Gradle worker 2、堆 2 GiB |
| APK | PASS，`com.predidit.kazumi.tv`，实际 ABI versionCode 203041，仅 ARMv7 native 库、双 launcher、触摸非必需 |
| 真实 TV 全链路/音轨/解码/遥控/待机/PIP | 未运行；Dart 与平台消息测试不等于 Android JNI/Activity 验收 |
| 真实站点/WebDAV/验证码 | 未运行；已有离线规则、同步和取消回归通过 |

APK SHA-256：`d89c2eb51ad762249dc564bf2604ab4122b9dd385c5be4a059425a3ab77faee6`。media-kit `994465d9bfca3f39d0b41199d16e7fd93fe97881`、libmpv `v1.2.7` 保持；lockfile 未改。以第一轮和本轮 APK 区分测试对象，旧真机结果不转借本轮。

## 升级、备份、回滚

本轮 APK 使用实验签名，和 Legacy 已安装包证书不同；同包名直接覆盖被签名边界阻塞。本轮没有安装、卸载、提取私钥或改变签名保护。正式覆盖前应由用户确认可用的原签名发布链；若选择独立安装包，需另行确认 appId，不能在本轮静默改变。

迁移前保留原 APK/版本/公共证书，以及原应用现有导出或 WebDAV 备份和可恢复的数据副本；不要把原生 JSON 直接当 Hive 数据。先在可回滚环境确认导入、来源/episode 身份、播放/暂停寻址、返回和重启恢复，再决定替换。真实 Android 强杀可能发生在持久化完成前，本机 close/reopen 仅证明已完成写入可重建。

源码回滚保留首轮原提交和同树 noreply 副本；使用自有实验中的新 review 分支检查首轮，避免 reset 用户主目录/native main。APK 降级也须证书兼容和备份确认。本机 runner、日志、JSON、源文件 hash 清单与每轮 Git bundle 留在实验交接目录，未作为公开仓库资料上传。

Compose 继续为有证据才采用的可选局部组件；本轮确认缺口已在 Flutter 与现有原生桥闭合，未产生其必要性证据。下一步只剩本轮 APK 真机全链路验收和签名/数据迁移决策，不能把这些人工关卡记作 PASS。

参见 [架构决策](FLUTTER_TV_LAB_ADR.md)、[首轮验收](FLUTTER_TV_LAB_ACCEPTANCE.md)、[上游补丁选择](FLUTTER_TV_UPSTREAM_SELECTION.md)。
