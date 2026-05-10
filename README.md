# Streamly

**A native macOS streaming media client with a cinematic Netflix-like interface.**

![Streamly hero banner](docs/assets/hero-banner.png)

Streamly is a local-first media client for macOS that brings Cinemeta/TMDB discovery, user-controlled playback sources, local-file playback, personal library features and updates into one polished Apple Silicon app.

Streamly is the public app, Swift package and executable product name. Some legacy source targets still use `CineFlow*` implementation names until a separate module-graph migration renames them safely.

## What Streamly Does

Streamly is designed for people who want a desktop-first media experience without switching between metadata sites, file managers and video players. The app focuses on discovery, source selection, local-file playback and continuing later from a native macOS interface.

Streamly does not provide or host media content. It is a media client that works with user-controlled sources and local data.

## Features

- Native macOS app built with SwiftUI.
- Netflix-like / Apple-like dark interface.
- User-controlled local file, magnet and `.torrent` source references.
- Native local-file playback through AVFoundation.
- Torrent streaming through the bundled `CineFlowLibtorrentNative.xcframework` runtime.
- mpv-capable playback bridge with AVFoundation fallback when no mpv runtime is available.
- Cinemeta/Stremio metadata integration with TMDB fallback for movie and series discovery.
- Local library and watch history.
- Continue Watching.
- User lists and favorites.
- User ratings.
- Embedded, local `.srt` / `.ass`, and online subtitle workflow.
- Sparkle 2 auto-updates.
- GitHub Releases distribution with `.dmg` installers.

## Screenshots

| Home | Search |
| --- | --- |
| ![Home screen](docs/screenshots/home.png) | ![Search screen](docs/screenshots/search.png) |

| Movie Detail | Series Detail |
| --- | --- |
| ![Movie detail screen](docs/screenshots/movie-detail.png) | ![Series detail screen](docs/screenshots/series-detail.png) |

| Player | Library | Settings |
| --- | --- | --- |
| ![Player screen](docs/screenshots/player.png) | ![Library screen](docs/screenshots/library.png) | ![Settings screen](docs/screenshots/settings.png) |

Screenshots are placeholder mock UI assets and can be replaced with real app captures later.

## System Requirements

- macOS 13.0 or newer.
- Apple Silicon Mac: M1, M2, M3, M4 or newer.
- Internet connection for metadata, search and release updates.
- Free disk space for local app data, image cache and diagnostics exports.

## Installation

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/GanbarovEmin/streamly/releases/latest).
2. Open the `.dmg`.
3. Drag `Streamly.app` to `Applications`.
4. Open the app from `Applications`.

If the app is unsigned or not notarized yet, macOS may block the first launch. Open **System Settings -> Privacy & Security**, find the Streamly warning and choose **Open Anyway**. You can also Control-click the app, choose **Open**, then confirm.

See [Installation](docs/installation.md) for uninstall steps and local data locations.

## Roadmap

- v1.0 macOS Apple Silicon release.
- Signed and notarized `.dmg` distribution.
- Sparkle 2 appcast updates.
- More source providers.
- More subtitle providers.
- Plugin system after v1.0.
- Optional account and sync layer after v1.0.
- More detailed diagnostics export tools.

## Privacy

Streamly is local-first:

- No telemetry is enabled by default.
- Library, watch history, settings and cache data are stored locally.
- User credentials and API tokens are stored through macOS Keychain.
- Diagnostics export is user-controlled and created locally.

See [Privacy](docs/privacy.md) for details.

## Legal Note

Streamly does not host, provide, sell or bundle media content. Streamly is a media client. Users are responsible for the sources they configure and for complying with applicable law and content rights.

Streamly does not bypass DRM, paywalls, captchas or technical access controls.

See [Legal](docs/legal.md) for details.

## Release Model

- Installers are distributed as `.dmg` files through [GitHub Releases](https://github.com/GanbarovEmin/streamly/releases/latest).
- Auto-updates use Sparkle 2 and a hosted appcast.
- Release notes are tracked in [CHANGELOG.md](CHANGELOG.md).

## Links

- [Landing Page](https://ganbarovemin.github.io/streamly/)
- [Latest Release](https://github.com/GanbarovEmin/streamly/releases/latest)
- [Issues](https://github.com/GanbarovEmin/streamly/issues)
- [Changelog](CHANGELOG.md)
- [Installation](docs/installation.md)
- [Updates](docs/updates.md)
- [Privacy](docs/privacy.md)
- [Legal](docs/legal.md)

## License

Streamly is released under the [MIT License](LICENSE).
