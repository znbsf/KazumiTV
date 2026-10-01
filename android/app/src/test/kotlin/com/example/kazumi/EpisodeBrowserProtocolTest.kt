package com.example.kazumi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EpisodeBrowserProtocolTest {
    private fun item(id: String = "opaque-1", label: String = "第一集", current: Boolean = true, seen: Boolean = false) =
        mapOf("opaqueId" to id, "label" to label, "current" to current, "seen" to seen)

    private fun snapshot(
        revision: Any = 4L,
        items: List<Map<String, Any>> = listOf(item()),
    ): Map<String, Any?> = mapOf(
        "sessionId" to "session-1", "revision" to revision,
        "items" to items, "initialOpaqueId" to "opaque-1",
    )

    private fun rejects(arguments: Any?) {
        try {
            EpisodeBrowserProtocol.parse(arguments)
            throw AssertionError("snapshot should have been rejected")
        } catch (_: IllegalArgumentException) {
            // Invalid method-channel data cannot reach the UI or owner.
        }
    }

    @Test fun parsesDisplayOnlySnapshotAndPreservesFlags() {
        val parsed = EpisodeBrowserProtocol.parse(snapshot(items = listOf(
            item(current = true, seen = true), item("opaque-2", "SP 特别篇", current = false),
        )))
        assertEquals("session-1", parsed.sessionId)
        assertEquals(4L, parsed.revision)
        assertTrue(parsed.items[0].current)
        assertTrue(parsed.items[0].seen)
        assertFalse(parsed.items[1].seen)
        assertEquals("SP 特别篇", parsed.items[1].label)
    }

    @Test fun acceptsBothMethodCodecIntegerWidthsAndRejectsOtherRevisions() {
        assertEquals(4L, EpisodeBrowserProtocol.parse(snapshot(revision = 4)).revision)
        assertEquals(Long.MAX_VALUE, EpisodeBrowserProtocol.parse(snapshot(revision = Long.MAX_VALUE)).revision)
        listOf(-1L, 4.0, "4", true).forEach { rejects(snapshot(revision = it)) }
    }

    @Test fun initialFocusFallsBackToCurrentThenFirstItem() {
        val withoutInitial = snapshot(items = listOf(
            item(current = false), item("opaque-2", current = true),
        )) - "initialOpaqueId"
        assertEquals(1, EpisodeBrowserProtocol.parse(withoutInitial).initialIndex)
        assertEquals(0, EpisodeBrowserProtocol.parse(snapshot(items = listOf(item(current = false))) - "initialOpaqueId").initialIndex)
    }

    @Test fun explicitInitialFocusUsesOpaqueMembership() {
        val arguments = snapshot(items = listOf(item(), item("opaque-2", current = false)))
        assertEquals(1, EpisodeBrowserProtocol.parse(arguments + ("initialOpaqueId" to "opaque-2")).initialIndex)
        rejects(arguments + ("initialOpaqueId" to "unknown"))
    }

    @Test fun rejectsMissingMalformedOrDuplicateItems() {
        rejects(null)
        rejects(listOf("wrong"))
        rejects(snapshot() - "sessionId")
        rejects(snapshot(items = emptyList()))
        rejects(snapshot(items = listOf(item(), item())))
        rejects(snapshot() + ("items" to listOf("wrong")))
        rejects(snapshot(items = listOf(item() - "seen")))
        rejects(snapshot(items = listOf(item() + ("current" to "true"))))
    }

    @Test fun rejectsBusinessAndNetworkPayloadFieldsAtEveryLevel() {
        listOf("url", "cookie", "headers", "episode", "source").forEach { field ->
            rejects(snapshot() + (field to "private"))
            rejects(snapshot(items = listOf(item() + (field to "private"))))
        }
    }

    @Test fun enforcesIdentifierAndLabelBounds() {
        val longId = "a".repeat(129)
        rejects(snapshot() + ("sessionId" to longId))
        rejects(snapshot() + ("sessionId" to " "))
        rejects(snapshot(items = listOf(item(id = longId))))
        rejects(snapshot(items = listOf(item(id = ""))))
        rejects(snapshot(items = listOf(item(label = "a".repeat(257)))))
        assertEquals(256, EpisodeBrowserProtocol.parse(snapshot(items = listOf(item(label = "a".repeat(256))))).items.single().label.length)
    }

    @Test fun accepts5000ItemsAndRejects5001() {
        val items = (1..5000).map { item(id = "opaque-$it", current = it == 1) }
        assertEquals(5000, EpisodeBrowserProtocol.parse(snapshot(items = items)).items.size)
        rejects(snapshot(items = items + item("opaque-5001", current = false)))
    }

    @Test fun cancelledResultHasNoOpaqueSelectionOrPrivatePayload() {
        val result = EpisodeBrowserResult("session-1", 4, "command-1", "cancelled").toMap()
        assertEquals(setOf("sessionId", "revision", "commandId", "action"), result.keys)
        assertNull(result["opaqueId"])
    }
}
