#!/usr/bin/env bash
# Builds the Gifsicle that KapKap bundles to shrink GIF exports and prints the path of its executable.
#
#   script/build_gifsicle.sh            build (or reuse) and print the executable's path
#   script/build_gifsicle.sh --sources  print the source archive the build uses
#
# Built from a pinned release for macOS 15, the app's minimum, with no X11 viewer or gifdiff.
# The result is cached in .build/gifsicle/, keyed by this script's contents.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIMUM_MACOS="15.0"
VERSION="1.96"
FILE="gifsicle-$VERSION.tar.gz"
# The checksum Homebrew publishes.
SHA256="fd23d279681a6dfe3c15264e33f344045b3ba473da4d19f49e67a50994b077fb"
URL="https://www.lcdf.org/gifsicle/$FILE"
# Kept with the release: the GPL requires Gifsicle's source next to the binary.
SOURCES_DIR="$ROOT_DIR/dist/release/sources"

archive() {
    local path="$SOURCES_DIR/$FILE"
    if [[ ! -f "$path" ]]; then
        mkdir -p "$SOURCES_DIR"
        curl --fail --location --silent --show-error -o "$path.part" "$URL" >&2
        mv "$path.part" "$path"
    fi
    echo "$SHA256  $path" | shasum -a 256 -c --status || { echo "$path does not match its pinned checksum" >&2; exit 1; }
    echo "$path"
}

if [[ "${1:-}" == "--sources" ]]; then archive; exit 0; fi

KEY="$(shasum -a 256 "${BASH_SOURCE[0]}" | cut -c1-12)"
OUT="$ROOT_DIR/.build/gifsicle/$KEY"
if [[ -x "$OUT/bin/gifsicle" ]]; then echo "$OUT/bin/gifsicle"; exit 0; fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kapkap-gifsicle.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT"
tar -xf "$(archive)" -C "$WORK" --strip-components 1
echo "== Gifsicle" >&2
(cd "$WORK" && ./configure --prefix="$OUT" --disable-gifview --disable-gifdiff \
    CFLAGS="-O2 -arch arm64 -mmacosx-version-min=$MINIMUM_MACOS" \
    LDFLAGS="-arch arm64 -mmacosx-version-min=$MINIMUM_MACOS" \
    && make -j"$(sysctl -n hw.ncpu)" && make install) >&2
# License text travels with the app (Contents/Resources/Licenses).
mkdir -p "$OUT/licenses/gifsicle"
cp "$WORK/COPYING" "$OUT/licenses/gifsicle/"

echo "$OUT/bin/gifsicle"
