package com.alexmercerind.media_kit_video;

/** Thread-safe evidence gate, independent from Surface/engine locks. */
final class FirstFrameGate {
    private boolean armed;
    private boolean consumed;
    private boolean disposed;
    private long baselineTimestamp;

    synchronized void arm(long timestamp) {
        if (!armed && !disposed) {
            baselineTimestamp = timestamp;
            armed = true;
        }
    }

    synchronized boolean consume(long timestamp) {
        // Zero is an uninitialized texture (or a first PTS of zero); in the
        // latter case wait for the next frame rather than claim false success.
        if (!armed || disposed || consumed || timestamp == 0 || timestamp == baselineTimestamp) {
            return false;
        }
        consumed = true;
        return true;
    }

    synchronized boolean isActive() { return !disposed; }
    synchronized void dispose() { disposed = true; }
}
