# 首轮上游提交选择（2026-10-01）

基础：Flutter TV `c54b2fd492a4baa4f5e8d604a2b2c83593ce0cda`，所含官方基线`1b395a501f7712d17adbe77a95af65743bf736f9`。
本轮冻结上游`0ea0bbd455a4ce4d30927f84cd50d1d2b2308a18`，其间共45提交。只吸收下列独立修复，不把“观察过最新上游”写成“已全量升级”。

| 提交 | 价值 | 依赖与TV回归风险 | 决定及原因 |
| --- | --- | --- | --- |
| [1317f20d98515c7ddf52faedf10dc7a5f9a1f8d4](https://github.com/Predidit/Kazumi/commit/1317f20d98515c7ddf52faedf10dc7a5f9a1f8d4) | 启动时尊重用户的WebDAV历史同步开关 | 开关、init/syncHistory接口已有；无新包。须核总开关/历史开关组合及失败处理 | 已应用原patch；避免关闭历史同步时仍自动合并 |
| [1bb6159a8476df7ba4f5bc6ee7cc39ec2934a51f](https://github.com/Predidit/Kazumi/commit/1bb6159a8476df7ba4f5bc6ee7cc39ec2934a51f) | 满10条历史时重搜已有词不误删另一个词 | 基线已有去重/淘汰/保存，保留TV generation与分页；不依赖父提交ECH | 已应用原patch；TV输入成本高，历史完整性有价值 |
| [241ec54ec6f76ccd56d74a9905887d8e6f643224](https://github.com/Predidit/Kazumi/commit/241ec54ec6f76ccd56d74a9905887d8e6f643224) | XPath非2xx验证码响应进入既有验证流程 | rawError、Dio响应及挑战检测器已存在；只改变启用antiCrawler的XPath错误分类。API/普通错误/取消须保持 | 已应用原patch及上游4个测试；不升级HTTP客户端/媒体库。真实验证码未验证 |
| [cd9bc04c3949c1dcfd8f1a791a079ae140e7a600](https://github.com/Predidit/Kazumi/commit/cd9bc04c3949c1dcfd8f1a791a079ae140e7a600) | 播放退出减少loading闪烁 | 依赖fullscreen布局重构，4个旧hunk均不匹配TV分支；与TV面板/返回重叠 | 暂缓；收益不足以扩大首轮播放器布局迁移 |
| media-kit、Flutter、ECH依赖升级 | 可能提供新兼容或网络能力 | 会改变定制libmpv、SDK/金图或请求层；需要单独版本/故障对照 | 暂缓；首轮保留Flutter3.47.3、media-kit994及锁文件 |
| 收藏布局、截图、弹幕、菜单与其他平台UI | 各有产品价值 | 需要逐页TV焦点/普通版回归，部分仅桌面或触控 | 后续按真实需求另审，不捆绑首轮 |

三项修改的旧上下文在固定基线唯一匹配；实际`git apply --check`及`git diff --check`均通过。完整官方SHA/父提交/文件patch、45条清单及应用哈希保存在任务`evidence/upstream-candidates.json`、`upstream-application.json`及`upstream-patches/`。

**本地自动回归已通过：336 PASS / 0 FAIL / 0 SKIP。** 满额历史丢失有旧代码 RED / 修复 GREEN 对照，XPath patch 的上游 4 项测试通过，CLI 分析及基线/实验 ARMv7 构建通过。初始沙箱与 --no-pub 插件注册问题的失败证据已保留；正常批准流程以普通用户运行工具，未提权或改系统设置。启动时真实 WebDAV 和真实验证码操作尚未验证。详细结果见[首轮验收](FLUTTER_TV_LAB_ACCEPTANCE.md)。

本文件保留首轮3项选择的历史回执；第三轮增加屏蔽规则同步和简繁转换，完整45提交冻结取舍及最终集中复验见 [上游逐项取舍](FLUTTER_TV_UPSTREAM_DISPOSITION.md)。
