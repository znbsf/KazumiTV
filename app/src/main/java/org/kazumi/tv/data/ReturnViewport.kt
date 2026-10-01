package org.kazumi.tv.data

/** Lazy-list positions include headers; only keys in [focusableKeys] can receive focus. */
data class ReturnPosition(val scrollIndex: Int, val scrollOffset: Int, val focusIndex: Int)

object ReturnViewport {
    fun <T> resolve(keys: List<T>, selectedKey: T?, viewportKey: T?, savedIndex: Int, savedOffset: Int,
                    focusableKeys: Set<T> = keys.toSet()): ReturnPosition? {
        if(keys.isEmpty())return null
        val anchor=keys.indexOf(viewportKey)
        val scroll=if(anchor>=0)anchor else savedIndex.coerceIn(keys.indices)
        val selected=keys.indexOf(selectedKey).takeIf { it>=0 && keys[it] in focusableKeys }
        val focus=selected ?: (scroll..keys.lastIndex).firstOrNull { keys[it] in focusableKeys }
            ?: (scroll-1 downTo 0).firstOrNull { keys[it] in focusableKeys } ?: return null
        return ReturnPosition(scroll,if(anchor>=0)savedOffset.coerceAtLeast(0) else 0,focus)
    }
}
