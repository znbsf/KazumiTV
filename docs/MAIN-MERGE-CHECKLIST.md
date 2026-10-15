# main 保护与合并检查

这是每次准备合并的执行清单，适用于所有后续 PR。保护规则是动态配置，下面的历史快照不能替代重新读取。不得为了合并修改规则、管理员绕过、关闭检查或强推 main。

## 固定步骤

1. 确认用户对当前 PR 的合并授权和范围；草稿、设备验收、发布是不同状态，不从 CI 通过推导授权。
2. 读取 main 的最新 SHA、经典 branch protection、仓库及继承 rulesets。逐个读取详情，检查 enforcement（active/evaluate/disabled）、ref include/exclude 是否匹配 `refs/heads/main`、bypass actors 与当前调用者绕过权限。
3. 读取 main 的有效规则列表。核对 required PR、审批数量、CODEOWNERS、旧审批失效、最后一次 push 审批、未解决讨论、required checks 的精确名字及 app/integration ID、是否要求最新 base、合并队列、线性历史/签名、删除/强推和管理员约束；以返回的规则为准，不凭印象补全。
4. 连接器若返回 403，记录缺失权限；若 URL 不受支持，记录工具边界。可使用已有授权的 GitHub CLI 做相同只读查询；不创建凭据、不改变权限。所有可用路径仍不可读时，把该部分列为未知，停止依赖该证据的合并动作。
5. 重新读取 PR：base/head SHA、draft、mergeable/mergeable_state、reviews、review threads、最新 SHA 的 checks/statuses、与 main 的落后情况。新 push 后旧 SHA 的绿色结果不算新 head 通过。`mergeable=true` 只说明内容可合并，不能替代规则、授权及验收检查。
6. 条件满足且获授权时才用允许的常规合并方式，并传入刚核对的 expected head SHA。禁止管理员 bypass、强推或直接推 main；若被保护拦下，报告具体未满足项，不能绕过。
7. 合并后读取实际 merged 状态与 merge SHA，更新 issue/PR 的“代码合并”状态；不把合并等同发布或真机验收。纯文档待办可与下一次正常分支更新一起推送；不能使用跳过 CI 标记伪造最新 head 通过。

只读 API 路径（仓库前缀 `repos/znbsf/KazumiTV/`）：

```text
branches/main
branches/main/protection
rulesets?includes_parents=true
rulesets/{id}
rules/branches/main
pulls/{number}
pulls/{number}/reviews
commits/{head_sha}/check-runs
commits/{head_sha}/status
```

## 2026-10-14 16:13 UTC 快照

后续复核（2026-10-15 07:00 UTC）：下方是历史快照。规则25095474现已匹配`~DEFAULT_BRANCH`，main的有效规则为deletion与non_fast_forward，branch元数据protected=true。没有required PR/reviews/checks规则；bypass仍为空、never。经典保护连接器403后，CLI补查为404 Branch not protected。PR12仍draft，原head四项checks成功，无reviews/review threads；legacy statuses为空（其汇总pending不是检查失败）。未修改保护，也不从这些只读结果推导合并许可。

- main：`ae2d9dab5b036cdde568d6b714ce498fb75a7a3b`，即 #10 的历史合并。#10 合并于 15:29:18 UTC；下面规则创建于 16:10:23 UTC，不应声称 #10 按这套新规则合并。
- ruleset [init / 25095474](https://github.com/znbsf/KazumiTV/rules/25095474)：仓库级 branch 规则，`enforcement=active`；ref `include=[]`、`exclude=[]`，没有目标分支。只列出 `deletion` 和 `non_fast_forward`，没有 PR 审批或 required checks 规则；`bypass_actors=[]`、`current_user_can_bypass=never`。这些是规则自身设置，不能因为 active 就说已应用到 main。
- main 有效规则接口返回 `[]`。branch 元数据 `protected=false`。连接器读取经典保护得到 403（集成权限不足），随后已有 CLI 的同一只读查询明确返回 404 `Branch not protected`。结论来自补充证据，不是把 403 当作无保护。
- #12：head `dae2bbede53f225a3f0c135181f0981f502ddcce`，base 为上述 main；open/draft，mergeable=true、mergeable_state=clean；无 reviews、无 review threads。该 head 的四项 CI 已成功（869 tests，三 ABI 候选 APK），但仍待用户后续决定和已记录的线上/设备验收。本次不转换 ready、不合并、不修改保护。
- 若希望保护 main，需要维护者把目标匹配设到 main/default branch，并按意图另选 PR、审批、checks 等规则；本快照只报告缺口，不代为配置。之后必须重新检查有效规则及当前 PR 条件。
