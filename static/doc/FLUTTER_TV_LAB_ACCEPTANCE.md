# Flutter TV 实验首轮验收

基线、边界与停止条件见[ADR-001](FLUTTER_TV_LAB_ADR.md)。结果仅适用于本地自动验收，尚未完成新包电视验收。

| 检查 | 实际结果 | 证据 / 限制 |
| --- | --- | --- |
| 独立工作树与所有权 | PASS | 基线 c54b2fd492a4，实验分支 codex/flutter-tv-reuse-lab-20261001 |
| 固定旧代码完整测试 | 326 PASS / 0 FAIL / 0 SKIP | 对照工作树仅新增测试夹具，生产代码未修改 |
| 搜索结果重排后返回原作品 | RED → GREEN | 旧代码真实焦点断言失败；按稳定 ID 修复后通过，下一次 OK 打开原 ID |
| 删除、空列表、新查询取消、屏外返回 | 4 项 UX PASS | 屏外回归先发现已卸载 context 缺陷，修复后通过；包含前行重排用例共 4 项 |
| 满额历史重复搜索 | RED → GREEN | 旧代码只剩 9/10 条；修复后 2 项真实 Hive 保留/淘汰断言通过 |
| 三项上游修复的完整回归 | 336 PASS / 0 FAIL / 0 SKIP | 包含新增 4 项 XPath 非 2xx / 普通错误 / API / 取消回归 |
| Flutter CLI 分析 | PASS | 0 error / 0 warning / 5 条既有 avoid_print info |
| 固定基线 TV release 构建 | PASS | 首次 --no-pub 开发插件注册错误已保留；正常 --pub 刷新后通过 |
| 实验 ARMv7 分包构建 | PASS | Flutter 3.47.3 / Dart 3.13.3，未升级媒体或依赖锁文件 |
| APK manifest / ABI / 签名 | PASS | 包名 .tv，双启动入口、返回设置、仅 ARMv7 本机库、签名验证通过 |
| 历史 Legacy 原位升级 | 未进行；签名不兼容 | 本轮任务内 debug 签名不同，不能直接覆盖；未卸载原包 |
| 新包真实电视 / 来源 / 音频 / 硬解 / 实体遥控 / 待机 | 未运行 | 不借用历史 d3b9ba64a0cd 的设备结果 |
| Compose 原型 | 暂缓 | 已确认缺口在 Flutter 内解决，目前无跨框架收益证据 |
| 五个受保护仓库 | PASS | HEAD 和精确 Git 状态一致；不声称重新校验既有脏文件的字节身份 |

版本：2.3.1-tv-lab.1+20303；ARMv7 分包实际 versionCode 为 203031（既有 ABI 编码规则）。启动器标签：KazumiTV Flutter Lab。APK SHA-256：`7dfcf3f4fc2262a8e1c2922e73015acdc6ce18767eff0b449119ff7f42533e59`。

中文实施记录、逐次日志、JSON、patch、APK 与重跑脚本已保存在本机任务目录 `kazumi-flutter-tv-lab-20261001`；最终证据入口为 `evidence/final-result.json`、`README-接手.md`。没有部署、设备安装或替换 Kotlin main。


后续架构迭代见 [本轮完整验收](FLUTTER_TV_ARCHITECTURE_ACCEPTANCE.md)：366 项最终测试通过，本页首轮数据与 APK 保留为历史验收点。
