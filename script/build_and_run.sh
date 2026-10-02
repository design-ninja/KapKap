#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--build-only|--verify|--debug|--logs|--telemetry) ;; *) echo "Usage: $0 [--build-only|--verify|--debug|--logs|--telemetry]"; exit 2 ;; esac
CONFIGURATION="${KAPKAP_CONFIGURATION:-debug}"
RELEASE="${KAPKAP_RELEASE:-0}"
INFO_PLIST="${KAPKAP_INFO_PLIST:-$ROOT_DIR/Resources/Info.plist}"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
APP_NAME="KapKap"
if [[ "$RELEASE" != "1" ]]; then
    BUNDLE_ID="$BUNDLE_ID.debug"
    APP_NAME="KapKap Debug"
fi
APP="${KAPKAP_APP:-$ROOT_DIR/dist/$APP_NAME.app}"
SIGNING_IDENTITY="${KAPKAP_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2}')"
    if [[ "$SIGNING_IDENTITY" == *$'\n'* ]]; then
        echo "Multiple development identities found. Set KAPKAP_SIGNING_IDENTITY to the intended certificate." >&2
        exit 1
    fi
    if [[ -z "$SIGNING_IDENTITY" ]]; then
        echo "No development certificate is visible. Run outside the sandbox with keychain access, or set KAPKAP_SIGNING_IDENTITY. For an intentional ad-hoc build, set KAPKAP_SIGNING_IDENTITY=-; privacy permissions may reset after code changes." >&2
        exit 1
    fi
fi

app_processes() {
    osascript -l JavaScript -e '
        ObjC.import("AppKit");
        function run(argv) {
            const apps = $.NSWorkspace.sharedWorkspace.runningApplications.js
                .filter(app => ObjC.unwrap(app.bundleIdentifier) === argv[0]);
            if (argv[1] === "quit") apps.forEach(app => app.terminate);
            return apps.map(app => app.processIdentifier).join("\n");
        }' "$BUNDLE_ID" "${1:-list}"
}

if [[ -n "$(app_processes)" ]]; then
    app_processes quit >/dev/null
    for attempt in 1 2 3 4 5; do
        if [[ -z "$(app_processes)" ]]; then break; fi
        sleep 1
    done
    if [[ -n "$(app_processes)" ]]; then
        echo "$APP_NAME is still running. Finish the recording before rebuilding." >&2
        exit 1
    fi
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
# Preserve the deployment floor while linking against the installed SDK appearance.
# Release builds (script/release.sh) set these; everyday builds keep the debug defaults.
swift build --arch arm64 -c "$CONFIGURATION" --sdk "$SDK_PATH" \
    -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION"
BUILD_DIR="$(swift build --arch arm64 -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/KapKap" "$APP/Contents/MacOS/KapKap"
# Sparkle (updates) ships as a framework; a bundled app looks for it in Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$BUILD_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/KapKap" 2>/dev/null || true
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"
if [[ "$RELEASE" != "1" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" \
        -c "Set :CFBundleName $APP_NAME" -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
fi
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
rm -rf "$APP/Contents/Resources/Licenses" && cp -R "$ROOT_DIR/Resources/Licenses" "$APP/Contents/Resources/Licenses"
# Builds FFmpeg and Gifsicle from source the first time (a few minutes), then reuses them; adds their license texts.
python3 "$ROOT_DIR/script/bundle_export_tools.py" "$APP"
if [[ "$RELEASE" == "1" ]]; then
    # Notarization wants every binary signed by us with the hardened runtime and a timestamp,
    # innermost first. Library validation also rejects Sparkle as shipped (another team's
    # signature), so it is re-signed in the order Sparkle's documentation gives.
    sign() { codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$@"; }
    # Symbols stay in a dSYM beside the app for crash reports; the shipped binary drops them (about 2 MB).
    rm -rf "$APP.dSYM"
    dsymutil "$APP/Contents/MacOS/KapKap" -o "$APP.dSYM" || echo "warning: no dSYM for KapKap" >&2
    strip -rSTx "$APP/Contents/MacOS/KapKap"
    sign "$APP/Contents/Resources/ffmpeg"
    sign "$APP/Contents/Resources/gifsicle"
    SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    sign "$SPARKLE/XPCServices/Installer.xpc"
    sign --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
    sign "$SPARKLE/Autoupdate"
    sign "$SPARKLE/Updater.app"
    sign "$APP/Contents/Frameworks/Sparkle.framework"
    sign --entitlements "$ROOT_DIR/Resources/KapKap.entitlements" "$APP"
else
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP"
fi
codesign --verify --deep --strict "$APP"
file "$APP/Contents/MacOS/KapKap"

case "$MODE" in
    --build-only) ;;
    --debug) lldb "$APP/Contents/MacOS/KapKap" ;;
    --verify) open -n "$APP"; sleep 2; PIDS="$(app_processes)"; [[ -n "$PIDS" ]]; echo "$PIDS" ;;
    --logs) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'process == "KapKap"' ;;
    --telemetry) open -n "$APP"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.lirik.KapKap"' ;;
    run) open -n "$APP" ;;
esac
