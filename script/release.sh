#!/usr/bin/env bash
# Publishes a KapKap release that installed copies pick up through Sparkle.
#
#   ./script/release.sh 0.2.0            build, notarize, tag and publish on GitHub
#   ./script/release.sh 0.2.0 --dry-run  everything up to notarization, nothing leaves the Mac
#
# One-time setup (see docs/RELEASE.md):
#   - a "Developer ID Application" certificate in the login keychain
#   - the Sparkle signing key:  .build/artifacts/sparkle/Sparkle/bin/generate_keys --account KapKap
#   - notarization credentials: xcrun notarytool store-credentials KapKap
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 <major.minor.patch> [--dry-run]" >&2; exit 2; }
TAG="v$VERSION"
REPO="design-ninja/KapKap"
NOTARY_PROFILE="${KAPKAP_NOTARY_PROFILE:-KapKap}"
# KapKap's own Sparkle key, kept apart from any other app's key in the same keychain.
KEY_ACCOUNT="${KAPKAP_SPARKLE_ACCOUNT:-KapKap}"
IDENTITY="${KAPKAP_RELEASE_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application:/{print $2; exit}')}"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate found." >&2; exit 1; }

fail() { echo "error: $*" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || fail "commit or stash your changes first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists"
grep -q '^## \[Unreleased\]' CHANGELOG.md || fail "CHANGELOG.md has no [Unreleased] section to release"

swift package resolve >/dev/null
SPARKLE_BIN="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin"
# The public half goes into the app; the private half never leaves the keychain (or the file
# named by KAPKAP_SPARKLE_KEY_FILE, used for dry runs with a throwaway key).
if [[ -n "${KAPKAP_SPARKLE_KEY_FILE:-}" ]]; then
    KEY_ARGS=(--ed-key-file "$KAPKAP_SPARKLE_KEY_FILE")
    PUBLIC_KEY="${KAPKAP_SPARKLE_PUBLIC_KEY:?set KAPKAP_SPARKLE_PUBLIC_KEY with KAPKAP_SPARKLE_KEY_FILE}"
else
    KEY_ARGS=(--account "$KEY_ACCOUNT")
    PUBLIC_KEY="$("$SPARKLE_BIN/generate_keys" --account "$KEY_ACCOUNT" -p 2>/dev/null)" \
        || fail "no Sparkle key for $KEY_ACCOUNT; run $SPARKLE_BIN/generate_keys --account $KEY_ACCOUNT once and back it up"
fi

OUT="$ROOT_DIR/dist/release/$VERSION"
rm -rf "$OUT" && mkdir -p "$OUT"

# 1. Version and changelog. The build number only ever grows; Sparkle compares it.
PLIST="$ROOT_DIR/Resources/Info.plist"
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" "$PLIST"
python3 - "$VERSION" "$(date +%Y-%m-%d)" "$REPO" "$OUT/notes.md" <<'EOF'
import re, sys
version, date, repo, notes_path = sys.argv[1:]
text = open("CHANGELOG.md").read()
start = text.index("## [Unreleased]") + len("## [Unreleased]")
end = text.index("\n## [", start)
notes = text[start:end].strip()
if not notes:
    sys.exit("error: the [Unreleased] section is empty")
text = text[:start] + f"\n\n## [{version}] - {date}\n\n{notes}\n" + text[end:]
previous = re.search(r"^\[Unreleased\]: .*compare/(v[\d.]+)\.\.\.HEAD$", text, re.M)
text = re.sub(r"^\[Unreleased\]: .*$",
              f"[Unreleased]: https://github.com/{repo}/compare/v{version}...HEAD\n"
              f"[{version}]: https://github.com/{repo}/compare/{previous.group(1)}...v{version}"
              if previous else f"[Unreleased]: https://github.com/{repo}/compare/v{version}...HEAD",
              text, count=1, flags=re.M)
open("CHANGELOG.md", "w").write(text)
open(notes_path, "w").write(notes + "\n")
EOF

# 2. A release bundle: Developer ID, hardened runtime, the real public key.
cp "$PLIST" "$OUT/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$OUT/Info.plist"
APP="$OUT/KapKap.app"
KAPKAP_CONFIGURATION=release KAPKAP_RELEASE=1 KAPKAP_APP="$APP" KAPKAP_INFO_PLIST="$OUT/Info.plist" \
    KAPKAP_SIGNING_IDENTITY="$IDENTITY" ./script/build_and_run.sh --build-only

ARCHIVE="$OUT/KapKap-$VERSION.zip"
# The GPL and LGPL parts of the bundled FFmpeg ship with their source (THIRD_PARTY_NOTICES.md).
SOURCES_DIR="$ROOT_DIR/dist/release/sources"
SOURCES="$OUT/KapKap-$VERSION-third-party-sources.tar"
ls "$SOURCES_DIR"/ffmpeg-*.tar.* >/dev/null 2>&1 || fail "put the FFmpeg, x264, x265, LAME and mpg123 sources in $SOURCES_DIR"
tar -cf "$SOURCES" -C "$SOURCES_DIR" .
if [[ "$DRY_RUN" == "0" ]]; then
    # 3. Notarize, then staple so the app opens offline, then archive the stapled app.
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$OUT/notarize.zip"
    spctl --assess --type execute "$APP"
fi
ditto -c -k --keepParent "$APP" "$ARCHIVE"

# 4. The feed Sparkle reads from the latest release, with notes shown in the update window.
python3 - "$OUT/notes.md" "$OUT/KapKap-$VERSION.html" <<'EOF'
import html, re, sys
lines, out, in_list = open(sys.argv[1]).read().splitlines(), [], False
def inline(s):
    s = html.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
for line in lines:
    if line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append(f"<li>{inline(line[2:])}")
    elif line.startswith("  ") and in_list:
        out[-1] += " " + inline(line.strip())
    else:
        if in_list: out.append("</ul>"); in_list = False
        if line.startswith("### "): out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line.strip(): out.append(f"<p>{inline(line)}</p>")
if in_list: out.append("</ul>")
open(sys.argv[2], "w").write("\n".join(out) + "\n")
EOF
FEED="$OUT/feed"
mkdir -p "$FEED" && cp "$ARCHIVE" "$OUT/KapKap-$VERSION.html" "$FEED/"
"$SPARKLE_BIN/generate_appcast" "${KEY_ARGS[@]}" --embed-release-notes \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$FEED"
cp "$FEED/appcast.xml" "$OUT/appcast.xml"

if [[ "$DRY_RUN" == "1" ]]; then
    git checkout -- "$PLIST" CHANGELOG.md
    echo "Dry run complete: $OUT (version and changelog changes reverted)"
    exit 0
fi

# 5. Publish: the commit and tag first, then the release that makes the feed live.
git commit -m "chore: release $VERSION" -- "$PLIST" CHANGELOG.md
git tag -a "$TAG" -m "KapKap $VERSION"
git push origin HEAD "$TAG"
gh release create "$TAG" "$ARCHIVE" "$OUT/appcast.xml" "$SOURCES" --repo "$REPO" \
    --title "KapKap $VERSION" --notes-file "$OUT/notes.md" --latest
echo "Released $TAG: https://github.com/$REPO/releases/tag/$TAG"
