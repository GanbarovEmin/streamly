#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Streamly"
INFO_PLIST="$ROOT_DIR/Configuration/Streamly-Info.plist"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$DIST_DIR/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
NATIVE_LIBTORRENT_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/CineFlowLibtorrentNative.framework"
MPV_PLAYBACK_SERVICE="$ROOT_DIR/Sources/CineFlowPlayback/MPVPlaybackService.swift"
FFMPEG_RUNTIME="$APP_BUNDLE/Contents/Resources/ffmpeg"
STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_DIR="$DIST_DIR/dmg"
SKIP_BUILD=0
BUILD_ARGS=()
DMG_PATH=""
ALLOW_MISSING_NATIVE_RUNTIME=0
ALLOW_PLACEHOLDER_MPV_RUNTIME=0

usage() {
    cat <<'USAGE'
Usage: script/create_dmg.sh [options]

Options:
  --version VERSION       Override app version and DMG filename.
  --build BUILD_NUMBER    Override CFBundleVersion in the staged app.
  --sign IDENTITY         Pass Developer ID identity to build_release.sh.
  --unsigned              Build without codesigning.
  --allow-missing-native-runtime
                         Development-only: package without native libtorrent.
  --allow-placeholder-mpv-runtime
                         Development-only: package while mpv bridge is placeholder.
  --skip-build            Reuse dist/release/Streamly.app.
  --output PATH           Write DMG to PATH.
  -h, --help              Show this help.
USAGE
}

read_info_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            BUILD_ARGS+=("--version" "${2:?Missing value for --version}")
            shift 2
            ;;
        --build)
            BUILD_ARGS+=("--build" "${2:?Missing value for --build}")
            shift 2
            ;;
        --sign)
            BUILD_ARGS+=("--sign" "${2:?Missing value for --sign}")
            shift 2
            ;;
        --unsigned)
            BUILD_ARGS+=("--unsigned")
            shift
            ;;
        --allow-missing-native-runtime)
            ALLOW_MISSING_NATIVE_RUNTIME=1
            BUILD_ARGS+=("--allow-missing-native-runtime")
            shift
            ;;
        --allow-placeholder-mpv-runtime)
            ALLOW_PLACEHOLDER_MPV_RUNTIME=1
            BUILD_ARGS+=("--allow-placeholder-mpv-runtime")
            shift
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --output)
            DMG_PATH="${2:?Missing value for --output}"
            shift 2
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

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    if [[ "${#BUILD_ARGS[@]}" -gt 0 ]]; then
        "$ROOT_DIR/script/build_release.sh" "${BUILD_ARGS[@]}"
    else
        "$ROOT_DIR/script/build_release.sh"
    fi
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Missing $APP_BUNDLE. Run script/build_release.sh first or omit --skip-build." >&2
    exit 66
fi

if [[ ! -d "$NATIVE_LIBTORRENT_FRAMEWORK" && "$ALLOW_MISSING_NATIVE_RUNTIME" != "1" ]]; then
    echo "Refusing to create DMG without native libtorrent runtime in $APP_BUNDLE." >&2
    echo "Use --allow-missing-native-runtime only for development QA DMGs." >&2
    exit 72
fi

if grep -q 'PlaceholderMPVBridge' "$MPV_PLAYBACK_SERVICE" && [[ "$ALLOW_PLACEHOLDER_MPV_RUNTIME" != "1" ]]; then
    echo "Refusing to create DMG while MPV playback bridge is placeholder." >&2
    echo "Use --allow-placeholder-mpv-runtime only for development QA DMGs." >&2
    exit 74
fi

if [[ ! -x "$FFMPEG_RUNTIME" ]]; then
    echo "Refusing to create DMG without ffmpeg runtime in $APP_BUNDLE." >&2
    echo "Expected executable: Contents/Resources/ffmpeg" >&2
    exit 75
fi

VERSION="$(read_info_value CFBundleShortVersionString "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="${DMG_PATH:-$DMG_DIR/$APP_NAME-$VERSION.dmg}"
VOLUME_NAME="$APP_NAME $VERSION"
DMG_ROOT="$STAGING_DIR/$VOLUME_NAME"

rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$DMG_DIR"

/usr/bin/ditto --noextattr --norsrc "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
cat > "$DMG_ROOT/README.txt" <<'README'
Install Streamly

Drag Streamly.app to the Applications shortcut.

If this build is not signed and notarized with Developer ID, macOS may block
the first launch. Open System Settings -> Privacy & Security and choose Open
Anyway for Streamly, or Control-click Streamly.app and choose Open.
README

if find "$DMG_ROOT" \( -name '*.local.json' -o -name '*.ed25519' -o -name '*.sparkle-private-key' -o -name '.env' \) -print -quit | grep -q .; then
    echo "Refusing to create DMG with local config or secret-like files." >&2
    exit 68
fi

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

(
    cd "$(dirname "$DMG_PATH")"
    shasum -a 256 "$(basename "$DMG_PATH")"
) > "$DMG_PATH.sha256"

MOUNT_POINT="$(mktemp -d "$DIST_DIR/dmg-mount.XXXXXX")"
cleanup() {
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_POINT" >/dev/null
test -d "$MOUNT_POINT/$APP_NAME.app"
test -L "$MOUNT_POINT/Applications"
test -f "$MOUNT_POINT/README.txt"

echo "DMG created:"
echo "$DMG_PATH"
echo "Checksum created:"
echo "$DMG_PATH.sha256"
