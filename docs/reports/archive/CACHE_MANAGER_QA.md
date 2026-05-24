# Smart Cache Manager QA

## Scope
- Settings -> Cache dashboard shows image, torrent, subtitles and metadata buckets with size and item count.
- Auto-clean uses local rules only: retention, max cache size, keep unfinished and remove completed.
- Active playback files and items marked "Keep" are protected from deletion.

## Manual Checks
1. Open Settings -> Cache after browsing posters and opening a detail screen. Confirm Image and Metadata buckets increase.
2. Start torrent playback, then open Settings -> Cache. Confirm the active title row shows `Active` and its Clear action is disabled.
3. Mark a cache item as `Keep`, run auto-clean, and confirm the item remains.
4. Set max cache size lower than current usage. Confirm the warning banner appears and Run auto-clean frees eligible old cache.
5. Clear each bucket separately. Confirm active playback continues and protected items remain.
6. Relaunch the app and confirm cache policy values persist.

## Automated Coverage
- `CoreModelTests.testStorageSettingsDecodeOlderPayloadWithSmartCacheDefaults`
- `DatabaseLayerTests.testMetadataCacheReportsSizeAndCanClearRecords`
- `DatabaseLayerTests.testSmartCacheManagerSummarizesProtectsAndCleansLocalCache`
- `SettingsViewModelTests.testSmartCacheDashboardPersistsPolicyAndRoutesSafeActions`
