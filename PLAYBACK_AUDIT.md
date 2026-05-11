# Playback Audit

Date: 2026-05-11  
Scope: Streamly playback pipeline, Stremio playback architecture research, production stabilization plan and implementation notes.

## Sources Reviewed

- Stremio Core repository: https://github.com/Stremio/stremio-core
- Stremio player model: https://github.com/Stremio/stremio-core/blob/development/src/models/player.rs
- Stremio stream model and conversion logic: https://github.com/Stremio/stremio-core/blob/development/src/types/resource/stream.rs
- Stremio streaming-server model: https://github.com/Stremio/stremio-core/blob/development/src/models/streaming_server.rs
- Stremio addon HTTP transport: https://github.com/Stremio/stremio-core/blob/development/src/addon_transport/http_transport/http_transport.rs
- Local Stremio server observed at `http://127.0.0.1:11470` on 2026-05-11. `/settings` reported server `4.20.17`, cache size `10GiB`, torrent handshake timeout `20000ms`, request timeout `4000ms`, soft download limit `2621440B/s`, hard limit `3670016B/s`, and minimum stable peers `5`.

## Current Streamly Playback Architecture Before This Pass

The pre-existing Streamly flow was split across UI routing, torrent engine, and player service:

1. `PlayerRouteView` received a selected `TorrentRelease`.
2. The route view directly called `torrentEngine.startStreaming(release)`.
3. It loaded app settings and applied torrent bandwidth limits.
4. It requested torrent files and optionally prompted for media file selection.
5. It requested `torrentEngine.getStreamingURL(sessionId:)`.
6. It only checked that the URL scheme was file/http/https.
7. It constructed `PlaybackMediaSource`.
8. `PlayerViewModel.start()` called `playbackService.play(source)`.
9. `AVFoundationPlaybackService` or `TranscodingAVPlaybackService` handed the URL to `AVPlayer` or a local HLS bridge.
10. Subtitles were injected through `SubtitleServiceProtocol` after player start.

That meant the route view was acting as an implicit playback orchestrator. It mixed source selection, stream resolving, file selection, player handoff, and fallback display without a bounded lifecycle.

## Playback Lifecycle Gaps Found

- No single production lifecycle existed. `PlaybackRunState` only represented `idle`, `loading`, `playing`, `paused`, `stopped`, and `failed`.
- `loading` covered several different operations: source selection, torrent start, stream resolving, URL readiness, and player startup.
- Stream URLs were not availability checked before player initialization.
- Fallback was mostly a UI suggestion after failure; route startup did not automatically try an alternative stream.
- Runtime monitoring relied on one-shot status streams in player services, so buffering/stalled/completed transitions could be missed.
- `PlayerViewModel.start()` could leave the UI visually loading if `service.play()` failed before a status update.
- Route-level async work had no request generation guard, so a stale async resolve could update state after a newer release selection.
- Debug logging was not consistently stage-based. Diagnostics existed, but there was no playback debug layer for source selected, resolve duration, availability, retry, buffering, subtitles, or player events.

## Race Conditions And Failure Points

- Release switching race: two `loadTorrentRelease` tasks could resolve out of order and the older task could set `.ready`.
- Infinite loading risk: thrown errors during player startup set `errorMessage`, but the playback state could remain `.loading`.
- Broken stream URL risk: a URL could pass scheme validation but fail immediately in `AVPlayer` or the HLS bridge.
- Manual file selection gap: after selecting a torrent file, the URL was handed off without availability verification.
- Status stream gap: one-shot service updates meant the UI could miss a later stall, buffering state, or completion.
- Duplicate logic: route startup and runtime fallback had separate paths with different assumptions.

## Stremio Architecture Observations

Stremio uses a layered model rather than a route-local playback script:

- Addons are queried through a resource transport. HTTP addon resources are normalized to predictable resource paths such as stream/meta/subtitle JSON endpoints.
- Stream objects preserve source metadata and behavior hints. Streams can be URL, YouTube, archives, NZB, torrent, external, player frame, or converted streaming-server sources.
- Stream conversion is explicit. Torrent streams are converted into streaming-server URLs using info hash, optional file index, trackers, and file filters. Archive/proxy cases also route through the streaming server when needed.
- The player model stores selected item, video params, subtitles, current stream, next streams, next stream, stream state, library item, and intro/outro state as independent model fields.
- On player load, Stremio resets the previous stream state, resolves current stream, updates subtitles, finds next video, loads next streams, and updates next-stream suggestion in one model transition.
- Async resource results are guarded against current selection/request before they mutate state.
- Streaming server state is explicit. It has settings, base URL, remote URL, playback devices, network/device info, torrent creation, and statistics loadables.
- Torrent statistics are modeled separately from player state, so buffering/peer/cache data can update without corrupting player selection.
- Last stream state is persisted per item and adjusted when source or binge group changes.

The architectural lesson is not to copy Stremio's code. The useful pattern for Streamly is: stream source resolution, streaming-server/torrent readiness, player handoff, subtitles, and runtime state must be separate stages with guarded async transitions.

## Comparison: Stremio vs Streamly Before

| Area | Stremio approach | Streamly before |
| --- | --- | --- |
| Source selection | Model-level selected stream and stream state | UI route directly selected and resolved release |
| Stream resolving | Explicit conversion layer with streaming server dependency | `startStreaming` then `getStreamingURL` inline in route |
| Torrent handling | Streaming server owns torrent creation/statistics | Torrent engine hidden behind protocol, but orchestration lived in UI |
| Availability | Streaming server readiness/base URL modeled | URL scheme check only |
| Subtitles | Player model refreshes subtitles on player load and video param changes | Subtitle service available, but not part of startup lifecycle |
| Fallback | Next stream/binge-group state modeled | Fallback suggestion existed, startup fallback was not automatic |
| Async safety | Request/selection guards on async results | Route task could update from stale result |
| Runtime monitoring | Stream state and statistics are separate model updates | Player status updates were mostly one-shot |

## Implemented Streamly Playback Pipeline

This pass introduced `PlaybackPipeline` in `CineFlowPlayback` and moved torrent startup orchestration out of `PlayerRouteView`.

New flow:

1. Source Selection
2. Stream Validation
3. Stream Resolve
4. Stream Availability Check
5. Player Initialization
6. Buffering State
7. Playback Start
8. Subtitle Injection
9. Runtime Monitoring
10. Recovery/Fallback Handling

Implemented details:

- `PlaybackRunState` now covers the required production lifecycle: `idle`, `loading`, `resolving`, `buffering`, `ready`, `playing`, `paused`, `stalled`, `failed`, `retrying`, and `completed`.
- `PlaybackPipelineRequest` carries media ID, selected release, fallback releases, bandwidth limits, ranking preferences, automatic fallback limit, and availability timeout.
- Torrent start, bandwidth setup, media file listing, media file selection, and streaming URL lookup are now bounded by an operation timeout.
- `PlaybackPipelineResult` returns `ready`, `needsMediaFileSelection`, or `failed` with structured attempts.
- `PlaybackPipelineAttempt` records the release, lifecycle state, resolved URL, and categorized `CineFlowError`.
- `DefaultPlaybackStreamAvailabilityChecker` performs HTTP HEAD with Range GET fallback; non-HTTP sources are treated as locally available.
- Startup fallback now automatically tries ranked alternative releases when the selected release cannot resolve or fails availability checks.
- `PlayerRouteView` now has a request counter guard so stale async resolve tasks cannot overwrite newer selections.
- Manual torrent file selection now also performs URL availability checking before player handoff.
- `PlayerViewModel` fails fast from loading/resolving/buffering/retrying states instead of leaving infinite loading.
- Runtime fallback can auto-trigger only when a route-level fallback handler exists. The existing manual fallback behavior remains intact for standalone player tests and local playback services.
- `AVFoundationPlaybackService.statusUpdates()` now monitors status periodically and can emit buffering, failed, and completed states.
- `PlaybackDebugLogger` adds a debug-gated logging layer. It is enabled via `STREAMLY_PLAYBACK_DEBUG=1`, `CINEFLOW_PLAYBACK_DEBUG=1`, or the `streamly.playback.debugEnabled` user default.

## Debug Events

The new debug layer supports these events:

- `source.selected`
- `stream.resolve.start`
- `torrent.session.started`
- `stream.availability.start`
- `stream.ready`
- `stream.failed`
- `fallback.retry`
- `player.status`

The logger is silent by default and writes to `DiagnosticsServiceProtocol` only when enabled.

## UI/UX Changes

- Route-level loading now renders a focused playback preparation surface instead of a generic skeleton.
- Startup errors now display the actual user-facing failure message where possible.
- Retry state sets the player to `.retrying` with a buffering presentation before route-level fallback takes over.
- Existing buffering, fallback, subtitle, fullscreen, seek, and pause/resume controls remain compatible with the new lifecycle.

## Remaining Recommendations

- Add integration tests with a real local streaming server URL and a controlled broken URL.
- Add a torrent-status bridge from `TorrentEngineProtocol.statusUpdates(sessionId:)` into `PlaybackStatus.bufferingState` so peer count, speed, and buffer fraction update continuously in the player overlay.
- Add subtitle startup telemetry for embedded/local/online track loading duration.
- Persist successful stream choice per media/episode and use it as the first candidate for future playback, similar to Stremio's stream item state.
- Add player-service adapters for unsupported codecs that can decide between direct AVPlayer, HLS bridge, or external MPV before player start.

## Verification

- `swift test --filter PlaybackEngineTests`
- `swift test --filter PlayerViewModelTests`

The transcoding HLS smoke test remains opt-in and was skipped because `STREAMLY_TRANSCODE_TEST_FFMPEG` was not set.
