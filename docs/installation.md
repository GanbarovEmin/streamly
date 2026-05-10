# Installation

Streamly is distributed outside the Mac App Store as a `.dmg`.

The public app bundle is `Streamly.app`. Swift package and target names may still use the internal `CineFlow*` names.

## Download

Download the latest `.dmg` from:

```text
https://github.com/GanbarovEmin/streamly/releases/latest
```

## Install

1. Open the downloaded `.dmg`.
2. Drag `Streamly.app` to `Applications`.
3. Eject the mounted disk image.
4. Open `Streamly.app` from `Applications`.

## Opening Unsigned Builds

If the build is not signed or notarized with Developer ID, macOS may block the first launch.

Recommended path:

1. Try to open `Streamly.app` once.
2. Open **System Settings -> Privacy & Security**.
3. Find the Streamly warning.
4. Click **Open Anyway**.
5. Confirm **Open**.

Alternative:

1. Control-click `Streamly.app`.
2. Choose **Open**.
3. Confirm **Open**.

## Local Data

Default local data is stored under:

```text
~/Library/Application Support/Streamly/
```

Important paths:

```text
~/Library/Application Support/Streamly/Streamly.sqlite
~/Library/Application Support/Streamly/ImageCache/
~/Library/Application Support/Streamly/TorrentCache/
~/Library/Application Support/Streamly/Subtitles/
~/Library/Application Support/Streamly/Logs/
~/Library/Application Support/Streamly/DiagnosticsExports/
```

TMDB credentials can be stored in local app settings, and source-provider credentials are stored in macOS Keychain.

## Uninstall

1. Quit the app.
2. Delete `Streamly.app` from `Applications`.
3. Optionally delete local data:

   ```text
   ~/Library/Application Support/Streamly/
   ```

4. Optionally remove related credentials from macOS Keychain.
