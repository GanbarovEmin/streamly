# Streamly v1.0 Release Candidate Checklist

Current release candidate:

- Version: `1.0.0`
- Build: `100`
- Distribution: unsigned local DMG unless `--sign` is supplied
- Sparkle feed placeholder: `https://<github-pages-domain>/streamly/appcast.xml`

## Automated Verification

Run before publishing a release candidate:

```bash
swift test
script/build_release.sh --version 1.0.0 --build 100 --unsigned
script/create_dmg.sh --version 1.0.0 --build 100 --unsigned
```

Expected artifacts:

```text
dist/release/Streamly.app
dist/dmg/Streamly-1.0.0.dmg
```

Latest local verification, 2026-05-10:

- `swift test`: passed, 120 tests, 0 failures.
- `script/create_dmg.sh --version 1.0.0 --build 100 --unsigned`: passed.
- Launch smoke: `dist/release/Streamly.app/Contents/MacOS/Streamly` stayed running after 5 seconds.
- DMG SHA-256: `4c251158b6bb01b42bdc561050bc516734ee4fae6f52710d99b8c1de8c83ed7c`.
- DMG contents verified: `Streamly.app`, `Applications`, `README.txt`.
- Sparkle framework verified in `Streamly.app/Contents/Frameworks/Sparkle.framework`.
- Secret-like file scan verified no `.env`, `*.local.json`, `*.ed25519`, `*.sparkle-private-key` or `sparkle_keys/` in release app or DMG staging.

## User Flow Checklist

- [ ] Launch app.
- [ ] Search media.
- [ ] Open movie detail.
- [ ] Open series detail.
- [ ] Select a release.
- [ ] Start playback.
- [ ] Load subtitles.
- [ ] Continue watching after progress is saved.
- [ ] Add media to library.
- [ ] Create and open a user list.
- [ ] Change settings and restart the app.
- [ ] Clear cache from Settings.
- [ ] Export diagnostics from Settings.
- [ ] Check updates from Settings -> Updates.

## Fresh Install

- [ ] Start with an empty `~/Library/Application Support/Streamly/`.
- [ ] Home, Library, Lists, Continue Watching and Watch History show designed empty states.
- [ ] No seeded user data is required for the app to launch.

## Upgrade Scenario

- [ ] Existing `Streamly.sqlite` opens after migration.
- [ ] Settings are preserved.
- [ ] Library, user lists and watch progress are preserved.
- [ ] Image, torrent and subtitle cache directories remain in place.

## Offline Mode

- [ ] Cached library data opens without network.
- [ ] Cached posters/backdrops render when available.
- [ ] Search and metadata network failures show user-facing error messages, not raw stack traces.
- [ ] Diagnostics include technical error details.

## Packaging

- [ ] `Configuration/Streamly-Info.plist` has the intended version and build.
- [ ] DMG contains `Streamly.app`.
- [ ] DMG contains an `Applications` shortcut.
- [ ] DMG contains `README.txt` with install/opening instructions.
- [ ] Sparkle `SUFeedURL` points to the production appcast before public rollout.
- [ ] Sparkle `SUPublicEDKey` is replaced before public update rollout.
- [ ] `appcast.xml` references the GitHub Releases DMG URL.

## Security

- [ ] No private Sparkle key is in git.
- [ ] No API keys, tokens, cookies or local provider config are in git.
- [ ] DMG does not include `.env`, `*.local.json`, `*.ed25519`, `*.sparkle-private-key` or `sparkle_keys/`.
- [ ] Production signing and notarization secrets stay outside the repository.

## Clean macOS Validation

Perform on a separate macOS user account or clean machine:

1. Download or copy `dist/dmg/Streamly-1.0.0.dmg`.
2. Mount the DMG.
3. Drag `Streamly.app` to `Applications`.
4. Launch without Xcode, SwiftPM or the source checkout.
5. If unsigned, use `System Settings -> Privacy & Security -> Open Anyway`.
6. Repeat the main user flow and update check.
