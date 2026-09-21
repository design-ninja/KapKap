# Changelog

All notable changes to KapKap are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- System audio recording alongside the microphone. Each source gets its own track, and exports
  mix them into one.
- A default export folder (`~/Movies/KapKap`, changeable in Settings): the save dialog opens there.
- Open With: export straight into another app from the export menu, like Kap's built-in action.
- A setting to turn off looping for GIF and APNG exports.
- Launch at login.
- A global, configurable shortcut for selecting a recording area (⌃⌥⌘A by default).
- The recorder panel remembers where it was dragged and reopens there after a relaunch.
- The About panel credits the author and links to the GitHub repository.
- A changelog, and a README section listing what Kap does that KapKap does not.

### Changed

- Settings are split into General, Recording and Shortcuts tabs built from standard macOS controls.
- The ⋯ button on the recorder panel opens Settings instead of a popover.
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
