# Streamly Critical Playback Fix Report

Date: 2026-05-11
Branch: `codex/critical-playback-fix`

## Architecture Summary

Streamly playback is now organized around a Stremio-like staged pipeline:

1. Selected media context
2. Selected torrent/source release
3. Torrent session start
4. Metadata/file list load
5. Explicit media file selection
6. File priority setup
7. Local HTTP stream URL resolution
8. Stream availability probe
9. In-app AV/HLS playback

This follows the same architectural split used by Stremio stream objects: source metadata provides `infoHash`/`fileIdx`, the runtime opens a torrent session, selects a specific file, then plays a local stream URL. References used:

- https://stremio.github.io/stremio-addon-sdk/api/responses/stream.html
- https://github.com/Stremio/stremio-core
- https://github.com/Stremio/stremio-web

## Root Causes Found

- Playback state was bound too closely to release metadata, so a player route could display stale media titles such as "The Matrix" after switching to another movie or series episode.
- `EmbeddedLibtorrentTorrentEngine.startStreaming` did too much work in one call: add/start torrent, metadata, file selection, priority, and URL resolution were coupled, which made timeout, cleanup, and fallback behavior hard to reason about.
- Old torrent/player sessions were not centrally owned at the route level, creating race windows when switching sources or episodes quickly.
- Failed torrent sessions could remain active while fallback releases were attempted.
- The native helper lacked a graceful `/shutdown` path and parent-process watchdog, increasing orphan-helper risk in production builds.

## Implemented Changes

### Session Lifecycle

- Added `PlaybackSessionCoordinator` in the player route layer.
- The coordinator owns one active route token and one active torrent session ID.
- Source switches, route disappearance, retry/fallback, and local source loads now stop the player and remove the previous active torrent session before continuing.
- Every async route load checks a monotonically increasing token before mutating player UI state.

### Stale Metadata Fix

- Added `PlaybackSelectionContext` with:
  - `mediaID`
  - `displayTitle`
  - `mediaKind`
  - `seasonNumber`
  - `episodeNumber`
  - `episodeID`
- Movie detail, series detail, search playback, local source playback, and hero playback now pass the selected media context into the player route.
- `PlaybackMediaSource` now stores `selectionContext` and uses the selected media title for UI display while preserving the release title as source metadata.
- Series progress now records against `mediaID + episodeID`, not a stale or collapsed player source ID.
- Player overlay now shows the selected episode label when available.
- Removed the live hero player path's hardcoded Matrix destination; it now uses the selected featured item.

### Torrent Pipeline

- Added `PlaybackPipeline` as the explicit staged torrent resolver.
- `EmbeddedLibtorrentTorrentEngine.startStreaming` now only adds/starts the torrent session and returns the session.
- File selection is centralized through `TorrentMediaFileSelector`.
- `TorrentRelease.preferredFileIndex` is honored for Torrentio `fileIdx`; without it, automatic selection uses the best/largest non-sample media file.
- Pipeline stages have bounded timeouts:
  - torrent start: 10s
  - metadata/file list: 35s
  - file select/priority: 10s
  - stream URL: 5s
  - stream availability: 8s
  - HLS startup: 90s in the existing HLS bridge
- On resolve failure, the started torrent session is removed before fallback release resolution starts.

### Native Helper Stabilization

- Added `/shutdown` endpoint to `streamly_torrent_helper.py`.
- Native C++ bridge now passes `--parent-pid` to the helper.
- Helper writes Streamly-scoped PID files under the torrent cache.
- Helper exits if the parent app/native bridge process dies.
- Helper startup cleans stale Streamly-owned PID files only; it does not globally kill processes.
- `cf_libtorrent_engine_destroy` now tries graceful `/shutdown`, then SIGTERM, then SIGKILL.
- Rebuilt `Vendor/CineFlowLibtorrentNative.xcframework` with the updated helper and C++ shim.

### Diagnostics

- Playback pipeline debug logs now include:
  - selected media ID
  - selected episode ID
  - season/episode numbers
  - selected release/source
  - preferred file index
  - info hash
  - torrent session ID
  - metadata/file count
  - selected video file
  - stream availability stage
  - retry/fallback stage
  - cleanup result
- Player status diagnostics continue to feed the advanced playback debug model.

## Changed Files

- `Sources/CineFlowCore/Models/PlaybackModels.swift`
- `Sources/CineFlowCore/Models/MediaItem.swift`
- `Sources/CineFlowPlayback/PlaybackPipeline.swift`
- `Sources/CineFlowPlayback/PlaybackProgressRecorder.swift`
- `Sources/CineFlowTorrent/LibtorrentBridge.swift`
- `Sources/CineFlowUI/ShellModels.swift`
- `Sources/CineFlowUI/ContentContainerView.swift`
- `Sources/CineFlowUI/MovieDetailView.swift`
- `Sources/CineFlowUI/SeriesDetailView.swift`
- `Sources/CineFlowUI/SearchView.swift`
- `Sources/CineFlowUI/PlayerView.swift`
- `Sources/CineFlowUI/PlayerViewModel.swift`
- `Native/CineFlowLibtorrentNative/helper/streamly_torrent_helper.py`
- `Native/CineFlowLibtorrentNative/src/CineFlowLibtorrentNative.cpp`
- `Vendor/CineFlowLibtorrentNative.xcframework`
- `Tests/CineFlowPlaybackTests/PlaybackEngineTests.swift`
- `Tests/CineFlowTorrentTests/TorrentEngineTests.swift`

## Verification Performed

Passed:

- `python3 -m py_compile Native/CineFlowLibtorrentNative/helper/streamly_torrent_helper.py`
- `c++ -std=c++17 -fsyntax-only -I Native/CineFlowLibtorrentNative/include Native/CineFlowLibtorrentNative/src/CineFlowLibtorrentNative.cpp`
- `script/build_native_libtorrent_runtime.sh`

Passed after GRDB vendoring:

- `swift package resolve`
- `swift test --filter PlaybackEngineTests`
- `swift test --filter NativeLibtorrentBridgeTests`
- `swift test --filter PlayerViewModelTests`
- `swift test --filter SeriesDetailViewModelTests`
- `swift test --filter TorrentPlaybackIntegrationTests`
- `swift test`
- `script/build_release.sh`
- `script/create_dmg.sh --version 1.0.10 --build 1010`
- `/Users/eminganbarov/.codex/skills/streamly-deploy/scripts/deploy_streamly.sh --dry-run`

GRDB dependency fix:

- Vendored the GRDB SPM package under `Vendor/GRDB.swift`.
- Switched `Package.swift` from remote `https://github.com/groue/GRDB.swift.git` to `.package(path: "Vendor/GRDB.swift")`.
- Removed GRDB from `Package.resolved`.
- Kept only the app-needed local GRDB package surface: `GRDB`, `Sources/GRDBSQLite`, package metadata, license/readme.
- Removed the unused upstream test/custom-SQLite surface from the vendored package manifest so SwiftPM no longer tries to fetch `SQLiteCustom/src` / `SQLiteLib.git`.

Blocked:

- Live `streamly-deploy --live` is blocked only by missing `GITHUB_TOKEN`/`GH_TOKEN` in the local environment.
- Manual legal torrent playback QA still requires legal torrent and ffmpeg test env vars.

## Test Matrix Status

| Area | Status | Notes |
| --- | --- | --- |
| Movie playback pipeline | Code implemented, tests passing | Manual legal torrent runtime QA still pending. |
| Series playback metadata | Code implemented, tests added | Series source title/episode context now travels into player source and progress. |
| Source switching cleanup | Code implemented | Route coordinator removes previous active torrent session and ignores stale async completions. |
| Torrent fallback cleanup | Code implemented, tests added | Failed sessions are removed before fallback. |
| Native helper shutdown | Code implemented, native runtime rebuilt | `/shutdown`, parent PID watchdog, graceful destroy path added. |
| Range server behavior | Existing helper behavior retained | Helper still serves ranged file responses and bounded `503` errors. |
| Production build | Passed | `dist/release/Streamly.app` built. |
| New DMG | Passed | `dist/dmg/Streamly-1.0.10.dmg` and `.sha256` created. |
| Deploy dry-run | Passed | `streamly-deploy --dry-run` resolves `v1.0.10` and validates the matching DMG. |
| Live deploy | Blocked | Requires `GITHUB_TOKEN` or `GH_TOKEN`. |

## Remaining Risks

- Manual playback still needs to be verified with legal movie and series torrents.
- Live GitHub Release publication needs `GITHUB_TOKEN` or `GH_TOKEN`.
- The release app is unsigned because no signing identity was provided.
