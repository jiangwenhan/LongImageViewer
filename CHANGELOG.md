# Changelog

**English** | [Simplified Chinese](CHANGELOG.zh-CN.md)

All notable changes to LongImageViewer are documented in this file.

## [Unreleased] - 2026-08-15

### Added

- Added Images and Videos tabs at the top of the media-library sidebar.
- Added direct video-folder access through the iOS Files picker. Videos remain
  in On My iPhone, iCloud Drive, or the selected macOS directory and are not
  copied, imported, or transcoded into the app.
- Added recursive video navigation with linked root folders, nested
  directories, and video-file rows.
- Added playback through the system AVPlayer interface. Tapping a directory
  only expands or collapses it; playback starts only after selecting a video
  file.
- Added recognition for MP4, MOV, M4V, 3GP, MPEG, MPG, TS, MTS, M2TS, M3U8,
  and other system movie types. Actual playback depends on device support for
  the container and its audio/video codecs.
- Added video-folder synchronization for source files added, changed, moved,
  or removed outside the app.
- Added controls to hide an individual video or nested directory from the app,
  remove a linked root folder, restore hidden entries, and link a folder again.
- Added automatic playback pause when the app resigns active, enters the
  background, switches to another app, or returns to the Home Screen.
- Added English, Simplified Chinese, and Japanese strings for all video
  browsing, management, playback, and error states.

### Safety and Storage

- Video management removes only app bookmarks, metadata, and sidebar entries.
  It never deletes or modifies source files.
- The app persists only security-scoped folder bookmarks and video metadata.
  No source video copy is stored under the app's Application Support
  directory.
- Security-scoped folder access remains active only while it is needed for
  scanning or playback.
- Picture in Picture and automatic Now Playing integration are disabled so
  playback cannot continue unintentionally after leaving the app.

### Compatibility

- Existing image browsing remains under the Images tab with no change to
  two-level image-folder scanning, continuous cross-directory scrolling,
  sorting, tile rendering, cache limits, folder management, app locking, or
  language selection.
- Video directory navigation supports at least two nested directory levels
  and currently handles deeper directory trees as well.
- iOS 16 or later and Mac Catalyst remain supported.

### Validation

- Verified MP4, MOV, M4V, and MPEG-TS fixtures in a root and two nested
  directory levels.
- Verified that directory taps do not start playback and video-file taps do.
- Verified file hiding, directory hiding, root unlinking, relinking, and
  source-file preservation.
- Verified that playback rate changes from `1` to `0` when the app resigns
  active.
- Verified that no video file is copied into Application Support.
- Re-ran the complete image regression on an iPhone 13 Pro Max simulator:
  60 FPS average, zero slow frames, and all 6 pages visited.
- Verified English, Simplified Chinese, and Japanese media-tab labels.
- Verified generic iOS arm64 and Mac Catalyst arm64 Release builds.
