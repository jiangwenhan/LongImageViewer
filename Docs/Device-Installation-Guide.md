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

After installation, the app appears on the Home Screen as `长图阅览`.

## 7. Trust the Developer

Some personal signatures may require manual trust on first launch:

1. Open Settings.
2. Go to General → VPN & Device Management.
3. Select the Apple ID under Developer App.
4. Tap Trust.
5. Open LongImageViewer again.

Newer iOS versions may validate the signature online instead. Keep the device online if validation is requested.

## 8. Import and Browse Images

The current app UI is Chinese. English descriptions below include the exact UI labels.

1. On first launch, tap `浏览图片文件夹` (Browse Image Folder).
2. In the system Files picker, open On My iPhone or iCloud Drive.
3. Select the first folder containing images.
4. Back in the app, tap `继续选择` (Continue Selecting) to authorize another folder.
5. When finished, tap `导入 N 个文件夹` (Import N Folders).
6. Selecting an existing folder again refreshes its permission without creating a duplicate.
7. Use `来源` (Sources) → `选择图片文件` (Select Image Files) to import individual files.
8. Scroll vertically to browse.
9. The top overlay shows page count, filename, and process memory.
10. The lower-left sorting control supports:
    - Creation date ascending
    - Creation date descending
    - Filename ascending
    - Filename descending
11. Swipe right in the viewer to open the folder sidebar.
12. The sidebar lists folders and image counts; the active folder is highlighted.
13. Tap a folder to make it the only folder shown in the viewer.
14. Swipe a folder row left to remove its app metadata and cache without deleting source images.
15. Swipe left on the sidebar header or empty area, or tap the close button, to dismiss it.

Folder mode stores only screen-width tile caches inside the app. It does not copy or modify source images. Sync again after source files are added, changed, or removed.

### App Password

1. Open `来源` (Sources) → `密码与锁定` (Password & Lock).
2. Enter the same 4–64 character password twice.
3. A cold launch requires the password.
4. Returning within three minutes does not require another password entry.
5. Returning after three minutes displays the lock screen.
6. A privacy cover immediately hides image content while the app is inactive.
7. Changing or disabling protection requires the current password.

With no password configured, the app opens directly. Password recovery and reset are intentionally unsupported. Removing and reinstalling the app does not guarantee removal of the Keychain credential, so retain the password securely.

## 9. Common Signing Problems

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

## 10. Install an Updated Build

Connect the same iPhone and press `Command + R` again. Xcode installs the new build over the old one, and app-managed image data normally remains. Deleting the app removes its image copies, but the Keychain password may remain.

## 11. Acceptance Checklist

1. The `长图阅览` icon appears and the app launches.
2. The initial screen shows `浏览图片文件夹`.
3. The system picker can access On My iPhone and iCloud Drive.
4. Selected images fill the screen width and scroll continuously.
5. The overlay shows page count, filename, and live memory.
6. All four sorting modes work.
7. Sources can add folders, import individual files, and trigger synchronization.
8. Password & Lock can enable protection.
9. Returning within three minutes bypasses reauthentication; returning after three minutes shows the lock screen.

## 12. Verified Project Configuration

- Device target: iPhone 13 Pro Max
- Minimum OS: iOS 16.0
- Display name: `长图阅览`
- Bundle Identifier: `com.trae.LongImageViewer`
- Signing: Automatic
- Device architecture: arm64
- Release device build: verified
