# Stable TV focus fixes accepted on 2026-10-16

This batch extracts production fixes from the locally validated integration candidate (source 3dd52150, candidate version 203295). It excludes temporary fixture entry points, test-only startup seams, private device artifacts, and AV1 experiments.

- Startup rule actions acquire a reachable TV dialog after destination-page focus; duplicate actions serialize, and obsolete SyncPlay reconnect actions are ignored.
- Completed collection sync moves focus to the available completion/close action.
- An empty failed home page permits Down to reach retry actions instead of swallowing the key.

Production files are taken unchanged from 91996734, 08013e67 and 4e8ce875. The corresponding targeted suite passes 34 tests on the clean main-based branch. Real TV evidence covers normal startup/INFO/playback; controlled emulator evidence covers startup actions and home recovery/failure/pagination. Genuine account sync and a naturally failing first page on candidate203295 were not exercised; those claims remain limited to controlled/component coverage.

PR13 separately includes INFO and monotonic rate limiting. No AV1 fallback, experimental forced software decoder, channel/EPG preview, media URL, device dump or screenshot is part of this batch. Release remains pending decoder-policy validation and final artifact verification.
