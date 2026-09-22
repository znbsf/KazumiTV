# Preview6 发布核验

2026-09-23（Asia/Hong_Kong），已公开测试版：[v0.3.3-preview.6](https://github.com/znbsf/KazumiTV/releases/tag/v0.3.3-preview.6)。GitHub回读 draft=false、prerelease=true，发布时间为2026-09-22T17:26:48Z。

- 远端标签解引用及Release target均为 `edbfe07b76449f20bfa69f8355a7e07ba4aa74b4`，包含AGE两类发现修复与播放诊断。此后的README/核验文档提交不改变已发布二进制。
- 直接manifest回读版本 `0.3.3-preview.6` / code52。公开APK `KazumiTV-0.3.3-preview.6.apk`，10805901字节。
- APK SHA256 `e385e1f8be5087e6e363de26a7084bd36d2ea9ae368ad0ef1f19483b17c19278` 与GitHub已上传资产digest完全一致，附带SHA256SUMS.txt。
- 上传来自独立固定目录 `artifacts/release-0.3.3-preview.6`。直接DEX核验AppId/AppSecret字段均为空；签名验证通过。没有上传随后生成的本地配置包。
- 公开包构建、217项单元测试（0 failures/errors）和release lint通过。
- 同一公开包在MiTV Android9/WebView66与现代Android36/WebView143均通过：无凭证配置保存/读取/移除与密钥不回显、实际视频渲染推进、缺配置指引；播放诊断受控会话失败、脱敏JSON、本机三份保留、取消或缺少保存器和清空。
- 同一公开包AGE第12集两端各5条线路全部完成首帧、短时推进、拖动、暂停/继续。没有重测全部17源，不扩展为全目录通过。
- 两端覆盖升级后及测试后，设置、片库、搜索历史与升级前检查点完全相等（只读比较，未通过恢复旧值掩盖变化）；17条已装规则与固定清单完全一致。
- 公开包专项后，电视覆盖恢复同版本本地配置包，SHA256 `26ae4f1e06ab978a2f4dc459051060ecc640ed89655438ddacfc18ad21252e09`；安装成功、设备回读code52/Preview6，再次只读验证三项用户存储不变，并返回正常主页。现代模拟器保留无凭证公开包。

本地证据位于忽略目录 `artifacts/recovery-20260922`：`build-preview6-public.txt`、`preview6-upgrade-{tv,modern}.txt`、`preview6-public-{tv,modern}.txt`、`preview6-diagnostics-{tv,modern}.txt`、`preview6-age-{tv,modern}.txt`、`preview6-inventory-{tv,modern}.txt`、`preview6-final-data-{tv,modern}.txt`及`preview6-restored-data-tv.txt`。所有相关构建和设备操作均已终止。

未关闭：akianime第2线、ezdmw第3线、白猫第6线等来源问题，dalvdm等真实人工验证闭环、网络恢复差异、搜索进程恢复及适用TV功能台账。不做整集测试，不把本版短测或受控验证称为完整迁移完成。
