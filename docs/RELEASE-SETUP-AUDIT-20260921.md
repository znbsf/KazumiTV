# 原生发行与初始引导审查（2026-09-21）

范围仅 B06/B07/B10/B14。读取当前 README、THIRD_PARTY_NOTICES、LICENSES、main/res、main/assets、应用 manifest/build 配置、TvApp 设置/引导入口、SetupScreen、S4SetupRegression，以及本机已有 release APK 的许可条目。未构建、安装或操作设备。

|项|当前证据|结论与剩余|
|---|---|---|
|B06 品牌与资源|main/res 只有独立 kazumitv_mark/banner 矢量及播放器布局；未打包字体/人物图片；README区分在线海报与品牌资源|当前原生未见上游人物图标残留。保留README在线截图版权说明。不能把旧Flutter资产授权状况当成原生许可状况|
|B07 许可和源码|根GPL全文、Apache全文、jsoup MIT及上游署名已跟踪；git index无160000 gitlink|新增确认 Public Suffix List 数据MPL-2.0，已补notice索引与原样声明。传递依赖全量SBOM未产生；这次不宣称全依赖许可审计完成|
|B07 APK分发|已有APK仅查到部分AndroidX/jsoup许可与OkHttp publicsuffix NOTICE，没有项目GPL全文和完整依赖索引；设置页只显示GPL简述|发行材料应附GPL/第三方notice及精确对应源码标签；建议后续打包本地可读许可。未因为清理旧README而删除GPL来源归属|
|B10 更新身份|applicationId=com.znbsf.kazumi.compose.tv；manifest原生标签；README下载znbsf/KazumiTV；Setup明确手动APK更新|未发现跳去上游手机APK的自动更新路径。仍缺长期正式签名方案，当前release使用开发签名；不改签名、不宣称自动升级已完成|
|B14 初始引导|四步、镜像开关立即保存、添加/更新来源、完成页实际检查启用兼容数、可仅浏览、设置重入可返回|S4SetupRegression验证受控失败重试和最后完成，但未覆盖真正干净安装与系统杀进程恢复。欢迎文案“不存储视频”与离线下载矛盾需修订|

GPL来源与对应源码依据根目录 LICENSE 的第4至6节；Apache NOTICE保留依据[Apache-2.0第4节](https://www.apache.org/licenses/LICENSE-2.0)。Public Suffix List 数据依据实际已打包NOTICE以及[Mozilla MPL-2.0](https://www.mozilla.org/en-US/MPL/2.0/)；本次GNU官方页面访问超时，GPL正文使用仓库完整许可证核对。本文是工程发行核验记录，不替代尚未完成的传递依赖与发行包检查。

## 本轮确定修复

已将根GPL、Apache、jsoup MIT、MPL-2.0、Public Suffix List 原样NOTICE及依赖索引打包至 `app/src/main/assets/licenses`；新增设置“开源许可与对应源码”入口，可离线阅读全文，仅展示正确原生源码/Release地址，不发送网络请求。文档由根文件复制，后续更新notice时应同步assets。首次引导文案已更正为不托管影视资源、离线下载来自所选第三方站点。等待统一构建验证打包和遥控阅读；没有修改签名或版本。仍不将已知许可材料齐备等同于未来新增传递依赖自动审计。
