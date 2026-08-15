# LongImageViewer

**English** | [简体中文](README.zh-CN.md)

A native iOS app for viewing long images and playing videos directly from Files, optimized for iPhone 13 Pro Max and requiring iOS 16 or later.

## Features

- Fits every image to the screen width and provides continuous vertical scrolling
- Draws a one-physical-pixel divider between image pages
- Shows the current page, total page count, filename, and live process memory usage
- Sorts by creation date or filename in ascending or descending order
- Imports multiple PNG, JPEG, HEIC, and other system-supported image files
- Adds multiple folders from On My iPhone, iCloud Drive, or local macOS storage
- Persists folder access and incrementally syncs added, changed, and removed images
- Includes each added root folder and its direct subfolders as a two-level hierarchy
- Ignores non-image files and directories deeper than the supported second level
- Browses root-folder images first, then each direct subfolder in name order
- Scrolls continuously across directory boundaries without resetting the viewer
- Opens the folder sidebar with a right swipe and closes it with a left swipe
- Removes app metadata and caches with a row swipe without deleting source files
- Separates image browsing and video playback with tabs at the top of the sidebar
- Links video folders from Files without importing, copying, transcoding, or modifying videos
- Displays nested video directories and plays only explicitly selected video files
- Recognizes MP4, MOV, M4V, 3GP, MPEG, MPG, TS, MTS, M2TS, M3U8, and other system movie types
- Hides linked video files or directory trees without deleting their source data, with restore and relink support
- Automatically pauses video when the app resigns active or enters the background
- Optionally protects the app with a password and a three-minute relock grace period
- Includes selectable English, Simplified Chinese, and Japanese interfaces
- Renders images in tiles with bounded decoding concurrency and memory caches

## Image and Video Sources

Tap `来源` (Sources) in the lower-right corner:

- `批量添加图片文件夹` (Batch Add Image Folders): on iPhone, authorize one folder at a time, return to the app, and continue selecting before importing the batch. Mac Catalyst supports native multi-selection.
- `选择图片文件` (Select Image Files): copy multiple individual images into the app-managed Manual Import collection.
- `同步已添加文件夹` (Sync Added Folders): scan all persisted folders immediately.
- `添加视频文件夹` (Add Video Folder): authorize a Files folder for direct video access without copying its contents into the app.
- `同步视频文件夹` (Sync Video Folders): rescan linked video directory trees.
- `恢复隐藏的视频项目` (Restore Hidden Video Items): restore video files and subdirectories previously hidden from the sidebar.
- `管理已加载文件夹` (Manage Loaded Folders): open the folder sidebar.
- `密码与锁定` (Password & Lock): set, change, or disable the app password.
- `语言` / `Language` / `言語`: switch the app interface language.

Opening a folder automatically adds images in that root and in each direct subfolder. Files below that second level are outside the browsing scope. Non-image files are ignored. The app reads only filenames, dimensions, timestamps, and other metadata up front; tiles are generated for the current viewport and at most two tiles ahead.

Within an added root, the viewer orders root-level images first, followed by direct subfolders in filename order. Each directory applies the selected image sort independently. The last image of one directory and the first image of the next share the same continuous scroll.

The sidebar's Images tab displays added roots and indented direct subfolders, but never individual images. Use the chevron on a root row to collapse or expand its direct subfolders; tapping the root name still navigates to its root-level images. Tapping a subfolder jumps to its first image without narrowing or replacing the continuous browsing sequence. Swipe a root row left to remove the root, its descendants, and app caches without deleting source files.

The Videos tab displays linked roots, nested directories, and video files. Tapping a directory only expands or collapses it; playback starts only after tapping a video file. Swipe a video file or nested directory left to hide that association, or swipe a linked root left to remove the entire bookmark. These operations modify only the app's index. They never delete the original Files item. Relinking the root or choosing Restore Hidden Video Items makes hidden entries visible again.

Video access remains security-scoped for the playback session, including iCloud-backed items. The app stores only the folder bookmark and video metadata. Actual playback depends on the device's AVPlayer support for both the file container and its audio/video codecs.

The same project supports iPhone and Mac Catalyst. On macOS, use the system picker to access local folders or iCloud Drive. A local Catalyst release build is produced at:

`.build/DerivedData-Catalyst-Release/Build/Products/Release-maccatalyst/LongImageViewer.app`

## Interface Languages

- English
- Simplified Chinese
- Japanese

On first launch, the app follows the device language when it is one of the supported languages and otherwise falls back to English. To override it, open `Sources` → `Language` and choose `English`, `简体中文`, or `日本語`. The selection is persisted and the app-owned interface refreshes immediately.

The system Files picker remains controlled by the device language because it is an iOS component. The Home Screen display name also follows the device language rather than the in-app override.

## Password and Lock

- With no password configured, the app opens directly into the viewer.
- Set a 4–64 character password from `来源` (Sources) → `密码与锁定` (Password & Lock).
- A cold launch always requires the password when protection is enabled.
- Returning within three minutes does not require another password entry.
- Returning after three minutes displays the lock screen.
- A privacy cover hides image content in the app switcher while the app is inactive.
- Changing or disabling the password requires the current password.
- The app stores a salted, iterated password digest in Keychain, not in image folders or ordinary preferences.
- Password recovery and reset are intentionally unsupported.

## Memory Strategy

- The decoded image cache is dynamically capped at 32–64 MiB and eight tiles.
- At most two decode operations run concurrently.
- Long source images are cropped and rendered by visible tile region without creating a full-size intermediate bitmap.
- Individually imported files retain one source copy and generate tiles only near the viewport.
- Entering the background or receiving a memory warning clears the image cache.
- Crossing a dynamic process-memory threshold triggers proactive eviction.

## Install on iPhone

See the [Device Installation Guide](Docs/Device-Installation-Guide.md) for signing, installation, and troubleshooting steps.

Apps signed with a free Apple ID generally expire after seven days and must be installed again through Xcode. Paid Apple Developer Program signing does not have this short expiration window.

## Simulator Validation

The generated fixtures are in `TestImages/`. See the [Test Image Guide](TestImages/README.md) for their dimensions and coverage.

After installing an iOS Simulator Runtime and the `jq` and `ffmpeg` command-line tools, run:

```bash
./Tools/RunSimulatorSmokeTest.sh
```

The script creates an iPhone 13 Pro Max simulator, builds and installs the app, generates image and video fixtures, performs an 18-second automated image scroll, validates video linking and background pause behavior, validates folder, lock, and language behavior, and writes screenshots and metrics to `Artifacts/Simulator/`.

See the [Simulator Validation Report](Docs/Simulator-Validation-Report.md) for the latest recorded results.

## Basic Usage

On first launch, tap Browse Image Folder. On iPhone, authorize one root folder in each system-picker pass, tap Continue Selecting to add another root, and finally tap Import N Folders. Every selected image root automatically includes its direct subfolders.

To play videos, open Sources → Add Video Folder and authorize a folder from Files. Open the sidebar, select Videos, expand directories as needed, and tap a video file. Returning to the Home Screen or another app pauses playback automatically.

## License

LongImageViewer is released under the [MIT License](LICENSE).

You may use, modify, and redistribute the source, including in commercial products, provided that the copyright and license notice are retained. The software is provided without warranty.
