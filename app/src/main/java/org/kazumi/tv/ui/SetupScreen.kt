@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.tv.material3.*
import org.kazumi.tv.data.NetworkSettings

@Composable
fun SetupScreen(onCancel: (() -> Unit)? = null, catalogContent: @Composable () -> Unit = { RuleCatalogScreen() }, onComplete: () -> Unit) {
    val context=androidx.compose.ui.platform.LocalContext.current
    val store=remember { org.kazumi.tv.rules.RuleStore(context) }
    var step by rememberSaveable { mutableIntStateOf(0) }
    val next = remember { FocusRequester() }
    LaunchedEffect(step) { withFrameNanos { }; next.requestFocus() }
    BackHandler(step > 0 || onCancel!=null) { if(step>0)step-- else onCancel?.invoke() }
    Column(Modifier.fillMaxSize().background(KazumiColors.background).padding(40.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text("KazumiTV · 初始设置", style = KazumiType.heading)
        Text("${step + 1} / 4   ·   ${listOf("欢迎使用", "网络镜像", "添加来源", "检查准备情况")[step]}", color = KazumiColors.accent)
        Box(Modifier.weight(1f)) {
            when(step) {
                0 -> Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text("先准备好连接与播放来源", style = KazumiType.heading)
                    Text("KazumiTV 是独立的原生电视版本，基于 Kazumi 开源项目开发。应用通过规则检索第三方站点。本项目不托管影视资源；播放和离线下载内容来自所选第三方站点。")
                    Text("已提供 7sefun 和 DM84 两个内置来源。接下来可设置镜像、添加和更新来源；以后也能从设置重新进入。")
                    Text("当前测试版通过安装包更新，不会从上游手机应用渠道下载更新。", style = KazumiType.caption)
                }
                1 -> NetworkOptions()
                2 -> catalogContent()
                3 -> Column(verticalArrangement=Arrangement.spacedBy(14.dp)) {
                    val all=store.all()
                    val enabled=all.filter { store.isEnabled(it) && runCatching { it.checkSupported() }.isSuccess }
                    Text("已安装 ${all.size} 个来源，${enabled.size} 个已启用且兼容",style=KazumiType.title)
                    Text(if(enabled.isEmpty()) "目前没有可用于检索的来源。可返回上一步添加，或先浏览节目资料，稍后从规则管理启用来源。" else "来源已准备好，可进入首页。安装和兼容性检查不代表每个第三方站点当前都能播放。",style=KazumiType.body)
                    Text("番剧资料与封面：${if(NetworkSettings.catalogMirror) "镜像加速" else "直接连接"}\n规则目录：${if(NetworkSettings.rulesMirror) "GitCode 镜像" else "GitHub 直连"}",style=KazumiType.body)
                    store.warning()?.let { Text(it,style=KazumiType.caption) }
                    Text("以后可从电视设置修改镜像、导入规则或重新进入引导。",style=KazumiType.caption)
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if(step==0 && onCancel!=null)PlayerAction("返回设置",onClick=onCancel)
            if (step > 0) Button(onClick = { step-- }) { Text("上一步") }
            Button(modifier = Modifier.focusRequester(next), onClick = { if (step < 3) step++ else onComplete() }) { Text(if (step == 3) { if(store.enabled().none { runCatching { it.checkSupported() }.isSuccess }) "仅浏览，稍后添加来源" else "完成，进入首页" } else "继续") }
            if (step == 2) Text("也可先使用内置来源，稍后再添加。", style = KazumiType.caption)
        }
    }
}

@Composable
fun NetworkOptions(onChange: () -> Unit = {}) {
    var catalog by remember { mutableStateOf(NetworkSettings.catalogMirror) }
    var rules by remember { mutableStateOf(NetworkSettings.rulesMirror) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text("网络镜像", style = KazumiType.title)
        Button(onClick = { catalog = !catalog; NetworkSettings.catalogMirror = catalog; onChange() }) { Text("番剧资料与封面：${if (catalog) "镜像加速" else "直接连接"}") }
        Text("镜像模式使用 Bangumi API 镜像与公共图片加速服务；关闭后直连 Bangumi。首页热门目录仍使用推荐目录服务。", style = KazumiType.caption)
        Button(onClick = { rules = !rules; NetworkSettings.rulesMirror = rules; onChange() }) { Text("规则目录：${if (rules) "GitCode 镜像" else "GitHub 直连"}") }
        Text("规则目录无法加载时可切换后重试。设置立即保存，不更改电视系统网络。", style = KazumiType.caption)
    }
}
