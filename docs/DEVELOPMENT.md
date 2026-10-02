# Developing KapKap

## Build and run

Open `Package.swift` in Xcode, or use:

```sh
./script/build_and_run.sh          # build and launch
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify # launch and check the process is running
swift test
```

You need Apple Silicon, Xcode 27 / Swift 6.4 and the tools that build the bundled FFmpeg:

```sh
brew install pkg-config cmake meson ninja
```

### Bundled FFmpeg

On the first run `script/build_ffmpeg.sh` downloads the pinned sources of FFmpeg and its codecs
(x264, x265, libvpx, SVT-AV1, Opus, dav1d), checks their SHA-256, and builds one static ARM
executable for macOS 15 with only what exports need. It takes a few minutes; later builds reuse it
from `.build/ffmpeg`. The app does not need Homebrew at runtime.

`script/build_gifsicle.sh` builds the Gifsicle that shrinks GIF exports the same way, from a pinned
release into `.build/gifsicle`, and the bundle carries it next to FFmpeg.

### Debug and release copies

Development builds are staged at `dist/KapKap Debug.app` with bundle ID `com.lirik.KapKap.debug`;
release builds keep `com.lirik.KapKap`. macOS stores privacy permissions against both the bundle ID
and the signing requirement, so separate IDs keep a development copy and an installed release from
conflicting. Grant Screen Recording to **KapKap Debug** once after switching to this build, and
launch that copy for development. The run script stops only the copy with the matching bundle ID.

### Signing

The build uses the sole Apple Development identity in the keychain, or an explicit
`KAPKAP_SIGNING_IDENTITY`. A stable certificate keeps the app's identity, and with it the privacy
permissions, consistent across rebuilds.

- If no certificate is visible, the script stops before building. Run it with keychain access,
  outside the command sandbox.
- Ad-hoc signing is available explicitly with `KAPKAP_SIGNING_IDENTITY=-`, but macOS may ask for
  permissions again after code changes.
- The first switch from ad-hoc to certificate signing may also require renewing the permission once.

## Architecture

- `CaptureCore`: display coordinates, shared pause timeline, export options, tests.
- `Sources/KapKap/Recording`: ScreenCaptureKit session and serial AVAssetWriter pipeline.
- `Sources/KapKap/Views`: SwiftUI recorder, settings, window picker, library and editor.
- `Sources/KapKap/Stores`: observable recording and editor state.
- `Sources/KapKap/Selection`: SwiftUI selection drawing and gestures; a small AppKit adapter
  creates borderless windows across displays, sets their level and handles Escape.
- `Sources/KapKap/Export`: cancellable bundled ARM FFmpeg execution and atomic export.

SwiftUI owns all screens and controls. AppKit is used narrowly for desktop overlay placement, app
lifecycle, and macOS file dialogs / Finder integration.

## Tests

`swift test` covers display coordinates, pause timing, static-screen duration, empty recordings,
recordings interrupted by the system, recovery of unfinished files, restoring the last area,
shortcut registration and labels, clean-up of clipboard exports, and encode/decode round trips for
all six export formats, looping, mixing of two audio tracks, the size order of the three export
qualities, lossy GIF compression, export progress and cancellation, using generated fixtures.

Build the app first so the bundled export executable is available;
`KAPKAP_REQUIRE_EXPORT_TOOLS=1 swift test` fails instead of skipping the export tests when it is not.

Real screen, system audio and microphone capture and multi-monitor behavior need permissions and
on-device testing; a successful build alone is not evidence that those scenarios work.

## Releases

`./script/release.sh <version>` builds, signs, notarizes and publishes a release that installed
copies pick up through [Sparkle](https://sparkle-project.org). See [RELEASE.md](RELEASE.md).
Third-party licenses, including the bundled FFmpeg, are listed in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
