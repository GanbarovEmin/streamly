# Security Policy

## Reporting Security Issues

Please do not open public GitHub issues for security vulnerabilities.

Report security issues privately by email:

```text
eminganbarov@gmail.com
```

Include:

- affected version or commit;
- operating system version;
- clear reproduction steps;
- expected and actual behavior;
- any relevant logs with secrets removed.

## Secrets Policy

The repository must not contain:

- TMDB API keys or read access tokens;
- OpenSubtitles credentials;
- source provider credentials, cookies or session tokens;
- Sparkle private keys or exported private key material;
- `.env` files;
- `*.local.json` files;
- user cache, logs, diagnostics exports, `.dmg` files or build artifacts.

Sparkle private keys must remain in the release machine Keychain or another secure release-only store. Only the Sparkle public key belongs in the app configuration.

## Credential Storage

User credentials and provider tokens are stored through macOS Keychain. Local settings should keep only provider status and Keychain references, not raw passwords, tokens or cookies.

## Diagnostics

Diagnostics exports are created only by explicit user action. Logs and diagnostics should redact tokens, passwords, cookies, API keys and session values before export.
