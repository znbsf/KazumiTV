package com.example.kazumi;

import java.util.*;

/** Pure bounded model; only the opt-in QA Activity writes it to its own file. */
public final class QaLaunchLedger {
    public static final int MAX_EVENTS = 64;
    public static final int MAX_BYTES = 32768;
    public static final List<String> DART_ORDER = Collections.unmodifiableList(Arrays.asList(
        "dart_binding", "dart_identity_enter", "dart_identity_exit", "dart_config_enter", "dart_config_exit",
        "dart_tvmode_enter", "dart_tvmode_exit", "dart_webview_enter", "dart_webview_exit",
        "dart_mediakit_enter", "dart_mediakit_exit", "dart_path_enter", "dart_path_exit",
        "dart_hive_enter", "dart_hive_exit", "dart_storage_enter", "dart_storage_exit",
        "dart_shaders_enter", "dart_shaders_exit", "dart_dio_guard_enter", "dart_dio_guard_exit",
        "dart_runapp", "dart_first_frame"));
    private static final Set<String> ALLOWED = new HashSet<>(DART_ORDER);
    static { ALLOWED.addAll(Arrays.asList("native_create_enter", "native_create_exit", "native_engine_enter",
        "native_super_engine_exit", "native_channel_ready", "native_resume", "native_window_focus",
        "native_destroy", "native_uncaught", "native_first_frame", "dart_failure", "probe_result")); }
    private final List<Map<String,Object>> events = new ArrayList<>();
    private long previous = -1;
    public synchronized boolean record(String stage, long elapsedMs, int pid, String errorType) {
        if (!ALLOWED.contains(stage) || elapsedMs < previous || elapsedMs < 0 || pid <= 0 ||
            (errorType != null && (!stage.equals("native_uncaught") && !stage.equals("dart_failure") ||
                !errorType.matches("[A-Za-z_$][A-Za-z0-9_.$]{0,159}")))) {
            throw new IllegalArgumentException("qa_launch_event_rejected");
        }
        if (events.size() >= MAX_EVENTS) return false;
        Map<String,Object> entry = new LinkedHashMap<>();
        entry.put("seq", events.size()); entry.put("stage", stage);
        entry.put("elapsed_ms", elapsedMs); entry.put("pid", pid);
        if (errorType != null) entry.put("error_type", errorType);
        events.add(entry); previous = elapsedMs;
        return true;
    }
    public synchronized List<Map<String,Object>> snapshot() {
        List<Map<String,Object>> copy = new ArrayList<>();
        for (Map<String,Object> event : events) copy.add(new LinkedHashMap<>(event));
        return copy;
    }
    public synchronized boolean ready() {
        List<String> stages = new ArrayList<>();
        for (Map<String,Object> event : events) {
            String stage = (String) event.get("stage");
            if (stage.equals("native_uncaught") || stage.equals("dart_failure")) return false;
            if (stage.startsWith("dart_")) stages.add(stage);
        }
        return stages.equals(DART_ORDER);
    }
}
