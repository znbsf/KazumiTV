package org.kazumi.tv

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.*
import org.junit.Test
import org.kazumi.tv.data.PlaybackOrigin
import org.kazumi.tv.rules.*
import org.kazumi.tv.ui.PlaybackStateSavers

class PlaybackStateSaversTest {
    private val scope = object : SaverScope { override fun canBeSaved(value: Any) = true }

    @Test fun switchedSourceContextRoundTripsOnlyStableCatalogueFields() {
        val origin = PlaybackOrigin("source-b", "title-b", "https://source.invalid/detail-b", "road-b")
        val saved = with(PlaybackStateSavers.origin) { scope.save(origin) }!!
        assertEquals(listOf(origin.rule, origin.sourceTitle, origin.sourceUrl, origin.roadTitle), saved)
        assertEquals(origin, PlaybackStateSavers.origin.restore(saved))
        val ep = Episode("第12集", "https://source.invalid/play/12")
        val savedEpisode = with(PlaybackStateSavers.requiredEpisode) { scope.save(ep) }!!
        assertEquals(ep, PlaybackStateSavers.requiredEpisode.restore(savedEpisode))
        val match = SourceMatch("title", "https://source.invalid/detail")
        assertEquals(match, PlaybackStateSavers.match.restore(with(PlaybackStateSavers.match) { scope.save(match) }!!))
    }

    @Test fun restorationNeverAutoplaysEvenIfSavedWhilePlaying() {
        assertEquals(false, PlaybackStateSavers.pausedOnRestore.restore(true))
        assertEquals(false, with(PlaybackStateSavers.pausedOnRestore) { scope.save(true) })
        assertEquals(true, PlaybackStateSavers.restored.restore(true))
    }

    @Test fun reloadUsesStablePageAndRoadTitleInsteadOfStaleListPosition() {
        val a = Road("A", listOf(Episode("第1集", "page-a")))
        val b = Road("B", listOf(Episode("第1集", "page-b")))
        assertEquals(0, PlaybackStateSavers.roadIndex(listOf(b, a), "B", 1, "page-b"))
        assertEquals(1, PlaybackStateSavers.roadIndex(listOf(b, a), "renamed", 0, "page-a"))
        assertEquals(0, PlaybackStateSavers.roadIndex(emptyList(), "missing", 900, null))
        assertEquals(1, PlaybackStateSavers.roadIndex(listOf(a, b), "missing", 900, null))
    }

    @Test fun emptyOptionalReferencesDoNotInventSelection() {
        assertNull(PlaybackStateSavers.match.restore(emptyList()))
        assertNull(PlaybackStateSavers.episode.restore(emptyList()))
        assertNull(PlaybackStateSavers.origin.restore(emptyList()))
    }
    @Test fun historyResumeRejectsEndAndInvalidPositions() {
        assertEquals(34_999L,PlaybackStateSavers.historyResumePosition(34_999,40_000,true))
        for(position in listOf(35_000L,39_999L,40_000L,50_000L,-1L))
            assertEquals(0L,PlaybackStateSavers.historyResumePosition(position,40_000,true))
        assertEquals(0L,PlaybackStateSavers.historyResumePosition(10_000,40_000,false))
        assertEquals(0L,PlaybackStateSavers.historyResumePosition(null,40_000,true))
        assertEquals(10_000L,PlaybackStateSavers.historyResumePosition(10_000,0,true))
    }

    @Test fun sharedEpisodeUrlRestoresSelectedRoadTitle() {
        val episode=Episode("第1集","same-page")
        val roads=listOf(Road("线路A",listOf(episode)),Road("线路B",listOf(episode)))
        assertEquals(1,PlaybackStateSavers.roadIndex(roads,"线路B",0,"same-page"))
        assertEquals(0,PlaybackStateSavers.roadIndex(roads.reversed(),"线路B",1,"same-page"))
        val removedEpisodeRoad=Road("旧线路",listOf(Episode("第2集","other-page")))
        assertEquals(0,PlaybackStateSavers.roadIndex(roads+removedEpisodeRoad,"旧线路",2,"same-page"))
    }

    @Test fun missingSourceNoticeSurvivesFallbackRefreshUntilExplicitSelection() {
        val fallback=PlaybackStateSavers.recoverSource("removed",listOf("A","B"),null)
        assertEquals("A",fallback.selectedName);assertEquals("removed",fallback.removedName)
        assertEquals(fallback,PlaybackStateSavers.recoverSource(fallback.selectedName,listOf("A","B"),fallback.removedName))
        assertNull(PlaybackStateSavers.recoverSource("B",listOf("A","B"),null).removedName)
    }
}
