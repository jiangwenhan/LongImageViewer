# iPhone 13 Pro Max Simulator Validation Report

**English** | [简体中文](模拟器验证报告.md)

Validation date: August 11, 2026

## Environment

- Host: Apple Silicon Mac
- Xcode: 26.3 (17C529)
- Simulator Runtime: iOS 26.3.1 (23D8133, arm64)
- Simulator: iPhone 13 Pro Max (iPhone14,3)
- App configuration: Debug, minimum deployment target iOS 16.0

## Test Data

The suite uses six generated images from `TestImages/`:

- Width range: 640–2400 px
- Height range: 1500–18000 px
- Narrow, wide, short, long, and ultra-long layouts
- Creation dates deliberately differ from filename ordering

## Automated Procedure

Run:

```bash
./Tools/RunSimulatorSmokeTest.sh
```

The script:

1. Creates and boots an iPhone 13 Pro Max simulator.
2. Builds the Debug simulator app with `xcodebuild`.
3. Installs `LongImageViewer.app`.
4. Copies all six fixtures into the app container.
5. Adds two fixture folders through the production batch API.
6. Adds the same folders again to verify path-based deduplication and metadata synchronization.
7. Scrolls continuously from page 1 to page 6 over 18 seconds.
8. Materializes image tiles on demand during scrolling.
9. Records frame timing, tile counts, page visits, memory, and all sorting results.
10. Removes and restores one source image to validate incremental synchronization.
11. Verifies folder-only sidebar hierarchy with two independent folders.
12. Switches folders and verifies viewer scope and page counts.
13. Removes the secondary folder and confirms that its source files remain.
14. Displays the sequential folder-selection progress sheet and verifies the continue/import actions.
15. Tests password setup, incorrect-password rejection, password changes, old-password invalidation, and password disabling.
16. Verifies that 179 seconds in the background remains within the grace period and 180 seconds requires authentication.
17. Installs a test password and verifies that a cold launch displays the lock screen.
18. Launches in English, Simplified Chinese, and Japanese and validates representative strings.
19. Switches through all three languages in one process and verifies immediate interface refresh.
20. Captures localized batch sheets in all three languages in addition to the existing UI states.

## Results

### Functional

- Build, installation, and launch: passed
- Six-image import: passed
- Folder bookmark persistence and restoration: passed
- Two-folder batch add: passed
- Duplicate batch add does not create duplicate folders: passed
- Continue-selection and batch-import actions are visible: passed
- Sidebar shows only two folders and their image counts: passed
- Current-folder highlighting: passed
- Primary folder scope: 6 images
- Secondary folder scope: 2 images
- Removing the selected secondary folder falls back to the primary folder: passed
- Removing a folder does not delete source files: passed
- Removing one source image synchronizes the folder to 5 images: passed
- Restoring the source image synchronizes back to 6 images: passed
- Width-adaptive image rendering: passed
- Continuous vertical scrolling: passed
- No black seams between tiles of the same image: passed
- One-physical-pixel divider between different files: passed
- Page indicator updates from `1/6` to `6/6`: passed
- Filename follows the current page: passed
- Process memory updates every second: passed
- Creation-date ascending/descending sorting: passed
- Filename ascending/descending sorting: passed
- No-password direct entry: passed
- Password digest persistence in Keychain: passed
- Correct-password acceptance and incorrect-password rejection: passed
- Changed password invalidates the old password: passed
- Disabling protection after current-password verification: passed
- Cold launch with protection displays the lock screen: passed
- Background duration below three minutes does not require a password: passed
- Background duration of three minutes requires a password: passed
- English interface resources and cold launch: passed
- Simplified Chinese interface resources and cold launch: passed
- Japanese interface resources and cold launch: passed
- In-process switching updates Sources and sorting immediately: passed
- Selected language persists in app preferences: passed
- Mac Catalyst arm64 release build: passed

### Warm Scrolling Performance

- Duration: 18.01 seconds
- Frames recorded: 1080
- Average frame rate: 60.0 FPS
- Frames over 22 ms: 0
- Pages visited: 6/6
- Final process memory: approximately 84.5 MiB

Warm-run result:

`Artifacts/Simulator/warm-smoke-test-result.json`

### Cold Scrolling Performance

This run includes first-time decoding:

- Two-folder batch add and metadata scan: 0.13 seconds
- Expected tile count: 30
- Tiles materialized before scrolling: 3
- Tiles materialized after reaching the end: 30
- Average frame rate: 60.0 FPS
- Frames over 22 ms: 0
- Pages visited: 6/6
- Peak process memory: approximately 108.3 MiB
- Final process memory: approximately 89.5 MiB

Only 3 of 30 tiles exist after folder opening, confirming that folder selection does not eagerly render every image. Folder switching produces 6 pages for the primary folder and 2 for the secondary folder. Removing the secondary folder reduces the sidebar from two entries to one while leaving the source directory intact.

The password tests cover setup, verification, change, and disable flows, including the 180-second relock boundary. A dedicated privacy cover prevents image content from appearing in the app switcher. The source-removal regression also maintains 60.0 FPS with no slow frames across all 5 remaining pages.

Physical-device performance should still be confirmed on an iPhone 13 Pro Max with Instruments or Xcode frame metrics. Simulator measurements primarily detect functional regressions and obvious performance problems.

## Artifacts

- `Artifacts/Simulator/first-page.png`: first page
- `Artifacts/Simulator/scrolling.png`: mid-scroll state
- `Artifacts/Simulator/completed.png`: end of page 6
- `Artifacts/Simulator/warm-scrolling.png`: warm-run scroll state
- `Artifacts/Simulator/running-now.png`: current simulator first page
- `Artifacts/Simulator/folder-sidebar.png`: primary folder selected
- `Artifacts/Simulator/folder-sidebar-secondary.png`: secondary folder selected
- `Artifacts/Simulator/folder-batch-progress.png`: batch progress after selecting two folders
- `Artifacts/Simulator/app-lock.png`: app lock screen
- `Artifacts/Simulator/smoke-test-result.json`: cold-run metrics
- `Artifacts/Simulator/warm-smoke-test-result.json`: warm-run metrics
- `Artifacts/Simulator/folder-removal-result.json`: source-removal synchronization
- `Artifacts/Simulator/folder-selection-result.json`: folder-switch result
- `Artifacts/Simulator/folder-management-result.json`: folder-removal result
- `Artifacts/Simulator/app-lock-result.json`: startup lock and grace-period boundary result
- `Artifacts/Simulator/password-store-result.json`: password setup, verification, change, and disable result
- `Artifacts/Simulator/localization-en.json`: English string validation
- `Artifacts/Simulator/localization-zh-Hans.json`: Simplified Chinese string validation
- `Artifacts/Simulator/localization-ja.json`: Japanese string validation
- `Artifacts/Simulator/localization-persisted.json`: language persistence across relaunch
- `Artifacts/Simulator/language-switch-result.json`: in-process language-switch validation
- `Artifacts/Simulator/language-en.png`: English batch-selection UI
- `Artifacts/Simulator/language-zh-Hans.png`: Simplified Chinese batch-selection UI
- `Artifacts/Simulator/language-ja.png`: Japanese batch-selection UI
