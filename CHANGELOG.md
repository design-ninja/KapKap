# Changelog

All notable changes to KapKap are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Automatic updates through Sparkle: KapKap checks GitHub Releases for a signed update and
  installs it when you agree. Check manually from the KapKap menu, or turn checks off in Settings.
- Signed, notarized release builds published on GitHub.
- System audio recording alongside the microphone. Each source gets its own track, and exports
  mix them into one.
- A default export folder (the Desktop, changeable in Settings): the save dialog opens there.
- Open With: export straight into another app from the export menu.
- A setting to turn off looping for GIF and APNG exports.
- Launch at login.
- A global, configurable shortcut for selecting a recording area (⌃⌥⌘A by default).
- A clock next to the menu bar icon while recording.
- Open Video and Show Recordings Folder in the File menu.
- The recorder panel remembers where it was dragged and reopens there after a relaunch.
- The About panel credits the author and links to the GitHub repository.
- A changelog.

### Changed

- Settings are split into General, Recording and Shortcuts tabs built from standard macOS controls.
- The ⋯ button on the recorder panel opens Settings instead of a popover.
- The editor's frame rate is a menu: Native or a lower rate.
- Trimming no longer resizes the timeline: the selected-length badge is gone and Reset trim
  is always there, enabled once the recording is trimmed. The timeline handles have no shadows.
- The full-screen button shows exit full screen while the editor is in full screen.
- The Recordings window has no toolbar; it refreshes whenever KapKap becomes active.
- The selection controls live in the selection overlay instead of a separate window.

### Fixed

- A recording exported in an earlier session is no longer offered for discarding when macOS
  reopens its editor after a relaunch.
- VoiceOver can open rows in Recent recordings, and the panel's buttons have readable names.

## [0.1.0] - 2026-09-20

### Added

- Native screen recorder for Apple Silicon: record an area, a display or a window with
  ScreenCaptureKit, with optional microphone, cursor and click highlighting.
- Recording at 60, 30, 24 or 15 fps, with pause and resume from the panel or the menu bar,
  and a customisable global start/stop shortcut (⌃⌥⌘R by default).
- Editor with trimming, resolution, frame rate and mute, exporting to MP4, GIF, APNG,
  WebM, HEVC and AV1 through a bundled FFmpeg.
- Recent recordings list with poster frames, reveal in Finder and copy to clipboard.
- The last selected area is restored on launch.

[Unreleased]: https://github.com/design-ninja/KapKap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/design-ninja/KapKap/releases/tag/v0.1.0
