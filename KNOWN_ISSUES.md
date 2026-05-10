# Known Issues

This file tracks public, release-facing limitations.

## Current

- The public app and distribution name is Streamly. Swift package, product and source module names still use the internal `CineFlow*` naming in this pass.
- Screenshots in the README are placeholder mock UI assets until real app captures are ready.
- The first public `.dmg` release may be unsigned until Developer ID signing and notarization are finalized.
- Sparkle appcast automation is not wired to the unsigned GitHub Release workflow yet.
- Some provider integrations may require user-supplied credentials or tokens.
- The Sparkle public EdDSA key in `Configuration/CineFlow-Info.plist` is a placeholder until the production release key is generated.
- A true clean-machine validation still requires installing the built DMG on a separate macOS user account or device without the development checkout.

## Not Bugs

- Streamly does not ship with a media library.
- Streamly does not ship with movie or series sources.
- Streamly does not host media content.
- Streamly does not bypass DRM, paywalls, captchas or access controls.
