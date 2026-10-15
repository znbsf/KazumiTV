# PR #12 模拟器验收（2026-10-15 UTC）

结论：API 9 官方规则线上链路、取消后恢复和重复设置分类的主要路径通过。本次没有确认需要追加代码修复的问题。PR 仍为草稿，未合并、未发布；这不是目标电视或所有站点验收。

## 构建与隔离

- 使用 [CI 38591191138](https://github.com/znbsf/KazumiTV/actions/runs/38591191138) 的 x86_64 候选 APK，没有本地 Android 构建。CI 已通过 869 项测试、三个 ABI 构建与校验。
- PR head：`dae2bbede53f225a3f0c135181f0981f502ddcce`；APK receipt 的测试合并源码：`9c422bb7113c67daaa7abc8de91bd88d741dbd80`。两者不是同一个 SHA。
- APK SHA256 实测与 receipt 一致：`c164c569e75895069b899ef484f158c8726cfb55b2c7eb9a248f5f495f5a5fde`。
- 包名 `com.znbsf.kazumi.fluttertv.candidate`，versionCode 203254，versionName `0.4.0-ci`。
- Android API 36 Google TV x86_64，1920×1080，2 核，无音频、无窗口。为本任务新建独立 userdata；原持久模拟器已经安装同包名 preview.13（204234），所以没有在其上覆盖安装、降级、清数据或卸载。
- 操作为遥控按键与坐标点击混合，不宣称全程纯遥控验收。站点公开可读，没有登录、验证码绕过或限制绕过。

## 结果与证据

原始证据位于本任务工作区 `qa-20261015/`，未公开上传原始日志或媒体画面。

| 场景 | 结果 | 证据 |
| --- | --- | --- |
| 官方 giriGiriLove 2.5 / API 9 导入 | 显示导入成功，规则数从 2 变 3 | `07-rule-installed.png` |
| 搜索→详情→选集→播放 | Fate 搜索中该源有 2 条结果；选中 UBW 后 27 集，实际视频播放，暂停时 01:27 / 50:38 | `12-sources.png`、`13-giri-results.png`、`14-giri-episodes.png`、`17-paused-controls.png` |
| 换源界面 Back 取消 | 取消前后 PAUSED，位置均为 87378 ms，焦点恢复到“播放” | `media-after-giri.txt`、`media-source-cancel.txt`、`source-cancel.xml` |
| 取消后重新换源 | 选择 7sefun；00 集无法直接对应时提供人工选集，选择第 01 集后成功播放，暂停为 00:32 / 47:40 | `switch-result.xml`、`media-switch-result.txt` |
| 加载期间真正取消并重试 | 切第 02 集后取消，出现“已取消加载，可重试当前集或选择其他线路”；点重试后第 02 集播放至 00:02 / 47:40 | `load-cancel.xml`、`cancel-retry-recovered.xml` |
| 播放退出 | MediaSession inactive、NONE、position 0 | `media-final.txt` |
| 重复点击当前设置分类 | 播放设置滚动到较低位置后重复点击当前分类，可见条目及坐标保持；切换操作分类正常 | `settings-scrolled-before.xml`、`settings-scrolled-after.xml`、`settings-operation.xml` |

来源辨识边界：入口元数据为 Fate/stay night（2006），实际手工选择的源条目为 Unlimited Blade Works。此记录证明所选源解析链路，不证明自动匹配了 2006 作品。换源人工选择第 01 集为从头播放，不是精确续播验证。

两次较早取消尝试因截图/工具延迟而在播放已经开始后才执行，排除在取消成功证据之外。设置“自定义按键”嵌套页未确认进入，不能据此宣称设备上的嵌套返回通过；相关逻辑仍只有自动测试覆盖。

## 尚未覆盖

未在设备注入永不完成的 load/init/unload，也没有自然发生解析超时；受控超时与旧 Future 隔离依据已有 red/green 测试。取消错误不等于网络解析失败。WebView 初始化卡住和原生资源最终释放仍不在修复保证内。

未覆盖真实验证码/Cookie 挑战、老 Android/WebView、目标电视、独立鼠标 hover、长时播放、音画同步及精确 seek。MediaSession 不是独立的原生播放时钟证据。

## 收尾

专用模拟器正常 `emu kill` 后，所属 emulator / qemu 两进程均已退出；退出前会话为 inactive/NONE。主机输出保持静音，音量约 4%。未操作电视、手机或 Quest，未改变电源计划、网络、签名、凭据或 main 保护规则。没有遗留正在运行的验收或本地构建。

GitHub 最后核对：2026-10-15 02:38 UTC 左右，PR #12 open/draft，head 仍为上述提交，base main `ae2d9dab5b036cdde568d6b714ce498fb75a7a3b`，未合并。

公开同步状态：首次写入被自动审批拒绝；用户随后明确批准“补上吧”，依据新增授权重试成功，issue #11 与 PR #12 正文均已读回确认一致，没有新增重复评论。本地记录尚未提交或推送。后续电视验收另见 [实机记录](ISSUE11-TV-QA-20261015.md)。
