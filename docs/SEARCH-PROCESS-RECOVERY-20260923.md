# 搜索正常入口的真实进程恢复

本轮不发新版本。使用已安装Preview6/code52电视本地配置包（SHA256 `26ae4f1e06ab978a2f4dc459051060ecc640ed89655438ddacfc18ad21252e09`），MiTV Android9。不是组件重建，也不是受控搜索结果；正常搜索UI请求真实目录服务。

## 实际步骤与证据

1. 保存设置、片库、搜索历史三项用户检查点。使用临时搜索词 `love`，实际遥控浏览多行，超过首20条页面，选择“出包王女 OVA”。未播放该节目。
2. 正常Launcher启动建立单Activity任务245，详情页保留“返回搜索”。HOME后确认电视Launcher前台，再执行 `am kill`，原PID27306消失。
3. 使用相同MAIN/LAUNCHER语义恢复原任务245，PID27900；仍为原详情和“返回搜索”，未增加额外Activity。
4. Back返回搜索，重新加载后关键词仍为love、排序相关；前后27个可见文字节点的文本及像素bounds完全一致，焦点卡片bounds均为 `[497,660][742,1020]`。
5. 不移动焦点直接按确认，重新打开同一节目详情，证明真实遥控焦点可用，不只截图相似。
6. 退出测试页面，恢复用户检查点并校验三项存储相等，移除临时搜索历史；返回正常Launcher入口。未卸载或清空用户数据。

本地忽略证据在 `artifacts/recovery-20260922`：`search-process52-normal-lifecycle.json`、`search-process-normal-{before,detail,restored-detail,restored-list,confirm}.xml`、`search-process52-viewport.json`、`search-process52-confirm.txt`、`search-process52-restored-data.txt`。

## 不计入通过的探索及剩余范围

早期工具通用无action启动建立的任务244与后续Launcher Intent不同，恢复时多开页面，Back后才看到原详情；该记录不能代表标准桌面入口验收。退出该任务后以统一Launcher语义重测得到上述结果，保留早期日志。

本轮仅证明旧电视、真实搜索结果未变化、已浏览后续页、详情后台进程回收这一条路径。不扩大为现代端、超过五页窗口淘汰、网络失败重试、所有资料入口或系统深度待机均通过。

只读代码检查发现待修边界：恢复时原focusId从服务端结果中消失，SearchScreen会清除restoreFocus但未选择替代卡片；实际焦点可能落空。此分支需要补实现及专项，当前结果未变的真实回收通过不覆盖它。
