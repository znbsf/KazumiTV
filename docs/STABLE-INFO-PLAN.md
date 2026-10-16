# 稳定播放器精简INFO方案

2026-10-15：用户授权先合并PR12，再尝试精简INFO，完成后考虑发布；不授权合并新的INFO PR或发布Release。PR12已正常合并为 `286ab90d7f59279fdd01675002cad4b3eacf6b41`。合并前head为ab5ea883，871项与三ABI成功，无reviews/未解决review threads；main有效规则为禁止删除及非快进，无必需审批/checks，未绕过或修改保护。经典保护连接器403，既有CLI核对404，不能把403直接解释为无保护。

独立分支 `feat/stable-playback-info` 从最新main建立；原本地文档ed555894保留在旧分支，完整带入新分支为8ca653f4。preview源码5f94fa70、文档135c202b只读参考，不修改preview。

## 源码评估

- preview `lib/pages/virtual_tv/tv_opapp_overlay.dart:229` 的compact-now-next是底部小透明卡（90%宽、最大720，surface alpha .66）；整个TvOpAppOverlay还依赖频道rail、TvOverlayChannel、navigation/details等层及大量频道回调，不能整文件移植。
- preview `video_page.dart:196` 的_showTvInfo依赖TvRuntime、排期与TvEpisodeMetadataClient，INFO仅在virtualTv非空时启用；`player_item.dart:441`普通播放仍走诊断。
- preview `tv_info_panel.dart`为详细资料面板、TvProgramPoster等；`tv_episode_metadata.dart:33`另取官方subject/episodes，TTL一小时、32项cache/请求去重、每页100且最多两页；ep优先sort回退，重复/非正整数身份排除。这不是小卡必需能力，暂不移植。官方episode没有图，不把番剧海报称单集剧照。
- 稳定版 `player_keyboard_shortcuts.dart:372`已有INFO/蓝色键到showdetails，`player_item.dart:424,508`目前打开诊断。诊断保留在设置“播放信息”；新增单独节目INFO入口与键行为。
- 稳定 `player_item_panel.dart:603,966`维护显式底部焦点顺序及TvPlayerAction；在设置前加入同风格INFO动作，注册/释放FocusNode。现有`TvPlayerSidePanel` surface alpha .64可复用，不带个人频道theme或全屏遮罩。
- `VideoPageController.playbackEpisode`优先已播放集，区别预选集；`roadList.identifier/data`配对边界检查后可显示来源标签。BangumiItem的nameCn/name/images与当前来源名已在内存；离线使用offlinePluginName。封面URL已有不等于像素已缓存，图片miss仍可能联网，必须placeholder/error降级。复用NetworkImgLayer现有缓存与限尺寸解码。

## MVP与工作量

小：只抽纯展示卡和播放快照（番剧名、来源已有集标签、可用海报/来源），接入一个INFO动作、关闭/焦点恢复；不请求节目元数据API。下一集仅在既有相邻来源标签能唯一确认连续普通集数时显示，不把列表索引当跨季集数。

中：若要求正式单集标题/简介，需要独立元数据服务、联网失败/缓存/身份映射及迟到响应保护；本机已有官方API连接超时证据，工作量主要在兼容与验收，不是加几行文案。

大：完整移植频道导航、EPG/排期、回频道/从头看等会引入虚拟电视生命周期，超出本次稳定INFO范围。

本次选择小方案：提取视觉思想，在稳定目录实现独立纯展示组件及可复用弹层生命周期；不建立跨分支包，不整提交cherry-pick preview。打开/关闭不调用pause/play/seek；单层Back关闭并恢复原按钮焦点，避免preview多层Back语义。防重复打开，路由销毁仅移除自己拥有的弹层，不影响其他对话框。播放状态变化只读展示。

## 验证与发布顺序

先补widget/数据测试：缺字段/空路线/越界/非标准与重复集数；主题明暗与透明度、长标题/窄屏/大字；INFO/蓝键、Back/返回按钮、重复打开关闭、焦点恢复及父路由销毁；与播放器快捷键隔离，播放/暂停状态不变。再实现并运行相关回归、全量测试与静态检查，必要独立QA构建/设备验收。封面失败不得阻塞关闭或播放。

先合并修复已完成。精简INFO另开draft PR，完成测试和代表性设备验收后再讨论新稳定版；不把未验证功能直接塞入已通过的PR12，也不由此次授权推导发布许可。当前状态仍以PROJECT-STATUS.md为入口。
