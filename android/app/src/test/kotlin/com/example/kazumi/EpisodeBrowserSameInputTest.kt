package com.example.kazumi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EpisodeBrowserSameInputTest {
    @Test fun sharedCasesPreserveOriginalIdentityAcrossSegmentOrderAndTerminalAction() {
        val stream = requireNotNull(javaClass.classLoader?.getResourceAsStream("episode_browser_cases.csv"))
        val cases = stream.bufferedReader(Charsets.UTF_8).use { it.readLines().drop(1).filter(String::isNotBlank) }
        assertEquals(8, cases.size)
        cases.forEach { row ->
            val fields = row.split(',')
            val name = fields[0]
            val countText = fields[1]
            val ordinalText = fields[2]
            val label = fields[3]
            val descendingText = fields[4]
            val pageText = fields[5]
            val action = fields[6]
            val count = countText.toInt()
            val index = ordinalText.toInt() - 1
            val snapshot = EpisodeBrowserProtocol.parse(mapOf(
                "sessionId" to name, "revision" to 7L, "initialOpaqueId" to "episode-$index",
                "items" to List(count) { i -> mapOf(
                    "opaqueId" to "episode-$i", "label" to if (i == index) label else "集${i + 1}",
                    "current" to (i == index), "seen" to (i == index),
                ) },
            ))
            val located = requireNotNull(EpisodeBrowserWindow.locate(ordinalText, count))
            assertEquals(index, located)
            assertEquals(pageText.toInt(), EpisodeBrowserWindow.pageOf(index, count, descendingText.toBooleanStrict()))
            assertTrue(index in EpisodeBrowserWindow.indices(count, pageText.toInt(), descendingText.toBooleanStrict()))
            assertEquals(index, snapshot.initialIndex)
            var counter = 0
            val coordinator = EpisodeBrowserCoordinator { "${name}-${counter++}" }
            val session = coordinator.open(snapshot)
            val result = requireNotNull(if (action == "selected") {
                coordinator.select(session.launchToken, snapshot.revision, snapshot.items[index].opaqueId)
            } else {
                coordinator.cancel(session.launchToken)
            })
            assertEquals(action, result.action)
            val id = if (action == "selected") "episode-$index" else null
            assertEquals(id, result.opaqueId)
            assertEquals(7L, result.toMap()["revision"])
            assertNull(coordinator.select(session.launchToken, snapshot.revision, "episode-$index"))
            println("EPISODE_CONTRACT|$name|${if (id == null) "none" else ordinalText}|$action|$label")
        }
    }
}
