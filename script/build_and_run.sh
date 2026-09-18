#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build-only|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]"; exit 2 ;; esac
SIGNING_IDENTITY="${KAPKAP_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2}')"
    if [[ "$SIGNING_IDENTITY" == *$'\n'* ]]; then
        echo "Multiple development identities found. Set KAPKAP_SIGNING_IDENTITY to the intended certificate." >&2
        exit 1
    fi
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        SIGNING_IDENTITY="-"
        echo "No development certificate found: ad-hoc builds may require new privacy permission after code changes." >&2
    fi
fi

if pgrep -x KapKap >/dev/null; then
    osascript -e 'tell application id "com.lirik.KapKap" to quit'
    for attempt in 1 2 3 4 5; do
        if ! pgrep -x KapKap >/dev/null; then break; fi
        sleep 1
    done
    if pgrep -x KapKap >/dev/null; then
        echo "KapKap is still running. Finish the recording before rebuilding." >&2
        exit 1
    fi
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# Preserve the deployment floor while linking against the installed SDK appearance.
swift build --arch arm64 --sdk "$SDK_PATH" \
    -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION"
BUILD_DIR="$(swift build --arch arm64 --show-bin-path)"
APP="$ROOT_DIR/dist/KapKap.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/KapKap" "$APP/Contents/MacOS/KapKap"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ ! -x "$APP/Contents/Resources/ffmpeg" ]]; then
    python3 "$ROOT_DIR/script/bundle_export_tools.py" "$APP"
fi
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
file "$APP/Contents/MacOS/KapKap"

case "$MODE" in
    --build-only) ;;
    --debug) lldb "$APP/Contents/MacOS/KapKap" ;;
    --verify) open -n "$APP"; sleep 2; pgrep -x KapKap ;;
    --logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "KapKap"' ;;
    --telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.lirik.KapKap"' ;;
    run) open -n "$APP" ;;
esac
