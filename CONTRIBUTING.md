# Contributing to Streamly

Thanks for your interest in Streamly. The project is public, but contribution scope may remain selective while the first macOS release stabilizes.

## Issues

Use the issue templates when possible:

- Bug report for app or UI defects.
- Playback issue for playback, subtitles, torrent streaming or mpv behavior.
- Source/search issue for provider, search or release ranking problems.
- Feature request for new product ideas.

Please include macOS version, Mac model, app version/build and clear reproduction steps.

## Pull Requests

Pull requests should:

- be focused on one change;
- explain user impact;
- include relevant tests or explain why tests are not practical;
- pass `swift build` and `swift test`;
- avoid unrelated formatting churn;
- avoid committing generated build artifacts.

## Coding Style

- Follow the existing SwiftPM module boundaries.
- Keep SwiftUI views separate from service and persistence logic.
- Prefer protocols and service abstractions already present in the codebase.
- Keep Streamly public copy aligned with the app, package and executable product name. Treat remaining `CineFlow*` source target names as legacy implementation details until a dedicated module-graph migration renames them.

## No Secrets

Do not commit:

- API keys;
- access tokens;
- source credentials;
- cookies;
- Sparkle private keys;
- local config;
- user cache, logs, diagnostics exports, `.dmg` files or archives.

## Copyrighted Content

Do not commit copyrighted media, posters, subtitles, sample torrents or media libraries unless the files are explicitly licensed for repository inclusion.

Streamly does not provide or host media content.
