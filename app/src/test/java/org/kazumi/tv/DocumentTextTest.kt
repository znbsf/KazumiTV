package org.kazumi.tv

import java.io.*
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.data.DocumentText
import org.kazumi.tv.data.DiagnosticLog

class DocumentTextTest {
    @Test fun successfulProviderWriteAndReadPreservesUtf8Exactly() {
        val raw="{\"title\":\"中文番剧🌙\"}"
        var closed=false
        val stream=object : ByteArrayOutputStream() { override fun close() { closed=true; super.close() } }
        DocumentText.write(raw) { stream }
        assertTrue(closed)
        assertArrayEquals(raw.toByteArray(Charsets.UTF_8),stream.toByteArray())
        assertEquals(raw,DocumentText.read(100) { ByteArrayInputStream(stream.toByteArray()) })
    }
    @Test fun missingOrDeniedProviderIsAFailure() {
        assertTrue(runCatching { DocumentText.read(10) { null } }.isFailure)
        assertTrue(runCatching { DocumentText.write("report") { null } }.isFailure)
        assertTrue(runCatching { DocumentText.write("report") { throw SecurityException("denied") } }.isFailure)
    }
    @Test fun partialWriteOrCloseFailureCannotBeReportedAsSuccess() {
        var closed=false
        val partial=object : OutputStream() {
            var count=0
            override fun write(value:Int) { if(++count>2)throw IOException("full") }
            override fun close() { closed=true }
        }
        assertTrue(runCatching { DocumentText.write("report") { partial } }.isFailure)
        assertTrue(closed)
        val closeFailure=object : ByteArrayOutputStream() { override fun close() { throw IOException("provider failed to close") } }
        assertTrue(runCatching { DocumentText.write("report") { closeFailure } }.isFailure)
        closed=false
        val flushFailure=object : ByteArrayOutputStream() {
            override fun flush() { throw IOException("provider failed to flush") }
            override fun close() { closed=true; super.close() }
        }
        assertTrue(runCatching { DocumentText.write("report") { flushFailure } }.isFailure)
        assertTrue(closed)
    }
    @Test fun oversizedOrBrokenReadsCloseTheProviderAndRejectInput() {
        var closed=false
        val oversized=object : ByteArrayInputStream("12345".toByteArray()) { override fun close() { closed=true; super.close() } }
        assertTrue(runCatching { DocumentText.read(4) { oversized } }.isFailure)
        assertTrue(closed)
        closed=false
        val broken=object : InputStream() {
            override fun read():Int { throw IOException("unavailable") }
            override fun close() { closed=true }
        }
        assertTrue(runCatching { DocumentText.read(4) { broken } }.isFailure)
        assertTrue(closed)
    }
    @Test fun exportedDiagnosticBytesContainOnlyTheWhitelistedReport() {
        val log=DiagnosticLog(clock={42})
        log.resolver("Cookie: private-session")
        log.resolver("Authorization: Bearer private-token")
        log.resolver("https://example.invalid/show?token=private")
        log.record(DiagnosticLog.Kind.PLAYER_ERROR,code=2004,http=403)
        val output=ByteArrayOutputStream()
        DocumentText.write(log.report("0.3.3","143.0.1.2",36)) { output }
        val raw=output.toString(Charsets.UTF_8.name())
        listOf("Cookie","Authorization","private","example.invalid","https://").forEach { assertFalse(raw.contains(it)) }
        val root=org.json.JSONObject(raw)
        assertEquals(setOf("schema","scope","appVersion","webViewVersion","androidSdk","dropped","events"),root.keys().asSequence().toSet())
        assertEquals(1,root.getJSONArray("events").length())
        assertEquals(2004,root.getJSONArray("events").getJSONObject(0).getInt("code"))
    }
}
