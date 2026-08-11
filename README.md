# LongImageViewer

**English** | [简体中文](README.zh-CN.md)

A native iOS app for viewing long images, optimized for iPhone 13 Pro Max and requiring iOS 16 or later.

## Features

- Fits every image to the screen width and provides continuous vertical scrolling
- Draws a one-physical-pixel divider between image pages
- Shows the current page, total page count, filename, and live process memory usage
- Sorts by creation date or filename in ascending or descending order
- Imports multiple PNG, JPEG, HEIC, and other system-supported image files
- Adds multiple folders from On My iPhone, iCloud Drive, or local macOS storage
- Persists folder access and incrementally syncs added, changed, and removed images
- Keeps browsing and page counts scoped to the selected folder
- Opens the folder sidebar with a right swipe and closes it with a left swipe
- Removes app metadata and caches with a row swipe without deleting source files
- Optionally protects the app with a password and a three-minute relock grace period
- Renders images in tiles with bounded decoding concurrency and memory caches

## Image Sources

Tap `来源` (Sources) in the lower-right corner:

- `批量添加图片文件夹` (Batch Add Image Folders): on iPhone, authorize one folder at a time, return to the app, and continue selecting before importing the batch. Mac Catalyst supports native multi-selection.
- `选择图片文件` (Select Image Files): copy multiple individual images into the app-managed Manual Import collection.
- `同步已添加文件夹` (Sync Added Folders): scan all persisted folders immediately.
- `管理已加载文件夹` (Manage Loaded Folders): open the folder sidebar.
- `密码与锁定` (Password & Lock): set, change, or disable the app password.

Opening a folder reads only filenames, dimensions, timestamps, and other metadata. It does not render every image up front. Tiles are generated for the current viewport and at most two tiles ahead, then evicted when they leave the cache window.

The sidebar has one folder-level hierarchy and does not list individual images. The main viewer and page counter include only the selected folder. Swipe right to open the sidebar, tap a folder to switch, swipe a row left to remove it, and swipe left on the header or empty area to close the sidebar.

The same project supports iPhone and Mac Catalyst. On macOS, use the system picker to access local folders or iCloud Drive. A local Catalyst release build is produced at:

`.build/CatalystReleaseDerivedData/Build/Products/Release-maccatalyst/LongImageViewer.app`

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

After installing an iOS Simulator Runtime, run:

```bash
./Tools/RunSimulatorSmokeTest.sh
```

The script creates an iPhone 13 Pro Max simulator, builds and installs the app, imports all fixtures, performs an 18-second automated scroll, validates folder and lock behavior, and writes screenshots and metrics to `Artifacts/Simulator/`.

See the [Simulator Validation Report](Docs/Simulator-Validation-Report.md) for the latest recorded results.

## Basic Usage

On first launch, tap `浏览图片文件夹` (Browse Image Folder). On iPhone, authorize one folder in each system-picker pass, tap `继续选择` (Continue Selecting) to add another, and finally tap `导入 N 个文件夹` (Import N Folders). Use the lower-left control to change sorting or clear app-managed caches and folder associations.
