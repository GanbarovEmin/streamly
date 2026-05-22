#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Streamly"
APP_BUNDLE="$ROOT_DIR/dist/release/$APP_NAME.app"
VERIFY=0
SKIP_BUILD=0
QUIT_AFTER_VERIFY=0
VERIFY_STABLE_SECONDS="${STREAMLY_LAUNCH_VERIFY_SECONDS:-8}"
BUILD_ARGS=(--unsigned)

usage() {
    cat <<'USAGE'
Usage: script/build_and_run.sh [options]

Options:
  --verify              Wait for the Streamly process after launch.
  --verify-seconds N    Require the launched process to stay alive for N seconds.
  --skip-build          Launch the existing dist/release/Streamly.app.
  --quit-after-verify   Quit Streamly after a successful --verify run.
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
        --verify-seconds)
            VERIFY_STABLE_SECONDS="${2:?Missing value for --verify-seconds}"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --quit-after-verify)
            QUIT_AFTER_VERIFY=1
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

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    "$ROOT_DIR/script/build_release.sh" "${BUILD_ARGS[@]}"
elif [[ ! -d "$APP_BUNDLE" ]]; then
    echo "Missing $APP_BUNDLE. Run without --skip-build first." >&2
    exit 66
fi

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

OPEN_STDOUT="$(mktemp "${TMPDIR:-/tmp}/streamly-open-stdout.XXXXXX")"
OPEN_STDERR="$(mktemp "${TMPDIR:-/tmp}/streamly-open-stderr.XXXXXX")"
CRASH_MARKER=""
if [[ "$VERIFY" -eq 1 ]]; then
    CRASH_MARKER="$(mktemp "${TMPDIR:-/tmp}/streamly-launch-marker.XXXXXX")"
    touch "$CRASH_MARKER"
fi

if ! /usr/bin/open -n "$APP_BUNDLE" >"$OPEN_STDOUT" 2>"$OPEN_STDERR"; then
    cat "$OPEN_STDOUT"
    cat "$OPEN_STDERR" >&2
    exit 70
fi

if [[ "$VERIFY" -eq 1 ]]; then
    STARTED=0
    for _ in {1..30}; do
        if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            STARTED=1
            break
        fi
        sleep 1
    done

    if [[ "$STARTED" -ne 1 ]]; then
        echo "$APP_NAME did not start within 30 seconds." >&2
        cat "$OPEN_STDERR" >&2
        find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 \( -name "$APP_NAME*.crash" -o -name "$APP_NAME*.ips" \) -newer "$CRASH_MARKER" -print 2>/dev/null || true
        exit 70
    fi

    sleep "$VERIFY_STABLE_SECONDS"

    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "$APP_NAME started but exited before the $VERIFY_STABLE_SECONDS second launch smoke completed." >&2
        cat "$OPEN_STDERR" >&2
        find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 \( -name "$APP_NAME*.crash" -o -name "$APP_NAME*.ips" \) -newer "$CRASH_MARKER" -print 2>/dev/null || true
        exit 70
    fi

    if find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 \( -name "$APP_NAME*.crash" -o -name "$APP_NAME*.ips" \) -newer "$CRASH_MARKER" -print -quit 2>/dev/null | grep -q .; then
        echo "$APP_NAME produced a crash report during launch smoke." >&2
        find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 \( -name "$APP_NAME*.crash" -o -name "$APP_NAME*.ips" \) -newer "$CRASH_MARKER" -print 2>/dev/null || true
        exit 70
    fi

    echo "$APP_NAME is running after $VERIFY_STABLE_SECONDS seconds."

    if [[ "$QUIT_AFTER_VERIFY" -eq 1 ]]; then
        osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
        sleep 1
        pkill -x "$APP_NAME" >/dev/null 2>&1 || true
    fi

    exit 0
fi
