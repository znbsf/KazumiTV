package org.kazumi.tv.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotEquals
import org.junit.Test

class HomeBackdropStateTest {
    private val a = HomeArtworkSource(1, "test://art/a")
    private val b = HomeArtworkSource(2, "test://art/b")
    private val c = HomeArtworkSource(3, "test://art/c")

    @Test fun rapidSelectionIgnoresEveryStaleCompletionAndFailureClearsOldArt() {
        var state = HomeBackdropState().select(a)
        val firstA = requireNotNull(state.desired)
        state = state.begin(firstA).succeed(firstA, landscape = true)
        state = state.select(b)
        val firstB = requireNotNull(state.desired)
        state = state.begin(firstB)
        state = state.select(c)
        val latestC = requireNotNull(state.desired)

        assertNotEquals(firstA, latestC)
        assertEquals(state, state.succeed(firstB, landscape = true))
        state = state.begin(latestC)
        assertEquals(state, state.fail(firstB))
        state = state.fail(latestC)

        assertNull(state.displayed)
        assertNull(state.pending)
        assertEquals(latestC, state.desired)
    }

    @Test fun missingCoverAndBlackModeClearDisplayedAndPendingRequests() {
        var state = HomeBackdropState().select(a)
        val current = requireNotNull(state.desired)
        state = state.begin(current).succeed(current, landscape = true)
        state = state.select(b)
        val loading = requireNotNull(state.desired)
        state = state.begin(loading)

        state = state.select(null)

        assertNull(state.desired)
        assertNull(state.pending)
        assertNull(state.displayed)
    }

    @Test fun repeatedAssetKeyDoesNotCreateASecondLoadIdentity() {
        val selected = HomeBackdropState().select(a)
        assertEquals(selected, selected.select(a))
    }

    @Test fun returningToEarlierAssetUsesANewGeneration() {
        var state = HomeBackdropState().select(a)
        val firstA = requireNotNull(state.desired)
        state = state.select(b)
        state = state.select(a)
        val secondA = requireNotNull(state.desired)

        assertNotEquals(firstA, secondA)
        assertEquals(state, state.succeed(firstA, landscape = true))
    }
}
