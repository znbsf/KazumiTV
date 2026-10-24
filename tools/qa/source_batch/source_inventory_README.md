# 来源清单与计划生成

只负责官方当前目录快照、生产模型预检及现有运行器的输入计划；不启动设备、播放器、
网络代理或验证码操作，不改变原始规则和已安装规则。播放执行仍使用同目录 run.py。
当前状态见项目 docs/PROJECT-STATUS.md；原始快照及结果仅留私有 artifact。

## 固定快照

~~~powershell
python tools/qa/source_batch/source_inventory.py --output PRIVATE_DIR --expected-commit FULL_SHA
~~~

入口先核对官方仓库身份和默认分支，固定该次 commit；下载 index 及目录所列规则，
不扫描或下载全部历史 JSON。逐文件保存原字节，校验 Git blob SHA-1，另记原文件
SHA-256。并发最多4、单请求25秒、单文件1MiB，不自动重试；单项失败保留缺口。
同一输出目录重开时复用已固定元数据和已核验文件，只补缺件，不重新查询移动分支；
需要新的目录版本时使用新目录。来源完整性检查不等于签名验证或播放成功。

## 生产模型预检

使用项目固定 Flutter3.47.3，从项目根目录执行：

~~~powershell
flutter test --no-pub --concurrency=1 --dart-define=SOURCE_INVENTORY_ROOT=PRIVATE_DIR tools/qa/source_batch/source_inventory_generate_test.dart
~~~

这个入口仅运行离线 Dart 工具，不构建 APK 或访问来源网站。它复用
PluginImportParser、Plugin 和 QaRuleFingerprint.fingerprint，不复制 schema 默认值。
生成 source_inventory.json 与 plans/wave-N-batch-N.json；记录生成器提交、脏状态及
工具文件摘要。生产准入失败、名称/版本不符、重复、deprecated、缺件分别保留。
raw_sha256、Git blob SHA-1、normalized_sha256 是不同算法/对象，不能直接互比。
app_rule_fingerprint 复用既有 ruleFingerprint，可关联较早批次；它也不能替代规范化摘要。

验证码声明不是本次挑战：启用验证码配置的合格源仍进入首轮，实际 stage=captcha
才停止该源后续尝试；不会启动验证码流程。未运行时挑战状态为未知。

每源3个备用作品，使用此前用户案例的明确题名；canonical_subject_id 未核实则 null。
UBW 使用包含 Unlimited Blade Works 的完整名称，不能拿 Fate 2006 或不唯一匹配代替。
names 交给现有运行器的唯一题名匹配；三个词都无匹配只算覆盖不足，不判来源失效。

## 交给既有运行器

先生成经过账本筛选的首轮计划：

~~~powershell
python tools/qa/source_batch/source_inventory.py --plan-from PRIVATE_DIR/source_inventory.json --output NEW_PLAN_DIR
~~~

将 NEW_PLAN_DIR/batch-1.json 交给已有 run.py，明确使用 --engines app --repeats 1，
沿用其精确APK/环境校验与时间预算。每批最多24个案例，不将多个内核/重复次数隐含
扩大为更多执行。plan 中 rule_file 指向私有原样快照，rule_provenance 是调用者的
快照来源声明；实际执行摘要仍由 observed_rule_snapshot 测量，不冒充签名或运行证据。

后续需把该轮 results.jsonl 和 attempts.jsonl 一起传入：

~~~powershell
python tools/qa/source_batch/source_inventory.py --plan-from PRIVATE_DIR/source_inventory.json --results RESULTS --attempts ATTEMPTS --output NEW_PLAN_DIR
~~~

可重复指定 --results/--attempts 累积已完成批次。仅 no_match/no_unique_match/
episode_missing 自动安排下一作品；解析/媒体失败转诊断，不盲换词刷成功。
成功需首帧、正进度、确认清理和实际规则摘要匹配；缓存成功不冒充新鲜解析通过。
清理分App的cleanup与宿主host_cleanup两层；两者确认才归played。宿主未确认、
字段畸形或状态自相矛盾归infrastructure_or_cleanup_unknown，不排下一候选。
旧格式缺host_cleanup明确记legacy_host_cleanup_unknown，也不强制重跑；
fresh_playback_observed单独保留已观察播放，cleanup_evidence保留两层原始值及格式，
不因此改写原始账本或声称全部清理确认。
挑战停止；环境/清理异常、身份不明、启动无终态、缺尝试账本均保留未知且不重排。
损坏/截断账本拒绝生成，不静默忽略尾行。对照不同 engine 的覆盖各自统计。

后续波次文件是候选，不应绕过账本筛选直接执行。source_coverage.json 保留目录
分母、排除原因、各源结果和未知；原输入的 plain 规则无运行时上游标签属于正常
边界，不能用调用者来源声明替换实际摘要。已有17源快照本身不意味着17源可播。
