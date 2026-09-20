package org.kazumi.tv.rules

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Only explicit, narrowly detected rate-limit responses establish a cooldown. */
class SourceRequestThrottle(
    private val nowMillis: () -> Long = { System.nanoTime() / 1_000_000L },
    private val pause: suspend (Long) -> Unit = { delay(it) }
) {
    class RetryBudget { var consumed = false }
    private class Gate { val lock = Mutex(); var blockedUntil = 0L }
    private val gates = mutableMapOf<String, Gate>()
    private fun gate(origin: String): Gate = synchronized(gates) {
        // Rules are user-editable. Keep process memory bounded without evicting a live gate.
        gates[origin] ?: Gate().also { if (gates.size < 256) gates[origin] = it }
    }
    suspend fun <T> execute(origin: String, budget: RetryBudget, request: suspend () -> T): T {
        val gate = gate(origin)
        return gate.lock.withLock {
            while (true) {
                val remaining = gate.blockedUntil - nowMillis()
                if (remaining > 0) pause(remaining)
                try { return@withLock request() }
                catch (limited: SourceRateLimited) {
                    val wait = limited.retryAfterMillis.takeIf { it in 1000L..10_000L }?.plus(250L)
                    if (wait != null) gate.blockedUntil = nowMillis() + wait
                    if (budget.consumed || wait == null) throw limited
                    budget.consumed = true
                }
            }
            @Suppress("UNREACHABLE_CODE")
            error("unreachable")
        }
    }
    companion object { val shared = SourceRequestThrottle() }
}
