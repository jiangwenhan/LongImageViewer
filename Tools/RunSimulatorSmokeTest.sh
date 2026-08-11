#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LongImageViewer.xcodeproj"
SCHEME="LongImageViewer"
BUNDLE_ID="com.trae.LongImageViewer"
DEVICE_NAME="LongImageViewer iPhone 13 Pro Max"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro-Max"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
ARTIFACTS_DIR="$ROOT_DIR/Artifacts/Simulator"

mkdir -p "$ARTIFACTS_DIR"

xcrun simctl runtime scan-and-mount >/dev/null

RUNTIME_ID="$(
  xcrun simctl list runtimes -j |
    jq -r '
      .runtimes
      | map(select(.platform == "iOS" and .isAvailable == true))
      | sort_by(.version)
      | last
      | .identifier // empty
    '
)"

if [[ -z "$RUNTIME_ID" ]]; then
  echo "No available iOS Simulator Runtime is installed." >&2
  echo "Install one with: xcodebuild -downloadPlatform iOS -architectureVariant arm64" >&2
  exit 1
fi

DEVICE_UDID="$(
  xcrun simctl list devices -j |
    jq -r --arg name "$DEVICE_NAME" '
      .devices[][]
      | select(.name == $name)
      | .udid
    ' |
    head -n 1
)"

if [[ -z "$DEVICE_UDID" ]]; then
  DEVICE_UDID="$(
    xcrun simctl create \
      "$DEVICE_NAME" \
      "$DEVICE_TYPE" \
      "$RUNTIME_ID"
  )"
fi

if ! xcrun simctl list devices -j |
  jq -e --arg udid "$DEVICE_UDID" '
    .devices[][]
    | select(.udid == $udid and .isAvailable == true)
  ' >/dev/null
then
  xcrun simctl delete "$DEVICE_UDID"
  DEVICE_UDID="$(
    xcrun simctl create \
      "$DEVICE_NAME" \
      "$DEVICE_TYPE" \
      "$RUNTIME_ID"
  )"
fi

open -a Simulator --args -CurrentDeviceUDID "$DEVICE_UDID"
xcrun simctl boot "$DEVICE_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_UDID" -b

rm -rf "$DERIVED_DATA"
xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_UDID" \
  -derivedDataPath "$DERIVED_DATA" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/LongImageViewer.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at $APP_PATH" >&2
  exit 1
fi

xcrun simctl terminate "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl uninstall "$DEVICE_UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_UDID" "$APP_PATH"

DATA_CONTAINER="$(
  xcrun simctl get_app_container "$DEVICE_UDID" "$BUNDLE_ID" data
)"
FIXTURE_DIR="$DATA_CONTAINER/Documents/SimulatorFixtures"
SECONDARY_FIXTURE_DIR="$DATA_CONTAINER/Documents/SimulatorFixturesSecondary"
mkdir -p "$FIXTURE_DIR"
mkdir -p "$SECONDARY_FIXTURE_DIR"
find "$ROOT_DIR/TestImages" -maxdepth 1 -type f \
  \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.heic' \) \
  -exec cp -p {} "$FIXTURE_DIR/" \;
cp -p \
  "$ROOT_DIR/TestImages/01_narrow_short_640x1800.jpg" \
  "$ROOT_DIR/TestImages/02_phone_medium_1284x5000.jpg" \
  "$SECONDARY_FIXTURE_DIR/"

xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --auto-scroll-smoke-test

sleep 6
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/scrolling.png"

RESULT_PATH="$DATA_CONTAINER/Documents/simulator-smoke-test-result.json"
for _ in {1..90}; do
  if [[ -f "$RESULT_PATH" ]]; then
    STATUS="$(jq -r '.status // empty' "$RESULT_PATH")"
    if [[ "$STATUS" == "passed" || "$STATUS" == *"-failed" ]]; then
      break
    fi
  fi
  sleep 1
done

if [[ ! -f "$RESULT_PATH" ]]; then
  echo "Smoke test did not produce a result within 90 seconds." >&2
  exit 1
fi

cp "$RESULT_PATH" "$ARTIFACTS_DIR/smoke-test-result.json"
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/completed.png"

jq -e '
  .status == "passed"
  and .documentCount == 6
  and .visitedPageCount == 6
  and .folderCount == 2
  and .sidebarItemCount == 2
  and .selectedFolderTitle == "SimulatorFixtures"
  and .usedMemoryBytes > 0
  and .peakMemoryBytes < 268435456
  and .directorySyncDurationSeconds < 5
  and .initialMaterializedTileCount < .expectedTileCount
  and .finalMaterializedTileCount <= .expectedTileCount
  and .sortOrders.filenameAscending == [
    "01_narrow_short_640x1800.jpg",
    "02_phone_medium_1284x5000.jpg",
    "03_wide_medium_2400x6000.jpg",
    "10_ultra_long_1284x18000.jpg",
    "20_wide_short_1800x1500.jpg",
    "Z_tall_narrow_900x12000.jpg"
  ]
  and .sortOrders.creationAscending == [
    "20_wide_short_1800x1500.jpg",
    "02_phone_medium_1284x5000.jpg",
    "01_narrow_short_640x1800.jpg",
    "10_ultra_long_1284x18000.jpg",
    "03_wide_medium_2400x6000.jpg",
    "Z_tall_narrow_900x12000.jpg"
  ]
' "$ARTIFACTS_DIR/smoke-test-result.json" >/dev/null

xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --show-folder-sidebar
sleep 3
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/folder-sidebar.png"

FOLDER_SELECTION_RESULT="$DATA_CONTAINER/Documents/folder-selection-result.json"
rm -f "$FOLDER_SELECTION_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --select-secondary-simulator-folder \
  --show-folder-sidebar

for _ in {1..30}; do
  if [[ -f "$FOLDER_SELECTION_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .selectedFolderTitle == "SimulatorFixturesSecondary"
  and .selectedDocumentCount == 2
  and .pageCount == 2
  and .sidebarItemCount == 2
' "$FOLDER_SELECTION_RESULT" >/dev/null
cp "$FOLDER_SELECTION_RESULT" \
  "$ARTIFACTS_DIR/folder-selection-result.json"
sleep 1
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/folder-sidebar-secondary.png"

FOLDER_MANAGEMENT_RESULT="$DATA_CONTAINER/Documents/folder-management-result.json"
rm -f "$FOLDER_MANAGEMENT_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --debug-delete-secondary-folder

for _ in {1..30}; do
  if [[ -f "$FOLDER_MANAGEMENT_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .folderCount == 1
  and .sidebarItemCount == 1
  and .selectedDocumentCount == 6
  and .sourceFolderStillExists == true
' "$FOLDER_MANAGEMENT_RESULT" >/dev/null
cp "$FOLDER_MANAGEMENT_RESULT" \
  "$ARTIFACTS_DIR/folder-management-result.json"
test -f "$SECONDARY_FIXTURE_DIR/01_narrow_short_640x1800.jpg"

REMOVED_FIXTURE="$FIXTURE_DIR/20_wide_short_1800x1500.jpg"
rm "$REMOVED_FIXTURE"
rm "$RESULT_PATH"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --auto-scroll-smoke-test

for _ in {1..90}; do
  if [[ -f "$RESULT_PATH" ]] &&
    [[ "$(jq -r '.status // empty' "$RESULT_PATH")" == "passed" ]]
  then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .documentCount == 5
  and .visitedPageCount == 5
  and .folderCount == 2
  and .sidebarItemCount == 2
' "$RESULT_PATH" >/dev/null
cp "$RESULT_PATH" "$ARTIFACTS_DIR/folder-removal-result.json"
cp -p "$ROOT_DIR/TestImages/20_wide_short_1800x1500.jpg" "$REMOVED_FIXTURE"
rm "$RESULT_PATH"

xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture
sleep 2
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/first-page.png"

xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --show-folder-batch-progress
sleep 3
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/folder-batch-progress.png"

PASSWORD_STORE_RESULT="$DATA_CONTAINER/Documents/password-store-result.json"
rm -f "$PASSWORD_STORE_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --password-store-smoke-test

for _ in {1..60}; do
  if [[ -f "$PASSWORD_STORE_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .initialPasswordWorks == true
  and .wrongPasswordRejected == true
  and .passwordChanged == true
  and .oldPasswordRejected == true
  and .newPasswordWorks == true
  and .passwordRemoved == true
  and .hasPasswordAfterRemoval == false
' "$PASSWORD_STORE_RESULT" >/dev/null
cp "$PASSWORD_STORE_RESULT" \
  "$ARTIFACTS_DIR/password-store-result.json"

APP_LOCK_RESULT="$DATA_CONTAINER/Documents/app-lock-result.json"
rm -f "$APP_LOCK_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --install-debug-app-password \
  "LongImageViewer#123" \
  --report-app-lock-state

for _ in {1..30}; do
  if [[ -f "$APP_LOCK_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .isLocked == true
  and .hasPassword == true
  and .gracePeriodSeconds == 180
  and .shortBackgroundRequiresPassword == false
  and .expiredBackgroundRequiresPassword == true
' "$APP_LOCK_RESULT" >/dev/null
cp "$APP_LOCK_RESULT" "$ARTIFACTS_DIR/app-lock-result.json"
sleep 1
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/app-lock.png"

xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password

echo
echo "Simulator: $DEVICE_NAME ($DEVICE_UDID)"
echo "Runtime: $RUNTIME_ID"
echo "App: $APP_PATH"
echo "Artifacts: $ARTIFACTS_DIR"
cat "$ARTIFACTS_DIR/smoke-test-result.json"
