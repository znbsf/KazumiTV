@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text

/** Offline-readable license copies; entering this page never contacts a service or opens a browser. */
@Composable
fun LicensesScreen(modifier:Modifier=Modifier) {
    val context=LocalContext.current
    val documents=remember { linkedMapOf(
        "来源、依赖与署名" to "THIRD_PARTY_NOTICES.md",
        "GNU GPL 3.0" to "GPL-3.0.txt",
        "Apache License 2.0" to "Apache-2.0.txt",
        "jsoup MIT" to "jsoup-MIT.txt",
        "Mozilla Public License 2.0" to "MPL-2.0.txt",
        "Public Suffix List 原始声明" to "OkHttp-publicsuffix-NOTICE.txt") }
    var document by rememberSaveable { mutableStateOf<String?>(null) }
    val first=remember { FocusRequester() }
    LaunchedEffect(document) { withFrameNanos { };first.requestFocus() }
    BackHandler(document!=null) { document=null }
    if(document==null) {
        LazyColumn(modifier,verticalArrangement=Arrangement.spacedBy(12.dp)) {
            item { Text("开源许可与对应源码",style=KazumiType.heading) }
            item { Text("本应用基于 Kazumi 开源项目迁移，按 GPL-3.0 提供源码。以下许可全文已随安装包保存，可离线阅读。",style=KazumiType.body) }
            item { Text("当前原生源码：https://github.com/znbsf/KazumiTV\n发行与对应源码标签：https://github.com/znbsf/KazumiTV/releases\n原项目：https://github.com/Predidit/Kazumi",style=KazumiType.caption) }
            item { Text("下载与安装版本同名的 Release 标签源码；开发版本请使用随该测试包提供的源码提交记录。原生与 Legacy 的源码标签不同。",style=KazumiType.caption) }
            itemsIndexed(documents.keys.toList()) { index,title->
                PlayerAction(title,if(index==0)Modifier.focusRequester(first) else Modifier) { document=title }
            }
        }
    } else {
        val text=remember(document) { runCatching { context.assets.open("licenses/${documents.getValue(document!!)}").bufferedReader().use { it.readText() } }.getOrElse { "本地许可文件读取失败，请查阅仓库 LICENSE 与 THIRD_PARTY_NOTICES.md。" } }
        Column(modifier,verticalArrangement=Arrangement.spacedBy(12.dp)) {
            PlayerAction("返回许可目录",Modifier.focusRequester(first)) { document=null }
            Text(document!!,style=KazumiType.title)
            Text("方向键上下翻阅许可正文",style=KazumiType.caption)
            // Bounded blocks ensure each focus target fits a TV viewport, including long license paragraphs.
            val blocks=remember(text) { text.lines().flatMap { line->if(line.isEmpty())listOf("") else line.chunked(100) }.chunked(8).map { it.joinToString("\n") } }
            LazyColumn(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(10.dp)) {
                itemsIndexed(blocks) { _,block->
                    var focused by remember { mutableStateOf(false) }
                    Text(block,style=KazumiType.body,modifier=Modifier.fillMaxWidth().background(if(focused)KazumiColors.surface else KazumiColors.background)
                        .onFocusChanged { focused=it.isFocused }.focusable().padding(8.dp))
                }
            }
        }
    }
}
