# Production Build Report

Date: 2026-05-11  
Version: Streamly 1.0.09  
Build: 1009  
Configuration: unsigned local production build  
DMG: `dist/dmg/Streamly-1.0.09.dmg`

## Build Status

Production build completed successfully from a cleaned build state.

Clean steps:

```bash
rm -rf dist/release dist/dmg-staging dist/dmg-mount.* .build/native-libtorrent
rm -f dist/dmg/Streamly-*.dmg dist/dmg/Streamly-*.dmg.sha256
swift package clean
swift package resolve
```

Build command:

```bash
script/build_release.sh --unsigned
```

Result:

- App bundle created at `dist/release/Streamly.app`.
- Bundle identifier: `com.streamly.app`.
- App name/display name: `Streamly`.
- Version/build: `1.0.09 (1009)`.
- Icon present: `Contents/Resources/Streamly.icns`.
- Bundled ffmpeg present: `Contents/Resources/ffmpeg`.
- Sparkle framework present.
- Native libtorrent framework present.

## QA Status

Clean automated suite:

```text
Executed 221 tests, with 4 tests skipped and 0 failures.
```

Production app launch:

- `dist/release/Streamly.app` launched successfully with isolated `CFFIXED_USER_HOME`.
- Window was visible after activation.
- Launch log recorded: `Streamly app launch`.
- Screenshot artifacts:
  - `qa_artifacts/2026-05-11/production-app-window.png`
  - `qa_artifacts/2026-05-11/dmg-installed-launch.png`

## DMG Status

DMG command:

```bash
script/create_dmg.sh --skip-build
```

Result:

- Created `dist/dmg/Streamly-1.0.09.dmg`.
- Created `dist/dmg/Streamly-1.0.09.dmg.sha256`.
- Size: 39 MB.
- SHA-256:

```text
3da0ed3ce6672eb5af777eb5d596718248d602c275f06a92ce6cc5579371ac45
```

DMG validation:

- `hdiutil verify` passed.
- DMG mounted read-only.
- DMG contents verified:
  - `Streamly.app`
  - `Applications` symlink
  - `README.txt`
- App copied from mounted DMG to a temp install directory.
- Installed temp copy launched successfully and showed a window.

## Production Playback Status

Production playback was validated with the public WebTorrent Big Buck Bunny torrent and bundled production `ffmpeg`.

Commands:

```bash
CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent \
STREAMLY_TRANSCODE_TEST_FFMPEG="$PWD/dist/release/Streamly.app/Contents/Resources/ffmpeg" \
swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided

INSTALL_DIR=$(ls -td /tmp/streamly-dmg-install-* | head -1)
CINEFLOW_NATIVE_LIBTORRENT_TEST_TORRENT_FILE=/tmp/big-buck-bunny.torrent \
STREAMLY_TRANSCODE_TEST_FFMPEG="$INSTALL_DIR/Streamly.app/Contents/Resources/ffmpeg" \
swift test --filter TorrentPlaybackIntegrationTests/testNativeTorrentStreamCanReachInAppAVPlayerWhenIntegrationEnvironmentIsProvided
```

Results:

- Release bundle playback smoke: passed in 60.454s.
- DMG-installed copy playback smoke: passed in 55.998s.
- No missing production `ffmpeg` issue.
- No missing native libtorrent runtime issue.
- No production-only HLS startup failure after retry fix.

## Production Issues Found And Fixed

- Fixed HLS bridge startup fragility when torrent HTTP stream returns transient startup errors.
- Rebuilt native libtorrent runtime with quieter helper behavior for expected probe disconnects.
- Verified bundled production `ffmpeg` path works.
- Verified DMG-installed copy launches and can supply its bundled playback runtime.

## Known Minor Issues

- Build is unsigned because no signing identity was requested/provided for this local QA DMG.
- `codesign --verify --deep --strict` reports an unsigned resource/signature mismatch expected for this unsigned local build, while `spctl` accepted execution on this machine.
- Build emits a non-critical macOS deployment target warning for the native libtorrent framework.
- Build emits a non-critical deprecated AVAsset duration warning.

## Final Status

The fresh DMG is ready for manual testing at:

```text
dist/dmg/Streamly-1.0.09.dmg
```

Production launch, DMG mount/install flow, bundled runtime presence, and real torrent-to-player playback smoke all passed.
