package com.example.kazumi

data class EpisodeBrowserItem(
    val opaqueId: String,
    val label: String,
    val current: Boolean,
    val seen: Boolean,
)

data class EpisodeBrowserSnapshot(
    val sessionId: String,
    val revision: Long,
    val items: List<EpisodeBrowserItem>,
    val initialOpaqueId: String?,
) {
    val initialIndex: Int
        get() = items.indexOfFirst { it.opaqueId == initialOpaqueId }.takeIf { it >= 0 }
            ?: items.indexOfFirst { it.current }.takeIf { it >= 0 }
            ?: 0
}

data class EpisodeBrowserResult(
    val sessionId: String,
    val revision: Long,
    val commandId: String,
    val action: String,
    val opaqueId: String? = null,
) {
    fun toMap(): Map<String, Any> = buildMap {
        put("sessionId", sessionId)
        put("revision", revision)
        put("commandId", commandId)
        put("action", action)
        opaqueId?.let { put("opaqueId", it) }
    }
}

/** A display-only protocol: URLs, cookies and business objects are rejected. */
object EpisodeBrowserProtocol {
    private val snapshotKeys = setOf("sessionId", "revision", "items", "initialOpaqueId")
    private val itemKeys = setOf("opaqueId", "label", "current", "seen")

    fun parse(arguments: Any?): EpisodeBrowserSnapshot {
        val map = arguments as? Map<*, *> ?: invalid("snapshot must be a map")
        requireKeys(map, snapshotKeys, setOf("sessionId", "revision", "items"))
        val sessionId = identifier(map["sessionId"], "sessionId")
        val revision = when (val value = map["revision"]) {
            is Int -> value.toLong()
            is Long -> value
            else -> invalid("revision must be an integer")
        }
        if (revision < 0) invalid("revision must be non-negative")
        val rawItems = map["items"] as? List<*> ?: invalid("items must be a list")
        if (rawItems.isEmpty()) invalid("items must not be empty")
        if (rawItems.size > 5000) invalid("items must contain at most 5000 entries")
        val ids = HashSet<String>(rawItems.size)
        val items = rawItems.map { raw ->
            val item = raw as? Map<*, *> ?: invalid("item must be a map")
            requireKeys(item, itemKeys, itemKeys)
            val opaqueId = identifier(item["opaqueId"], "opaqueId")
            if (!ids.add(opaqueId)) invalid("opaqueId must be unique")
            EpisodeBrowserItem(
                opaqueId = opaqueId,
                label = (item["label"] as? String)?.takeIf { it.length <= 256 }
                    ?: invalid("label must be a string of at most 256 characters"),
                current = item["current"] as? Boolean ?: invalid("current must be a boolean"),
                seen = item["seen"] as? Boolean ?: invalid("seen must be a boolean"),
            )
        }
        val initialOpaqueId = map["initialOpaqueId"]?.let { identifier(it, "initialOpaqueId") }
        if (initialOpaqueId != null && initialOpaqueId !in ids) {
            invalid("initialOpaqueId must belong to items")
        }
        return EpisodeBrowserSnapshot(sessionId, revision, items, initialOpaqueId)
    }

    private fun requireKeys(map: Map<*, *>, allowed: Set<String>, required: Set<String>) {
        if (!map.keys.all { it is String && it in allowed } || !map.keys.containsAll(required)) {
            invalid("snapshot contains missing or unsupported fields")
        }
    }

    private fun identifier(value: Any?, name: String): String =
        (value as? String)?.takeIf { it.isNotBlank() && it.length <= 128 }
            ?: invalid("$name must be a non-empty string of at most 128 characters")

    private fun invalid(message: String): Nothing = throw IllegalArgumentException(message)
}

/** Indexes always address the original Dart snapshot, including in descending order. */
object EpisodeBrowserWindow {
    const val SIZE = 50

    fun pageCount(count: Int): Int = if (count <= 0) 0 else (count - 1) / SIZE + 1

    fun indices(count: Int, page: Int, descending: Boolean): List<Int> {
        if (count <= 0) return emptyList()
        val start = page.coerceIn(0, pageCount(count) - 1) * SIZE
        return (start until minOf(start + SIZE, count)).map {
            if (descending) count - 1 - it else it
        }
    }

    fun pageOf(index: Int, count: Int, descending: Boolean): Int {
        if (count <= 0) return 0
        val originalIndex = index.coerceIn(0, count - 1)
        return (if (descending) count - 1 - originalIndex else originalIndex) / SIZE
    }

    fun locate(text: String, count: Int): Int? =
        text.toIntOrNull()?.takeIf { it in 1..count }?.minus(1)
}

/** One live caller and one terminal command; stale callbacks never consume a new session. */
class EpisodeBrowserCoordinator(private val newId: () -> String) {
    data class Session(
        val launchToken: String,
        val commandId: String,
        val snapshot: EpisodeBrowserSnapshot,
    )

    var active: Session? = null
        private set

    fun open(snapshot: EpisodeBrowserSnapshot): Session {
        check(active == null) { "episode browser already has a pending caller" }
        return Session(newId(), newId(), snapshot).also { active = it }
    }

    fun select(launchToken: String, revision: Long, opaqueId: String): EpisodeBrowserResult? {
        val session = active?.takeIf { it.launchToken == launchToken } ?: return null
        if (revision != session.snapshot.revision || session.snapshot.items.none { it.opaqueId == opaqueId }) {
            return null
        }
        return complete(session, "selected", opaqueId)
    }

    fun cancel(launchToken: String): EpisodeBrowserResult? {
        val session = active?.takeIf { it.launchToken == launchToken } ?: return null
        return complete(session, "cancelled")
    }

    fun cancelMatching(launchToken: String, sessionId: String, revision: Long): EpisodeBrowserResult? {
        val session = active?.takeIf {
            it.launchToken == launchToken && it.snapshot.sessionId == sessionId && it.snapshot.revision == revision
        } ?: return null
        return complete(session, "cancelled")
    }

    // Rebuilding cannot restore a command or replay a selection.
    fun rebuilt(launchToken: String): EpisodeBrowserResult? = cancel(launchToken)

    private fun complete(session: Session, action: String, opaqueId: String? = null): EpisodeBrowserResult {
        active = null
        return EpisodeBrowserResult(
            session.snapshot.sessionId, session.snapshot.revision, session.commandId, action, opaqueId,
        )
    }
}
