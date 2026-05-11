# Streamly Direct Torrent Playback Fix

Date: 2026-05-11
Project: Streamly / CineFlow
Scope: critical direct torrent playback stabilization

## Executive Status

Direct torrent playback was verified through the native torrent pipeline and the in-app AVPlayer path with a legal movie torrent. The current production app bundle reached player playback through:

Selected source -> torrent metadata -> video file selection -> local stream URL -> AVPlayer-ready playback.

The current DMG is:

- `dist/dmg/Streamly-1.0.10.dmg`
- Version/build inside app: `1.0.10` / `1010`
- SHA-256: `ed8ad7a21b5c5fce265bd878d4de010619cfc338547e0e22404341f401757968`
- `hdiutil verify` status: passed

## Stremio Research

Reviewed open-source Stremio playback/source behavior from:

- Stremio core stream model: https://github.com/Stremio/stremio-core/blob/development/src/types/resource/stream.rs
- Stremio core streaming server model: https://github.com/Stremio/stremio-core/blob/development/src/models/streaming_server.rs
- Stremio core player model: https://github.com/Stremio/stremio-core/blob/development/src/models/player.rs
- Stremio addon stream response docs: https://stremio.github.io/stremio-addon-sdk/api/responses/stream.html

Relevant Stremio approach:

1. Addons return stream/source objects, not direct player state.
2. Torrent streams carry `infoHash`, optional `fileIdx`, and tracker/source hints.
3. Stremio converts torrent stream data into a streaming-server URL.
4. Missing `fileIdx` means the server can choose a playable video file, commonly the largest valid file.
5. Stream conversion and torrent handling are separated from player state.
6. Player load resets previous stream/video/subtitle/next-stream state before attaching the next playable source.
7. Async streaming-server updates are guarded against stale selected stream data.

Adaptation in Streamly:

- Torrentio/Stremio-style `infoHash` and `fileIdx` are preserved on `TorrentRelease`.
- Torrent metadata and file selection happen before the player receives a URL.
- `preferredFileIndex` is honored when present.
- If no preferred file exists, Streamly selects the best non-sample media file.
- The player receives a validated local stream URL, not a half-ready torrent release.

## Root Cause

The screenshots show the older failure mode: the UI entered buffering, then collapsed into:

- `Torrent source is not ready`
- `Playback is not available right now.`

The failure was not an Electron main/preload/renderer issue. This project is a SwiftPM/macOS app. The actual risk area was the torrent-to-player pipeline.

The old behavior failed because torrent start, metadata readiness, file selection, priority setup, local URL creation, and player startup were not clearly separated at the route level. When any intermediate stage was late or missing, the user saw a generic "source is not ready" state instead of a staged retry/fallback/error. Fast source switches could also leave old async callbacks or torrent sessions alive long enough to affect the new playback attempt.

Follow-up root cause found after reproducing the user's home/player screenshot:

- The visible player route showed `Best release: No user sources`.
- `TorrentioSourceProvider.defaultIsEnabled` was `false`, so new/default installs had no active torrent source.
- `CineFlowRootViewModel` used `environment.torrentEngine.searchReleases`, but the real embedded libtorrent engine is not a source-search provider.
- `PlayerRouteView.load()` without an explicit `TorrentRelease` only checked local user media files, then entered a player route with no torrent release.
- The UI then surfaced this upstream source-resolution failure as `Torrent source is not ready`, which was misleading.

Second follow-up root cause after the next reproduced screenshot:

- Source lookup was fixed; the player route now showed a real Torrentio release with seeders.
- The next failure was lower in the pipeline: Streamly created a local torrent stream URL such as `http://127.0.0.1:<port>/stream/<session>/<file>`, then immediately ran an 8 second HTTP byte preflight against that URL.
- For torrent streaming this was wrong. The first `Range` request may legitimately block while libtorrent fetches the first pieces. That made a valid local stream look unavailable before AVPlayer/FFmpeg was allowed to buffer.
- The local FFmpeg HLS bridge also used `-rw_timeout 8000000` for all local HTTP inputs. Eight seconds is too short for first-piece torrent buffering, so FFmpeg could exit before the torrent stream had a fair chance to serve bytes.
- Manual file-selection playback had the same preflight issue outside the main `PlaybackPipeline`.

Third follow-up root cause after video started but stopped after a few seconds:

- The app did reach playback, but the local torrent HTTP server treated a request without a `Range` header as "return only the first 1 MiB".
- FFmpeg often opens HTTP input without a range request first.
- After receiving only the first chunk, FFmpeg interpreted the response as end-of-input, generated a tiny HLS playlist with `#EXT-X-ENDLIST`, and AVPlayer naturally stopped after the first few seconds.
- The fix is to stream no-range and open-ended-range requests continuously from the selected file, waiting for each next torrent chunk before writing it to the HTTP response.

Specific failure points investigated:

- Empty source: `PlaybackPipeline.validate(_:)` now rejects releases with neither magnet URI nor torrent file URL.
- Torrent engine start: bounded by a torrent-start timeout.
- Metadata load: file list is fetched as a distinct stage.
- Peers/status: status is recorded in the debug trace after metadata when available.
- Video file selection: centralized in `TorrentMediaFileSelector`.
- Sample/trailer files: filtered out before automatic selection.
- Local stream URL: resolved after file selection and priority setup.
- Player URL: passed after URL validation; non-local URLs are availability-checked, while local torrent streams are handed to bounded player buffering.
- Session state: route coordinator owns cleanup and stale-token protection.

## Implemented Fixes

### Torrent playback pipeline

`Sources/CineFlowPlayback/PlaybackPipeline.swift` runs the playback path as explicit stages:

1. Validate selected release has a magnet or torrent file URL.
2. Start torrent session.
3. Load torrent metadata/file list.
4. Capture torrent status/peer diagnostics.
5. Select playable video file.
6. Set selected file to high priority and non-selected files to low/disabled priority.
7. Resolve local stream URL.
8. Validate the URL is a supported playable media URL.
9. Skip byte preflight for Streamly local torrent stream URLs and let the player/bridge perform bounded buffering.
10. Probe stream availability only for non-local-stream URLs.
11. Return a `PlaybackMediaSource` to the player.

Timeouts are bounded:

- Torrent start: 10 seconds
- Metadata/file list: 35 seconds
- File selection/priority: 10 seconds
- Stream URL: 5 seconds
- Stream availability: 8 seconds
- Existing HLS startup bridge: 120 seconds

Local torrent stream handling now matches the Stremio-style boundary:

- Torrent engine owns metadata, peers, file selection, cache, and the local `127.0.0.1` stream server.
- Playback pipeline treats `http://127.0.0.1:<port>/stream/...` as a valid stream handoff once the engine has produced it.
- FFmpeg/AVPlayer owns buffering from that local URL instead of the pipeline trying to synchronously read first bytes.
- Errors appear only after the bounded player-start window or a real torrent/helper failure.

### File selection

`TorrentMediaFileSelector` now applies the Stremio-like logic:

- Use source-provided `preferredFileIndex` when available.
- Otherwise pick the strongest media candidate.
- Ignore likely samples/trailers.
- Ignore very small media files below the playable threshold.
- Prefer larger/high-confidence video files.

### Session/state protection

`PlaybackSessionCoordinator` in `Sources/CineFlowUI/ContentContainerView.swift` now:

- Creates a new route token per playback attempt.
- Stops the existing player before a new attempt.
- Removes the previous torrent session.
- Stores only one active torrent session ID.
- Ignores stale async completions by token.
- Logs cleanup failures instead of silently hiding them.

This prevents old sessions, old metadata, and old async callbacks from mutating a newer playback state.

### Auto source resolution

Added `PlaybackAutoSourceResolver` so the default player flow now performs the missing Stremio/Torrentio lookup before playback:

1. Resolve `tmdb:*` IDs to IMDb/Stremio IDs through metadata detail.
2. For movies, build `tt...`.
3. For series with selected episode context, build `tt...:season:episode`.
4. For series without selected episode context, choose the first released episode and build its Stremio episode ID.
5. Ensure Torrentio is enabled for playback lookup, including old local settings where it had been created disabled.
6. Search active sources through `TorrentSearchAggregator`.
7. Pass the best `TorrentRelease` plus fallback releases into `PlaybackPipeline`.

`TorrentioSourceProvider.defaultIsEnabled` is now `true`, because direct torrent playback is a core feature and a default install must have at least one active unauthenticated torrent source.

### Debug logging

Debug logs now show the full path:

- Selected media and episode context
- Selected source/release
- Magnet/infoHash
- Torrent engine session start
- Metadata ready and file count
- Torrent state and peer/seeder/leecher counts when available
- Selected video file
- Stream URL creation
- URL scheme
- Stream availability check
- Ready/failed/fallback stage
- Cleanup stage

This turn added the missing readiness trace for:

- `torrent.metadata.ready` with peer/status fields
- `stream.url.ready`
- `stream.availability.skipped` for local torrent streams handed directly to player buffering
- `stream.ready` with sanitized stream URL

Local file paths are sanitized in debug metadata as `file://<local-file>/<filename>`.

### Local stream server and player bridge

`Native/CineFlowLibtorrentNative/helper/streamly_torrent_helper.py` now behaves more like a streaming server:

- It starts a local `127.0.0.1` HTTP server for selected torrent files.
- It supports `HEAD` for `/stream/...` without waiting for first-piece bytes.
- It prioritizes the beginning of the selected video file immediately after file selection.
- It streams no-range and open-ended range requests continuously instead of returning only the first chunk.
- It waits chunk-by-chunk for torrent pieces, then flushes each chunk to the player/FFmpeg.
- It keeps bounded range waits, returning a real failure only after timeout.

`TranscodingAVPlaybackService` now gives local torrent streams longer first-byte tolerance:

- Local torrent stream FFmpeg read timeout: 60 seconds.
- HLS startup window: 120 seconds.
- Series/movie selection context is preserved when bridging local HTTP to HLS.

## Changed Files In This Pass

- `Sources/CineFlowPlayback/PlaybackPipeline.swift`
- `Sources/CineFlowPlayback/AVFoundationPlaybackService.swift`
- `Sources/CineFlowSources/TorrentioSourceProvider.swift`
- `Sources/CineFlowUI/PlaybackAutoSourceResolver.swift`
- `Sources/CineFlowUI/CineFlowRootViewModel.swift`
- `Sources/CineFlowUI/ContentContainerView.swift`
- `Sources/CineFlowUI/MainShellView.swift`
- `Native/CineFlowLibtorrentNative/helper/streamly_torrent_helper.py`
- `Vendor/CineFlowLibtorrentNative.xcframework`
- `Tests/CineFlowPlaybackTests/PlaybackEngineTests.swift`
- `Tests/CineFlowSourcesTests/SourceProviderArchitectureTests.swift`
- `Tests/CineFlowUITests/PlaybackAutoSourceResolverTests.swift`
- `PLAYBACK_STREMIO_RESEARCH_FIX.md`

## Verification

### Focused automated tests

Passed:

- `python3 -m py_compile Native/CineFlowLibtorrentNative/helper/streamly_torrent_helper.py`
- `swift test --filter PlaybackEngineTests/testPlaybackPipelineHandsLocalTorrentStreamToPlayerWithoutBytePreflight`
- `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided`
- `swift test --filter PlaybackEngineTests/testPlaybackPipelineDebugTraceIncludesTorrentReadinessAndStreamURL`
- `swift test --filter PlaybackAutoSourceResolverTests`
- `swift test --filter PlaybackEngineTests`
- `swift test --filter TorrentEngineTests`
- `swift test --filter PlayerViewModelTests`
- `swift test --filter SourceProviderArchitectureTests`
- `swift test --filter SeriesDetailViewModelTests`

### Full test suite

Passed:

- `swift test`

Result:

- 228 tests passed
- 4 tests skipped
- 0 failures

### Live Torrentio source lookup

Passed:

- Torrentio movie endpoint for `tt0133093` returned streams with `infoHash`, `fileIdx`, trackers, and filename hints.
- Torrentio series endpoint for `tt0944947:1:1` returned streams with `infoHash`, `fileIdx`, trackers, and episode filename hints.

### Live legal torrent movie playback smoke

Source:

- Big Buck Bunny torrent from WebTorrent public sample torrents.

Passed:

- Native bridge resolved torrent files and streaming URL.
- In-app AVPlayer integration reached playback through the generated stream URL.

Commands passed:

- `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent swift test --filter NativeLibtorrentBridgeTests/testNativeBridgeCanResolveFilesAndStreamingURLWhenTorrentFileEnvironmentIsProvided`
- `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided`

The final post-build torrent-to-player smoke passed in 85.777 seconds with the bounded 120 second HLS startup window. The integration test now also waits until AVPlayer reaches at least 12 seconds of playback time, covering the previous "plays for about 4 seconds then stops" regression.

### Production build

Passed:

- `script/build_native_libtorrent_runtime.sh`
- `script/build_release.sh --unsigned`

Output:

- `dist/release/Streamly.app`

Bundle checks:

- Version/build: `1.0.10` / `1010`
- `Contents/Resources/ffmpeg`: present and executable
- `Contents/Frameworks/CineFlowLibtorrentNative.framework`: present

Non-blocking build warnings:

- AVFoundation deprecated `asset.duration`.
- Native framework built for macOS 15 while app target is macOS 13.

### DMG

Passed:

- `script/create_dmg.sh --skip-build`
- `hdiutil verify dist/dmg/Streamly-1.0.10.dmg`
- SHA-256: `4751b350c2923cc3c07892e5c8bde0d6ff40ab63c219307a2b2048243f557ec0`

DMG runtime smoke:

- Mounted the new DMG.
- Verified `Streamly.app` is present.
- Verified bundled `ffmpeg` is executable.
- Verified rebuilt `streamly-torrent-helper` is executable inside `CineFlowLibtorrentNative.framework`.
- Detached the DMG cleanly.

### Production app launch smoke

Passed:

- Launched `dist/release/Streamly.app/Contents/MacOS/Streamly` with isolated app home and playback debug enabled.
- Process stayed alive through startup.
- No immediate production-launch crash.

## Scenario Coverage

| Scenario | Status | Evidence |
| --- | --- | --- |
| Movie playback | Passed | Legal Big Buck Bunny torrent reached AVPlayer playback and sustained beyond the 12-second regression threshold after final build. |
| Movie source lookup | Passed | `tmdb:movie:603` resolves to `tt0133093`, searches Torrentio, and populates hero/player best release. |
| Series playback | Passed by automated coverage | Series ID without episode context resolves first released episode; selected episode context remains selected-media based. |
| Series source lookup | Passed | `tmdb:tv:1399` resolves to `tt0944947:1:1` for automatic first-episode playback lookup. |
| Source switching | Passed by automated coverage | Route session coordinator and playback pipeline fallback/cleanup tests passed. |
| Repeated launch/session reset | Passed by automated coverage plus launch smoke | Coordinator cleanup and stale-token behavior covered; production app launch smoke passed. |
| Failed source fallback | Passed by automated coverage | Playback pipeline fallback tests passed and failed sessions are removed before next attempt. |
| Dev mode | Passed | SwiftPM test suite and native bridge integration tests passed. |
| Production build | Passed | `dist/release/Streamly.app` rebuilt and launch-smoked. |
| Production DMG | Passed | New DMG created, verified, mounted, and runtime-checked. |

Manual GUI click-through against arbitrary third-party Torrentio movie/series releases was not automated in this pass. The blocker-level playback path was validated with a legal live torrent and with the same bundled runtime assets used by the production app/DMG.

## Current Acceptance Status

- Film starts after selecting a valid torrent/source: passed with legal live torrent smoke.
- `Torrent source is not ready` should not appear for a working source: local torrent stream URLs are handed to player buffering instead of failing a short byte preflight.
- No endless buffering: staged timeouts and fallback boundaries are in place.
- Player receives playable stream URL: verified in debug test and live torrent integration test.
- Playback does not stop after the first few seconds: final live torrent integration test now waits for at least 12 seconds of AVPlayer playback time.
- Player route receives a real Torrentio release before starting torrent playback: verified by `PlaybackAutoSourceResolverTests`.
- Torrent metadata and peers are processed: metadata/file list is required; peer/status fields are logged when available.
- Old playback sessions do not break new ones: route coordinator owns cleanup and token checks.
- Debug logs expose exact failure stage: added/verified staged diagnostic events.
- Playback works in dev and production runtime: SwiftPM/dev tests, release-bundled FFmpeg integration smoke, production launch smoke, and DMG runtime check passed.
- New working DMG is in `dist`: `dist/dmg/Streamly-1.0.10.dmg`.

## 2026-05-11 Final Buffering Fix

### Root cause of the 8-9 second stall

The previous fix proved the selected torrent could reach AVPlayer, but the stream was still too fragile:

- FFmpeg handed AVPlayer an HLS playlist as soon as the first segment existed, so playback could start before there was enough forward buffer.
- The local torrent HTTP server waited on each requested range with a fixed timeout. On slow peers, one chunk could time out even while the torrent was still making progress.
- The helper prioritized only the initial startup bytes. After playback started, there was no dedicated background loop keeping the selected file downloading to completion.
- The UI had no live torrent transfer status wired into the player, so the buffering card showed `Download speed: unavailable` even when libtorrent had real speed and peer data.

### Changes made

- Native helper now starts a background selected-file downloader after file selection or stream URL creation.
- The helper keeps only the selected media file at high priority, keeps sequential download enabled, and continuously prioritizes a 128 MiB rolling window ahead of the current contiguous buffer.
- Range serving now uses a 120 second no-progress timeout instead of a fixed deadline. Active slow downloads are allowed to continue.
- `TorrentStatus.progress` now reports selected-file totals when a file is selected: downloaded bytes, total bytes, contiguous playable buffer, and live speed.
- Local torrent HLS startup now waits for at least 4 segments and at least 8 seconds of playlist duration.
- Local torrent HLS uses an event-style playlist with `hls_list_size 0` and no segment deletion, so AVPlayer cannot stall because a lagging segment was removed.
- Local torrent FFmpeg read timeout is now 120 seconds.
- Player routing carries the active `TorrentSession` into `PlayerViewModel`.
- `PlayerViewModel` polls live `TorrentStatus` for the current session and ignores unrelated session IDs.
- Buffering card now shows real transfer details:
  - download speed;
  - loaded bytes / selected file size / percent;
  - playable buffer bytes;
  - ETA;
  - peers and selected file in advanced details.

### Updated test coverage

Passed focused tests:

- `python3 -m py_compile Native/CineFlowLibtorrentNative/helper/streamly_torrent_helper.py`
- `swift build --product Streamly`
- `swift test --filter PlaybackEngineTests/testTorrentHLSStartupRequiresFourSegmentsAndEightSeconds`
- `swift test --filter PlayerViewModelTests/testBufferingPresentation`
- `swift test --filter NativeLibtorrentBridgeTests/testNativeBridgeDecodesStatusFilesAndStreamingURLFromABI`

Integration threshold updated:

- `TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided` now requires AVPlayer to reach at least 30 seconds of playback time.

### Production build status

Completed in this pass.

Passed:

- `swift test`: 259 tests, 4 skipped, 0 failures.
- Live legal torrent-to-player smoke after rebuilding the native helper:
  - `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided`
  - Result: passed in 70.935 seconds.
  - The test requires AVPlayer to reach at least 30 seconds of playback time.
- `script/build_native_libtorrent_runtime.sh`
- `script/build_release.sh --unsigned`
- `script/create_dmg.sh --skip-build`
- `hdiutil verify dist/dmg/Streamly-1.0.10.dmg`
- DMG mount/runtime check:
  - `Streamly.app` present.
  - bundled `ffmpeg` executable.
  - bundled `streamly-torrent-helper` executable.
- Production app launch smoke:
  - `dist/release/Streamly.app/Contents/MacOS/Streamly` stayed alive through startup.

Output:

- App: `dist/release/Streamly.app`
- DMG: `dist/dmg/Streamly-1.0.10.dmg`
- SHA-256: `ed8ad7a21b5c5fce265bd878d4de010619cfc338547e0e22404341f401757968`

Remaining manual validation:

- User click-through against real Torrentio/RuTor/Rutracker sources in the production DMG. Automated validation covered the same native torrent helper, FFmpeg HLS bridge, selected-file streaming path, and AVPlayer reaching 30 seconds on a legal live torrent.
