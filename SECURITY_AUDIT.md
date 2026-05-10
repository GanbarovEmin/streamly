# Security Audit

Date checked: 2026-05-10

## Scope

- Repository contents and ignored local artifacts.
- Release artifacts and local QA/profiling outputs.
- Diagnostics export redaction.
- Keychain usage for API keys, source credentials, cookies and tokens.
- README, legal and privacy statements for local-first behavior and content-hosting boundaries.

## Findings

| Severity | Area | Finding | Mitigation | Status |
| --- | --- | --- | --- | --- |
| High | TMDB credentials | TMDB read access token and API key were saved through settings repository keys `tmdb_read_access_token` and `tmdb_api_key`, which can persist in SQLite-backed local settings. | TMDB credentials now save to macOS Keychain account IDs `api:tmdb:read_access_token` and `api:tmdb:api_key`. Settings load and metadata provider reads migrate legacy settings values into Keychain and delete the old settings values. | Fixed |
| Medium | Diagnostics export | Existing redaction covered simple `token=` and JSON fields but did not cover Authorization headers, Cookie headers, URL userinfo, sensitive URL query params or magnet links. | Diagnostics sanitization now redacts Authorization/Proxy-Authorization, Cookie/Set-Cookie, userinfo URLs, sensitive query params and `magnet:?` links before logs and export package content are written. | Fixed |
| Low | Local artifacts | Local `.trace`, `.log`, `.db`, `.sqlite`, `.env`, private-key-like files and `qa_artifacts/` were not fully covered by `.gitignore`. | `.gitignore` now blocks profiling traces, logs, SQLite/DB files, env files, common private key formats, local Streamly config and QA artifacts. | Fixed |
| Info | Release artifacts | Existing `dist/dmg/*.dmg` files were local release outputs and are ignored. Older CineFlow-named DMGs remain in local `dist/`, but `dist/` is ignored and not part of the source tree. | Keep release outputs outside commits; run release secret checks before publishing. | Checked |
| Info | Legal/privacy docs | README links to privacy/legal docs. Privacy states local-first storage and Keychain use. Legal states Streamly does not host or distribute content and users are responsible for source legality. | Privacy diagnostics language updated to include headers, URLs and magnet links. | Checked |

## Secret Scan

Manual scan checked for:

- TMDB and OpenSubtitles tokens or API keys;
- source credentials, cookies and session tokens;
- Sparkle private keys and EdDSA key material;
- JWT-like secrets, `.env` files, local configs, logs, databases and release artifacts.

No committed production secrets were found. Search hits are limited to documentation, placeholder test values, Keychain implementation code and local ignored build/profiling artifacts.

## Diagnostics Policy

Diagnostics exports must be safe for a user to attach manually:

- no raw `token=`, `password=`, `api_key=`, `session=`, `cookie=` or `secret=` values;
- no Authorization or Cookie header values;
- no sensitive URL query parameter values;
- no URL username/password userinfo;
- no magnet links;
- no private source credential values in metadata.

Regression coverage: `DiagnosticsServiceTests.testLocalLoggerRedactsHeadersPrivateURLsAndMagnetLinks`.

## Credential Storage Policy

- TMDB credentials: Keychain only, with one-time migration from legacy local settings.
- Source provider credentials: Keychain only.
- SQLite/UserDefaults may store provider status, enabled flags, public settings, usernames intended for display and Keychain references.
- Local `.streamly/tmdb.local.json` and `.cineflow/tmdb.local.json` remain developer-only fallback inputs and are ignored by repository policy.

Regression coverage:

- `SettingsViewModelTests.testTMDBCredentialsCanBeSavedAndClearedFromSettings`
- `TMDBMetadataServiceTests.testKeychainTMDBCredentialProviderMigratesLegacyDatabaseCredentials`

## QA Checklist

- Fresh install: save TMDB token/API key, confirm settings summary shows saved credentials and local settings do not contain raw values.
- Upgrade install: start with legacy `tmdb_read_access_token`/`tmdb_api_key` settings, open Settings or load metadata, confirm values migrate to Keychain and legacy settings are cleared.
- Diagnostics export: log source failures containing Authorization, Cookie, private URL query params and magnet links, export diagnostics and confirm only redacted values remain.
- Release prep: run repository secret scan before publishing DMG/appcast assets and confirm Sparkle private key material is not in the repo or app bundle.
