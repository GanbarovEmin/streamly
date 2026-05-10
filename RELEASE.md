# Streamly Release

This document covers public DMG distribution from a landing page or GitHub Releases.
Auto-update specific signing and appcast details are also documented in `RELEASE_UPDATES.md`.

## Build Release App

Create a local release `.app` bundle:

```bash
script/build_release.sh
```

Override the version and build when cutting a release:

```bash
script/build_release.sh --version 1.0.0 --build 100
```

For Developer ID distribution:

```bash
script/build_release.sh \
  --version 1.0.0 \
  --build 100 \
  --sign "Developer ID Application: Your Name (TEAMID)"
```

The staged app is written to:

```text
dist/release/Streamly.app
```

By default this creates an unsigned local distribution build. Pass `--sign` or set
`STREAMLY_CODESIGN_IDENTITY` for Developer ID release builds.

The script packages only the release executable, `Configuration/Streamly-Info.plist`,
SwiftPM resource bundles, and `Sparkle.framework`. It refuses to package common local
config or secret-like files such as `.env`, `*.local.json`, `*.ed25519`, or
`*.sparkle-private-key`.

## Create DMG

Create a distributable DMG:

```bash
script/create_dmg.sh --version 1.0.0 --build 100
```

With Developer ID signing:

```bash
script/create_dmg.sh \
  --version 1.0.0 \
  --build 100 \
  --sign "Developer ID Application: Your Name (TEAMID)"
```

Output:

```text
dist/dmg/Streamly-1.0.0.dmg
```

The DMG contains:

- `Streamly.app`
- `Applications` shortcut
- `README.txt` with install/opening instructions

The script mounts the finished DMG and verifies that these files exist.

## Unsigned Builds

If you do not sign and notarize with Developer ID, downloaded builds may show an
unidentified developer warning.

User-facing opening instructions:

1. Drag `Streamly.app` to `Applications`.
2. Try to open Streamly once.
3. Open `System Settings -> Privacy & Security`.
4. Click `Open Anyway` for Streamly.
5. Confirm `Open`.

Alternative: Control-click `Streamly.app`, choose `Open`, then confirm.

## Upload to GitHub Releases

1. Create and push a version tag:

   ```bash
   git tag v1.0.0-rc.1
   git push origin v1.0.0-rc.1
   ```

2. Create a GitHub Release for the tag.

3. Upload:

   ```text
   dist/dmg/Streamly-1.0.0.dmg
   ```

4. The landing page should link either to the latest GitHub Release page or to the
   direct release asset URL:

   ```text
   https://github.com/<owner>/<repo>/releases/latest
   https://github.com/<owner>/<repo>/releases/download/v1.0.0-rc.1/Streamly-1.0.0.dmg
   ```

Prefer the latest-release URL for landing pages when you do not want to update the
site for every version.

## Update Appcast

After uploading the DMG, update Sparkle appcast metadata. Recommended:

```bash
mkdir -p releases/sparkle
cp dist/dmg/Streamly-1.0.0.dmg releases/sparkle/
.build/artifacts/sparkle/Sparkle/bin/generate_appcast releases/sparkle/
```

Review that `appcast.xml` points to the GitHub Releases DMG URL, then publish it
to the configured `SUFeedURL`, for example:

```text
https://<github-pages-domain>/streamly/appcast.xml
```

## Test Release And Update

1. Mount `dist/dmg/Streamly-1.0.0.dmg`.
2. Drag `Streamly.app` to `Applications`.
3. Confirm the app shows the intended version/build in Settings -> Updates.
4. Confirm the app launches on a clean macOS user account.
5. For signed releases, run:

   ```bash
   spctl --assess --type execute --verbose=4 /Applications/Streamly.app
   codesign --verify --deep --strict --verbose=2 /Applications/Streamly.app
   ```

6. Publish an appcast entry with a higher `CFBundleVersion`.
7. Open Streamly -> Settings -> Updates -> Check for updates.
8. Confirm Sparkle offers the new GitHub Releases DMG.
