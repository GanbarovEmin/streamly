# Torrent Stability QA

## Scope
- Torrent lifecycle: add magnet/torrent, start streaming, pause, resume, stop, remove and app termination.
- Streaming setup: sequential download, media-file selection and file priorities.
- Runtime status: connecting, metadata loading, buffering, streaming, stalled, paused, error and completed.
- Cache lifecycle: temporary storage under `Application Support/Streamly/TorrentCache`, cleanup policies and active-session protection.

## Manual Checks
1. Start a magnet release and confirm playback moves through loading/buffering to streaming without blocking the UI.
2. Use a torrent with multiple files. Confirm Streamly selects the largest media file, not samples or `.nfo` files.
3. Pause, resume, stop and close the player. Confirm the session status changes and the app stays responsive.
4. Start playback, open Settings -> Cache and run auto-clean. Confirm active stream cache is protected.
5. Set download/upload bandwidth limits in Settings -> Cache, start a new stream and confirm the engine receives the limits.
6. Simulate a bad connection/no peers. Confirm the user-facing state is stalled/error instead of a raw technical failure.
7. Quit the app while a stream is active. Confirm the app performs graceful torrent shutdown before termination.

## Automated Coverage
- `TorrentEngineTests.testTorrentStatusModelCoversStreamingLifecycleAndBandwidthLimits`
- `TorrentEngineTests.testEmbeddedEngineStartStreamingSelectsLargestMediaFileAndPrioritizesOnlyThatFile`
- `TorrentEngineTests.testCleanupPoliciesProtectActiveSessionsAndShutdownStopsRemainingSessions`
- Existing torrent lifecycle tests for pause, resume, stop, remove and cleanup.
