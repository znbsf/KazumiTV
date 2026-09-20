package org.kazumi.tv.ui

import androidx.compose.runtime.saveable.Saver
import org.kazumi.tv.data.PlaybackOrigin
import org.kazumi.tv.rules.Episode
import org.kazumi.tv.rules.Road
import org.kazumi.tv.rules.SourceMatch

/** Save stable catalogue references only: never media URLs, HTML, cookies or complete road lists. */
object PlaybackStateSavers {
    val requiredEpisode = Saver<Episode, List<String>>(
        save = { listOf(it.title, it.pageUrl) },
        restore = { if (it.size == 2) Episode(it[0], it[1]) else null }
    )
    val episode = Saver<Episode?, List<String>>(
        save = { it?.let { value -> listOf(value.title, value.pageUrl) } ?: emptyList() },
        restore = { if (it.size == 2) Episode(it[0], it[1]) else null }
    )
    val match = Saver<SourceMatch?, List<String>>(
        save = { it?.let { value -> listOf(value.title, value.url) } ?: emptyList() },
        restore = { if (it.size == 2) SourceMatch(it[0], it[1]) else null }
    )
    val origin = Saver<PlaybackOrigin?, List<String>>(
        save = { it?.let { value -> listOf(value.rule, value.sourceTitle, value.sourceUrl, value.roadTitle) } ?: emptyList() },
        restore = { if (it.size == 4) PlaybackOrigin(it[0], it[1], it[2], it[3]) else null }
    )
    // Only restoration changes intent. Normal navigation continues using the current Boolean.
    val pausedOnRestore = Saver<Boolean, Boolean>(save = { false }, restore = { false })
    val restored = Saver<Boolean, Boolean>(save = { true }, restore = { true })

    /** History positions near the end restart; invalid positions never reach the player. */
    fun historyResumePosition(position: Long?, duration: Long, enabled: Boolean): Long =
        position?.takeIf { enabled && it >= 0 && (duration <= 0 || it < duration - 5000) } ?: 0L

    data class SourceRecovery(val selectedName: String, val removedName: String?)
    /** The removal notice survives the subsequent successful fallback reconciliation. */
    fun recoverSource(selectedName: String, available: List<String>, previousRemovedName: String?): SourceRecovery {
        require(available.isNotEmpty())
        return if(selectedName in available) SourceRecovery(selectedName,previousRemovedName)
        else SourceRecovery(available.first(),selectedName)
    }

    fun roadIndex(roads: List<Road>, title: String, previousIndex: Int, page: String?): Int {
        if (roads.isEmpty()) return 0
        val matchingPage = roads.indices.filter { index -> roads[index].episodes.any { it.pageUrl == page } }
        matchingPage.firstOrNull { roads[it].title == title }?.let { return it }
        if (matchingPage.isNotEmpty()) return previousIndex.takeIf { it in matchingPage } ?: matchingPage.first()
        roads.indexOfFirst { it.title == title }.takeIf { it >= 0 }?.let { return it }
        return previousIndex.coerceIn(roads.indices)
    }
}
