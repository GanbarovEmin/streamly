# Changelog

All notable changes to Streamly will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project intends to use semantic versioning for public releases.

## [Unreleased]

### Added

- Post-RC bug fixes and release documentation updates will be listed here.

## [1.0.0-rc.1] - 2026-05-10

### Added

- Native macOS SwiftUI app shell with search, detail pages, release selection and playback surfaces.
- Local library, user lists, continue watching, watch history and settings flows.
- Source provider, torrent, playback, subtitle, metadata, cache, database, diagnostics and update service layers.
- Sparkle 2 integration through Swift Package Manager with appcast and EdDSA signing documentation.
- DMG release scripts for local archive creation and public GitHub Releases distribution.
- Unified user-facing error layer with reusable SwiftUI error states and diagnostics logging.
- Image cache, poster/backdrop prefetching and optional performance debug overlay.
- Baseline unit and integration tests for ranking, repositories, settings, metadata mapping, playback progress, watch completion, cache behavior and view models.
- CI placeholder workflow for build and test.

### Changed

- Release candidate version is `1.0.0` with build `100`.
- Release documentation now separates DMG packaging, Sparkle updates and final RC validation.

### Security

- Private Sparkle signing keys, local provider config, cookies, tokens and API keys are excluded from source control and release packaging.

## [1.0.0] - Planned

### Added

- First stable public macOS release, promoted from the v1.0 release candidate after manual distribution validation.

[Unreleased]: https://github.com/GanbarovEmin/streamly/compare/v1.0.0-rc.1...HEAD
[1.0.0-rc.1]: https://github.com/GanbarovEmin/streamly/releases/tag/v1.0.0-rc.1
[1.0.0]: https://github.com/GanbarovEmin/streamly/releases/tag/v1.0.0
