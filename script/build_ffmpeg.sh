#!/usr/bin/env bash
# Builds the FFmpeg that KapKap bundles and prints the path of its `ffmpeg` executable.
#
#   script/build_ffmpeg.sh            build (or reuse) and print the executable's path
#   script/build_ffmpeg.sh --sources  print the source archives the build uses, one per line
#
# Everything is built from pinned sources for macOS 15, the app's minimum, and linked statically
# into one executable: Homebrew's bottles target the Mac they were built for, so they fail to load
# on older systems. Only the encoders, muxers and filters that exports use are kept; every decoder
# and demuxer stays, so any video can still be imported. There is no network access, OpenSSL,
# libvmaf, LAME or mpg123. Exports are 8-bit 4:2:0, so x264 and x265 are built for that alone.
# VideoToolbox, part of macOS, adds the Mac's hardware H.264 and HEVC encoders for fast exports.
#
# Needs Xcode's command line tools, pkg-config, cmake, meson and ninja (brew install pkg-config cmake meson ninja).
# The result is cached in .build/ffmpeg/, keyed by this script's contents.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIMUM_MACOS="15.0"

# name, archive, sha256, url. Checksums are those Homebrew publishes, except x264, which has no
# release tarballs: its archive is the snapshot KapKap ships as source.
SOURCES="
ffmpeg   ffmpeg-8.1.2.tar.xz        464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz
x264     x264-b35605a.tar.bz2       6eeb82934e69fd51e043bd8c5b0d152839638d1ce7aa4eea65a3fedcf83ff224 https://code.videolan.org/videolan/x264/-/archive/b35605ace3ddf7c1a5d67a2eb553f034aef41d55/x264-b35605ace3ddf7c1a5d67a2eb553f034aef41d55.tar.bz2
x265     x265_4.3.tar.gz            83c53e4c8bbb8f1e33ed59e10a7d621d1d7801ca853910c3eb41f038b8ffb121 https://github.com/Multicorewareinc/x265/releases/download/4.3/x265_4.3.tar.gz
libvpx   libvpx-1.17.0.tar.gz       1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz
svt-av1  SVT-AV1-v4.2.0.tar.bz2     512f2ea5649e3e76c2dddcc25c2556fb67a9582baaab207c9c96161c94659dad https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.bz2
opus     opus-1.6.1.tar.gz          6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1 https://ftp.osuosl.org/pub/xiph/releases/opus/opus-1.6.1.tar.gz
dav1d    dav1d-1.5.4.tar.bz2        2abfb0c89212e6e4733a54e0ae509ec00a5b845a6360946f918806e14aedb011 https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2
"
# Kept with the release: the GPL requires FFmpeg's, x264's and x265's source next to the binary.
SOURCES_DIR="$ROOT_DIR/dist/release/sources"

ENCODERS=libx264,libx265,h264_videotoolbox,hevc_videotoolbox,libvpx_vp9,libsvtav1,libopus,aac,gif,apng,wrapped_avframe,pcm_s16le
MUXERS=mp4,webm,gif,apng,null
# What ExportOptions builds, what the ffmpeg tool and libavfilter insert on their own (trimming,
# rotation, cropping, format conversion), and the sources and meters the export tests use.
FILTERS=buffer,buffersink,abuffer,abuffersink,format,aformat,null,anull,scale,aresample,fps,split
FILTERS+=,palettegen,paletteuse,amix,trim,atrim,transpose,hflip,vflip,rotate,crop,apad
FILTERS+=,testsrc2,sine,bandpass,volumedetect

archive() {
    local name file sha url
    while read -r name file sha url; do
        [[ "$name" == "$1" ]] || continue
        local path="$SOURCES_DIR/$file"
        if [[ ! -f "$path" ]]; then
            mkdir -p "$SOURCES_DIR"
            curl --fail --location --silent --show-error -o "$path.part" "$url" >&2
            mv "$path.part" "$path"
        fi
        echo "$sha  $path" | shasum -a 256 -c --status || { echo "$path does not match its pinned checksum" >&2; exit 1; }
        echo "$path"
        return
    done <<< "$SOURCES"
    echo "Unknown source $1" >&2; exit 1
}

if [[ "${1:-}" == "--sources" ]]; then
    while read -r name _; do [[ -n "$name" ]] && archive "$name"; done <<< "$SOURCES"
    exit 0
fi

KEY="$(shasum -a 256 "${BASH_SOURCE[0]}" | cut -c1-12)"
OUT="$ROOT_DIR/.build/ffmpeg/$KEY"
if [[ -x "$OUT/bin/ffmpeg" ]]; then echo "$OUT/bin/ffmpeg"; exit 0; fi
for tool in pkg-config cmake meson ninja; do
    command -v "$tool" >/dev/null || { echo "$tool is required: brew install pkg-config cmake meson ninja" >&2; exit 1; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kapkap-ffmpeg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT"
DEPS="$OUT/deps"
LICENSES="$OUT/licenses"
mkdir -p "$DEPS" "$LICENSES"
JOBS="$(sysctl -n hw.ncpu)"
export MACOSX_DEPLOYMENT_TARGET="$MINIMUM_MACOS"
# Only the libraries built here, never Homebrew's.
export PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
export PKG_CONFIG_PATH=""
CMAKE_ARGS=(-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" -DCMAKE_INSTALL_LIBDIR=lib
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$MINIMUM_MACOS" -DCMAKE_OSX_ARCHITECTURES=arm64
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

unpack() {
    local directory="$WORK/$1"
    mkdir -p "$directory"
    tar -xf "$(archive "$1")" -C "$directory" --strip-components 1
    echo "$directory"
}

# License texts travel with the app (Contents/Resources/Licenses).
keep_license() {
    local name="$1" directory="$2"; shift 2
    mkdir -p "$LICENSES/$name"
    for file in "$@"; do cp "$directory/$file" "$LICENSES/$name/"; done
}

log() { echo "== $*" >&2; }

log x264
SRC="$(unpack x264)"
(cd "$SRC" && ./configure --prefix="$DEPS" --enable-static --enable-pic --disable-cli --disable-opencl \
    --disable-lsmash --disable-swscale --disable-ffms --disable-gpac --bit-depth=8 --chroma-format=420 \
    --extra-cflags="-mmacosx-version-min=$MINIMUM_MACOS" && make -j"$JOBS" && make install-lib-static) >&2
keep_license x264 "$SRC" COPYING

log x265
SRC="$(unpack x265)"
cmake -S "$SRC/source" -B "$SRC/build" "${CMAKE_ARGS[@]}" -DENABLE_SHARED=OFF -DENABLE_CLI=OFF >&2
cmake --build "$SRC/build" -j "$JOBS" >&2 && cmake --install "$SRC/build" >&2
keep_license x265 "$SRC" COPYING

log libvpx
SRC="$(unpack libvpx)"
# darwin24 is macOS 15, which also sets libvpx's deployment target.
(cd "$SRC" && ./configure --prefix="$DEPS" --target=arm64-darwin24-gcc --enable-static --disable-shared \
    --enable-pic --enable-runtime-cpu-detect --disable-examples --disable-tools --disable-docs \
    --disable-unit-tests --disable-vp8 --disable-vp9-decoder && make -j"$JOBS" && make install) >&2
keep_license libvpx "$SRC" LICENSE PATENTS

log SVT-AV1
SRC="$(unpack svt-av1)"
cmake -S "$SRC" -B "$SRC/build" "${CMAKE_ARGS[@]}" -DBUILD_SHARED_LIBS=OFF -DBUILD_APPS=OFF -DBUILD_TESTING=OFF >&2
cmake --build "$SRC/build" -j "$JOBS" >&2 && cmake --install "$SRC/build" >&2
keep_license svt-av1 "$SRC" LICENSE.md PATENTS.md

log Opus
SRC="$(unpack opus)"
(cd "$SRC" && ./configure --prefix="$DEPS" --enable-static --disable-shared --disable-doc \
    --disable-extra-programs && make -j"$JOBS" && make install) >&2
keep_license opus "$SRC" COPYING

log dav1d
SRC="$(unpack dav1d)"
meson setup "$SRC/build" "$SRC" --prefix="$DEPS" --libdir=lib --buildtype=release --default-library=static \
    -Denable_tools=false -Denable_tests=false >&2
meson compile -C "$SRC/build" >&2 && meson install -C "$SRC/build" >&2
keep_license dav1d "$SRC" COPYING

log FFmpeg
SRC="$(unpack ffmpeg)"
(cd "$SRC" && ./configure --prefix="$OUT" --arch=arm64 --target-os=darwin --cc=clang \
    --enable-gpl --enable-version3 \
    --disable-shared --enable-static --pkg-config-flags=--static \
    --disable-programs --enable-ffmpeg --disable-doc --disable-debug \
    --disable-autodetect --disable-network --enable-videotoolbox \
    --enable-zlib --enable-bzlib --enable-iconv \
    --enable-libx264 --enable-libx265 --enable-libvpx --enable-libsvtav1 --enable-libopus --enable-libdav1d \
    --disable-encoders --enable-encoder="$ENCODERS" \
    --disable-muxers --enable-muxer="$MUXERS" \
    --disable-filters --enable-filter="$FILTERS" \
    --disable-protocols --enable-protocol=file,pipe \
    --disable-indevs --enable-indev=lavfi --disable-outdevs \
    --extra-cflags="-mmacosx-version-min=$MINIMUM_MACOS" \
    --extra-ldflags="-mmacosx-version-min=$MINIMUM_MACOS -Wl,-dead_strip" --extra-libs=-liconv \
    && make -j"$JOBS" && make install) >&2
keep_license ffmpeg "$SRC" LICENSE.md COPYING.GPLv3

echo "$OUT/bin/ffmpeg"
