# CineFlow Sparkle Updates

CineFlow is distributed outside the Mac App Store as a signed and notarized `.dmg`.
Auto-updates use Sparkle 2:

`CineFlow.app -> appcast.xml -> GitHub Releases .dmg -> Sparkle update`

The placeholder appcast URL in `Configuration/CineFlow-Info.plist` is:

```text
https://<github-pages-domain>/cineflow/appcast.xml
```

Replace it with the final GitHub Pages or static hosting URL before shipping.

## One-Time Sparkle Setup

1. Keep Sparkle integrated through Swift Package Manager:

   ```text
   https://github.com/sparkle-project/Sparkle.git
   ```

2. Generate the EdDSA key pair once on the release Mac:

   ```bash
   .build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   Sparkle stores the private key in the macOS login Keychain and prints the public key.

3. Copy the printed public key into `Configuration/CineFlow-Info.plist`:

   ```xml
   <key>SUPublicEDKey</key>
   <string>PUBLIC_KEY_FROM_GENERATE_KEYS</string>
   ```

4. Do not commit private keys or exported key material. If a local export is needed for a release machine migration, keep it outside the repository. The repository ignores common local paths such as `sparkle_keys/`, `*.ed25519`, and `*.sparkle-private-key`.

5. `SUEnableInstallerLauncherService` is not enabled by default because this SwiftPM app currently has no sandbox entitlement file. If CineFlow becomes sandboxed, add the boolean key to `Configuration/CineFlow-Info.plist` and embed Sparkle's required XPC services during archive packaging.

## Create a Release Build

1. Increment both bundle values in the release Info.plist used for packaging:

   ```xml
   <key>CFBundleShortVersionString</key>
   <string>1.0.1</string>
   <key>CFBundleVersion</key>
   <string>101</string>
   ```

   Sparkle compares `CFBundleVersion`, so it must always increase.

2. Build the app in release mode.

3. Code sign the app with the Developer ID Application certificate.

4. Create the `.dmg`, include an `/Applications` symlink, sign the disk image if the release pipeline supports it, and notarize/staple the final artifact.

5. Name the artifact predictably:

   ```text
   CineFlow-1.0.1.dmg
   ```

## Sign the Update

Recommended path: use Sparkle's `generate_appcast`, which signs the update and creates delta updates automatically.

```bash
mkdir -p releases/sparkle
cp path/to/CineFlow-1.0.1.dmg releases/sparkle/
.build/artifacts/sparkle/Sparkle/bin/generate_appcast releases/sparkle/
```

The tool reads the EdDSA private key from Keychain and writes `appcast.xml` plus any delta artifacts into the releases folder.

Manual signature path, only when you are maintaining appcast XML yourself:

```bash
.build/artifacts/sparkle/Sparkle/bin/sign_update path/to/CineFlow-1.0.1.dmg
```

Copy the emitted `sparkle:edSignature` and `length` attributes into the appcast enclosure.

## Update `appcast.xml`

The appcast must point to the `.dmg` uploaded in GitHub Releases:

```xml
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CineFlow Updates</title>
    <item>
      <title>Version 1.0.1</title>
      <sparkle:version>101</sparkle:version>
      <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
      <pubDate>Sun, 10 May 2026 00:00:00 +0400</pubDate>
      <enclosure
        url="https://github.com/<owner>/<repo>/releases/download/v1.0.1/CineFlow-1.0.1.dmg"
        type="application/octet-stream"
        sparkle:edSignature="SIGNATURE_FROM_GENERATE_APPCAST_OR_SIGN_UPDATE"
        length="DMG_SIZE_IN_BYTES" />
    </item>
  </channel>
</rss>
```

When using `generate_appcast`, prefer the generated XML and only review it for URLs and version metadata.

## Upload to GitHub Releases

1. Create a GitHub tag:

   ```bash
   git tag v1.0.1
   git push origin v1.0.1
   ```

2. Create a GitHub Release for the tag.

3. Upload:

   ```text
   CineFlow-1.0.1.dmg
   ```

4. Publish `appcast.xml` to the configured static URL, for example GitHub Pages:

   ```text
   https://<github-pages-domain>/cineflow/appcast.xml
   ```

5. Open CineFlow and use Settings -> Updates -> Check for updates. Sparkle should read the hosted appcast and offer the GitHub Releases `.dmg` when its `CFBundleVersion` is newer than the installed app.

## Release Checklist

- `SUFeedURL` points to the production appcast URL.
- `SUPublicEDKey` contains the real public key, not the placeholder.
- `CFBundleVersion` increased.
- `.dmg` is signed/notarized and uploaded to GitHub Releases.
- `appcast.xml` references the GitHub Releases `.dmg` URL.
- `sparkle:edSignature` is present.
- No private key files are staged or committed.
