package org.kazumi.tv

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.data.DiagnosticLog

class DiagnosticLogTest {
    @Test fun rawMessagesAndMetadataNeverPersist() {
        val log=DiagnosticLog(clock={42})
        val private="https://user:secret@example.invalid/path?token=private#cookie"
        listOf(private,"Cookie: session=private","Authorization: Bearer private","candidate=media host=example.invalid $private",
            "web_discovery mode=document_start\nCookie: private","page_metadata bytes=20 token=private",
            "inline_player_reference depth=0\rAuthorization: private").forEach(log::resolver)
        assertTrue(log.events.value.isEmpty())
        log.resolver("web_discovery mode=document_start")
        log.resolver("page_metadata bytes=20")
        val raw=log.report(private,"Cookie: private",35)
        listOf("private","secret","example.invalid","Cookie","Authorization","token=","https://").forEach { assertFalse(raw.contains(it)) }
        val report=JSONObject(raw)
        assertEquals("unavailable",report.getString("appVersion"))
        assertEquals(2,report.getJSONArray("events").length())
        assertEquals(setOf("time","event","stage"),report.getJSONArray("events").getJSONObject(0).keys().asSequence().toSet())
    }

    @Test fun countAndByteCapsDropOldestAndClearResets() {
        var time=0L
        val count=DiagnosticLog(capacity=3,clock={++time})
        repeat(5){count.record(DiagnosticLog.Kind.RESOLVE_START)}
        assertEquals(listOf(3L,4L,5L),count.events.value.map { it.time })
        assertEquals(2,JSONObject(count.report("0.3.3-preview.5","143.0.1.2",35)).getInt("dropped"))
        val bytes=DiagnosticLog(byteLimit=2048,clock={Long.MAX_VALUE})
        repeat(500){bytes.record(DiagnosticLog.Kind.RESOLVE_FAILURE,DiagnosticLog.Stage.INITIALIZATION,99999,599)}
        assertTrue(bytes.events.value.size<200)
        assertTrue(bytes.report("0.3.3-preview.5","143.0.1.2",35).toByteArray().size<=2048)
        bytes.clear()
        assertTrue(bytes.events.value.isEmpty())
        assertEquals(0,JSONObject(bytes.report("1.0","66.0",24)).getInt("dropped"))
    }

    @Test fun numericFieldsAndKnownStagesAreBounded() {
        val log=DiagnosticLog(clock={-1})
        log.record(DiagnosticLog.Kind.PLAYER_ERROR,code=Int.MAX_VALUE,http=-200)
        val invalid=log.events.value.single()
        assertEquals(0L,invalid.time);assertNull(invalid.code);assertNull(invalid.http)
        log.record(DiagnosticLog.Kind.PLAYER_ERROR,code=2004,http=403)
        val valid=log.events.value.last()
        assertEquals(2004,valid.code);assertEquals(403,valid.http)
        assertEquals(DiagnosticLog.Stage.NONE,DiagnosticLog.stage("媒体探测 token=secret"))
        assertEquals(DiagnosticLog.Stage.PROBE,DiagnosticLog.stage("媒体探测"))
    }
}
