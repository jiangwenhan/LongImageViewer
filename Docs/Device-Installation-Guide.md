# LongImageViewer Device Installation Guide

**English** | [简体中文](真机安装指南.md)

- Target device: iPhone 13 Pro Max
- Minimum OS: iOS 16
- Development tool: Xcode 26.3 or a compatible version

## Quick Installation

If Xcode already has your Apple ID and Developer Mode is enabled on the iPhone:

1. Open `LongImageViewer.xcodeproj` from the repository root.
2. Select the `LongImageViewer` target and open `Signing & Capabilities`.
3. Enable `Automatically manage signing` and select your Team.
4. Connect and unlock the iPhone 13 Pro Max.
5. Select that iPhone as the Xcode run destination. Do not select a simulator or My Mac.
6. Press `Command + R`.
7. Wait for `Build Succeeded`; Xcode installs and launches the app automatically.

Use the complete instructions below for first-time setup or troubleshooting.

## 1. Prerequisites

1. Install Xcode on the Mac.
2. Prepare a Lightning cable that supports data transfer.
3. Using the same Apple ID on the Mac and iPhone is convenient but not required.
4. A free Apple ID can sign a debug build, which normally expires after seven days. A paid Apple Developer Program account provides a longer-lived development signature.

## 2. Sign In to Xcode

1. Open Xcode.
2. Select `Xcode` → `Settings...`.
3. Open the `Accounts` tab.
4. Click `+` and select `Apple Account`.
5. Sign in with the Apple ID used for code signing.
6. Confirm that the corresponding Team appears:
   - Free accounts usually show `Personal Team`.
   - Paid accounts show an individual or organization Team.

## 3. Connect and Trust the iPhone

1. Connect the iPhone 13 Pro Max to the Mac.
2. Unlock the iPhone.
3. If the iPhone asks whether to trust the computer, tap Trust and enter the device passcode.
4. In Xcode, open `Window` → `Devices and Simulators`.
5. Confirm that the iPhone appears in the sidebar.
6. On the first connection, wait for `Preparing debugger support` to finish.

If the device does not appear:

1. Try another data-capable cable or USB port.
2. Keep the iPhone unlocked.
3. Reconnect it and accept the trust prompt again.
4. Verify that macOS and Xcode support the installed iOS version.

## 4. Enable Developer Mode

iOS 16 and later require Developer Mode for development builds:

1. Open Settings on the iPhone.
2. Go to Privacy & Security.
3. Scroll to Developer Mode.
4. Enable Developer Mode.
5. Restart when prompted.
6. After restart, confirm Developer Mode and enter the device passcode.

If Developer Mode is not visible, keep the iPhone connected and try running the project from Xcode once. This normally makes the option appear.

## 5. Configure Signing

1. Open `LongImageViewer.xcodeproj`.
2. Select the blue `LongImageViewer` project in the navigator.
3. Select the `LongImageViewer` target.
4. Open `Signing & Capabilities`.
5. Enable `Automatically manage signing`.
6. Choose the Team configured earlier.
7. Check the Bundle Identifier:
   - The default is `com.trae.LongImageViewer`.
   - If it is unavailable, change it to a unique value such as `com.yourname.LongImageViewer`.
8. Wait for Xcode to create the development certificate and provisioning profile.

A valid configuration shows `Apple Development` as the signing certificate and no red errors.

## 6. Build and Install

1. Select the connected iPhone 13 Pro Max as the run destination.
2. Keep the iPhone unlocked.
3. Press `Command + R`.
4. Xcode builds, signs, installs, and launches the app.
5. The first installation may pause while the device prepares debugging services.

After installation, the Home Screen name follows the device language: `LongImageViewer`, `长图阅览`, or `ロング画像ビューア`.

## 7. Trust the Developer

Some personal signatures may require manual trust on first launch:

1. Open Settings.
2. Go to General → VPN & Device Management.
3. Select the Apple ID under Developer App.
4. Tap Trust.
5. Open LongImageViewer again.

Newer iOS versions may validate the signature online instead. Keep the device online if validation is requested.

## 8. Select the Interface Language

The app supports English, Simplified Chinese, and Japanese. It follows a supported device language on first launch and falls back to English for other device languages.

1. Tap Sources in the lower-right corner.
2. Tap Language.
3. Choose `English`, `简体中文`, or `日本語`.
4. The app-owned interface updates immediately and remembers the selection.

The system Files picker and Home Screen display name continue to follow the device language.

## 9. Import and Browse Images

1. On first launch, tap `浏览图片文件夹` (Browse Image Folder).
2. In the system Files picker, open On My iPhone or iCloud Drive.
3. Select the first folder containing images.
4. Back in the app, tap `继续选择` (Continue Selecting) to authorize another folder.
5. When finished, tap `导入 N 个文件夹` (Import N Folders).
6. Each selected root automatically includes images in the root and its direct subfolders. Deeper folders are not scanned.
7. Non-image files are ignored.
8. Selecting an existing root again refreshes its permission without creating a duplicate.
9. Use `来源` (Sources) → `选择图片文件` (Select Image Files) to import individual files.
10. Scroll vertically to browse. Root-level images appear first, followed by each direct subfolder in name order.
11. Scrolling continues directly across directory boundaries.
12. The top overlay shows page count, filename, and process memory.
13. The lower-left sorting control supports:
    - Creation date ascending
    - Creation date descending
    - Filename ascending
    - Filename descending
14. Swipe right in the viewer to open the folder sidebar.
15. The sidebar lists root folders and indented direct subfolders with image counts.
16. Tap the chevron on a root row to collapse or expand its direct subfolders; tapping the root name still navigates to root-level images.
17. Tap a subfolder to jump to its first image while preserving the full continuous sequence.
18. Swipe a root row left to remove its hierarchy and caches without deleting source images.
19. Swipe left on the sidebar header or empty area, or tap the close button, to dismiss it.

Folder mode stores only screen-width tile caches inside the app. It does not copy or modify source images. Sync again after source files or direct subfolders are added, changed, or removed.

### App Password

1. Open `来源` (Sources) → `密码与锁定` (Password & Lock).
2. Enter the same 4–64 character password twice.
3. A cold launch requires the password.
4. Returning within three minutes does not require another password entry.
5. Returning after three minutes displays the lock screen.
6. A privacy cover immediately hides image content while the app is inactive.
7. Changing or disabling protection requires the current password.

With no password configured, the app opens directly. Password recovery and reset are intentionally unsupported. Removing and reinstalling the app does not guarantee removal of the Keychain credential, so retain the password securely.

## 10. Common Signing Problems

### `Signing for "LongImageViewer" requires a development team`

Select the Team associated with your Apple ID in `Signing & Capabilities`.

### `The app identifier cannot be registered`

Change the Bundle Identifier to a unique value.

### `No profiles for ... were found`

1. Confirm that automatic signing is enabled.
2. Confirm that the Mac can reach Apple Developer services.
3. Sign in to the Apple ID again under Xcode `Settings` → `Accounts`.
4. Open the Team details and wait for certificates to refresh.

### `Developer Mode disabled`

Enable Developer Mode using section 4, then restart the iPhone.

### A free-signed app no longer opens

Free Apple ID development signatures normally expire after seven days. Reconnect the iPhone and press `Command + R` in Xcode to reinstall.

## 11. Install an Updated Build

Connect the same iPhone and press `Command + R` again. Xcode installs the new build over the old one, and app-managed image data normally remains. Deleting the app removes its image copies, but the Keychain password may remain.

## 12. Acceptance Checklist

1. The localized app icon name appears and the app launches.
2. English, Simplified Chinese, and Japanese can be selected from Sources → Language.
3. The initial screen shows the browse-folder action in the selected language.
4. The system picker can access On My iPhone and iCloud Drive.
5. Selected images fill the screen width and scroll continuously.
6. The overlay shows page count, filename, and live memory.
7. All four sorting modes work.
8. Sources can add folders, import individual files, and trigger synchronization.
9. Adding a root includes its direct subfolders but excludes non-image and third-level files.
10. Root images scroll directly into the first child folder, then into later siblings.
11. Root chevrons collapse and re-expand direct subfolders without changing the current page.
12. Password & Lock can enable protection.
13. Returning within three minutes bypasses reauthentication; returning after three minutes shows the lock screen.

## 13. Verified Project Configuration

- Device target: iPhone 13 Pro Max
- Minimum OS: iOS 16.0
- Localized display names: `LongImageViewer`, `长图阅览`, `ロング画像ビューア`
- Bundle Identifier: `com.trae.LongImageViewer`
- Signing: Automatic
- Device architecture: arm64
- Release device build: verified
