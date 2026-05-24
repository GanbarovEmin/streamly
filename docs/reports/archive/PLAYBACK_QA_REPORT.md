# Playback QA Report

Date: 2026-05-11  
Build under test: Streamly 1.0.09 (1009)  
Scope: playback pipeline, torrent-to-player handoff, fallback/retry behavior, subtitles contract, app launch, production bundle playback smoke.

## Summary

Playback QA found one real startup failure in the torrent-to-HLS bridge: `ffmpeg` could start before the native torrent HTTP stream had enough data and exit on early `503`, partial-file, or timeout responses. The playback service now treats these as bounded startup-transient failures and retries HLS bridge startup before surfacing an error.

After the fix, the real torrent playback smoke passed repeatedly using the public WebTorrent Big Buck Bunny torrent and both Stremio's `ffmpeg` and the bundled production `ffmpeg`.

## What Was Tested

- App cold launch from `dist/release/Streamly.app`.
- App launch from a DMG-installed temp copy.
- Full automated suite after a clean SwiftPM build graph.
- Real native torrent playback using `/tmp/big-buck-bunny.torrent`.
- In-app transcoding playback with `TranscodingAVPlaybackService`.
- Source resolving and fallback state machine tests.
- Stream availability fallback.
- Startup timeout fallback.
- Player status monitoring for buffering, playing, stalled/failed, and completed states.
- Subtitle service tests covering embedded/local/OpenSubtitles preference behavior.
- Source/provider tests covering Torrentio movie and series episode stream endpoint mapping.
- Navigation tests covering player route entry and back-stack behavior.

## Real Playback Evidence

Legal test source: WebTorrent Free Torrents lists Big Buck Bunny as public domain / Creative Commons test content.

Commands executed:

```bash
curl -L --fail --retry 2 --connect-timeout 10 \
  -o /tmp/big-buck-bunny.torrent \
  https://webtorrent.io/torrents/big-buck-bunny.torrent

CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent \
STREAMLY_TRANSCODE_TEST_FFMPEG=/Applications/Stremio.app/Contents/MacOS/ffmpeg \
swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided

CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent \
STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" \
swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided
```

Results:

- Stremio ffmpeg live smoke: passed after the HLS startup retry fix.
- Bundled production ffmpeg live smoke: passed in 60.454s.
- DMG-installed copy ffmpeg live smoke: passed in 55.998s.

## Issues Found

### HLS bridge failed on early torrent HTTP readiness

Before the fix, the integration smoke failed with:

```text
ffmpeg exited before HLS playback became ready
HTTP error 503 Service Unavailable
Operation timed out
Stream ends prematurely
```

Cause: `ffmpeg` was treated as a one-shot startup process. Torrent streams can legitimately return transient `503`, partial data, or timeout while pieces are still arriving.

Fix:

- Added bounded HLS startup retries in `TranscodingAVPlaybackService`.
- Retries are limited by both attempt count and a 90s startup deadline.
- Retries are only allowed for transient startup logs such as `503`, `5xx`, partial stream, premature EOF, and operation timeout.
- Each attempt writes a separate `ffmpeg-attempt-N.log`.
- Non-transient errors still fail fast with user-safe playback errors.

### Native helper log noise during probe disconnects

`ffmpeg` may close early HTTP probe connections during retry. The native helper previously printed `BrokenPipeError` tracebacks for expected client disconnects.

Fix:

- Native helper now ignores `BrokenPipeError` and `ConnectionResetError` during stream response/error writes.
- Deprecated libtorrent Python binding warnings are filtered in helper startup.
- `Vendor/CineFlowLibtorrentNative.xcframework` was rebuilt so the production app bundle contains the updated helper.

### Missing fallback guardrails in tests

The previous suite did not explicitly cover resolved-stream unavailability or slow torrent startup timeout fallback.

Fix:

- Added playback pipeline tests for:
  - fallback when the resolved stream fails availability check;
  - fallback when `startStreaming` exceeds the operation timeout.

## Edge Cases Covered

- Broken primary release falls back to the next ranked release.
- All releases fail without entering an infinite loading state.
- Resolved stream URL fails availability check and falls back.
- Slow torrent startup times out and falls back.
- Debug logging remains disabled unless the debug flag is enabled.
- Playback status stream is cancellable and does not keep orphaned polling tasks alive.
- Native torrent stream reaches AVPlayer through in-app HLS.
- Production bundled `ffmpeg` can create playable HLS.
- DMG-installed copy can launch and use its bundled playback runtime.

## Performance Observations

- Full clean test suite: 221 tests, 4 skipped, 0 failures.
- Real torrent playback startup varied from roughly 48s to 62s with the public torrent, depending on peer/piece readiness.
- HLS startup retries prevent early hard failures without introducing an unbounded loop.
- Player status updates poll every 750ms and cancel on stream termination.
- Image pipeline and source aggregator coalescing tests continue to pass.

## UX Observations

- No infinite loading was observed in the tested failure paths.
- Fallback states now have deterministic transitions instead of one-shot player failure.
- Production app launch produced a normal `Streamly app launch` diagnostic event.
- Screenshot artifacts were captured under `qa_artifacts/2026-05-11/`.

## Remaining Low-Priority Issues

- The release app is unsigned for this local QA build, so downloaded distribution can still trigger macOS unidentified developer warnings.
- Build emits a non-blocking warning because the native libtorrent framework is built for macOS 15 while the app deployment target is macOS 13.
- Build emits a non-blocking deprecation warning for synchronous AVAsset duration access.
- Full GUI click-through against third-party provider search was not automated; provider behavior is covered by source/provider tests and real playback is covered with a legal torrent file.

## Stability Summary

Playback is now stable across the validated startup, fallback, timeout, stream availability, HLS bridge, and production resource paths. The main real-world failure discovered during QA was fixed and re-tested against the actual native torrent and AVPlayer pipeline.
