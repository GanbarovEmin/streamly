# Installation

Streamly is distributed outside the Mac App Store as a `.dmg`.

The public project name is Streamly. The current app bundle is still `CineFlow.app` until a separate rename task changes the macOS target.

## Download

Download the latest `.dmg` from:

```text
https://github.com/GanbarovEmin/Streamly/releases/latest
```

## Install

1. Open the downloaded `.dmg`.
2. Drag `CineFlow.app` to `Applications`.
3. Eject the mounted disk image.
4. Open `CineFlow.app` from `Applications`.

## Opening Unsigned Builds

If the build is not signed or notarized with Developer ID, macOS may block the first launch.

Recommended path:

1. Try to open `CineFlow.app` once.
2. Open **System Settings -> Privacy & Security**.
3. Find the CineFlow warning.
4. Click **Open Anyway**.
5. Confirm **Open**.

Alternative:

1. Control-click `CineFlow.app`.
2. Choose **Open**.
3. Confirm **Open**.

## Local Data

Default local data is stored under:

```text
~/Library/Application Support/CineFlow/
```

Important paths:

```text
~/Library/Application Support/CineFlow/CineFlow.sqlite
~/Library/Application Support/CineFlow/ImageCache/
~/Library/Application Support/CineFlow/TorrentCache/
~/Library/Application Support/CineFlow/Subtitles/
~/Library/Application Support/CineFlow/Logs/
~/Library/Application Support/CineFlow/DiagnosticsExports/
```

Credentials and provider tokens are stored in macOS Keychain.

## Uninstall

1. Quit the app.
2. Delete `CineFlow.app` from `Applications`.
3. Optionally delete local data:

   ```text
   ~/Library/Application Support/CineFlow/
   ```

4. Optionally remove related credentials from macOS Keychain.
