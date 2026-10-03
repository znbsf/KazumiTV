# 仓库清理与保留清单 · 2026-10-01

## 盘点与范围

整理前远端main为`e5793f08`，本任务隔离工作树干净。只读盘点18个worktree、23个本地分支、0个stash；12个worktree无跟踪/未跟踪改动，6个有未提交内容；12分支HEAD已是此main祖先。本次另建1维护分支，旧分支/worktree全部保留，“已合入”不等于本机证据可删。

盘点58份docs Markdown和根README，缺统一当前入口，旧交接仍把观看数据包写成待派工。62份跟踪Markdown唯一完全重复组为根THIRD_PARTY_NOTICES与包内副本；属于离线许可交付，保留。

## 已执行的可恢复归档

仅移动我方隔离工作树最终main测试生成且已忽略的4目录；核验无跟踪文件、无Java构建进程、无reparse point，每个文件移动前后SHA-256相等。永久删除0。

| 相对目录 | 文件数 | 字节 |
| --- | ---: | ---: |
| .gradle | 13 | 7,651,201 |
| .kotlin | 0 | 0 |
| build | 1 | 132,307 |
| app/build | 4,122 | 169,725,363 |
| 合计 | 4,136 | 177,508,871（约169.3MiB） |

保留于本机任务目录`kazumi-watch-data-20261001/cleanup-archive/20261001T084009Z/`；`manifest.json`含逐文件原/新位置、大小和哈希，统计规范化前回执也保留。完整清单不进入公共源码。恢复脚本在同任务目录`restore-hygiene-archive.ps1`，WhatIf已核验4,136个哈希且未实际移回。

```powershell
$kazumiTaskRoot = '<本机 kazumi-watch-data-20261001 任务目录的绝对路径>'
& (Join-Path $kazumiTaskRoot 'restore-hygiene-archive.ps1') `
  -Archive (Join-Path $kazumiTaskRoot 'cleanup-archive/20261001T084009Z') -WhatIf
```

核对后去掉WhatIf才恢复。脚本限定原任务工作树及4目录，遇哈希改变、reparse point或原处已有新目录则停止，不覆盖。下一次Gradle也可重新生成目录；离线依赖缓存仍保留。

## 文档整理

新增[当前状态与具体目标](PROJECT-STATUS-20261001.md)和[文档目录](README.md)，根README区分正式0.3.3/229项与开发main/247项。路线图列前三目标及长期原路线；旧交接、审查、候选加历史/已合入提示，台账补本轮增量。原正文、版本、失败及文件名不删不移动，旧链接可追溯。.gitignore已经覆盖生成物、artifacts及本机密钥，不另加宽泛ignore隐藏用户工作。

## 保留项与原因

| 对象 | 盘点观察 / 保留原因 |
| --- | --- |
| 原主目录main | c8f1ab3f，6个跟踪修改+8个未跟踪文件；用户工作，14文件状态/内容摘要前后保护，未checkout/reset/clean/stash或移走 |
| P2集成worktree | 1个未跟踪文件，归属/引用未确认，只列候选 |
| 旧Flutter完整/基础worktree | 分别122/6个未跟踪文件，不属于本轮原生main，未猜测源码/生成物边界 |
| QuickSR探索 | 10个跟踪修改+59个未跟踪文件，是独立工作，未覆盖或归档 |
| 旧focus detached baseline | 1个跟踪修改+3个未跟踪文件，不能证明废弃，保持 |
| 其他分支/worktree和原始证据 | 历史APK/设备检查点仍有引用，未删分支/worktree或prune；需原任务归属确认 |
| 离线依赖、签名材料、用户/设备数据 | 非本轮4目录，保留重建与恢复条件；不清Trash、不进行不可恢复删除 |
| 两份许可证 | 有意随APK提供，字节一致，不当垃圾 |

既有包内声明有一处相对链接`LICENSES/OkHttp-publicsuffix-NOTICE.txt`，相对于asset目录不能定位；根声明链接有效，应用LicensesScreen以离线纯文本显示并单列notice。没有运行时坏链接证明，保持根/包内字节一致，文档目录指向根声明；作为已知文档呈现例外保留。其余README/docs相对链接须通过本轮检查。

## 适用检查与交付

只改维护Markdown，生产/测试源码、构建脚本、依赖、版本、签名和规则不变。检查链接/范围/事实一致性、git空白、归档及恢复WhatIf、用户文件前后哈希；继承e5793f08功能树的247项/lint/构建，不重复构建或增加设备PASS。维护检查后按用户授权合入main并非强制推送，精确远端SHA/CI另核验；不自动Release/部署。真实焦点、SAF、Activity重建和存储instrumentation仍NOT_RUN。
