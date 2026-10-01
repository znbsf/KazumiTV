package org.kazumi.tv.data

import java.io.FilterInputStream
import java.io.InputStream
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** At most two provider reads can remain blocked. Cancellation does not wait on provider code. */
class CancellableDocumentReader(
    private val workers: ExecutorService = pool("Kazumi-document-read"),
    private val cancellationWorkers: ExecutorService = pool("Kazumi-document-close")
) {
    suspend fun read(maxChars: Int, cancelOpen: () -> Unit = {}, open: () -> InputStream?): String {
        require(maxChars in 1..10_000_000)
        return suspendCancellableCoroutine { continuation ->
            val activeStream=AtomicReference<OwnedStream?>(null)
            val task=AtomicReference<Future<*>?>(null)
            continuation.invokeOnCancellation {
                task.get()?.cancel(true)
                try {
                    cancellationWorkers.execute {
                        // A blocking remote cancellation or close must not block the UI thread.
                        activeStream.getAndSet(null)?.let { runCatching { it.close() } }
                        runCatching(cancelOpen)
                    }
                } catch(_:RejectedExecutionException) {
                    // Uncooperative providers may occupy both cleanup workers. Reads remain bounded;
                    // the interrupted reader still closes its stream if the provider returns.
                }
            }
            if(!continuation.isActive)return@suspendCancellableCoroutine
            try {
                val future=workers.submit {
                    var stream:OwnedStream?=null
                    try {
                        if(!continuation.isActive)return@submit
                        stream=OwnedStream(open() ?: error("无法读取文件"))
                        activeStream.set(stream)
                        if(!continuation.isActive)return@submit
                        val raw=stream.bufferedReader(Charsets.UTF_8).use { BoundedText.read(it,maxChars) }
                        if(continuation.isActive)continuation.resume(raw)
                    } catch(failure:Exception) {
                        if(continuation.isActive)continuation.resumeWithException(failure)
                    } finally {
                        stream?.let { owned ->
                            activeStream.compareAndSet(owned,null)
                            runCatching { owned.close() }
                        }
                    }
                }
                task.set(future)
                if(!continuation.isActive)future.cancel(true)
            } catch(_:RejectedExecutionException) {
                if(continuation.isActive)continuation.resumeWithException(IllegalStateException("文件提供者仍在处理中，请稍后重试"))
            }
        }
    }

    private class OwnedStream(private val source:InputStream):FilterInputStream(source) {
        private val closed=AtomicBoolean(false)
        override fun close() { if(closed.compareAndSet(false,true))source.close() }
    }

    companion object {
        private fun pool(name:String):ExecutorService=ThreadPoolExecutor(0,2,30,TimeUnit.SECONDS,
            SynchronousQueue(),ThreadFactory { task -> Thread(task,name).apply { isDaemon=true } },ThreadPoolExecutor.AbortPolicy())
    }
}
