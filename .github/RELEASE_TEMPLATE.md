# Streamly v1.0.0-rc.1

## Summary

Release candidate for Streamly v1.0 public DMG distribution.

## Assets

- [ ] `Streamly-1.0.0.dmg`
- [ ] `appcast.xml` published to `https://<github-pages-domain>/streamly/appcast.xml`
- [ ] Optional checksums attached or included below

## Checksums

```text
shasum -a 256 dist/dmg/Streamly-1.0.0.dmg
```

## Install

1. Download `Streamly-1.0.0.dmg`.
2. Drag `Streamly.app` to `Applications`.
3. If the build is unsigned, open it through `System Settings -> Privacy & Security -> Open Anyway`.

## Update Notes

- Sparkle feed: `https://<github-pages-domain>/streamly/appcast.xml`
- Sparkle public key: replace the placeholder before public update rollout.
- App version: `1.0.0`
- Build: `100`

## Verification

- [ ] `swift test`
- [ ] `script/build_release.sh --version 1.0.0 --build 100 --unsigned`
- [ ] `script/create_dmg.sh --version 1.0.0 --build 100 --unsigned`
- [ ] DMG contains `Streamly.app`, `Applications` shortcut and `README.txt`
- [ ] Settings -> Updates shows version `1.0.0` and build `100`
- [ ] Settings -> Updates -> Check for Updates reaches Sparkle
- [ ] Fresh install empty state renders without seeded user data
- [ ] Cached library opens offline
- [ ] Diagnostics export completes

## Security Checklist

- [ ] No private Sparkle key is committed.
- [ ] No API keys, tokens, cookies or local config files are committed.
- [ ] DMG does not include `.env`, `*.local.json`, `*.ed25519`, `*.sparkle-private-key` or `sparkle_keys/`.

## Known Issues

See `KNOWN_ISSUES.md`.
