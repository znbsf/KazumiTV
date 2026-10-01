package org.kazumi.tv.data

import java.io.InputStream
import java.io.OutputStream

/** Provider streams are closed on every outcome; success includes flush and close. */
object DocumentText {
    private val reader=CancellableDocumentReader()
    suspend fun readCancellable(maxChars: Int, cancelOpen: () -> Unit = {}, open: () -> InputStream?): String =
        reader.read(maxChars,cancelOpen,open)

    fun read(maxChars: Int, open: () -> InputStream?): String {
        require(maxChars in 1..10_000_000)
        val stream=open() ?: error("无法读取文件")
        return stream.bufferedReader(Charsets.UTF_8).use { BoundedText.read(it,maxChars) }
    }

    fun write(raw: String, open: () -> OutputStream?) {
        val stream=open() ?: error("无法写入文件")
        stream.use { it.write(raw.toByteArray(Charsets.UTF_8)); it.flush() }
    }
}
