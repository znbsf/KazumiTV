# Independent full UI QA

This debug-only entrypoint runs the normal app shell and VideoPage in the
existing `com.znbsf.kazumi.fluttertv.parserqa` identity. It does not import or run
the batch page, consume its `case.json`, or change ordinary/release defaults.

Both sides must opt in: Dart `KAZUMI_QA_FULL_UI=true`, parserQa flavor, exact
package/debug identity, and a positive native `QA_FULL_UI`/TV/non-offline Activity
handshake. A mismatched or headless engine shows the fixed unavailable page and
does not install the resolver override. Ordinary TV flavor behavior is unchanged.

The QA route binds the exact immutable playback headers before queuing. Only
the existing WebView66 capability gate, without document-start support and with
iframe-only mode disabled, can use primary10/shared25/max1. All other requests
use the ordinary service with the page's explicit15 and its existing HTML-page
fallback. Queue/retirement time consumes the same25; unconfirmed cleanup blocks
subsequent routes. No source/domain-specific eligibility is added.

The same production parser services, cancellation/session guards, first-frame
cache rules and player are used. A route-local cache avoids mixing QA routes;
cached attempts retain their confirmed headers. Gecko is a parser engine here,
not a replacement system WebView or video decoder. The native bridge issues
process-wide monotonic owner tokens; a late route/isolate cannot close another
session. Close acknowledgements do not prove OS processes or memory were freed.

Scope A covers initial online playback, retry, same-plugin episode/road changes,
cancel and route exit. SourceSheet's pre-resolved cross-source switch, downloads
and health probes retain their original paths. Their successful integration is
not implied by these tests or this entrypoint.

## Future build identity (not executed as part of this change)

Use the existing pinned toolchain, debug signing bytes, single target ABI and
source-freeze/GeneratedPluginRegistrant checks from the QA runbook. Preserve the
existing package's certificate and data; select a newly approved version above
20592 before an upgrade. No version/build/install is performed by this entrypoint.

The existing batch `build.ps1` hardcodes the batch target and must not be used
to label that output as full UI. A separately approved build invocation needs:

```text
--debug --no-pub --flavor parserQa
--target tools/qa/full_ui/main.dart
--target-platform android-arm
--android-project-arg=kazumiParserQa=true
--android-project-arg=kazumiQaFullUi=true
--android-project-arg=disable-abi-filtering=true
--dart-define=KAZUMI_QA_FULL_UI=true
--dart-define=KAZUMI_QA_LAUNCH_ONLY=false
```

Do not combine `kazumiTv` or the offline launch profile with this build. Reuse
the existing `source_batch/prepare.py` parser generation as an approved build
preparation step; do not fork/add JavaScript. Gecko dependency/version and parser
assets remain QA-only. Verify the merged manifest, actual ABI/certificate, target
and dependency hashes for the new artifact. Those native/build checks and real
device, visible-picture, memory, audio/AV and long-run acceptance remain pending.
