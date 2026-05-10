#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/Native/CineFlowLibtorrentNative"
BUILD_DIR="$ROOT_DIR/.build/native-libtorrent"
PY_DEPS_DIR="$BUILD_DIR/python-deps"
HELPER_DIST_DIR="$BUILD_DIR/helper-dist"
FRAMEWORK_BUILD_DIR="$BUILD_DIR/framework"
FRAMEWORK_DIR="$FRAMEWORK_BUILD_DIR/CineFlowLibtorrentNative.framework"
XCFRAMEWORK_DIR="$ROOT_DIR/Vendor/CineFlowLibtorrentNative.xcframework"

PYTHON="${PYTHON:-/usr/bin/python3}"
LIBTORRENT_VERSION="${LIBTORRENT_VERSION:-2.0.11}"

rm -rf "$BUILD_DIR"
mkdir -p "$PY_DEPS_DIR" "$HELPER_DIST_DIR" "$FRAMEWORK_DIR/Versions/A/Headers" "$FRAMEWORK_DIR/Versions/A/Resources" "$ROOT_DIR/Vendor"

echo "Installing Python build/runtime dependencies..."
"$PYTHON" -m pip install --upgrade --target "$PY_DEPS_DIR" "pyinstaller>=6.0,<7.0" "libtorrent==$LIBTORRENT_VERSION"

echo "Building bundled libtorrent helper..."
PYTHONPATH="$PY_DEPS_DIR" "$PYTHON" -m PyInstaller \
    --clean \
    --noconfirm \
    --onedir \
    --name streamly-torrent-helper \
    --distpath "$HELPER_DIST_DIR" \
    --workpath "$BUILD_DIR/helper-work" \
    --specpath "$BUILD_DIR" \
    --collect-binaries libtorrent \
    "$NATIVE_DIR/helper/streamly_torrent_helper.py"

echo "Building CineFlowLibtorrentNative.framework shim..."
clang++ \
    -std=c++17 \
    -mmacosx-version-min=15.0 \
    -dynamiclib \
    -I "$NATIVE_DIR/include" \
    "$NATIVE_DIR/src/CineFlowLibtorrentNative.cpp" \
    -install_name "@rpath/CineFlowLibtorrentNative.framework/Versions/A/CineFlowLibtorrentNative" \
    -current_version 1.0 \
    -compatibility_version 1.0 \
    -o "$FRAMEWORK_DIR/Versions/A/CineFlowLibtorrentNative"

cp "$NATIVE_DIR/include/CineFlowLibtorrentNative.h" "$FRAMEWORK_DIR/Versions/A/Headers/"
/usr/bin/ditto --noextattr --norsrc "$HELPER_DIST_DIR/streamly-torrent-helper" "$FRAMEWORK_DIR/Versions/A/Resources/streamly-torrent-helper"

cat > "$FRAMEWORK_DIR/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>CineFlowLibtorrentNative</string>
    <key>CFBundleIdentifier</key>
    <string>com.streamly.CineFlowLibtorrentNative</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>CineFlowLibtorrentNative</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
</dict>
</plist>
PLIST

ln -s A "$FRAMEWORK_DIR/Versions/Current"
ln -s Versions/Current/CineFlowLibtorrentNative "$FRAMEWORK_DIR/CineFlowLibtorrentNative"
ln -s Versions/Current/Headers "$FRAMEWORK_DIR/Headers"
ln -s Versions/Current/Resources "$FRAMEWORK_DIR/Resources"

chmod 755 "$FRAMEWORK_DIR/Versions/A/CineFlowLibtorrentNative"
find "$FRAMEWORK_DIR/Versions/A/Resources/streamly-torrent-helper" -type f -name 'streamly-torrent-helper' -exec chmod 755 {} \;

rm -rf "$XCFRAMEWORK_DIR"
xcodebuild -create-xcframework \
    -framework "$FRAMEWORK_DIR" \
    -output "$XCFRAMEWORK_DIR"

echo "Created $XCFRAMEWORK_DIR"
