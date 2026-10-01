package org.kazumi.tv

import java.io.*
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.data.CancellableDocumentReader

class CancellableDocumentReaderTest {
    private fun pool()=ThreadPoolExecutor(0,2,5,TimeUnit.SECONDS,SynchronousQueue<Runnable>(),
        ThreadFactory { Thread(it).apply { isDaemon=true } },ThreadPoolExecutor.AbortPolicy())
    private fun await(latch:CountDownLatch) { assertTrue("provider did not reach expected phase",latch.await(2,TimeUnit.SECONDS)) }
    private fun ignoreInterrupts(latch:CountDownLatch) { while(latch.count>0)try { latch.await() } catch(_:InterruptedException) {} }

    @Test fun cancellingBlockedReadClosesStreamAndReturnsPromptly()=runBlocking {
        val workers=pool(); val cleanup=pool(); val entered=CountDownLatch(1); val closed=CountDownLatch(1)
        val cancelled=CountDownLatch(1); val closes=AtomicInteger(0); var delivered=false
        val stream=object:InputStream() {
            override fun read():Int { entered.countDown(); ignoreInterrupts(closed); throw IOException("closed") }
            override fun close() { closes.incrementAndGet(); closed.countDown() }
        }
        try {
            val job=launch(start=CoroutineStart.UNDISPATCHED) {
                CancellableDocumentReader(workers,cleanup).read(100,{cancelled.countDown()}) { stream }; delivered=true
            }
            await(entered)
            withTimeout(500) { job.cancelAndJoin() }
            await(cancelled); await(closed)
            workers.shutdown(); assertTrue(workers.awaitTermination(2,TimeUnit.SECONDS))
            assertFalse(delivered); assertEquals(1,closes.get())
        } finally { closed.countDown(); workers.shutdownNow(); cleanup.shutdownNow() }
    }

    @Test fun cancelledOpenThatReturnsLateIsClosedAndCannotReplaceRetry()=runBlocking {
        val workers=pool(); val cleanup=pool(); val opened=CountDownLatch(1); val release=CountDownLatch(1)
        val closed=CountDownLatch(1); val reader=CancellableDocumentReader(workers,cleanup); var delivered=false
        try {
            val old=launch(start=CoroutineStart.UNDISPATCHED) {
                reader.read(100) {
                    opened.countDown(); ignoreInterrupts(release)
                    object:ByteArrayInputStream("old".toByteArray()) { override fun close() { closed.countDown(); super.close() } }
                }; delivered=true
            }
            await(opened)
            withTimeout(500) { old.cancelAndJoin() }
            assertEquals("新备份",withTimeout(2000) { reader.read(100) { ByteArrayInputStream("新备份".toByteArray(Charsets.UTF_8)) } })
            release.countDown(); await(closed); assertFalse(delivered)
        } finally { release.countDown(); workers.shutdownNow(); cleanup.shutdownNow() }
    }

    @Test fun blockingCancelCallbackCannotPreventOpenedStreamFromClosing()=runBlocking {
        val workers=pool(); val cleanup=pool(); val entered=CountDownLatch(1); val closed=CountDownLatch(1)
        val cancelling=CountDownLatch(1); val releaseCancellation=CountDownLatch(1); val closes=AtomicInteger(0)
        var delivered=false
        val stream=object:InputStream() {
            override fun read():Int { entered.countDown(); ignoreInterrupts(closed); throw IOException("closed") }
            override fun close() { closes.incrementAndGet(); closed.countDown() }
        }
        try {
            val job=launch(start=CoroutineStart.UNDISPATCHED) {
                CancellableDocumentReader(workers,cleanup).read(100,{
                    cancelling.countDown(); ignoreInterrupts(releaseCancellation)
                }) { stream }; delivered=true
            }
            await(entered)
            withTimeout(500) { job.cancelAndJoin() }
            await(cancelling); await(closed)
            workers.shutdown(); assertTrue(workers.awaitTermination(2,TimeUnit.SECONDS))
            assertFalse(delivered); assertEquals(1,closes.get())
        } finally { closed.countDown(); releaseCancellation.countDown(); workers.shutdownNow(); cleanup.shutdownNow() }
    }

    @Test fun uncooperativeOpensCannotSpawnUnboundedReaders()=runBlocking {
        val workers=pool(); val cleanup=pool(); val entered=CountDownLatch(2); val release=CountDownLatch(1)
        val reader=CancellableDocumentReader(workers,cleanup)
        try {
            val jobs=List(2) { launch(start=CoroutineStart.UNDISPATCHED) { reader.read(100) {
                entered.countDown(); ignoreInterrupts(release); ByteArrayInputStream(byteArrayOf())
            } } }
            await(entered); withTimeout(500) { jobs.forEach { it.cancelAndJoin() } }
            assertTrue(runCatching { withTimeout(500) { reader.read(100) { error("third reader must not run") } } }.exceptionOrNull() is IllegalStateException)
            assertEquals(2,workers.largestPoolSize)
        } finally { release.countDown(); workers.shutdownNow(); cleanup.shutdownNow() }
    }

    @Test fun failedAndOversizedProviderReadsCloseWithoutReturningPartialBackup()=runBlocking {
        val workers=pool(); val cleanup=pool(); val reader=CancellableDocumentReader(workers,cleanup)
        var closed=false
        try {
            assertTrue(runCatching { reader.read(3) { object:ByteArrayInputStream("1234".toByteArray()) {
                override fun close() { closed=true; super.close() }
            } } }.isFailure)
            assertTrue(closed)
            assertTrue(runCatching { reader.read(100) { null } }.isFailure)
        } finally { workers.shutdownNow(); cleanup.shutdownNow() }
    }
}
