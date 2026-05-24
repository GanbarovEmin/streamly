# Streamly Full Application QA Report

Audit date: 2026-05-10
Scope: Block 36, full manual and technical audit before further product work.
Build under test: local unsigned `dist/release/Streamly.app`, version `1.0.01` build `1001`.
Environment: macOS, Apple Silicon, isolated QA homes via `CFFIXED_USER_HOME`.

## Naming Note

The public app name under test is `Streamly`. Some source modules and legacy migration paths still use `CineFlow*` implementation names. Bugs below use public Streamly naming unless the legacy path is directly relevant to data migration.

## Verification Commands

```bash
swift test
script/build_release.sh --unsigned
script/create_dmg.sh --skip-build
open -n dist/release/Streamly.app --env "CFFIXED_USER_HOME=<temporary QA home>"
```

Result summary:

- `swift test`: passed, 162 tests executed, 1 skipped, 0 failures.
- `script/build_release.sh --unsigned`: passed; release bundle created at `dist/release/Streamly.app`.
- `script/create_dmg.sh --skip-build`: passed; DMG created at `dist/dmg/Streamly-1.0.01.dmg`.
- Bundle launch smoke: passed with normal `open -n`; System Events saw `Streamly` window at `{308, 211}`, size `{1440, 900}`.
- Direct raw executable smoke: process started, but no accessible window appeared through System Events. Normal bundle launch is the valid run path.

## QA Artifacts

- Window/Home smoke screenshot: `qa_artifacts/2026-05-10/window-smoke.png`
- Search smoke screenshot: `qa_artifacts/2026-05-10/search-smoke.png`
- Detail click smoke screenshot: `qa_artifacts/2026-05-10/detail-click-smoke.png`
- Fresh install log sample: `/tmp/streamly-fresh-home.RVsjks/Library/Application Support/Streamly/Logs/streamly.log`
- Upgrade migration QA home: `/tmp/streamly-upgrade-home.3MXk9D`

## Block 40 Bug Bash Update

Update date: 2026-05-10

- `QA-001`: fixed. Development seed data is gated behind `STREAMLY_SEED_DEVELOPMENT_DATA=1` / `CINEFLOW_SEED_DEVELOPMENT_DATA=1`; fresh isolated launch now creates zero media/library/list/progress rows.
- `QA-002`: fixed as a release-blocking gate. Production release packaging now refuses to build/create a DMG without `Vendor/CineFlowLibtorrentNative.xcframework`; development QA builds require explicit `--allow-missing-native-runtime`.
- `QA-003`: fixed as a release-blocking gate. Production release packaging now refuses to build/create a DMG while `MPVPlaybackService` still contains the placeholder mpv bridge; development QA builds require explicit `--allow-placeholder-mpv-runtime`.
- `QA-004`: fixed. Production app initialization now wires `SubtitleService()` instead of `MockSubtitleService()`.

Block 40 regression checks:

```bash
bash -n script/build_release.sh && bash -n script/create_dmg.sh
script/build_release.sh --unsigned
script/build_release.sh --unsigned --allow-missing-native-runtime
script/create_dmg.sh --skip-build
script/create_dmg.sh --skip-build --allow-missing-native-runtime
script/build_release.sh --unsigned --allow-missing-native-runtime --allow-placeholder-mpv-runtime
open -n dist/release/Streamly.app --env "CFFIXED_USER_HOME=<temporary QA home>"
swift test --filter 'ReleasePackagingTests|SubtitleServiceTests|SettingsViewModelTests/testActionsClearCacheCheckUpdatesAndExportDiagnostics'
```

Observed results:

- Default `build_release` exits `72` without native libtorrent.
- Default `create_dmg --skip-build` exits `72` without native libtorrent in the app bundle.
- `build_release --allow-missing-native-runtime` exits `74` while mpv bridge is placeholder.
- `create_dmg --skip-build --allow-missing-native-runtime` exits `74` while mpv bridge is placeholder.
- Development QA build with both override flags succeeds and launches.
- Fresh isolated launch after the fix produced:

  ```text
  media_items|0
  library_items|0
  user_lists|0
  playback_progress|0
  ```

## Scenario Checklist

| Area | Scenario | Status | Evidence / Notes |
| --- | --- | --- | --- |
| Install | Fresh isolated launch with no prior app data | Fixed | Block 40 smoke with `CFFIXED_USER_HOME=/tmp/streamly-block40-fresh.FyOcG5` produced zero media/library/list/progress rows. See `QA-001`. |
| Install | Upgrade from legacy `Application Support/CineFlow/CineFlow.sqlite` | Passed | Runtime migration moved data to `Application Support/Streamly/Streamly.sqlite`; library/progress counts preserved. |
| Install | DMG creation and mount verification | Passed | `script/create_dmg.sh --skip-build` verified `Streamly.app`, `Applications`, `README.txt`. |
| Launch | Bundle launch through Finder/open | Passed | Window visible, traffic lights visible, hidden titlebar active. |
| Launch | Raw executable launch | Limited | Process runs, but window not accessible; use bundle launch for QA and user installs. |
| Window | Default size / min layout | Passed | Window smoke at 1440x900; app declares min frame 1200x760. |
| Window | Fullscreen command | Partially covered | Code path exists via `NSApp.keyWindow?.toggleFullScreen(nil)`; not fully manually exercised. |
| Window | Resize | Partially covered | Min frame verified by code; no full visual resize matrix completed in this pass. |
| Window | Multi-monitor | Not verified | Requires physical multi-monitor manual pass. |
| Window | Sleep/wake | Not verified | Requires long-running manual device pass. |
| Search | Missing TMDB API key | Passed | Search still works through Cinemeta fallback; screenshot shows Matrix results without configured TMDB keys. |
| Search | Metadata search | Passed | `matrix` returns visible results and caches metadata/images. |
| Search | Offline / metadata unavailable | Passed in automated mock | `SearchErrorHandlingTests` covers no internet and retry messaging. Manual network-disconnect pass not performed to avoid changing system networking. |
| Detail | Movie detail | Partially verified | UI smoke reached search results. Existing tests cover movie detail metadata, releases, local source selection. Coordinate click smoke did not reliably navigate. |
| Detail | Series detail / season / episode | Covered by tests | `SeriesDetailViewModelTests` and `TMDBUIProvidersTests` cover season/episode release lookup and progress. |
| Releases | Release ranking | Covered by tests | `ReleaseRankingEngineTests`, `SearchViewModelTests`, `SeriesDetailViewModelTests`. |
| Torrent | Torrent source unavailable | Fixed as release gate | Production packaging now fails without native libtorrent; development override is explicit. See `QA-002`. |
| Playback | Local AVFoundation playback | Covered by tests | `PlaybackEngineTests` covers AVFoundation local state changes. |
| Playback | Torrent -> mpv E2E | Fixed as release gate | Production packaging now fails while mpv bridge is placeholder; full E2E remains blocked until the runtime is supplied. See `QA-003` and `../../known-issues.md`. |
| Subtitles | Local subtitle load and disable | Covered by tests | `PlayerViewModelTests` covers `.srt` / `.ass` local track handling. |
| Subtitles | Online subtitle search/download in app | Fixed | Production app now wires `SubtitleService()`. Missing credentials produce the real unavailable-provider path. See `QA-004`. |
| Audio | Audio track selection | Covered by tests | `PlayerViewModelTests` covers audio selection through mock playback service. |
| Stop/progress | Stop saves progress | Covered by tests | `PlayerViewModelTests`, `PlaybackEngineTests`, database tests. |
| Continue Watching | Resume from saved progress | Fixed | Fresh install no longer seeds Matrix progress; resume behavior remains covered by `PlayerViewModelTests` and database tests. See `QA-001`. |
| Library | Add/remove library and lists | Covered by tests | `LibraryViewModelTests`, `UserListsViewModelTests`, database persistence tests. |
| Favorites | Favorites persistence | Covered by tests | Database layer includes favorite tables and CRUD coverage. |
| Ratings | Ratings persistence | Covered by tests | Database layer covers ratings CRUD. |
| History | Watch history | Covered by tests | `WatchHistoryViewModelTests`, database layer tests. |
| Settings | Settings persistence | Covered by tests | `SettingsViewModelTests`, `DatabaseLayerTests`. |
| Settings | TMDB credentials save/clear | Covered by tests | `SettingsViewModelTests` verifies missing/saved/cleared states. |
| Settings | Source settings persistence | Covered by tests | Torrentio settings tests cover provider/language/quality/result limit. |
| Settings | Diagnostics export | Covered by tests | `DiagnosticsServiceTests` verifies sanitized ZIP and `streamly.log`. |
| Cache | Corrupted cache file present | Passed smoke | App launched with bogus `ImageCache/posters/corrupt-image.bin`; no crash. |
| Cache | Clear cache action | Covered by tests | `SettingsViewModelTests` covers clear image cache. |
| Updates | GitHub release check | Covered by tests | `GitHubReleaseUpdateServiceTests`; Sparkle appcast docs/config verified by packaging tests. |
| Privacy | Local-first storage | Partially passed | Data is local. Fresh install still seeds dev library/progress, which violates expected empty local state. |

## Bugs / Findings

### QA-001 - Fresh install is not empty and shows development library/progress

Severity: High
Status: Fixed
Affected module: `Sources/CineFlowApp/CineFlowApp.swift`, `Sources/CineFlowDatabase/Seed/DatabaseSeeder.swift`, Home / Library / Continue Watching.

Steps to reproduce:

1. Create an isolated user home: `QA_HOME="$(mktemp -d /tmp/streamly-fresh-home.XXXXXX)"`.
2. Launch app: `open -n dist/release/Streamly.app --env "CFFIXED_USER_HOME=$QA_HOME"`.
3. Inspect `"$QA_HOME/Library/Application Support/Streamly/Streamly.sqlite"`.
4. Open Home / Continue Watching.

Expected result:

- Fresh install starts with an empty user library, no favorites, no lists, no watch progress and no seeded personal data.
- Empty states explain how to search, add local files, configure sources and build a library.

Actual result:

- Original QA result: fresh install created seeded data:

  ```text
  media_items|2
  library_items|2
  user_lists|1
  playback_progress|1
  ```

- Home screenshot shows seeded hero content and `Continue Watching` with `The Matrix`.
- Source: app init calls `DatabaseSeeder.seedDevelopmentData(in:)` unconditionally when a live database opens.

Block 40 fix summary:

- `CineFlowApplication` now seeds development data only when `STREAMLY_SEED_DEVELOPMENT_DATA=1` or `CINEFLOW_SEED_DEVELOPMENT_DATA=1` is set.
- Production/default launch does not seed personal media, lists or progress.

Regression check:

- Development QA build launched with an isolated `CFFIXED_USER_HOME`.
- SQLite counts after launch:

  ```text
  media_items|0
  library_items|0
  user_lists|0
  playback_progress|0
  ```

- Automated guard: `ReleasePackagingTests.testProductionAppDoesNotSeedDevelopmentDataByDefaultAndUsesRealSubtitles`.

Logs/screenshots:

- `qa_artifacts/2026-05-10/window-smoke.png`
- Fresh launch log: `2026-05-10T16:54:26Z [INFO] app: Streamly app launch {}`

Impact:

- Violates fresh-install acceptance criteria.
- Creates misleading personal library/history on first run.
- Makes offline/fresh-state QA unreliable because the app is not testing true empty state.

Recommended fix:

- Gate development seeding behind an explicit debug/development flag or remove it from production app init.
- Add a regression test that production `CineFlowApplication`/app bootstrap does not seed library/progress by default.

### QA-002 - Torrent E2E is blocked because the release bundle has no native libtorrent framework

Severity: Critical
Status: Fixed
Affected module: `script/build_release.sh`, `Sources/CineFlowTorrent/NativeLibtorrentBridge.swift`, `Sources/CineFlowTorrent/EmbeddedLibtorrentTorrentEngine`.

Steps to reproduce:

1. Run `script/build_release.sh --unsigned`.
2. Observe build output.
3. Try to start a torrent route from a release or magnet in the app.

Expected result:

- Release build includes the native libtorrent bridge or has a clearly supported production alternative.
- Movie/series release flow can start torrent streaming and produce a playable local streaming URL.

Actual result:

- Original QA result: build output stated that `Vendor/CineFlowLibtorrentNative.xcframework` was missing and torrent routes would surface the unavailable bridge state.
- Current result: `Vendor/CineFlowLibtorrentNative.xcframework` is present, exported ABI symbols load, and `NativeLibtorrentBridge` can create/start a magnet session through the bundled helper.

Block 40 fix summary:

- `script/build_release.sh` now refuses production packaging without `Vendor/CineFlowLibtorrentNative.xcframework`.
- `script/create_dmg.sh --skip-build` now refuses to create a DMG if `Streamly.app` lacks `Contents/Frameworks/CineFlowLibtorrentNative.framework`.
- Development-only packaging requires explicit `--allow-missing-native-runtime`.

Block 41 fix summary:

- Added `Native/CineFlowLibtorrentNative` C ABI shim source and `script/build_native_libtorrent_runtime.sh`.
- Built and packaged `Vendor/CineFlowLibtorrentNative.xcframework` with a bundled `libtorrent 2.0.11` helper.
- Added Torrentio `fileIdx` propagation to `TorrentRelease.preferredFileIndex` and route selection, so series episodes select the intended file from multi-file torrents.
- Fixed helper metadata polling so libtorrent `error_code(value=0)` is treated as no error instead of `metadata_unavailable`.
- Fixed native bridge/helper timeout mismatch that surfaced as `helper_read_failed` on real Torrentio playback.
- Fixed the local torrent HTTP server so open-ended/no-Range requests return a small progressive Range window instead of waiting for the whole movie file.
- Added `HEAD`, `Accept-Ranges`, and byte-range handling to the local HLS server used by AVFoundation.
- Replaced the external-player default path with in-app HLS preparation: `TranscodingAVPlaybackService` uses bundled `ffmpeg`, serves generated HLS over `127.0.0.1`, and feeds that URL to the in-app `AVPlayer`.

Regression check:

- `CINEFLOW_NATIVE_LIBTORRENT_TEST_MAGNET='magnet:?xt=urn:btih:0123456789012345678901234567890123456789' swift test --filter NativeLibtorrentBridgeTests/testNativeBridgeCanStartRealMagnetWhenIntegrationEnvironmentIsProvided` passes.
- `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent swift test --filter NativeLibtorrentBridgeTests/testNativeBridgeCanResolveFilesAndStreamingURLWhenTorrentFileEnvironmentIsProvided` passes.
- Installed app bundle helper streamed Big Buck Bunny over `127.0.0.1` and returned HTTP `206` Range bytes to the player path.
- Installed app bundle helper plus bundled `ffmpeg` produced an HLS playlist and media segments from the local torrent stream; AVFoundation accepted the same HLS over `127.0.0.1` as playable.
- `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent STREAMLY_TRANSCODE_TEST_FFMPEG=/Applications/Streamly.app/Contents/Resources/ffmpeg swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided` passes.
- `script/build_release.sh --unsigned` passes and copies `CineFlowLibtorrentNative.framework`.
- `script/build_release.sh --unsigned` copies `Contents/Resources/ffmpeg` and refuses release packaging without it.
- `script/create_dmg.sh --skip-build` passes and creates `dist/dmg/Streamly-1.0.01.dmg` with `CineFlowLibtorrentNative.framework` and `Contents/Resources/ffmpeg`; latest checksum: `c66bece7d81003956ffa53f6ffddfc7f8444aaefc611106b9da46d7a2c264542`.
- `ReleasePackagingTests.testReleaseScriptRequiresNativeLibtorrentUnlessDevelopmentOverrideIsExplicit` passes.
- `ReleasePackagingTests.testReleaseScriptsRequireBundledFFmpegForInAppTorrentPlayback` passes.

Logs/screenshots:

- Build output from `script/build_release.sh --unsigned`.

Impact:

- Critical torrent runtime blocker is closed for macOS 15+ arm64 builds.
- Full manual swarm validation still depends on testing with a healthy legal torrent.

Recommended fix:

- Run clean-machine DMG QA with a healthy legal movie/series torrent and record playback startup timing.

### QA-003 - production playback path was external/placeholder instead of in-app

Severity: Critical
Status: Fixed
Affected module: `Sources/CineFlowApp/CineFlowApp.swift`, `Sources/CineFlowPlayback/AVFoundationPlaybackService.swift`, `Sources/CineFlowPlayback/MPVPlaybackService.swift`, `Sources/CineFlowPlayback/MPVRenderView.swift`.

Steps to reproduce:

1. Inspect production app environment construction.
2. Run playback tests.
3. Attempt required E2E path: torrent release -> mpv playback.

Expected result:

- Production app opens torrent streams inside the Streamly player view.
- MKV/HEVC torrent streams are prepared locally without requiring the user to install or switch to an external player.

Actual result:

- Original QA result: production app wired `AVFoundationPlaybackService()`, `MPVPlaybackService` used placeholder behavior, and no full torrent -> mpv -> progress path was executable in the production bundle.
- Current result: production app uses `TranscodingAVPlaybackService`, which turns local torrent HTTP streams into local HLS through bundled `ffmpeg`, serves that HLS over `127.0.0.1`, and plays it inside the Streamly `AVPlayer` surface.

Block 40 fix summary:

- `script/build_release.sh` now refuses production packaging while `MPVPlaybackService` contains `PlaceholderMPVBridge`.
- `script/create_dmg.sh --skip-build` now applies the same mpv placeholder gate before creating a DMG.
- Development-only packaging requires explicit `--allow-placeholder-mpv-runtime`.

Block 41 fix summary:

- Replaced the production default playback wiring with `TranscodingAVPlaybackService`.
- Added bundled `ffmpeg` release packaging and DMG gates for in-app torrent playback.
- Added local HLS HTTP server support for `HEAD` and byte-range responses so AVFoundation can load generated HLS manifests and segments reliably.
- Kept `MPVPlaybackService` as a separate bridge path, but it is no longer the default production path because external `iina-cli/mpv` does not render inside Streamly.

Regression check:

- `swift test --filter PlaybackEngineTests` passes.
- `STREAMLY_TRANSCODE_TEST_FFMPEG=/Applications/Streamly.app/Contents/Resources/ffmpeg swift test --filter PlaybackEngineTests/testTranscodingAVPlaybackServiceCanStartInAppHLSWhenIntegrationEnvironmentIsProvided` passes.
- `CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent STREAMLY_TRANSCODE_TEST_FFMPEG=/Applications/Streamly.app/Contents/Resources/ffmpeg swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided` passes.
- Installed app bundle produced playable HLS over `127.0.0.1` from a local torrent stream and AVFoundation accepted the HTTP HLS as playable.
- `script/build_release.sh --unsigned` passes without `--allow-placeholder-mpv-runtime`.
- `script/create_dmg.sh --skip-build` passes without `--allow-placeholder-mpv-runtime`.
- `ReleasePackagingTests.testReleaseScriptsRejectPlaceholderMPVRuntimeForProductionArtifacts` passes.
- `ReleasePackagingTests.testReleaseScriptsRequireBundledFFmpegForInAppTorrentPlayback` passes.

Logs/screenshots:

- Test evidence: `PlaybackEngineTests.testMPVPlaybackServiceUsesSwiftBoundaryAndConfiguredOptions`.

Impact:

- Release-blocking external/placeholder playback path is closed for the main Play flow.
- Full embedded libmpv rendering and native track sync can still be revisited later, but it is no longer required for first playback.

Recommended fix:

- Keep profiling startup latency on real healthy swarms and tune ffmpeg transcode settings for faster first frame.

### QA-004 - Production app wires mock subtitles, so online subtitle workflow is unavailable

Severity: High
Status: Fixed
Affected module: `Sources/CineFlowApp/CineFlowApp.swift`, `Sources/CineFlowSubtitles/SubtitleService.swift`, player subtitle UI.

Steps to reproduce:

1. Inspect production app environment construction.
2. Try online subtitle search/download in app.
3. Compare with `PlayerViewModelTests`, which only injects a real `SubtitleService` manually.

Expected result:

- Production app provides a real subtitle service or a clear disabled/unavailable state with recovery text.
- Online subtitle workflow can be tested for available/unavailable provider states.

Actual result:

- Original QA result: app environment used `subtitleService: MockSubtitleService()`, while real `SubtitleService` was tested only in isolation.

Block 40 fix summary:

- Production app init now wires `subtitleService: SubtitleService()`.
- Missing OpenSubtitles credentials now follow the real `SubtitleServiceError.openSubtitlesCredentialsMissing` path instead of silently returning mock data.

Regression check:

- `ReleasePackagingTests.testProductionAppDoesNotSeedDevelopmentDataByDefaultAndUsesRealSubtitles` passes.
- `SubtitleServiceTests` pass.

Logs/screenshots:

- Code evidence: `Sources/CineFlowApp/CineFlowApp.swift`.
- Test evidence: `PlayerViewModelTests.testPlayerViewModelCanFindOnlineLoadLocalAndDisableSubtitles`.

Impact:

- Required subtitles/audio scenario cannot be fully validated in the production app.
- Users may see subtitle UI expectations without a real provider behind it.

Recommended fix:

- Wire a production subtitle service or explicitly mark online subtitle search unavailable until credentials/provider setup exists.
- Add an app-environment test proving production bootstrap does not use mock subtitle services.

### QA-005 - Manual detail navigation via coordinate smoke was unreliable

Severity: Medium
Status: Needs follow-up
Affected module: UI automation/accessibility surface, Search -> Detail flow.

Steps to reproduce:

1. Launch bundle with isolated home.
2. Use AppleScript to activate Streamly.
3. Send `Cmd+L`, type `matrix`.
4. Attempt coordinate click on the first result.

Expected result:

- First visible search result opens detail reliably.
- UI controls are accessible enough for deterministic automation.

Actual result:

- Search results rendered, but coordinate click smoke did not navigate to detail in the captured run.
- Existing unit tests cover detail view models and provider mapping, but manual UI automation is not robust yet.

Logs/screenshots:

- `qa_artifacts/2026-05-10/search-smoke.png`
- `qa_artifacts/2026-05-10/detail-click-smoke.png`

Impact:

- Could be only coordinate fragility, but it exposes a QA gap: no stable UI automation identifiers or accessibility-driven navigation smoke.

Recommended fix:

- Add accessibility identifiers/labels for search result cards and primary actions.
- Add a small UI smoke harness for Search -> Detail -> Play affordance.

### QA-006 - Multi-monitor and sleep/wake behavior are not yet validated

Severity: Medium
Status: Not verified
Affected module: macOS window lifecycle, `WindowGroup`, hidden titlebar, playback/progress lifecycle.

Steps to reproduce:

1. Use a multi-monitor setup.
2. Move Streamly between monitors.
3. Enter/exit fullscreen.
4. Start playback/progress.
5. Sleep and wake the Mac.

Expected result:

- Window restores sanely, traffic lights remain usable, playback state/progress survives sleep/wake, and no hidden-titlebar layout breaks occur.

Actual result:

- Not completed in this environment.
- Single-window bundle launch and default 1440x900 smoke passed.

Logs/screenshots:

- `qa_artifacts/2026-05-10/window-smoke.png`

Impact:

- Required manual QA area remains open before a release candidate.

Recommended fix:

- Run on real hardware with at least two displays and a real sleep/wake cycle.
- Add a release checklist line requiring evidence for fullscreen, resize, multi-monitor and sleep/wake.

## Error Scenario Matrix

| Error scenario | Status | Evidence |
| --- | --- | --- |
| No internet | Covered by automated test | `SearchErrorHandlingTests.testSearchFailureShowsUserSafeMessageAndLogsTechnicalDetails`. |
| Metadata unavailable | Covered by automated test | Search retry and provider failure tests. |
| Missing TMDB API key | Passed smoke | `matrix` search worked through Cinemeta fallback in isolated home. |
| Source unavailable | Covered by tests / release-gated | Source manager tests cover disabled sources; production packaging still blocks missing native runtime via `QA-002`. |
| Torrent not starting | Fixed | Native libtorrent bridge is bundled; native bridge integration smoke passes. |
| Player cannot open file | Covered by tests | Playback error paths and mock/AVFoundation state covered. |
| Subtitles unavailable | Fixed | Production app now wires real `SubtitleService`; missing credentials are surfaced through the real error path. |
| Corrupted cache | Passed launch smoke | App launched with bogus cache file and did not crash. |
| Settings persistence | Covered by tests | `SettingsViewModelTests`, `DatabaseLayerTests`. |

## Release Readiness Assessment

Current status: release gates pass with bundled torrent runtime; clean-machine and real-swarm manual QA are still required before public release.

Critical blockers:

1. Clean-machine DMG install has not yet been validated outside the development checkout.
2. Full real-swarm movie/series playback should be manually tested with a healthy legal torrent before public release.

High priority:

1. Closed: production development seeding is gated behind explicit env flags.
2. Closed: production app wires real subtitles.

Recommended next block:

- Run true torrent -> playback E2E from the DMG without development override flags.
- Continue Medium findings after clean-machine playback QA.
