# Known Issues

This file tracks public, release-facing limitations.

## Current

- The public app, distribution name, Swift package and executable product are Streamly. Some legacy source target names still use `CineFlow*` until a separate module-graph migration renames them safely.
- Screenshots in the README are placeholder mock UI assets until real app captures are ready.
- The first public `.dmg` release may be unsigned until Developer ID signing and notarization are finalized.
- Sparkle appcast automation is not wired to the unsigned GitHub Release workflow yet.
- Some provider integrations may require user-supplied credentials or tokens.
- The Sparkle public EdDSA key in `Configuration/Streamly-Info.plist` is a placeholder until the production release key is generated.
- A true clean-machine validation still requires installing the built DMG on a separate macOS user account or device without the development checkout.
- The first torrent runtime package uses the macOS arm64 `libtorrent 2.0.11` wheel and requires macOS 15+ for torrent playback.
- The mpv path is a process bridge to bundled/system `mpv` or IINA CLI; full in-window libmpv rendering and audio/subtitle track synchronization remain follow-up work.

## Not Bugs

- Streamly does not ship with a media library.
- Streamly does not ship with movie or series sources.
- Streamly does not host media content.
- Streamly does not bypass DRM, paywalls, captchas or access controls.
