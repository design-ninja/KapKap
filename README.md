# KapKap

Native Apple Silicon screen recorder inspired by [Kap](https://github.com/wulkano/Kap).
SwiftUI interface, ScreenCaptureKit capture, AVFoundation recording. No Electron,
Node.js, Rosetta, or plugin system.

## Development

Open `Package.swift` in Xcode, or use:

```sh
./script/build_and_run.sh
swift test
```

Requirements: Apple Silicon, Xcode 27 / Swift 6.4 for this development build,
and an ARM Homebrew FFmpeg installation (`brew install ffmpeg`). The build script
copies FFmpeg and its linked libraries into the app and checks every binary for ARM
support. The resulting local `.app` does not need Homebrew at runtime.

The app is staged at `dist/KapKap.app`. The build uses the sole Apple Development
identity in the keychain, or an explicit `KAPKAP_SIGNING_IDENTITY`. A stable certificate
keeps the application's identity consistent across rebuilds for macOS privacy permissions.
Without a certificate it falls back to ad-hoc signing, which can require granting access
again after code changes. The first switch from ad-hoc to certificate signing may also
require renewing the permission once.
`--build-only` builds without opening it; `--verify` checks the launched process.
The Codex Run action uses the same script.

## Recording

1. The last selected area is restored on launch. Before an area is saved, the built-in display is selected (otherwise the main display). You can select a new area, display or window.
2. Enable microphone / cursor / click highlighting if needed. Recording and export share one set of
   frame rates — 60, 30, 24 and 15 fps; the editor never offers more than the recording holds.
3. Press Record. Grant Screen Recording and, optionally, Microphone access when macOS asks.
4. Pause/resume or stop from the recorder window or menu bar.
5. The recording is saved automatically and opens in the editor.

The global start/stop shortcut defaults to **⌃⌥⌘R**. Change it in Settings by clicking
its button and pressing Command or Control with a letter or number; Escape cancels.
The choice persists across launches. A registration conflict keeps the previous choice;
shortcuts handled locally by another app cannot always be detected.
Left-clicking the menu-bar icon opens the recorder panel; while recording it stops. Right-click opens the menu. The source menu also
lets you return to the last area after choosing a display or window. A disconnected display
or a saved area outside the current display bounds requires selecting a new area.

The window picker lists one entry per app with an on-screen window, front to back. Choosing one
activates that app and outlines the window that will be captured; the recorder panel stays on top.
While an area is being drawn or resized, the selection panel fades out of the way.

Originals are stored in `~/Library/Application Support/KapKap/Recordings`.
Unfinished files have a leading dot and are retained for diagnosis rather than silently deleted.
Exports preserve the original file. The editor supports trimming, resolution, frame rate,
mute, and MP4, GIF, APNG, WebM, HEVC and AV1 export. A finished export plays a system sound.
Closing the editor while its own recording has never been exported asks first, and offers to keep
it in Recent recordings or move it to the Trash; imported videos are never touched. The recorder
panel hides while an editor window is open. Recent recordings is a list with a 16:9 poster frame per row and can
reveal a file in Finder or copy it to the clipboard.

## Architecture

- `CaptureCore`: display coordinates, shared pause timeline, export options, tests.
- `Sources/KapKap/Recording`: ScreenCaptureKit session and serial AVAssetWriter pipeline.
- `Sources/KapKap/Views`: SwiftUI recorder, settings, window picker, library and editor.
- `Sources/KapKap/Stores`: observable recording and editor state.
- `Sources/KapKap/Selection`: SwiftUI selection drawing and gestures; a small AppKit adapter
  creates borderless windows across displays, sets their level and handles Escape.
- `Sources/KapKap/Export`: cancellable bundled ARM FFmpeg execution and atomic export.

SwiftUI owns all screens and controls. AppKit is used narrowly for desktop overlay
placement, app lifecycle, and macOS file dialogs / Finder integration.

## Scope and verification

This is the first native implementation, not a feature-complete or pixel-identical Kap port.
Tests cover display coordinates, pause timing, static-screen duration, empty recordings, and
encode/decode round trips for all six export formats using a generated video/audio fixture.
Build the app before testing so the bundled export executable is available.

Full visual parity, editable selection handles/aspect ratios, original Kap settings/history migration, crash recovery, and signed public
distribution remain follow-up work. Real screen/microphone capture and multi-monitor
behavior require permissions and on-device testing; a successful build alone is not evidence
that those scenarios work.

See `THIRD_PARTY_NOTICES.md` before distributing an export-enabled build.
