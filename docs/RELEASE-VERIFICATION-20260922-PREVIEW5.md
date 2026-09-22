# Preview 5 发布回读

2026-09-22，已公开 Pre-release：[v0.3.3-preview.5](https://github.com/znbsf/KazumiTV/releases/tag/v0.3.3-preview.5)。

- Release target 与远端 tag 均为 `6079a7736514ecc53ee0a238ab007c3c4a98db99`，versionName 0.3.3-preview.5 / versionCode 51。
- 公共 APK `KazumiTV-0.3.3-preview.5.apk`，10789521 字节；GitHub asset state=uploaded，远端 digest 与本地 SHA256 均为 `0b3fe7f11ebb07f5d25ca20db5d109636fcd8574679d90bd6ce469c34629009f`。同时发布 SHA256SUMS.txt。
- 上传前直接检查固定公共 APK 的 DEX，DANDAN_APP_ID / DANDAN_APP_SECRET 均为空。只上传独立发布目录中的此 APK，没有上传本地配置包。
- 最终公共包构建、204 项单元测试和 release lint 通过；两设备通过无凭证设置保存/移除、密钥不回显、视频渲染推进和缺配置指引专项。
- 同一公共包两设备通过集表验证 POST/Cookie 恢复、原播放器/暂停位置保持、睡眠到期、实际 HOME 收到 ON_STOP 后恢复不自动播放、旧挑战销毁。旧电视完成 MXdm 第 12 集两条线路短测。
- AGE 现代端 5 线短测通过、旧电视 5 线媒体发现失败，对应较早同功能本地候选 `70428765…`；未冒称最终公共包重新完成 17 源或旧电视 AGE 播放验收。
- 发布后旧电视覆盖安装本机配置包，SHA256 `9d82307595e370fdd0afd25f3ba06fd3635f3cbd8c48ec5336a361f120cae6b0`，实际回读 code51 / Preview5，已打开原主页并确认最近观看入口。未卸载、未清应用数据；此包未上传。现代模拟器保留公共包。

本地最终证据在 `artifacts/recovery-20260922`：`build-preview5-public.txt`、`preview5-public-tv.txt`、`preview5-public-modern.txt`、`preview5-catalogue-tv.txt`、`preview5-catalogue-modern.txt`、`preview5-mxdm-tv.txt`、`preview5-home.png`。固定上传文件在 `artifacts/release-0.3.3-preview.5`。

完整迁移仍未完成。旧 WebView 的 AGE 媒体发现、其他来源真实人工验证、网络恢复差异及适用 TV 功能台账继续推进；不做整集测试，不将部分通过扩大为完整验收。
