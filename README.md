<p align="center">
  <img src="landing/assets/icons/streamly-logo-primary.png" width="160" alt="Streamly logo">
</p>

<h1 align="center">Streamly</h1>

<p align="center">
  <strong>A native Apple Silicon cinema center for discovery, release selection, local-first library management and playback.</strong>
</p>

<p align="center">
  <a href="https://github.com/GanbarovEmin/streamly/releases/latest"><img src="https://img.shields.io/badge/download-latest%20DMG-7C3AED?style=for-the-badge" alt="Download latest DMG"></a>
  <a href="https://ganbarovemin.github.io/streamly/"><img src="https://img.shields.io/badge/website-streamly-2563FF?style=for-the-badge" alt="Streamly website"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-111827?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/architecture-Apple%20Silicon-111827?style=for-the-badge" alt="Apple Silicon">
</p>

![Streamly hero banner](docs/assets/hero-banner.png)

Streamly brings the core desktop movie-night flow into one focused macOS app: browse movies and series, open cinematic detail pages, compare ranked user-controlled releases, start playback, resume progress, manage a local library and keep settings private on this Mac.

This is a public beta. The app is already built around the real release pipeline and downloadable DMG distribution, but Developer ID signing/notarization and some provider polish remain active release work.

## Why Streamly

| Product promise | What the user gets |
| --- | --- |
| Native macOS | SwiftUI interface, keyboard-friendly desktop navigation and Apple Silicon focused packaging. |
| Cinema-first browsing | Home shelves, catalogs, search, posters, logos, cast, trailers, seasons and episode detail pages. |
| Fast decisions | Releases are normalized and ranked by quality, seeders and source metadata so the best option is obvious. |
| Local-first privacy | Library, progress, settings, cache, diagnostics and credentials stay local by default. |
| User-controlled sources | Streamly does not host or bundle media. Users choose and configure their own sources. |

## How It Works

1. Browse the Home, Movies or Series surfaces.
2. Inspect a title page with artwork, overview, cast, seasons, episodes, trailers and similar titles.
3. Choose the recommended release or open the full release list when you want a specific quality/source.
4. Watch through the local playback path and come back later from Continue Watching, History or Library.

## Current Beta Features

- Cinemeta/Stremio metadata with TMDB fallback.
- Movie and series catalogs, search, detail pages and recommendations.
- Episode-aware series release lookup for compatible Stremio/Torrentio IDs.
- Torrentio source-provider integration for normalized release discovery.
- Release ranking by quality, seeders, codec, HDR and source metadata.
- Local files, magnet links and `.torrent` references.
- Native torrent streaming through the bundled libtorrent runtime.
- AVFoundation local playback and an mpv-capable playback bridge.
- Continue Watching, watch history, user lists, favorites and ratings.
- Embedded, local and online subtitle workflows.
- Local diagnostics export with privacy-aware redaction.
- Sparkle/GitHub Releases update foundation.

## Screenshots

| Home | Search |
| --- | --- |
| ![Home screen](docs/screenshots/home.png) | ![Search screen](docs/screenshots/search.png) |

| Movie Detail | Series Detail |
| --- | --- |
| ![Movie detail screen](docs/screenshots/movie-detail.png) | ![Series detail screen](docs/screenshots/series-detail.png) |

| Player | Settings |
| --- | --- |
| ![Player screen](docs/screenshots/player.png) | ![Settings screen](docs/screenshots/settings.png) |

## Installation

1. Download the latest `.dmg` from [GitHub Releases](https://github.com/GanbarovEmin/streamly/releases/latest).
2. Open the DMG and drag `Streamly.app` to `Applications`.
3. Launch Streamly from `Applications`.
4. If macOS blocks the unsigned beta build, open **System Settings -> Privacy & Security** and choose **Open Anyway** for Streamly.

Detailed install, local data and uninstall steps live in [docs/installation.md](docs/installation.md).

## System Requirements

- macOS 13.0 or newer.
- Apple Silicon Mac: M1, M2, M3, M4 or newer.
- Internet connection for metadata, source lookup and updates.
- Disk space for image cache, torrent cache, subtitles, diagnostics and temporary playback data.

Torrent playback currently depends on the bundled macOS arm64 libtorrent runtime and is expected to work best on modern macOS releases.

## Privacy And Legal

Streamly is local-first:

- No telemetry is enabled by default.
- Library, watch history, settings, cache and diagnostics are stored locally.
- Credentials and source-provider secrets are stored through macOS Keychain where supported.
- Diagnostics export is user-created and local.

Streamly does not host, provide, sell, bundle or distribute media content. Streamly does not bypass DRM, paywalls, captchas or technical access controls. Users are responsible for the sources they configure and for complying with applicable law and content rights.

See [Privacy](docs/privacy.md), [Legal](docs/legal.md) and [Security](SECURITY.md).

## Architecture

Streamly is a SwiftPM macOS app with separated service layers:

```text
CineFlowApp          App entry point
CineFlowUI           SwiftUI screens, view models and navigation
CineFlowDesignSystem Visual tokens and reusable UI primitives
CineFlowCore         Shared models, protocols and app environment
CineFlowMetadata     Cinemeta/TMDB discovery and metadata mapping
CineFlowSources      Source providers, Torrentio and credential policy
CineFlowTorrent      Torrent engine abstraction and native libtorrent bridge
CineFlowPlayback     AVFoundation/mpv playback services
CineFlowSubtitles    Subtitle matching, loading and cache workflows
CineFlowDatabase     GRDB repositories and local persistence
CineFlowUpdater      Sparkle and GitHub Releases update services
CineFlowDiagnostics  Local logs and diagnostics export
```

The public app, Swift package and executable product are named `Streamly`. Some internal source targets still use `CineFlow*` implementation names until a separate module rename is safe.

## Build Locally

```bash
swift build
swift test
swift run Streamly
```

Release packaging scripts live under `script/`:

```bash
bash script/build_release.sh
bash script/create_dmg.sh
```

## Links

- [Website](https://ganbarovemin.github.io/streamly/)
- [Latest Release](https://github.com/GanbarovEmin/streamly/releases/latest)
- [Changelog](CHANGELOG.md)
- [Installation](docs/installation.md)
- [Updates](docs/updates.md)
- [Privacy](docs/privacy.md)
- [Legal](docs/legal.md)
- [Contributing](CONTRIBUTING.md)

## License

Streamly is released under the [MIT License](LICENSE).
