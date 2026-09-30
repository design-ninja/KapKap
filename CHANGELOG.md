# Changelog

All notable changes to KapKap are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Fast Hardware Encoding for MP4 and HEVC exports, in the quality menu. The Mac's media engine
  encodes game and video footage two to four times faster than x264 and x265, at a bigger file.
- A recording quality in Settings → Recording: High doubles the bit rate for games and video.

### Changed

- Recordings at 4K and 60 fps get their full bit rate: the ceiling rose from 80 to 100 Mbps.
- The README explains how to stop and pause while the recorder panel is hidden.
- Settings no longer carry explanatory notes under each section.

## [0.4.0] - 2026-09-30

### Added

- Settings → Recording offers the last area drawn next to the displays.
- Unfinished recordings left by a crash are recovered into Recent recordings at the next launch.

### Changed

- Recordings are written in two-second fragments, so an unexpected quit keeps what was recorded.
- Quitting, logging out or shutting down during a recording saves it instead of being refused.
- Copies made for the clipboard or Open With no longer pile up: a new copy replaces the last one,
  and the rest are removed after a day.
- The editor's playback and trim controls stay visible for VoiceOver and keyboard navigation.
- FFmpeg is built from source for exports only: one static executable instead of 18 Homebrew
  libraries, without network access, and the app is smaller.

### Removed

- The Screen Recording prompt inside the recorder panel. macOS shows its own dialog.

### Fixed

- Exports work on macOS 15 and later: the bundled FFmpeg came from Homebrew builds that required
  macOS 26.
- A recording stopped by the system (its screen-recording controls, a disconnected display) is
  saved up to that moment instead of being deleted.
- The last selected area is restored on launch, as documented.
- Errors show up even while the recorder panel is hidden, and only permission errors offer
  System Settings.
- A whole-display recording follows a changed resolution instead of capturing the old size.
- Export no longer fails after the trim start is nudged back to zero.
- Shortcuts with Shift and a number can be recorded, and labels show the Latin letter on
  Cyrillic keyboard layouts.
- A paused editor no longer redraws its controls ten times a second.

## [0.3.0] - 2026-09-30

### Added

- A quality choice for video exports (Smaller file, Balanced, Best quality), remembered between exports.
- An estimated file size next to the export settings.
- Export progress in percent.
- A sound when a recording starts. It never ends up in the recording.

### Changed

- Export settings sit directly in the editor bar instead of a popover.
- The recorder panel can be dragged over the menu bar and the Dock, up to the screen edges.
- A slimmer frame with viewfinder corners marks the area while recording.
- The record button dims while there is nothing to record.
- The playhead moves smoothly during playback and follows the pointer while dragging.

### Removed

- The "Keep original file" export option.

## [0.2.0] - 2026-09-21

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

[Unreleased]: https://github.com/design-ninja/KapKap/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/design-ninja/KapKap/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/design-ninja/KapKap/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/design-ninja/KapKap/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/design-ninja/KapKap/releases/tag/v0.1.0
