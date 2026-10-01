<p align="center">
  <img src="docs/images/icon.png" width="80" height="80" alt="KapKap icon">
</p>

<h1 align="center">KapKap</h1>

<p align="center">A native macOS screen recorder for Apple Silicon.</p>

<p align="center"><a href="https://github.com/design-ninja/KapKap/releases/latest"><b>Download the latest release</b></a></p>

<p align="center">
  <img src="docs/images/panel-dunes.webp" width="100%" alt="The KapKap recorder panel: select an area, choose a window, record, recent recordings and settings">
</p>

Record an area, a window or a whole display, trim the result and export it as MP4, GIF, APNG,
WebM, HEVC or AV1. KapKap is written in Swift with SwiftUI, ScreenCaptureKit and AVFoundation,
lives in the menu bar and keeps itself up to date.

- System audio and microphone, cursor and click highlighting, 15 to 60 fps
- Global shortcuts to start or stop a recording and to select an area
- An editor with trimming, resizing, frame rate, quality and mute, with the expected file size
- Save, copy to the clipboard or open the export straight in another app

## Install

Download `KapKap-<version>.zip` from the [latest release](https://github.com/design-ninja/KapKap/releases/latest),
unzip it and move KapKap to Applications. Builds are signed with Developer ID and notarized by Apple.
KapKap checks GitHub for new versions and installs them when you agree; turn automatic checks off
in Settings → General. It requires macOS 15 or later on Apple Silicon.

## Development

Open `Package.swift` in Xcode, or use:

```sh
./script/build_and_run.sh
swift test
```

Requirements: Apple Silicon, Xcode 27 / Swift 6.4 for this development build, and the tools that
build the bundled FFmpeg: `brew install pkg-config cmake meson ninja`. On the first run
`script/build_ffmpeg.sh` downloads the pinned sources of FFmpeg and its codecs (x264, x265, libvpx,
SVT-AV1, Opus, dav1d), checks their SHA-256, and builds one static ARM executable for macOS 15 with
only what exports need, in a few minutes; later builds reuse it from `.build/ffmpeg`. The app does
not need Homebrew at runtime.

Development builds are staged at `dist/KapKap Debug.app`, with bundle ID
`com.lirik.KapKap.debug`. Release builds keep `com.lirik.KapKap`. macOS stores privacy
permissions against both the bundle ID and the signing requirement; separate IDs keep
development and installed release copies from conflicting. Grant Screen Recording to
**KapKap Debug** once after switching to this build, and launch that copy for development.
The run script stops only the copy with the matching bundle ID.

The build uses the sole Apple Development
identity in the keychain, or an explicit `KAPKAP_SIGNING_IDENTITY`. A stable certificate
keeps the application's identity consistent across rebuilds for macOS privacy permissions.
If no certificate is visible, the script stops before building; run with keychain access
outside the command sandbox. Ad-hoc signing is available explicitly with
`KAPKAP_SIGNING_IDENTITY=-`, but can require granting access again after code changes.
The first switch from ad-hoc to certificate signing may also require renewing the permission once.
`--build-only` builds without opening it; `--verify` checks the launched process.

## Recording

1. The last selected area is restored on launch. Before an area is saved, the built-in display is selected (otherwise the main display). You can select a new area, display or window.
2. Enable system audio, the microphone, the cursor or click highlighting in Settings (the ⋯ button
   on the panel). With system audio and the microphone both on, each gets its own track and
   exports mix them. Recording and export share one set of
   frame rates — 60, 30, 24 and 15 fps; the editor never offers more than the recording holds.
   Recording quality is Standard or High: High doubles the bit rate for games and video, where
   Standard can soften fine detail, and makes files twice as big. Exports can't restore detail the
   recording lacks.
3. Press Record; a short sound marks the start and is kept out of the recording. Grant Screen Recording and, optionally, Microphone access when macOS asks; macOS shows its own dialog for Screen Recording.
4. The recorder panel hides while recording, so it never covers what you record. Stop by clicking
   the menu-bar icon (it shows the elapsed time) or with the shortcut; Option-click pauses and
   resumes, and right-click opens a menu with both.
5. The recording is saved automatically and opens in the editor.

Two global shortcuts work from any app: start/stop recording (**⌃⇧R**, R for Record) and select a recording
area (**⌃⇧A**, A for Area). Change either in Settings → Shortcuts by clicking its button and pressing
Command or Control with a letter or number; Escape cancels. The label always shows the key's
Latin letter, whatever keyboard layout is active.
The choice persists across launches. A registration conflict keeps the previous choice;
shortcuts handled locally by another app cannot always be detected.
Left-clicking the menu-bar icon opens the recorder panel; while recording it stops. Right-click opens the menu. The source menu in
Settings → Recording also lets you return to the last area after choosing a display or window. The
display is measured again when recording starts: a whole display follows a new resolution, while a
disconnected display or an area on a display whose resolution changed requires selecting a new area.

The window picker lists one entry per app with an on-screen window, front to back. Choosing one
activates that app and outlines the window that will be captured; the recorder panel stays on top.
While an area is being drawn or resized, the selection panel fades out of the way.

Originals are stored in `~/Library/Application Support/KapKap/Recordings`.
Recordings are written in two-second fragments. When ScreenCaptureKit ends a recording on its own
(from the system's screen-recording controls, or when a display disconnects), everything recorded
until then is saved and KapKap says why it stopped. If KapKap quits unexpectedly, the unfinished file
(its name starts with a dot) is recovered into Recent recordings at the next launch; a file that cannot
play keeps its dot for diagnosis. Quitting, logging out or shutting down during a recording saves it first.
Exports preserve the original file. The editor supports trimming, resolution, frame rate,
mute, quality (smaller file, balanced or best; see [docs/export-quality.md](docs/export-quality.md)), and MP4, GIF, APNG, WebM, HEVC and AV1 export.
MP4 and HEVC can also use Fast Hardware Encoding, from the quality menu: the Mac's media engine
encodes game and video footage two to four times faster, at a bigger file for the same detail. A finished export plays a system sound.
Closing the editor while its own recording has never been exported asks first, and offers to keep
it in Recent recordings or move it to the Trash; imported videos are never touched. The export
menu can also open the result straight in another app (Open With). Copies made for the clipboard or
Open With live in `~/Library/Application Support/KapKap`: a new copy replaces the previous clipboard
export, and the rest are removed after a day. The save dialog starts in
the export folder chosen in Settings → General (the Desktop by default), where GIF and APNG
looping can be turned off and KapKap can be set to launch at login. The recorder
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

## Tests

`swift test` covers display coordinates, pause timing, static-screen duration, empty recordings,
recordings interrupted by the system, recovery of unfinished files, restoring the last area,
shortcut registration and labels, clean-up of clipboard exports, and encode/decode round trips for
all six export formats, looping, mixing of two audio tracks, the size order of the three export
qualities, export progress and cancellation, using generated fixtures. Build the app first so the
bundled export executable is available; `KAPKAP_REQUIRE_EXPORT_TOOLS=1 swift test` fails instead of
skipping the export tests when it is not. Real screen, system audio and microphone capture and multi-monitor
behavior need permissions and on-device testing; a successful build alone is not evidence that
those scenarios work.

## Releases

`./script/release.sh <version>` builds, signs, notarizes and publishes a release that installed
copies pick up through [Sparkle](https://sparkle-project.org). See [docs/RELEASE.md](docs/RELEASE.md).
Third-party licenses, including the bundled FFmpeg, are listed in `THIRD_PARTY_NOTICES.md`.

## Acknowledgements

Thank you to [Kap](https://github.com/wulkano/Kap) by [Wulkano](https://wulkano.com) and its
contributors: KapKap is inspired by it. Kap is MIT-licensed; its notice is in `THIRD_PARTY_NOTICES.md`.

The README screenshot's background is [Deserto de Huacachina](https://unsplash.com/photos/brown-sand-dunes-under-white-sky-during-daytime-GeReAnOMiZ8)
by [Ze Paulo](https://unsplash.com/@euzepaulo) on Unsplash.
