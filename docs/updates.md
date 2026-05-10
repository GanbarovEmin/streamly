# Updates

Streamly uses Sparkle 2 for automatic updates.

The app update flow is:

```text
CineFlow.app -> Sparkle appcast -> GitHub Releases .dmg -> Sparkle update
```

## GitHub Releases

Public releases are distributed as `.dmg` files through:

```text
https://github.com/GanbarovEmin/Streamly/releases/latest
```

Release assets should use predictable names such as:

```text
CineFlow-1.0.0.dmg
```

## Appcast

Sparkle reads update metadata from the appcast configured in `Configuration/CineFlow-Info.plist`.

The current placeholder feed URL is:

```text
https://<github-pages-domain>/cineflow/appcast.xml
```

Before shipping, replace it with the production GitHub Pages or static hosting URL.

## Release Relationship

1. Build and package the `.dmg`.
2. Upload the `.dmg` to a GitHub Release.
3. Generate or update the Sparkle appcast.
4. Publish the appcast to the configured static URL.
5. Sparkle reads the appcast and downloads the GitHub Releases `.dmg`.

## Private Keys

Sparkle private keys must not be committed. Keep private key material in the release machine Keychain or another release-only secure store.

Only the public Sparkle key belongs in app configuration.
