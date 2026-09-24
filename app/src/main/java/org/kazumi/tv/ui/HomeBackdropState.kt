package org.kazumi.tv.ui

/** Request identity for a home backdrop. The revision prevents A -> B -> A stale completions. */
internal data class HomeArtworkSource(val subjectId: Int, val url: String)

internal data class HomeArtworkIdentity(val source: HomeArtworkSource, val revision: Int)

internal data class HomeDisplayedArtwork(val identity: HomeArtworkIdentity, val landscape: Boolean)

internal data class HomeBackdropState(
    val desired: HomeArtworkIdentity? = null,
    val pending: HomeArtworkIdentity? = null,
    val displayed: HomeDisplayedArtwork? = null,
    private val nextRevision: Int = 0
) {
    fun select(source: HomeArtworkSource?): HomeBackdropState {
        if (desired?.source == source) return this
        val next = source?.let { HomeArtworkIdentity(it, nextRevision) }
        return copy(
            desired = next,
            pending = null,
            // Keep the last successful art only while a new valid candidate loads.
            // Missing art and OLED mode immediately return to the neutral background.
            displayed = if (source == null) null else displayed,
            nextRevision = if (next == null) nextRevision else nextRevision + 1
        )
    }

    fun begin(identity: HomeArtworkIdentity): HomeBackdropState =
        if (identity == desired && displayed?.identity != identity) copy(pending = identity) else this

    fun succeed(identity: HomeArtworkIdentity, landscape: Boolean): HomeBackdropState =
        if (identity == desired && identity == pending) {
            copy(displayed = HomeDisplayedArtwork(identity, landscape), pending = null)
        } else this

    fun fail(identity: HomeArtworkIdentity): HomeBackdropState =
        if (identity == desired && identity == pending) copy(displayed = null, pending = null) else this
}
