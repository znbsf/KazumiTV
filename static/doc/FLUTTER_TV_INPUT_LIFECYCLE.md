# Optional TV input lifecycle evidence

`KAZUMI_TV_PERF=true` now adds a bounded `report.lifecycle` alongside the existing FrameTiming report. Ordinary builds keep the flag off. The frame report's down/repeat inputs retain their original meaning; the lifecycle stream separately retains down, repeat, up and synthesized events.

The pinned Flutter 3.47.3 KeyEventManager calls HardwareKeyboard handlers before routing the KeyMessage through FocusManager. The observer always returns false and uses the actual KeyEvent object to associate a sequence with existing home navigation callbacks. A widget test checks this order, including keys with no primary focus. No frame, player-property query, FFI, network request or per-key log is added by collection.

Home snapshots reuse runtime subject IDs from TvDesktopNavigation. They include the catalog, five-column geometry, pending focus request, loading state and every existing scroll-controller notification. Unknown controls and unregistered routes remain unknown. Leaving a registered scroll surface revokes whole-window scroll completeness. Visibility checkpoints also record focus/route state even if the FocusNode does not change. Platform BACK method-channel receipts remain a separate stream; they are not fabricated as Flutter keys or treated as proof of the native dispatch decision.

Events are held in memory: 512 per stream, 2048 scroll samples, 512 catalog entries, within the existing 60-second window bound. Dropped entries and state-read errors invalidate the corresponding completeness flags. The planned held-key scenes last less than 30 seconds. Stop freezes the lifecycle before the existing late-frame drain and chunked output.

Targeted checks cover the full key lifecycle, no-focus delivery, pre-routing sequence association, a missing release at stop, stale page-owner disposal, overflow, cross-page coverage and paced five-column navigation 1→21→1. Each held direction uses a 450ms first-repeat delay, three repeats 180ms apart, then 250ms settling plus 1250ms observation. These component checks do not claim physical remote hardware or device performance acceptance; those require independent plans and actual captured windows.


Player windows register only the logical player page and cached business state; unknown focused controls stay unknown and player scroll coverage stays false. Optional rate evidence listens to the existing media-kit typed rate stream, with the subscription owned and disposed by the player. Cached position/rate observations reuse the existing playback synchronization timer. Collection adds no native getter, synchronous FFI, polling timer, or media URL logging.

Keyboard forward now distinguishes a genuine key release from cancellation. Focus/route/lifecycle loss, action blocking, synthesized events and disposal cancel the hold, restore its own base speed when needed, and never commit a tap seek. A repeated key is a hold even if the current speed already reaches the configured boost speed. Cancellation clears ownership before callbacks; UI mutations triggered during widget builds are deferred until after that build. Touch hold state remains separate.
