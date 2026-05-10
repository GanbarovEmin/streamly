# Privacy

Streamly is designed as a local-first macOS app.

## Stored Locally

Streamly may store the following data under `~/Library/Application Support/Streamly/`:

- local library records;
- watch history;
- Continue Watching progress;
- user lists and favorites;
- user ratings;
- app settings;
- source provider status;
- cached metadata images;
- subtitle cache;
- temporary torrent cache;
- diagnostics logs and user-created diagnostics exports.

## Keychain Data

Credentials and tokens are stored through macOS Keychain where supported:

- TMDB tokens or API keys;
- OpenSubtitles credentials or tokens;
- source provider usernames, passwords, cookies or session tokens.

Local settings should store only references to Keychain items, not raw secrets.

## Not Sent Automatically

Streamly does not send telemetry by default.

Diagnostics are not uploaded automatically. A diagnostics export is created only when the user explicitly chooses to export it.

## Diagnostics Export

Diagnostics exports are local files that the user can choose to share manually. Logs should redact secret-like values such as passwords, tokens, cookies, sessions and API keys.

## Delete Local Data

To remove local app data:

1. Quit the app.
2. Delete:

   ```text
   ~/Library/Application Support/Streamly/
   ```

3. Remove related credentials from macOS Keychain if desired.
