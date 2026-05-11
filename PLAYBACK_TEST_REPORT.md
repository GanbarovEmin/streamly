# Playback Test Report

Date: 2026-05-11  
Scope: Block 61 playback stability stress test for mpv boundary, torrent engine, player controls, subtitles, audio selection, diagnostics, and local-first behavior.

## Executive Summary

The deterministic playback/torrent/subtitle suite passed, and the local HLS playback smoke passed with the bundled production `ffmpeg`. A live native torrent-to-player smoke using the public Big Buck Bunny torrent failed in this environment after the HLS bridge exhausted 3 startup attempts and timed out while opening the native local stream URL.

The failure is recorded as a real stress-test finding, not hidden as a pass. No local media fixture set exists in the repository for full MP4/MKV/AVI/HDR/Dolby Vision/manual sleep-wake validation, so those rows are listed as manual/blocked QA items.

## Environment

- Platform: macOS, SwiftPM package in `/Users/eminganbarov/Documents/CineFlow`.
- Bundled playback runtime: `dist/release/Streamly.app/Contents/Resources/ffmpeg`.
- `ffmpeg`: `7.1.1-Jellyfin`.
- `ffmpeg` decoders present: H.264, HEVC, AV1, SRT, ASS.
- Encoders present for synthetic fixtures: `libx264`, `h264_videotoolbox`, `libx265`, `hevc_videotoolbox`, `libsvtav1`.
- Standalone `mpv`: not found on PATH.
- mpv-compatible launcher found: `/Applications/IINA.app/Contents/MacOS/iina-cli`.
- Local media fixtures in repo: none found for `.mp4`, `.mkv`, `.avi`, `.srt`, `.ass`, `.torrent`.

## Commands Run

```bash
curl -L --fail --retry 2 --connect-timeout 10 \
  -o /tmp/streamly-big-buck-bunny.torrent \
  https://webtorrent.io/torrents/big-buck-bunny.torrent
```

```bash
CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/streamly-big-buck-bunny.torrent \
STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" \
swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided
```

Result: failed after 121.988s.

```bash
swift test --filter 'PlaybackEngineTests|TorrentEngineTests|PlayerViewModelTests|SubtitleServiceTests|SourceProviderArchitectureTests|PlaybackAutoSourceResolverTests'
```

Result: passed, 76 tests, 0 failures, 1 skipped HLS smoke without env.

```bash
STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" \
swift test --filter PlaybackEngineTests/testTranscodingAVPlaybackServiceCanStartInAppHLSWhenIntegrationEnvironmentIsProvided
```

Result: passed, 1 test, 0 failures.

## Playback Matrix

| Format | Codec | Quality | Subtitles | Audio | Result | Notes |
|---|---|---:|---|---|---|---|
| MP4 | H.264 | generated smoke | none | generated AAC | PASS | `TranscodingAVPlaybackService` generated sample MP4, served it over local HTTP, and AVPlayer reached playable HLS state. |
| Local HTTP stream | H.264 source via HLS | generated smoke | none | generated AAC | PASS | Same smoke verifies local-first loopback stream handling through the in-app HLS bridge. |
| MKV | Any playable local media URL | 2160p HDR metadata path | mock embedded SRT/ASS tracks | RU/EN mock tracks | PASS | Mock playback covers seek, volume, speed, fullscreen, audio track, subtitle track, quality label, and source label state. Does not decode a real MKV fixture. |
| MKV | HEVC | 1080p/2160p | manual | manual | MANUAL REQUIRED | Runtime supports HEVC decode through bundled `ffmpeg`, but no HEVC MKV fixture exists in repo. |
| MKV | AV1 | 720p/1080p | manual | manual | MANUAL REQUIRED | Bundled `ffmpeg` reports AV1 decoder support. Needs real AV1 fixture and hardware/device observation. |
| MP4/MKV | HDR10 | 2160p | manual | manual | MANUAL REQUIRED | mpv options include tone mapping/HDR flags, but no HDR10 fixture or display validation was available. |
| MP4/MKV | Dolby Vision | 2160p | manual | manual | MANUAL REQUIRED | Requires real Dolby Vision fixture and target display validation. |
| AVI | legacy codecs | optional | none | single track | MANUAL REQUIRED | AVI is optional and no fixture exists. |
| Torrent file | Public Big Buck Bunny torrent | live network | embedded/unknown | source-dependent | FAIL | Native torrent stream reached local URL but HLS bridge timed out after 3 startup attempts. |
| Torrent engine mock | media-file selection | 1080p/2160p metadata | n/a | n/a | PASS | Covers sequential download, priority, selected file, status updates, pause/resume/stop/remove, cleanup protection. |
| Torrent pipeline | fallback releases | HD/FHD metadata | n/a | n/a | PASS | Covers broken primary fallback, all-fail terminal state, resolved-stream unavailable fallback, slow-start timeout fallback, and local stream handoff without byte preflight. |
| Embedded subtitles | SRT/ASS model paths | n/a | embedded/local/OpenSubtitles strategy | n/a | PASS | Covers embedded-first, local/cache fallback, OpenSubtitles fallback, forced subtitle behavior, disabled auto-search, cache list/delete/reload. |
| External subtitles | `.srt` / `.ass` | n/a | local file/cache | n/a | PASS | Subtitle service tests cover SRT/ASS cache handling; PlayerViewModel covers local subtitle load and menu grouping. |
| Audio tracks | RU/EN/original | n/a | n/a | multi-track mock | PASS | Smart audio tests cover RU -> EN -> Original fallback, manual override per media, and quality label display. |
| Controls | n/a | n/a | switch during playback | switch during playback | PASS | PlayerViewModel tests cover seek, pause/resume, fullscreen state, keyboard shortcuts, subtitle delay, audio boost, speed, audio/subtitle selection. |
| Pause 10 min | n/a | n/a | n/a | n/a | MANUAL REQUIRED | Needs wall-clock player session; not run in automated suite. |
| Sleep/wake Mac | n/a | n/a | n/a | n/a | MANUAL REQUIRED | Requires interactive macOS sleep/wake cycle; not run from SwiftPM. |
| Fullscreen enter/exit | n/a | n/a | n/a | n/a | PASS/PARTIAL | State transition is covered in player service/view model tests; real window fullscreen needs manual GUI QA. |

## Failure Details

### Live torrent-to-player smoke timeout

Command:

```bash
CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/streamly-big-buck-bunny.torrent \
STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" \
swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided
```

Observed result:

```text
failed: caught error: "unsupported(operation: "ffmpeg HLS startup timeout after attempt 3:
[in#0 @ ...] Error opening input: Immediate exit requested |
Error opening input file http://127.0.0.1:<port>/stream/<session>/1.")"
```

Impact:

- This live network test did not meet the stability acceptance criteria in the current environment.
- Deterministic fallback/timeout tests still pass, so the failure is isolated to live torrent stream readiness or peer/piece availability during HLS startup.
- The error is user-safe and sanitized: it contains a loopback URL/session path but no magnet URI, credentials, provider token, or file-system secret.

Recommended follow-up:

- Re-run with a controlled local torrent fixture/seed instead of public peer availability.
- Add a diagnostics-backed integration harness for `TranscodingAVPlaybackService` startup failures, or route this smoke through `PlayerViewModel` so playback failures are asserted through `DiagnosticsServiceProtocol`.
- Capture native helper stream status at each HLS retry attempt to distinguish no peers, no selected pieces, helper abort, and ffmpeg timeout.

## Diagnostics Coverage

- `PlaybackPipeline` debug trace logs sanitized playback/torrent events through `DiagnosticsServiceProtocol`.
- Tests verify sanitized stream URLs such as `file://<local-file>/debug.mkv`.
- Player-level subtitle/search/playback errors are logged through UI view models.
- The direct `TranscodingAVPlaybackService` integration smoke currently surfaces a sanitized `PlaybackServiceError`; it does not itself receive a diagnostics service. In app usage, the player layer is expected to log the failure.

## Manual QA Checklist

Use this checklist with a controlled media pack:

- MP4/H.264 720p with single audio track: play, seek forward/back, pause/resume, close player.
- MKV/H.264 1080p with RU/EN audio and embedded SRT: auto audio selection, manual audio switch, subtitle switch.
- MKV/HEVC 2160p with ASS subtitles: subtitle style, delay +/-0.5s, font size, fullscreen enter/exit.
- MKV/AV1 1080p if supported by target machine: start, seek 10 times, pause/resume, close/reopen.
- HDR10 2160p: verify tone mapping, no washed-out image, no crash on fullscreen.
- Dolby Vision sample where possible: verify fallback/tone mapping behavior.
- External `.srt` and `.ass`: load local file, switch off/on, close/reopen player.
- OpenSubtitles: with credentials configured in Keychain, force no embedded/local match and verify online fallback; with auto-search off, verify no online request.
- Pause for 10 minutes, then resume and seek.
- Sleep Mac for at least 30 seconds during paused playback; wake and resume.
- Torrent stream under constrained network: start, seek before fully buffered, wait for recovery, verify no infinite loading.

## Acceptance Criteria Status

- Основные форматы воспроизводятся стабильно: PARTIAL. Local HLS MP4/H.264 passed; real MKV/HEVC/AV1/HDR/Dolby Vision fixtures were not available.
- Seek не ломает state: PASS in automated player service/view model tests.
- Смена audio/subtitles не вызывает crash: PASS in automated mock/view model tests; real multi-track fixture still required.
- `PLAYBACK_TEST_REPORT.md` создан: PASS.
- Live torrent-to-player stability: FAIL in this run due HLS startup timeout on public torrent stream.
