# UX Writing Polish Report

## Scope
- Home, Search, Library, Lists, Continue Watching, History, movie detail, series detail, Player, Sources, image cache and update/diagnostic hints were reviewed for empty/error/help states.
- The pass is UI/UX-copy only except for a small Lists helper that triggers the existing repository-backed default list creation.
- Local-first behavior is preserved: source credentials remain in Keychain, diagnostics copy stays sanitized, cache/library/history remain local.

## Empty States
- Empty states now include a title, short explanation and CTA on the main user-facing empty surfaces.
- Home and inline Home sections route users to Settings or Search instead of leaving blank panels.
- Search idle and no-results states focus search or clear filters.
- Library, Lists, Continue Watching and History empty states route to Search, Library, list creation or filter reset.
- Detail and episode release rails provide clear return/search CTAs when metadata or sources are unavailable.
- Sources settings explain that sources are user-controlled and offer a retry action.

## Error States
- Raw technical messages are not shown directly in the touched error surfaces.
- User-facing errors now use localized title/message/recovery copy and retry/back/settings CTAs where useful.
- Player and torrent/source failures show generic recovery guidance instead of raw engine text.
- Cache/source failures keep local-first privacy language visible.

## Tooltips
- Added localized tooltips for release ranking score, seeders, cache actions, diagnostics exports and Sparkle auto updates.
- Upcoming series episodes explain that releases are not requested before the air date.

## Localization
- New UX strings were added to `ru.lproj/Localizable.strings` and `en.lproj/Localizable.strings`.
- Added `LocalizationTests.testUXWritingKeysResolveInRussianAndEnglish` to guard the new keys.

## QA Checklist
- Check empty states at 1200x760, 1440x900, full screen and ultra-wide.
- Check loading skeletons for Home, Search, Library, Lists, Detail and Player route setup.
- Check hover/help text on release rows, source rows, diagnostics, cache and update controls.
- Check keyboard focus on CTA buttons and Search focus actions.
- Check local-only mode with no TMDB credentials, empty Library, empty Lists and no configured sources.
