# Streamly Performance Report

Date: 2026-05-10
Scope: Block 38, Home/Search/Library/Image Cache/Player startup.

## Profiling Environment

- Machine: macOS 26.4.1, Apple Silicon MacBook Pro.
- Build: unsigned local `Streamly.app` from `script/build_and_run.sh --verify`.
- Instruments/xctrace:
  - Time Profiler: `qa_artifacts/performance/time-profiler.trace`
  - SwiftUI: `qa_artifacts/performance/swiftui.trace`
  - SwiftUI hitches export: `qa_artifacts/performance/swiftui-hitches.xml`
  - Potential hangs exports:
    - `qa_artifacts/performance/swiftui-potential-hangs.xml`
    - `qa_artifacts/performance/time-profiler-potential-hangs.xml`
  - Main Thread Checker log: `qa_artifacts/performance/main-thread-checker.log`

Allocations and Leaks were attempted through `xctrace`, but this Codex desktop session could not acquire the required task port for those instruments. Time Profiler and SwiftUI traces were captured successfully.

## Measurements

| Area | Before | After | Status |
| --- | --- | --- | --- |
| Home 1000 items | Section filtering/sorting/card mapping ran inside `HomeViewModel.load()` on `@MainActor`. | `HomeViewModelTests.testLargeHomeDatasetKeepsSectionsAndPrefetchBounded`: 1000 items load in 0.005s, sections capped to 6, section cards capped to 8, prefetch URLs capped to 24. | Fixed |
| Search 1000 media + 1200 releases | Provider response filtering/ranking was applied synchronously on `@MainActor` after network/source response. | `SearchViewModelTests.testLargeSearchResponseBuildsLoadedStateWithRankedReleases`: 1200 ranked releases in 0.016s with result preparation moved to detached work before UI state mutation. | Fixed |
| Library 1500 items | `summary` recomputed by filtering full arrays from SwiftUI body; prefetch URL list exposed all 750 filtered poster URLs in the large fixture. | `LibraryViewModelTests.testLargeLibraryFilteringUsesCachedVisibleItemsAndArtworkPrefetchList`: filtering fixture 0.010s, summary cached, prefetch list capped to 48. | Fixed |
| Image duplicate requests | Concurrent requests for the same URL could each call the cache service before memory cache was filled. | `CineFlowImagePipelineTests.testImagePipelineCoalescesConcurrentRequestsForSameURL`: two concurrent requests produce 1 cache-service request and `loadedImageCount == 1`. | Fixed |
| SwiftUI hitches | Baseline code audit found avoidable body invalidation work in Library summary and broad image prefetch preparation. | SwiftUI trace: 10 hitches during startup/idle capture, max 50ms; potential hangs >250ms: 0. | Acceptable |
| Main Thread Checker | Need to verify no obvious main-thread API violations during launch. | `main-thread-checker.log` is empty after an 8s launch with `libMainThreadChecker.dylib`. | No findings |

## Fixes Applied

### Home

Bottleneck: section preparation was coupled to `@MainActor` state loading.

Fix:
- `HomeViewModel.load()` now fetches async dependencies, then prepares featured items and sections through `Task.detached(priority: .userInitiated)`.
- Home artwork prefetch is bounded to the first 24 URLs.

Result:
- Home remains local-first and still limits rendered carousel data to the existing small section sizes.
- 1000-item fixture is covered by regression tests.

### Search

Bottleneck: large source responses were filtered, grouped, and ranked on the UI actor.

Fix:
- Search response preparation now runs in `SearchResultsBuilder` through detached user-initiated work.
- Existing stale-response protection remains in place, so old search responses cannot overwrite newer input.

Result:
- Large search response test covers 1000 media items and 1200 releases.

### Library

Bottleneck: SwiftUI body access to `summary` repeatedly filtered `items`; prefetch URL preparation exposed every visible poster URL.

Fix:
- `summary` is now cached as published state and rebuilt after repository loads.
- Library artwork prefetch list is capped to 48 nearest candidate URLs.

Result:
- Existing visible item cache remains intact.
- Large library fixture now verifies bounded prefetch.

### Image Cache / Pipeline

Bottleneck: duplicate concurrent image requests could hit disk/network/cache service more than once.

Fix:
- `CineFlowImagePipeline` now coalesces in-flight requests per URL.
- Prefetch runs in small batches of 4 while still respecting the existing limit.

Result:
- Repeated visible cells and prefetch overlap no longer duplicate the same image fetch.

### Player Startup

Audit:
- Torrent startup and local-source lookup are async through service actors/repositories.
- `PlayerViewModel.start()` awaits progress lookup, playback start, optional seek, and status refresh without synchronous file/network loops in the view layer.
- Previous Block 37 diagnostics fixes remain active for torrent/local-source failures.

Status:
- No code change required in this pass.
- Time Profiler exported 0 potential hangs during launch capture.

## Remaining QA Checklist

- Run a manual scroll pass on Home with live metadata posters once TMDB credentials are configured.
- Re-run Allocations and Leaks from the full Instruments app if macOS grants task-port permission.
- Measure real torrent playback startup with native libtorrent framework present; current local build is packaged without `Vendor/CineFlowLibtorrentNative.xcframework`.
