#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Streamly"
APP_BUNDLE="$ROOT_DIR/dist/release/$APP_NAME.app"
VERIFY=0
BUILD_ARGS=(--unsigned)

usage() {
    cat <<'USAGE'
Usage: script/build_and_run.sh [options]

Options:
  --verify              Wait for the Streamly process after launch.
  --version VERSION     Forward a version override to build_release.sh.
  --build BUILD_NUMBER  Forward a build override to build_release.sh.
  -h, --help            Show this help.

The script creates an unsigned local app bundle and launches it.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)
            VERIFY=1
            shift
            ;;
        --version|--build)
            BUILD_ARGS+=("$1" "${2:?Missing value for $1}")
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

"$ROOT_DIR/script/build_release.sh" "${BUILD_ARGS[@]}"

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

/usr/bin/open -n "$APP_BUNDLE"

if [[ "$VERIFY" -eq 1 ]]; then
    for _ in {1..30}; do
        if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            echo "$APP_NAME is running."
            exit 0
        fi
        sleep 1
    done
    echo "$APP_NAME did not start within 30 seconds." >&2
    exit 70
fi
