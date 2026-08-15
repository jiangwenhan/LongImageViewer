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
VIDEO_FIXTURE_DIR="$DATA_CONTAINER/Documents/SimulatorVideoFixtures"
CHILD_A_DIR="$FIXTURE_DIR/01_Chapter_A"
CHILD_B_DIR="$FIXTURE_DIR/02_Chapter_B"
EMPTY_CHILD_DIR="$FIXTURE_DIR/03_Empty_Chapter"
DEEP_DIR="$CHILD_A_DIR/DeepIgnored"
mkdir -p "$CHILD_A_DIR"
mkdir -p "$CHILD_B_DIR"
mkdir -p "$EMPTY_CHILD_DIR"
mkdir -p "$DEEP_DIR"
mkdir -p "$SECONDARY_FIXTURE_DIR"
mkdir -p "$VIDEO_FIXTURE_DIR/Level_1/Level_2"
mkdir -p "$VIDEO_FIXTURE_DIR/Sibling"
cp -p \
  "$ROOT_DIR/TestImages/01_narrow_short_640x1800.jpg" \
  "$ROOT_DIR/TestImages/02_phone_medium_1284x5000.jpg" \
  "$FIXTURE_DIR/"
cp -p \
  "$ROOT_DIR/TestImages/03_wide_medium_2400x6000.jpg" \
  "$ROOT_DIR/TestImages/10_ultra_long_1284x18000.jpg" \
  "$CHILD_A_DIR/"
cp -p \
  "$ROOT_DIR/TestImages/20_wide_short_1800x1500.jpg" \
  "$ROOT_DIR/TestImages/Z_tall_narrow_900x12000.jpg" \
  "$CHILD_B_DIR/"
cp -p \
  "$ROOT_DIR/TestImages/01_narrow_short_640x1800.jpg" \
  "$DEEP_DIR/deep_ignored.jpg"
printf 'not an image\n' >"$FIXTURE_DIR/notes.txt"
printf '{"ignored": true}\n' >"$CHILD_A_DIR/metadata.json"
printf 'empty child marker\n' >"$EMPTY_CHILD_DIR/README.txt"
cp -p \
  "$ROOT_DIR/TestImages/01_narrow_short_640x1800.jpg" \
  "$ROOT_DIR/TestImages/02_phone_medium_1284x5000.jpg" \
  "$SECONDARY_FIXTURE_DIR/"

FFMPEG_BIN="$(command -v ffmpeg || true)"
if [[ -z "$FFMPEG_BIN" ]]; then
  echo "ffmpeg is required for the video playback smoke test." >&2
  exit 1
fi
"$FFMPEG_BIN" -y -loglevel error \
  -f lavfi -i "testsrc=size=640x360:rate=30" \
  -t 8 -an -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
  -movflags +faststart \
  "$VIDEO_FIXTURE_DIR/root_clip.mp4"
"$FFMPEG_BIN" -y -loglevel error \
  -i "$VIDEO_FIXTURE_DIR/root_clip.mp4" -an -c:v copy \
  "$VIDEO_FIXTURE_DIR/Level_1/child_clip.mov"
"$FFMPEG_BIN" -y -loglevel error \
  -i "$VIDEO_FIXTURE_DIR/root_clip.mp4" -an -c:v copy \
  "$VIDEO_FIXTURE_DIR/Level_1/Level_2/deep_clip.m4v"
"$FFMPEG_BIN" -y -loglevel error \
  -i "$VIDEO_FIXTURE_DIR/root_clip.mp4" -an -c:v copy \
  -bsf:v h264_mp4toannexb -f mpegts \
  "$VIDEO_FIXTURE_DIR/Sibling/sibling_clip.ts"
printf 'not a video\n' >"$VIDEO_FIXTURE_DIR/notes.txt"

VIDEO_RESULT_PATH="$DATA_CONTAINER/Documents/video-library-result.json"
rm -f "$VIDEO_RESULT_PATH"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-video-fixtures \
  --video-library-smoke-test

for _ in {1..60}; do
  if [[ -f "$VIDEO_RESULT_PATH" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .videoCount == 4
  and .sidebarItemCount == 8
  and .videoRowCount == 4
  and .folderRowCount == 4
  and .maximumDepth == 3
  and .formats == ["m4v", "mov", "mp4", "ts"]
  and .directoryPaths == [
    "Level_1",
    "Level_1/Level_2",
    "Sibling"
  ]
  and .fileHiddenWithoutDeletion == true
  and .directoryHiddenWithoutDeletion == true
  and .associationRemovedWithoutDeletion == true
  and .sourceFilesStillExist == true
  and .rateBeforeBackgroundPause > 0
  and .rateAfterBackgroundPause == 0
' "$VIDEO_RESULT_PATH" >/dev/null
if find \
  "$DATA_CONTAINER/Library/Application Support/LongImageViewer" \
  -type f \
  \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \
    -o -iname '*.ts' \) \
  -print -quit | grep -q .
then
  echo "Video source data was copied into App Support." >&2
  exit 1
fi
cp "$VIDEO_RESULT_PATH" \
  "$ARTIFACTS_DIR/video-library-result.json"
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/video-player-paused.png"

xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-video-fixtures \
  --show-video-sidebar
sleep 3
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/video-sidebar.png"

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
  and .sidebarItemCount == 5
  and .directoryCount == 3
  and .directoryOrder == [
    "__root__",
    "__root__",
    "01_Chapter_A",
    "01_Chapter_A",
    "02_Chapter_B",
    "02_Chapter_B"
  ]
  and .directorySummaries == [
    {
      "displayName": "SimulatorFixtures",
      "imageCount": 2,
      "relativePath": "__root__"
    },
    {
      "displayName": "01_Chapter_A",
      "imageCount": 2,
      "relativePath": "01_Chapter_A"
    },
    {
      "displayName": "02_Chapter_B",
      "imageCount": 2,
      "relativePath": "02_Chapter_B"
    },
    {
      "displayName": "03_Empty_Chapter",
      "imageCount": 0,
      "relativePath": "03_Empty_Chapter"
    }
  ]
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
    "02_phone_medium_1284x5000.jpg",
    "01_narrow_short_640x1800.jpg",
    "10_ultra_long_1284x18000.jpg",
    "03_wide_medium_2400x6000.jpg",
    "20_wide_short_1800x1500.jpg",
    "Z_tall_narrow_900x12000.jpg"
  ]
' "$ARTIFACTS_DIR/smoke-test-result.json" >/dev/null

MANIFEST_PATH="$DATA_CONTAINER/Library/Application Support/LongImageViewer/manifest.json"
jq -e '
  map(select(.sourceFolderID != null)) as $folderDocuments
  | ($folderDocuments | length) == 8
  and ($folderDocuments | map(.filename) | index("notes.txt")) == null
  and ($folderDocuments | map(.filename) | index("metadata.json")) == null
  and ($folderDocuments | map(.filename) | index("deep_ignored.jpg")) == null
' "$MANIFEST_PATH" >/dev/null

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

CHILD_DIRECTORY_RESULT="$DATA_CONTAINER/Documents/child-directory-result.json"
rm -f "$CHILD_DIRECTORY_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --select-first-child-directory \
  --show-folder-sidebar

for _ in {1..30}; do
  if [[ -f "$CHILD_DIRECTORY_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .selectedDirectory == "01_Chapter_A"
  and .currentPageIndex == 2
  and .documentCount == 6
  and .previousDirectory == "__root__"
' "$CHILD_DIRECTORY_RESULT" >/dev/null
cp "$CHILD_DIRECTORY_RESULT" \
  "$ARTIFACTS_DIR/child-directory-result.json"
sleep 1
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/folder-sidebar-child.png"

FOLDER_COLLAPSE_RESULT="$DATA_CONTAINER/Documents/folder-collapse-result.json"
rm -f "$FOLDER_COLLAPSE_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --import-simulator-fixtures \
  --import-secondary-simulator-fixture \
  --collapse-primary-folder \
  --show-folder-sidebar

for _ in {1..30}; do
  if [[ -f "$FOLDER_COLLAPSE_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .folderCollapsed == true
  and .totalItemCount == 5
  and .expandedItemCount == 5
  and .collapsedItemCount == 2
  and .reexpandedItemCount == 5
  and .selectedVisibleTitle == "SimulatorFixtures"
  and .pageAfterCollapse == 2
' "$FOLDER_COLLAPSE_RESULT" >/dev/null
cp "$FOLDER_COLLAPSE_RESULT" \
  "$ARTIFACTS_DIR/folder-collapse-result.json"
sleep 1
xcrun simctl io "$DEVICE_UDID" screenshot \
  "$ARTIFACTS_DIR/folder-sidebar-collapsed.png"

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
  and .sidebarItemCount == 5
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
  and .sidebarItemCount == 4
  and .selectedDocumentCount == 6
  and .sourceFolderStillExists == true
' "$FOLDER_MANAGEMENT_RESULT" >/dev/null
cp "$FOLDER_MANAGEMENT_RESULT" \
  "$ARTIFACTS_DIR/folder-management-result.json"
test -f "$SECONDARY_FIXTURE_DIR/01_narrow_short_640x1800.jpg"

REMOVED_FIXTURE="$CHILD_B_DIR/20_wide_short_1800x1500.jpg"
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
  and .sidebarItemCount == 5
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

for APP_LANGUAGE in en zh-Hans ja; do
  LOCALIZATION_RESULT="$DATA_CONTAINER/Documents/localization-$APP_LANGUAGE.json"
  rm -f "$LOCALIZATION_RESULT"
  xcrun simctl launch \
    --terminate-running-process \
    "$DEVICE_UDID" \
    "$BUNDLE_ID" \
    --reset-app-password \
    --app-language "$APP_LANGUAGE" \
    --report-localization-state \
    --show-folder-batch-progress

  for _ in {1..30}; do
    if [[ -f "$LOCALIZATION_RESULT" ]]; then
      break
    fi
    sleep 1
  done

  case "$APP_LANGUAGE" in
    en)
      EXPECTED_SOURCE="Sources"
      EXPECTED_EMPTY="No Image Folders Yet"
      EXPECTED_SORT="Image Sorting"
      EXPECTED_VIDEO_TAB="Videos"
      ;;
    zh-Hans)
      EXPECTED_SOURCE="来源"
      EXPECTED_EMPTY="还没有图片文件夹"
      EXPECTED_SORT="图片排序"
      EXPECTED_VIDEO_TAB="视频播放"
      ;;
    ja)
      EXPECTED_SOURCE="ソース"
      EXPECTED_EMPTY="画像フォルダがありません"
      EXPECTED_SORT="画像の並べ替え"
      EXPECTED_VIDEO_TAB="動画"
      ;;
  esac

  jq -e \
    --arg language "$APP_LANGUAGE" \
    --arg source "$EXPECTED_SOURCE" \
    --arg empty "$EXPECTED_EMPTY" \
    --arg sort "$EXPECTED_SORT" \
    --arg videoTab "$EXPECTED_VIDEO_TAB" '
      .status == "passed"
      and .language == $language
      and .sourceButton == $source
      and .emptyTitle == $empty
      and .sortTitle == $sort
      and .videosTab == $videoTab
    ' "$LOCALIZATION_RESULT" >/dev/null
  cp "$LOCALIZATION_RESULT" \
    "$ARTIFACTS_DIR/localization-$APP_LANGUAGE.json"
  sleep 3
  xcrun simctl io "$DEVICE_UDID" screenshot \
    "$ARTIFACTS_DIR/language-$APP_LANGUAGE.png"
done

PERSISTED_LANGUAGE_RESULT="$DATA_CONTAINER/Documents/localization-ja.json"
rm -f "$PERSISTED_LANGUAGE_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --report-localization-state

for _ in {1..30}; do
  if [[ -f "$PERSISTED_LANGUAGE_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .language == "ja"
  and .sourceButton == "ソース"
' "$PERSISTED_LANGUAGE_RESULT" >/dev/null
cp "$PERSISTED_LANGUAGE_RESULT" \
  "$ARTIFACTS_DIR/localization-persisted.json"

LANGUAGE_SWITCH_RESULT="$DATA_CONTAINER/Documents/language-switch-result.json"
rm -f "$LANGUAGE_SWITCH_RESULT"
xcrun simctl launch \
  --terminate-running-process \
  "$DEVICE_UDID" \
  "$BUNDLE_ID" \
  --reset-app-password \
  --app-language en \
  --language-switch-smoke-test

for _ in {1..30}; do
  if [[ -f "$LANGUAGE_SWITCH_RESULT" ]]; then
    break
  fi
  sleep 1
done

jq -e '
  .status == "passed"
  and .sourceButtonTitles.en == "Sources"
  and .sourceButtonTitles["zh-Hans"] == "来源"
  and .sourceButtonTitles.ja == "ソース"
  and .sortMenuTitles.en == "Image Sorting"
  and .sortMenuTitles["zh-Hans"] == "图片排序"
  and .sortMenuTitles.ja == "画像の並べ替え"
  and .videoTabTitles.en == "Videos"
  and .videoTabTitles["zh-Hans"] == "视频播放"
  and .videoTabTitles.ja == "動画"
' "$LANGUAGE_SWITCH_RESULT" >/dev/null
cp "$LANGUAGE_SWITCH_RESULT" \
  "$ARTIFACTS_DIR/language-switch-result.json"

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
