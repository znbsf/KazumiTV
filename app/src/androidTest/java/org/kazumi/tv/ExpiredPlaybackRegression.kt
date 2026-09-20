package org.kazumi.tv

import android.app.Instrumentation
import android.content.ContextWrapper
import android.content.Intent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.*
import org.json.JSONObject
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.*
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/** Real HTTP 403 recovery; stop/prepare forces the already-playing expired lease to be re-requested.
 * This isolates request expiry and UI retry; it does not claim a physical network-outage test.
 */
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
object ExpiredPlaybackRegression {
    fun run(test:Instrumentation) {
        val actual=test.targetContext
        val beforeSettings=actual.getSharedPreferences("tv_settings",0).all.toMap()
        val beforeLibrary=actual.getSharedPreferences("tv_library",0).all.toMap()
        val context=object:ContextWrapper(actual) { override fun getSharedPreferences(name:String,mode:Int)=baseContext.getSharedPreferences("expiry_fixture_$name",mode) }
        context.getSharedPreferences("tv_settings",0).edit().clear().commit()
        context.getSharedPreferences("tv_library",0).edit().clear().commit()
        val prefs=TvPreferences(context);prefs.incognito=true;prefs.danmakuEnabled=false;prefs.controlsSeconds=10;prefs.speed=1f
        val server=LeaseServer(test.context.assets.open("tracks-fixture.mp4").use { it.readBytes() })
        val rule=SourceRule(JSONObject().put("name","expiry-fixture").put("baseURL","http://127.0.0.1:${server.port}"))
        val episode=Episode("第1集","http://127.0.0.1:${server.port}/episode")
        val catalog=object:SourceCatalog {
            override val rules=listOf(rule)
            override suspend fun search(rule:SourceRule,keyword:String)=emptyList<SourceMatch>()
            override suspend fun chapters(rule:SourceRule,match:SourceMatch)=emptyList<Road>()
        }
        val activity=test.startActivitySync(Intent(actual,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        fun player():Player? {
            fun find(v:View):Player? { if(v is PlayerView&&v.player!=null)return v.player;if(v is ViewGroup)for(i in 0 until v.childCount)find(v.getChildAt(i))?.let { return it };return null }
            return find(activity.window.decorView)
        }
        fun await(label:String,predicate:()->Boolean) { repeat(250) { if(predicate())return;Thread.sleep(100) };error("timeout $label") }
        fun nodes():List<AccessibilityNodeInfo> { val out=mutableListOf<AccessibilityNodeInfo>();fun walk(n:AccessibilityNodeInfo?) { if(n==null)return;out+=n;for(i in 0 until n.childCount)walk(n.getChild(i)) };walk(test.uiAutomation.rootInActiveWindow);return out }
        fun click(text:String) { await(text) { nodes().any { it.text?.toString()==text } };var n=nodes().first { it.text?.toString()==text };while(!n.isClickable&&n.parent!=null)n=n.parent;check(n.performAction(AccessibilityNodeInfo.ACTION_CLICK));test.waitForIdleSync() }
        fun shot(name:String) { test.uiAutomation.takeScreenshot()?.let { b->java.io.File(actual.getExternalFilesDir(null),name).outputStream().use { b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it) };b.recycle() } }
        try {
            for(paused in listOf(true,false)) {
                server.expired.set(false)
                val resolves=AtomicInteger();val inFlight=AtomicInteger();val peak=AtomicInteger()
                test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                    key(paused) { PlaybackSessionScreen(Subject(19000923,"地址失效测试","",""),rule.name,episode,
                        initialRoads=listOf(Road("测试线路",listOf(episode))),sourceCatalog=catalog,
                        resolveEpisode={ _,_->
                            val active=inFlight.incrementAndGet();peak.updateAndGet { maxOf(it,active) }
                            try { val attempt=resolves.incrementAndGet();delay(150)
                                PlaybackRequest("http://127.0.0.1:${server.port}/${if(attempt==1) "lease" else "fresh"}.mp4",emptyMap(),"第1集",mimeType="video/mp4")
                            } finally { inFlight.decrementAndGet() }
                        },onClose={}) }
                } } } }
                await("initial real playback") { var ok=false;test.runOnMainSync { val p=player();ok=p!=null&&p.playbackState==Player.STATE_READY&&(p.currentPosition>=2500)&&(p.videoSize.width>0) };ok }
                var saved=0L
                test.runOnMainSync {
                    val p=checkNotNull(player());if(paused)p.pause();saved=p.currentPosition
                    server.expired.set(true)
                    // Force a new HTTP read without changing the media, desired state or position.
                    p.stop();p.prepare()
                }
                await("real HTTP 403 error") { nodes().any { it.text?.toString()?.contains("HTTP 403")==true } }
                check(server.forbidden.get()>0)
                shot("expired-${if(paused) "paused" else "playing"}-error.png")
                click("重新加载")
                await("fresh URL ready at saved position") {
                    var ok=false;test.runOnMainSync { val p=player();ok=resolves.get()==2&&p!=null&&p.playbackState==Player.STATE_READY&&p.currentPosition>=saved-350&&p.playWhenReady==!paused&&((p as? ExoPlayer)?.videoDecoderCounters?.renderedOutputBufferCount ?: 0)>0 };ok
                }
                if(paused) {
                    var at=0L;test.runOnMainSync { at=checkNotNull(player()).currentPosition };Thread.sleep(900)
                    test.runOnMainSync { check(kotlin.math.abs(checkNotNull(player()).currentPosition-at)<250) }
                } else {
                    await("fresh playback continues") { var ok=false;test.runOnMainSync { ok=(player()?.currentPosition ?: 0)>saved+1500 };ok }
                }
                check(resolves.get()==2&&peak.get()==1&&inFlight.get()==0)
                shot("expired-${if(paused) "paused" else "playing"}-recovered.png")
            }
            val cancelled=AtomicBoolean();val pending=AtomicInteger();val closed=mutableStateOf(false)
            test.runOnMainSync { activity.setContent { CompositionLocalProvider(LocalContext provides context) { KazumiTheme(false) {
                if(!closed.value)PlaybackSessionScreen(Subject(19000924,"取消重解析","",""),rule.name,episode,
                    initialRoads=listOf(Road("测试线路",listOf(episode))),sourceCatalog=catalog,
                    resolveEpisode={ _,_->pending.incrementAndGet();try { awaitCancellation() } finally { pending.decrementAndGet();cancelled.set(true) } },onClose={ closed.value=true })
            } } } }
            await("one pending resolver") { pending.get()==1 }
            click("返回选集 / 换源")
            await("resolver cancelled on exit") { closed.value&&cancelled.get()&&pending.get()==0 }
        } catch(e:Throwable) { runCatching { shot("expired-playback-failure.png") };throw e }
        finally {
            test.runOnMainSync { activity.setContent { };activity.finish() };test.waitForIdleSync();server.close()
            context.getSharedPreferences("tv_settings",0).edit().clear().commit()
            check(beforeSettings==actual.getSharedPreferences("tv_settings",0).all)
            check(beforeLibrary==actual.getSharedPreferences("tv_library",0).all)
        }
    }
    private class LeaseServer(private val media:ByteArray) {
        val expired=AtomicBoolean();val forbidden=AtomicInteger()
        private val socket=ServerSocket(0,10,java.net.InetAddress.getByName("127.0.0.1"))
        val port=socket.localPort
        private val closed=AtomicBoolean()
        init { Thread { while(!closed.get()) { val client=try { socket.accept() } catch(_:Exception) { break };Thread { serve(client) }.apply { isDaemon=true;start() } } }.apply { isDaemon=true;start() } }
        private fun serve(client:Socket) { try { client.use { s->
            val reader=s.getInputStream().bufferedReader();val path=reader.readLine()?.split(' ')?.getOrNull(1) ?: return
            var range:String?=null
            while(true) { val line=reader.readLine() ?: break;if(line.isEmpty())break;if(line.startsWith("Range:",true))range=line.substringAfter(':').trim() }
            val out=s.getOutputStream()
            if(path=="/lease.mp4"&&expired.get()) { forbidden.incrementAndGet();out.write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".toByteArray());return }
            val offset=range?.substringAfter("bytes=")?.substringBefore('-')?.toIntOrNull() ?: 0
            if(offset !in 0 until media.size)return
            val status=if(offset>0)"206 Partial Content\r\nContent-Range: bytes $offset-${media.lastIndex}/${media.size}\r\n" else "200 OK\r\n"
            out.write(("HTTP/1.1 $status"+"Content-Type: video/mp4\r\nContent-Length: ${media.size-offset}\r\nConnection: close\r\n\r\n").toByteArray());out.write(media,offset,media.size-offset)
        } } catch(_:Exception) { } }
        fun close() { closed.set(true);socket.close() }
    }
}
