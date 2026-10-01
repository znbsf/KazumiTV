# Kazumi 观看数据与返回路径实施记录（2026-10-01）

> 本候选已作为70e3375e合入main e5793f08，精确最终合并树247项/lint/构建通过；本文初次权限与分支状态按当时记录解读。设备NOT_RUN仍保留，最新状态/目标见[当前入口](PROJECT-STATUS-20261001.md)。

## 交付状态

已完成返回路径、备份与诊断文件交互、慢提供者读取取消的实现和可审阅补丁。本文描述测试候选与基线；指定工作树的实际应用结果以 `evidence/application-evidence.json` 为准。**设备验收未运行，不能将本包记为完整设备验收或已部署。**

指定工作树为 `C:/Users/hentai/.codex/worktrees/kazumi-focus-fix-20260927/Kazumi`，分支 `codex/home-nav-focus-fix-20260927`，本轮实测基线为 `100580e3c9f1bdb2a461b49723103d8d9d1b48f1`。开始与生成补丁前检查 Git status 与全部 363 个跟踪文件 SHA-256；证据见 `baseline-evidence.json`、`evidence/delivery-evidence.json`。生成补丁前目标树干净，`git apply --check` 通过。本任务没有使用主目录作为源码基线，也没有写入主目录。应用入口会再次核验 HEAD、分支、全部基线字节和新文件占用，出现争用即停止；应用后逐文件比对测试候选哈希。

最初观察到的边界是执行环境仅声明 task-3 和临时目录可写，指定工作树在范围外；此前没有实际写入尝试、权限拒绝或 Windows Access Denied 证据，不能称为已遭权限拒绝。候选从目标 HEAD 的 `git archive` 导出到本任务目录，补丁与测试在此隔离副本完成。续作指令明确普通沙箱目录写入授权可申请，和 Windows 管理员/UAC 是不同权限；最终仅对这个精确目录申请普通授权后应用补丁，不申请管理员权限，不更改沙箱或系统设置。实际授权及应用回执独立记录。

## 需求与所有权

完整读取探索报告第 9 节，以及 NEXT-PHASE-PLAYBACK-20260927、MIGRATION-STATUS、RELEASE-ACCEPTANCE-20260927、RELEASE-VERIFICATION-20260927、PLAYBACK-P1-MATRIX-20260924、NETWORK-RECOVERY-STAGE-20260923、AV-ACCEPTANCE-20260927。边界限定 A02/A08/A10/B02/B15。

目标树及主目录未发现仓库 AGENTS.md/.agents；可见上层 `.codex/AGENTS.md` 为空。检查旧执行/复核和统筹的有界生命周期尾部，未观察未配对的新执行回合；这不是全局客户端实时所有权证明。目标状态与文件哈希再次检查未发现争用。本任务的两个并行 agent 只读复核，均不写代码或操作设备。

## 具体改动

- A02/A10：新增 `ReturnViewport`，分别保存视口稳定 key、索引、像素偏移和所选作品身份。搜索、收藏、历史返回时保留原视口；作品消失则选择原视口附近剩余可聚焦条目，空收藏/历史回管理按钮。历史普通组标题被可聚焦白名单排除。
- A02/A10：收藏/历史保存一次性 `pendingReturn`，当前列表变化或用户筛选/管理取消旧恢复，成功后停止请求，避免旧 requester 与后续刷新抢焦点。历史保留详情/续播动作。
- A08：核验现有 generation、协程取消、五页窗口和失败重试，没有发现需要修改的确定缺陷，保留现有实现；其五项单测本轮重跑通过。
- B02/B15：新增有界 `DocumentTransferViewModel`，配置重建保留导出快照，内容不放入 Bundle；设置子页使用 rememberSaveable 以重新注册 launcher。重复确认立即拒绝第二次操作且不替换首次快照。正常离开子页清理待处理状态，配置重建保留状态。
- B02/B15：明确区分取消与有效 URI 缺少快照；无文件选择器/保存器或启动错误可重试。提取 UTF-8 `DocumentText`，读取有界，写入/flush/close 全部成功才显示成功，失败也关闭流。
- B02：新增 `CancellableDocumentReader`，读取在独立有界线程池运行；导入中可使用“取消读取”或 Back。取消及时解除 UI 等待、优先关闭已开流，再通知 Android CancellationSignal；generation 与 ensureActive 拒绝旧预览/旧任务清理新 busy。未开流任务迟到返回时关闭其流。读取和清理各最多两个线程、无等待队列，拒绝无限累积挂起提供者。
- B02：备份错误页面使用固定中文文案，不展示异常原文或提供者 URI；撤销在 journal/commit 前同时验证旧收藏和旧历史，历史损坏/未来版本/坏行时禁止写回。扩展隔离存储 instrumentation 回归，断言失败前后完整 preferences 相等。
- B15：诊断仍为既有白名单播放子集，数量/字节限制不扩张；新增导出字节逐字段测试，确认没有 Cookie、Authorization、URL 和私人测试标记。

## 本轮测试结果

| 检查 | 结果 | 证据及限制 |
| --- | --- | --- |
| `:app:testDebugUnitTest` | PASS | 60 份 XML、247 项，failure/error/skipped 全为 0；`evidence/unit-tests` 是最终运行副本 |
| 新增 JVM 用例 | PASS | ReturnViewport 5 项、DocumentText 5 项、DocumentTransferViewModel 3 项、CancellableDocumentReader 5 项，共 18 项 |
| `:app:lintRelease` | PASS | 0 error/fatal、72 warning；完整 XML 保留，不为清理警告扩大本包 |
| `:app:assembleRelease` | PASS | 版本 0.3.3/code53，applicationId 沿用仓库；精确 APK SHA-256 见交付 JSON |
| `:app:assembleDebugAndroidTest` | PASS | 包含新增坏历史撤销保护用例；**只编译，未运行 instrumentation** |
| 生产/测试 APK 签名核验 | PASS | v2，使用本任务隔离 debug key，证书 SHA-256 `455383d038a8bf624ca3e82a9971851bda0bcbc15911717359481f76cca07409` |
| 对指定工作树 `git apply --check` | PASS | 应用前检查；实际应用独立见 `evidence/application-evidence.json` |
| 两路最终只读复核 | 无新确定阻塞 | 返回列表/时序与文件回执/数据安全分别复核，不替代运行证据 |
| 真实搜索分页、遥控焦点、收藏/历史完整返回 | NOT_RUN | 纯函数不能证明实际控件获焦或像素偏移 |
| 实际 SAF 提供者成功/失败、Activity 重建与离页重入 | NOT_RUN | 流/模型单测不等于 ContentResolver/系统选择器或生命周期验收 |
| 新增撤销坏历史存储 instrumentation | NOT_RUN | 已编译；需独占测试设备及四存储保护 |

最终成功构建日志和起止时间见 `evidence/delivery-evidence.json` 的 latest_build_run 字段及对应 `candidate-checks-*.log`。采用已有 JDK17、Gradle8.14.5、SDK36；离线、2 worker、3 GiB 堆、Kotlin in-process、JVM 2 个有效处理器。依赖缓存复制到任务目录，原共享缓存未写入；Java/Android/Gradle 用户目录和 debug 签名均在任务目录。未安装软件或 SDK、未联网同步仓库、未改系统设置。

失败历史保留：初始 Android 用户目录两种环境变量冲突；第二次带 stacktrace 确认原因；随后隔离 debug 签名在 DSL 锁定后设置导致配置失败。修正仅限任务脚本和进程环境，最终四项检查成功。没有单测失败被删除、跳过或隐藏。

## 交付材料与续作

- `watch-data-return.patch`：源码、测试及本记录的候选补丁；基线、文件清单和每个文件前后哈希见 `evidence/delivery-evidence.json`。
- `run-candidate-checks.ps1` / `isolated-signing.gradle`：可复用本机离线检查入口。`make-delivery.py` 在输出证据前再次核验目标工作树未变，再检查补丁可应用。
- `apply-reviewed-patch.py`：只在 `--apply` 与精确目录普通写入授权后执行；校验补丁 SHA-256、基线/所有权、允许路径、应用后全部变更哈希及无关跟踪文件未变。不会提交、重置、清理或部署。
- `设备验收续作清单.md`：最少代表路径、实际焦点/文件回执断言、检查点和交还要求。
- 生产/测试 APK 位置与哈希、lint XML、单测 XML、签名记录及全部构建失败/成功日志留在本任务目录。

本次 APK 是任务本地 debug 签名的构建证据，不应直接覆盖已有电视/模拟器应用。设备续作需在既定签名环境重建，禁止卸载、清数据或降级绕过。没有启动或占用 AVD，没有安装 APK，没有写入设备用户数据，因此没有设备检查点恢复操作。

## 剩余决定点与边界

1. 历史组头“继续最近观看”保持原语义：回到该组最新记录的续播按钮。本包没有新增组头按钮焦点身份。
2. 慢提供者读取取消的软件边界已完成隔离夹具验证：挂起 read、迟到 open、阻塞取消回调、有界线程饱和和超限读五项通过。不能强制终止同时拒绝 interrupt/cancel/close 的外部提供者；池饱和时拒绝新读取/额外清理，迟到任务最终返回仍关闭流。释放容量需等待提供者返回或重启进程；本任务未自动重启或操作设备。真实提供者及 UI 取消仍未验。
3. 配置重建快照由 ViewModel 保留；进程丢失快照后明确要求重试，不跨进程保存私人导出内容。真实配置重建和系统选择器仍待验。
4. 未修改共享迁移台账以宣告关闭，未进行全来源扫站、自然 LMK、真实人机挑战、实体电视声画、全应用日志、过滤新增或同步功能。
5. 本实现及构建阶段未提交、推送、部署或发布，未恢复 heartbeat。其后用户新增授权要求在可交付节点提交、按既有流程推送并有条件合并；当前候选仅沿本任务分支保存，不以设备 NOT_RUN 作为验收通过或合并放行。精确提交、远端 SHA 和 CI 状态由后续 Git 交付记录提供。权限/UAC/登录/人工设备步骤未尝试绕过。
