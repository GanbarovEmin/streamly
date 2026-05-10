#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Streamly"
PRODUCT_NAME="CineFlow"
INFO_PLIST="$ROOT_DIR/Configuration/CineFlow-Info.plist"
APP_ICON="$ROOT_DIR/Configuration/Streamly.icns"
NATIVE_LIBTORRENT_XCFRAMEWORK="$ROOT_DIR/Vendor/CineFlowLibtorrentNative.xcframework"
NATIVE_LIBTORRENT_FRAMEWORK_NAME="CineFlowLibtorrentNative.framework"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
SIGN_IDENTITY="${STREAMLY_CODESIGN_IDENTITY:-}"
SKIP_SIGN=1
VERSION=""
BUILD_NUMBER=""

usage() {
    cat <<'USAGE'
Usage: script/build_release.sh [options]

Options:
  --version VERSION       Override CFBundleShortVersionString in the staged app.
  --build BUILD_NUMBER    Override CFBundleVersion in the staged app.
  --sign IDENTITY         Sign with a Developer ID Application identity.
  --unsigned              Do not codesign the staged app.
  -h, --help              Show this help.

Default output is unsigned. Set STREAMLY_CODESIGN_IDENTITY or pass --sign for
Developer ID distribution builds.
USAGE
}

if [[ -n "$SIGN_IDENTITY" ]]; then
    SKIP_SIGN=0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:?Missing value for --version}"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="${2:?Missing value for --build}"
            shift 2
            ;;
        --sign)
            SIGN_IDENTITY="${2:?Missing value for --sign}"
            SKIP_SIGN=0
            shift 2
            ;;
        --unsigned)
            SKIP_SIGN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

plist_read() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

VERSION="${VERSION:-$(plist_read CFBundleShortVersionString)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(plist_read CFBundleVersion)}"

if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
    echo "Version and build number must be non-empty." >&2
    exit 65
fi

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) with SwiftPM product $PRODUCT_NAME..."
(cd "$ROOT_DIR" && swift build -c release --product "$PRODUCT_NAME")
BIN_DIR="$(cd "$ROOT_DIR" && swift build -c release --product "$PRODUCT_NAME" --show-bin-path)"
EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$EXECUTABLE" ]]; then
    echo "SwiftPM did not produce executable at $EXECUTABLE" >&2
    exit 66
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"

/usr/bin/ditto --noextattr --norsrc "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
/usr/bin/ditto --noextattr --norsrc "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$APP_ICON" ]]; then
    /usr/bin/ditto --noextattr --norsrc "$APP_ICON" "$APP_BUNDLE/Contents/Resources/Streamly.icns"
else
    echo "Missing app icon at $APP_ICON" >&2
    exit 70
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

while IFS= read -r -d '' bundle; do
    /usr/bin/ditto --noextattr --norsrc "$bundle" "$APP_BUNDLE/Contents/Resources/$(basename "$bundle")"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

if [[ -d "$BIN_DIR/Sparkle.framework" ]]; then
    /usr/bin/ditto --noextattr --norsrc "$BIN_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
else
    echo "Sparkle.framework was not found in $BIN_DIR" >&2
    exit 67
fi

NATIVE_LIBTORRENT_COPIED=0
if [[ -d "$NATIVE_LIBTORRENT_XCFRAMEWORK" ]]; then
    NATIVE_LIBTORRENT_FRAMEWORK_SRC="$(find "$NATIVE_LIBTORRENT_XCFRAMEWORK" -type d -name "$NATIVE_LIBTORRENT_FRAMEWORK_NAME" -print -quit)"
    if [[ -z "$NATIVE_LIBTORRENT_FRAMEWORK_SRC" ]]; then
        echo "Missing native libtorrent framework: $NATIVE_LIBTORRENT_FRAMEWORK_NAME was not found inside $NATIVE_LIBTORRENT_XCFRAMEWORK" >&2
        exit 72
    fi
    /usr/bin/ditto --noextattr --norsrc "$NATIVE_LIBTORRENT_FRAMEWORK_SRC" "$APP_BUNDLE/Contents/Frameworks/$NATIVE_LIBTORRENT_FRAMEWORK_NAME"
    if [[ ! -x "$APP_BUNDLE/Contents/Frameworks/$NATIVE_LIBTORRENT_FRAMEWORK_NAME/CineFlowLibtorrentNative" ]]; then
        echo "Native libtorrent framework is missing executable payload in Contents/Frameworks/$NATIVE_LIBTORRENT_FRAMEWORK_NAME" >&2
        exit 73
    fi
    NATIVE_LIBTORRENT_COPIED=1
else
    echo "Native libtorrent framework not found at $NATIVE_LIBTORRENT_XCFRAMEWORK."
    echo "Packaging Streamly without torrent playback; torrent routes will surface the unavailable bridge state."
fi

if ! otool -l "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
fi

chmod -R u+rwX "$APP_BUNDLE"
xattr -crs "$APP_BUNDLE" || true
dot_clean "$APP_BUNDLE" || true
find "$APP_BUNDLE" -exec xattr -c -s {} \; 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d -s com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d -s com.apple.ResourceFork {} \; 2>/dev/null || true

if find "$APP_BUNDLE" \( -name '*.local.json' -o -name '*.ed25519' -o -name '*.sparkle-private-key' -o -name '.env' \) -print -quit | grep -q .; then
    echo "Refusing to package local config or secret-like files in $APP_BUNDLE" >&2
    exit 68
fi

if [[ "$SKIP_SIGN" -eq 0 ]]; then
    echo "Codesigning with identity: $SIGN_IDENTITY"
    SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
    SIGN_ARGS+=(--options runtime --timestamp)
    if [[ "$NATIVE_LIBTORRENT_COPIED" -eq 1 ]]; then
        codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Frameworks/$NATIVE_LIBTORRENT_FRAMEWORK_NAME"
    fi
    codesign "${SIGN_ARGS[@]}" --deep "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
else
    echo "Skipping codesign. This app will trigger macOS unidentified developer warnings after download."
fi

plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null
if [[ "$SKIP_SIGN" -eq 0 ]]; then
    codesign --verify --deep --strict "$APP_BUNDLE" >/dev/null 2>&1 || {
        echo "codesign verification failed for $APP_BUNDLE" >&2
        exit 69
    }
fi

echo "Release app created:"
echo "$APP_BUNDLE"
