@file:androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
package org.kazumi.tv.download

import android.content.Context
import android.net.Uri
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.*
import androidx.media3.datasource.cache.*
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.offline.*
import androidx.media3.exoplayer.scheduler.Requirements
import org.kazumi.tv.data.*
import org.kazumi.tv.playback.PlaybackRequest
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.Executor
import okhttp3.CookieJar
import okhttp3.HttpUrl.Companion.toHttpUrl

class OfflineDownloads private constructor(private val context:Context) {
    private val directory=File(context.filesDir,"offline-media")
    private val database=StandaloneDatabaseProvider(context)
    val cache=SimpleCache(directory,NoOpCacheEvictor(),database)
    private val index=DefaultDownloadIndex(database)
    private val replacementJournal=context.getSharedPreferences("download_replacement",Context.MODE_PRIVATE)
    @Volatile var replacementError:String=""; private set
    private val failureStore=context.getSharedPreferences("download_failures",Context.MODE_PRIVATE)
    fun failureReason(id:String)=DownloadFailure.stored(failureStore.getString(id,null)).label
    private val execute=Executor { it.run() }
    private fun keys(id:String)=CacheKeyFactory { spec -> id+"|"+(spec.key ?: spec.uri.toString()) }
    private fun factory(id:String)=CacheDataSource.Factory().setCache(cache).setCacheKeyFactory(keys(id))
    val manager=DownloadManager(context,index,DownloaderFactory { request ->
        val metadata=DownloadMetadata.read(request.data)
        val origin=request.uri.toString().toHttpUrl()
        val client=AppHttp.streamingClient.newBuilder().cookieJar(CookieJar.NO_COOKIES)
            .addNetworkInterceptor { chain ->
                val current=chain.request(); val target=current.url
                val adjusted=if(target.scheme==origin.scheme && target.host==origin.host && target.port==origin.port) current else {
                    val builder=current.newBuilder()
                    metadata.headers.keys.filter { it.lowercase() !in listOf("user-agent","referer","origin") }.forEach { builder.removeHeader(it) }
                    builder.removeHeader("Authorization").removeHeader("Cookie").removeHeader("Proxy-Authorization").build()
                }
                chain.proceed(adjusted)
            }.build()
        val cancelled=java.util.concurrent.atomic.AtomicBoolean()
        val calls=java.util.concurrent.ConcurrentHashMap.newKeySet<okhttp3.Call>()
        val guarded=DataSource.Factory {
            var activeCall:okhttp3.Call?=null
            val delegate=OkHttpDataSource.Factory(okhttp3.Call.Factory { networkRequest ->
                client.newCall(networkRequest).also { call -> activeCall=call; calls.add(call); if(cancelled.get())call.cancel() }
            }).setDefaultRequestProperties(metadata.headers.filterKeys { it.lowercase() !in listOf("range","if-range","if-match","accept-encoding") }).createDataSource()
            object:DataSource by delegate {
                var budget=0
                private fun space() {
                    if(directory.usableSpace<RESERVE || cache.cacheSpace>=MAX_CACHE)throw DownloadRejected(DownloadFailure.SPACE)
                }
                override fun open(spec:DataSpec):Long {
                    space()
                    val key=spec.key ?: throw IOException("下载缓存标识缺失")
                    val cached=cache.getCachedSpans(key).isNotEmpty()
                    val expected=DownloadRangePolicy.strongTag(cache.getContentMetadata(key).get("custom_kazumitv_etag",""))
                    if(cached && expected==null)throw DownloadRejected(DownloadFailure.RANGE)
                    val headers=spec.httpRequestHeaders.toMutableMap()
                    // Resolver headers must not override the downloader's byte range or precondition.
                    if(cached)headers["If-Match"]=expected!!
                    val guardedSpec=spec.buildUpon().setHttpRequestHeaders(headers).build()
                    try {
                        val length=delegate.open(guardedSpec)
                        fun header(name:String)=delegate.responseHeaders.entries.firstOrNull { it.key.equals(name,true) }?.value?.singleOrNull()
                        val tag=header("ETag")
                        DownloadRangePolicy.validate(spec.position,cached,expected,delegate.responseCode,tag,header("Content-Range"),header("Content-Type"))
                        val mutation=ContentMetadataMutations()
                        DownloadRangePolicy.strongTag(tag)?.let { mutation.set("custom_kazumitv_etag",it) } ?: mutation.remove("custom_kazumitv_etag")
                        cache.applyContentMetadataMutations(key,mutation)
                        return length
                    } catch(error:Exception) { runCatching { close() }; throw error }
                }
                override fun close() { try { delegate.close() } finally { activeCall?.let { calls.remove(it) }; activeCall=null } }
                override fun read(buffer:ByteArray,offset:Int,length:Int):Int {
                    if(budget<=0) { space(); budget=1024*1024 }
                    val count=delegate.read(buffer,offset,length); if(count>0)budget-=count
                    return count
                }
            }
        }
        val sources=factory(request.id).setUpstreamDataSourceFactory(guarded)
        val downloader=DefaultDownloaderFactory(sources,execute).createDownloader(request)
        object:Downloader by downloader {
            override fun download(progressListener:Downloader.ProgressListener?) {
                DownloadManifestCheck(sources,cancelled).check(request)
                downloader.download(progressListener)
            }
            override fun cancel() { cancelled.set(true); calls.forEach { it.cancel() }; downloader.cancel() }
            override fun remove() {
                downloader.remove()
                // A task owns all of its URL generations, including obsolete manifests and segments.
                cache.keys.filter { it.startsWith(request.id+"|") }.forEach { cache.removeResource(it) }
            }
        }
    }).apply {
        maxParallelDownloads=1; minRetryCount=2; requirements=Requirements(Requirements.NETWORK_UNMETERED)
        addListener(object:DownloadManager.Listener {
            override fun onInitialized(manager:DownloadManager) { recoverReplacement(manager) }
            override fun onDownloadRemoved(manager:DownloadManager,download:Download) { failureStore.edit().remove(download.request.id).apply(); recoverReplacement(manager) }
            override fun onDownloadChanged(manager:DownloadManager,download:Download,finalException:Exception?) {
                if(download.state==Download.STATE_FAILED && finalException!=null) {
                    val chain=generateSequence<Throwable>(finalException) { it.cause }.take(12).toList()
                    val reason=chain.filterIsInstance<DownloadRejected>().firstOrNull()?.reason
                        ?: if(chain.filterIsInstance<HttpDataSource.InvalidResponseCodeException>().any { it.responseCode in listOf(401,403,410) })DownloadFailure.ADDRESS
                        else if(chain.any { it is IOException })DownloadFailure.NETWORK else DownloadFailure.OTHER
                    failureStore.edit().putString(download.request.id,reason.name).apply()
                } else if(download.state!=Download.STATE_FAILED)failureStore.edit().remove(download.request.id).apply()
                val pending=pendingReplacement()
                if(pending?.stage==ReplacementStage.ADD && pending.media.id==download.request.id)recoverReplacement(manager)
            }
        })
    }
    private fun pendingReplacement():DownloadReplacement? = try {
        replacementJournal.getString("pending",null)?.let(DownloadReplacement::read)
    } catch(_:Exception) { replacementError="下载替换记录无法读取，原记录已保留"; null }
    fun replacingId()=pendingReplacement()?.media?.id
    fun recoverPending() { if(manager.isInitialized)recoverReplacement(manager) }
    fun isReplacing(id:String)=pendingReplacement()?.media?.id==id
    private fun persistReplacement(value:DownloadReplacement?) {
        val serialized=value?.json()?.also { DownloadReplacement.read(it) }
        check((if(serialized==null)replacementJournal.edit().remove("pending") else replacementJournal.edit().putString("pending",serialized)).commit()) { "无法保存下载替换记录" }
    }
    private fun media(request:DownloadRequest)=ReplacementMedia(request.id,request.uri.toString(),request.mimeType,request.data.toString(Charsets.UTF_8))
    private fun request(value:ReplacementMedia)=DownloadRequest.Builder(value.id,Uri.parse(value.url)).setMimeType(value.mime).setData(value.metadata.toByteArray(Charsets.UTF_8)).build()
    private fun recoverReplacement(downloadManager:DownloadManager) {
        try {
            val pending=pendingReplacement() ?: return
            val current=index.getDownload(pending.media.id)
            when(ReplacementRecovery.next(pending,current?.let { media(it.request) },current?.state in listOf(Download.STATE_REMOVING,Download.STATE_RESTARTING))) {
                ReplacementAction.REMOVE -> downloadManager.removeDownload(pending.media.id)
                ReplacementAction.STAGE_ADD -> { persistReplacement(pending.copy(stage=ReplacementStage.ADD)); downloadManager.addDownload(request(pending.media)) }
                ReplacementAction.ADD -> downloadManager.addDownload(request(pending.media))
                ReplacementAction.FINISH -> { persistReplacement(null); replacementError="" }
                ReplacementAction.CONFLICT -> { replacementError="下载任务已变化，已停止自动替换" }
                ReplacementAction.WAIT -> Unit
            }
        } catch(_:Exception) { replacementError="下载地址替换未完成，重开下载页后可继续恢复" }
    }
    fun replaceResolved(expected:Download,resolved:PlaybackRequest) {
        check(manager.isInitialized) { "下载记录仍在加载" }
        check(!replacementJournal.contains("pending")) { "还有一项下载地址正在替换" }
        val current=index.getDownload(expected.request.id)
        check(current!=null && current.startTimeMs==expected.startTimeMs && current.updateTimeMs==expected.updateTimeMs && current.state==expected.state && current.stopReason==expected.stopReason && current.request==expected.request) { "任务已变化，请重新打开下载列表" }
        check(current.state in listOf(Download.STATE_FAILED,Download.STATE_STOPPED)) { "请先暂停任务" }
        require(resolved.offlineId==null)
        val uri=resolved.url.toHttpUrl(); require(uri.username.isEmpty() && uri.password.isEmpty())
        val old=DownloadMetadata.read(current.request.data)
        val metadata=DownloadMetadata(old.subject,old.title,old.resumeKey,resolved.headers,old.origin).bytes().toString(Charsets.UTF_8)
        val pending=DownloadReplacement(ReplacementMedia(current.request.id,resolved.url,resolved.mimeType,metadata))
        persistReplacement(pending)
        DownloadService.start(context,TvDownloadService::class.java)
        recoverReplacement(manager)
    }

    fun all():List<Download> = index.getDownloads().use { cursor -> buildList { while(cursor.moveToNext())add(cursor.download) } }.sortedByDescending { it.startTimeMs }
    fun enqueue(request:PlaybackRequest,subject:Subject,origin:PlaybackOrigin?):String {
        require(request.offlineId==null)
        val uri=request.url.toHttpUrl(); require(uri.username.isEmpty() && uri.password.isEmpty())
        check(directory.usableSpace>=RESERVE && cache.cacheSpace<MAX_CACHE) { "下载空间不足，请删除部分离线内容" }
        val id=DownloadMetadata.id(subject.id,request.resumeKey.ifBlank { request.url })
        check(!isReplacing(id)) { "下载地址正在替换" }
        val existing=index.getDownload(id)
        check(existing==null || existing.state==Download.STATE_FAILED) { "该集已在下载列表" }
        check(existing!=null || all().size<200) { "下载列表已满（200项）" }
        // A changed signed URL is a new byte source; require deleting the old partial task first.
        check(existing==null || existing.request.uri.toString()==request.url) { "地址已变化，请先删除旧任务再下载" }
        val data=DownloadMetadata(subject,request.title,request.resumeKey,request.headers,origin).bytes()
        val download=DownloadRequest.Builder(id,Uri.parse(request.url)).setMimeType(request.mimeType).setData(data).build()
        DownloadService.sendAddDownload(context,TvDownloadService::class.java,download,false)
        return id
    }
    fun pause(id:String) { check(!isReplacing(id)) { "下载地址正在替换" }; DownloadService.sendSetStopReason(context,TvDownloadService::class.java,id,1,false) }
    fun resume(id:String) {
        check(!isReplacing(id)) { "下载地址正在替换" }
        val task=index.getDownload(id) ?: return
        if(task.state==Download.STATE_FAILED)DownloadService.sendAddDownload(context,TvDownloadService::class.java,task.request,false)
        else DownloadService.sendSetStopReason(context,TvDownloadService::class.java,id,0,false)
    }
    fun restart(id:String) {
        check(!isReplacing(id)) { "下载地址正在替换" }
        val request=index.getDownload(id)?.request ?: return
        // Media3 serializes remove then add as RESTARTING, removing old spans before downloading.
        DownloadService.sendRemoveDownload(context,TvDownloadService::class.java,id,false)
        DownloadService.sendAddDownload(context,TvDownloadService::class.java,request,false)
    }
    fun remove(id:String) {
        if(isReplacing(id))persistReplacement(null)
        DownloadService.sendRemoveDownload(context,TvDownloadService::class.java,id,false)
    }
    fun offlineFactory(id:String):DataSource.Factory {
        check(index.getDownload(id)?.state==Download.STATE_COMPLETED) { "下载尚未完成" }
        return factory(id).setUpstreamDataSourceFactory(null).setCacheWriteDataSinkFactory(null)
    }
    companion object {
        const val RESERVE=256L*1024*1024
        const val MAX_CACHE=4L*1024*1024*1024
        @Volatile private var instance:OfflineDownloads?=null
        fun get(context:Context):OfflineDownloads=instance ?: synchronized(this) { instance ?: OfflineDownloads(context.applicationContext).also { instance=it } }
    }
}

class DownloadMetadata(val subject:Subject,val title:String,val resumeKey:String,val headers:Map<String,String>,val origin:PlaybackOrigin?) {
    fun bytes():ByteArray {
        val entry=HistoryEntry(resumeKey.ifBlank { "offline" },subject,title,0,0,origin)
        val data=JSONObject().put("version",1).put("entry",LibraryCodec.historyJson(entry)).put("headers",JSONObject(headers)).toString().toByteArray(Charsets.UTF_8)
        require(data.size<=128*1024) { "下载信息过长" }; return data
    }
    companion object {
        fun read(data:ByteArray):DownloadMetadata {
            require(data.size<=128*1024)
            val json=JSONObject(data.toString(Charsets.UTF_8)); require(json.getInt("version")==1)
            val entry=LibraryCodec.history(json.getJSONObject("entry")); val headers=json.getJSONObject("headers")
            return DownloadMetadata(entry.subject,entry.episode,entry.key,headers.keys().asSequence().associateWith { headers.getString(it) },entry.origin)
        }
        fun id(subject:Int,key:String):String=java.security.MessageDigest.getInstance("SHA-256").digest("$subject|$key".toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
