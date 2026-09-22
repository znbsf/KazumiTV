@file:OptIn(androidx.tv.material3.ExperimentalTvMaterial3Api::class)
package org.kazumi.tv.ui
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Text
import org.kazumi.tv.domain.PlaybackIdentity
import org.kazumi.tv.rules.*

@Composable
internal fun RoadSelectionScreen(roads:List<Road>,currentRoad:Int,current:Episode,position:Long?,onBack:()->Unit,onSelect:(Int,Int,Long?)->Unit) {
    // A list index is valid only for this catalogue snapshot. Reloading after process
    // restoration may temporarily supply no roads, or reorder/remove a road.
    var unmatched by remember(roads) { mutableStateOf<Int?>(null) }
    val backFocus=remember { FocusRequester() }
    BackHandler { if(unmatched!=null)unmatched=null else onBack() }
    LaunchedEffect(unmatched) { withFrameNanos { }; backFocus.requestFocus() }
    Column(Modifier.fillMaxSize().background(KazumiColors.background).padding(30.dp),verticalArrangement=Arrangement.spacedBy(12.dp)) {
        if(unmatched==null) {
            PlayerAction("返回播放",Modifier.focusRequester(backFocus),onClick=onBack)
            Text("选择线路 · 仅确认同一集时继承进度",style=KazumiType.title)
            if(roads.isEmpty())Text("集表暂未恢复，可返回播放后重试。",style=KazumiType.caption)
            LazyColumn(verticalArrangement=Arrangement.spacedBy(8.dp),modifier=Modifier.weight(1f)) {
                items(roads.indices.toList()) { index ->
                    PlayerAction((if(index==currentRoad) "✓ " else "")+roads[index].title.ifBlank { "线路 ${index+1}" }) {
                        val match=PlaybackIdentity.matchingEpisode(current,roads[index].episodes)
                        if(match==null)unmatched=index else onSelect(index,match,position)
                    }
                }
            }
        } else {
            val next=unmatched!!
            Row(horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                PlayerAction("返回线路",Modifier.focusRequester(backFocus)) { unmatched=null }
                PlayerAction("返回播放",onClick=onBack)
            }
            Text(roads[next].title.ifBlank { "线路 ${next+1}" },style=KazumiType.title)
            Text("无法确认同一集，请手动选择；所选集将从头播放。",style=KazumiType.caption)
            if(roads[next].episodes.isEmpty())Text("这条线路没有可用集数，请选择其他线路。",style=KazumiType.body)
            else key(next) { EpisodeBrowser(roads[next].episodes.map { it.title },modifier=Modifier.weight(1f)) { index -> onSelect(next,index,0L) } }
        }
    }
}
