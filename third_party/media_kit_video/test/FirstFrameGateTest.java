package com.alexmercerind.media_kit_video;

/** Plain Java regression harness: no Android, Gradle, device or JUnit required. */
public final class FirstFrameGateTest {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] args) {
        FirstFrameGate gate = new FirstFrameGate();
        require(!gate.consume(123), "initial texture consumption must not pass");
        gate.arm(123);
        require(!gate.consume(0), "empty texture must not pass");
        require(!gate.consume(123), "old consumed buffer must not pass");
        require(gate.consume(456), "new consumed video buffer should pass");
        require(!gate.consume(789), "must notify only once");
        gate.dispose();
        require(!gate.isActive(), "queued notification must be suppressed after dispose");

        FirstFrameGate cancelled = new FirstFrameGate();
        cancelled.arm(0);
        cancelled.dispose();
        require(!cancelled.consume(456), "late frame after disposal must not pass");
        FirstFrameGate disposedBeforeArm = new FirstFrameGate();
        disposedBeforeArm.dispose();
        disposedBeforeArm.arm(0);
        require(!disposedBeforeArm.consume(456), "late dimensions must not revive output");
    }
}
