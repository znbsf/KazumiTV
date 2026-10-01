package com.example.kazumi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EpisodeBrowserCoordinatorTest {
    private fun snapshot(id: String = "session-1", revision: Long = 4) = EpisodeBrowserSnapshot(
        id, revision,
        listOf(EpisodeBrowserItem("opaque-1", "第一集", true, false), EpisodeBrowserItem("opaque-2", "SP", false, true)),
        "opaque-1",
    )

    private fun coordinator(): EpisodeBrowserCoordinator {
        var id = 0
        return EpisodeBrowserCoordinator { "unique-${++id}" }
    }

    @Test fun onlyOneCallerCanBePending() {
        val coordinator = coordinator()
        val active = coordinator.open(snapshot())
        try {
            coordinator.open(snapshot("second"))
            throw AssertionError("second caller should be rejected")
        } catch (_: IllegalStateException) {
            assertEquals(active, coordinator.active)
        }
    }

    @Test fun selectedCommandPreservesOwnerRevisionAndOpaqueIdentity() {
        val coordinator = coordinator()
        val active = coordinator.open(snapshot())
        val selected = coordinator.select(active.launchToken, 4, "opaque-2")!!
        assertEquals("session-1", selected.sessionId)
        assertEquals(4L, selected.revision)
        assertEquals(active.commandId, selected.commandId)
        assertEquals("selected", selected.action)
        assertEquals("opaque-2", selected.opaqueId)
        assertNull(coordinator.active)
    }

    @Test fun wrongTokenOldRevisionAndUnknownMemberCannotConsumePendingCaller() {
        val coordinator = coordinator()
        val active = coordinator.open(snapshot())
        assertNull(coordinator.select("wrong-owner", 4, "opaque-1"))
        assertNull(coordinator.select(active.launchToken, 3, "opaque-1"))
        assertNull(coordinator.select(active.launchToken, 4, "unknown"))
        assertEquals(active, coordinator.active)
    }

    @Test fun repeatedSelectBackOrHomeProducesOnlyOneTerminalCommand() {
        val coordinator = coordinator()
        val active = coordinator.open(snapshot())
        assertEquals("selected", coordinator.select(active.launchToken, 4, "opaque-1")?.action)
        assertNull(coordinator.select(active.launchToken, 4, "opaque-1"))
        assertNull(coordinator.cancel(active.launchToken))
        assertNull(coordinator.rebuilt(active.launchToken))
    }

    @Test fun backHomeAndHostDetachUseIdempotentCancellation() {
        listOf("back", "home", "host-detach").forEach {
            val coordinator = coordinator()
            val active = coordinator.open(snapshot())
            val cancelled = coordinator.cancel(active.launchToken)!!
            assertEquals("cancelled", cancelled.action)
            assertNull(cancelled.opaqueId)
            assertNull(coordinator.active)
            assertNull(coordinator.cancel(active.launchToken))
            assertNull(coordinator.select(active.launchToken, 4, "opaque-1"))
        }
    }

    @Test fun ownerScopedDisposeCancellationRequiresSessionAndRevision() {
        val coordinator = coordinator()
        val active = coordinator.open(snapshot())
        assertNull(coordinator.cancelMatching("wrong-owner", "session-1", 4))
        assertNull(coordinator.cancelMatching(active.launchToken, "old-session", 4))
        assertNull(coordinator.cancelMatching(active.launchToken, "session-1", 3))
        assertEquals(active, coordinator.active)
        assertEquals("cancelled", coordinator.cancelMatching(active.launchToken, "session-1", 4)?.action)
    }

    @Test fun activityRebuildCancelsAndNeverRestoresSelection() {
        val coordinator = coordinator()
        val active = coordinator.open(snapshot())
        assertEquals("cancelled", coordinator.rebuilt(active.launchToken)?.action)
        assertNull(coordinator.active)
        assertNull(coordinator.select(active.launchToken, 4, "opaque-1"))
        assertNull(coordinator.rebuilt(active.launchToken))
    }

    @Test fun staleActivityAndDetachedOwnerCannotCancelNewActivity() {
        val coordinator = coordinator()
        val old = coordinator.open(snapshot())
        coordinator.cancel(old.launchToken)
        val current = coordinator.open(snapshot("session-2", 5))
        assertNotEquals(old.launchToken, current.launchToken)
        assertNotEquals(old.commandId, current.commandId)
        assertNull(coordinator.cancel(old.launchToken))
        assertNull(coordinator.rebuilt(old.launchToken))
        assertNull(coordinator.cancelMatching(old.launchToken, "session-2", 5))
        assertEquals(current, coordinator.active)
        assertTrue(coordinator.select(current.launchToken, 5, "opaque-2") != null)
    }

    @Test fun processRestartDoesNotHaveAReplayableCommand() {
        val previous = coordinator().open(snapshot())
        val restarted = coordinator()
        assertNull(restarted.active)
        assertNull(restarted.select(previous.launchToken, 4, "opaque-1"))
        assertNull(restarted.rebuilt(previous.launchToken))
    }
}
