#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CONFIGURATION=${CONFIGURATION:-release}
BUILD_ROOT=${DIALNRAY_BUILD_ROOT:-/private/tmp/DialnRayBuild}
OUTPUT_ROOT=${DIALNRAY_OUTPUT_ROOT:-${PROJECT_DIR}/build}
APP_PATH=${OUTPUT_ROOT}/DialnRay.app
CONTENTS=${APP_PATH}/Contents
MACOS=${CONTENTS}/MacOS
RESOURCES=${CONTENTS}/Resources

mkdir -p "${OUTPUT_ROOT}"
swift build --package-path "${PROJECT_DIR}" -c "${CONFIGURATION}" --scratch-path "${BUILD_ROOT}"
BIN_PATH=$(swift build --package-path "${PROJECT_DIR}" -c "${CONFIGURATION}" --scratch-path "${BUILD_ROOT}" --show-bin-path)

if [[ -d "${APP_PATH}" ]]; then
  rm -rf "${APP_PATH}"
fi
mkdir -p "${MACOS}" "${RESOURCES}"
cp "${BIN_PATH}/DialnRay" "${MACOS}/DialnRay"
cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS}/Info.plist"

if [[ -n "${GUMROAD_PRODUCT_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :DialnRayGumroadProductID ${GUMROAD_PRODUCT_ID}" "${CONTENTS}/Info.plist"
fi

ICON_SOURCE=${PROJECT_DIR}/Resources/AppIcon.svg
ICON_PNG=${OUTPUT_ROOT}/AppIcon-1024.png
if sips -s format png "${ICON_SOURCE}" --out "${ICON_PNG}" >/dev/null 2>&1; then
  ICONSET=${OUTPUT_ROOT}/AppIcon.iconset
  if [[ -d "${ICONSET}" ]]; then
    rm -rf "${ICONSET}"
  fi
  mkdir -p "${ICONSET}"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${ICON_PNG}" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "${double}" "${double}" "${ICON_PNG}" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS}/Info.plist" 2>/dev/null || true
fi

LOCAL_SIGNING_IDENTITY=${DIALNRAY_LOCAL_SIGNING_IDENTITY:-DialnRay Local Development}

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --deep --options runtime --timestamp \
    --entitlements "${PROJECT_DIR}/Resources/DialnRay.entitlements" \
    --sign "${CODE_SIGN_IDENTITY}" "${APP_PATH}"
elif security find-identity -v -p codesigning | grep -Fq "\"${LOCAL_SIGNING_IDENTITY}\""; then
  codesign --force --deep --options runtime --timestamp=none \
    --entitlements "${PROJECT_DIR}/Resources/DialnRay.entitlements" \
    --sign "${LOCAL_SIGNING_IDENTITY}" "${APP_PATH}"
else
  codesign --force --deep --sign - "${APP_PATH}"
fi

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${OUTPUT_ROOT}/DialnRay-macOS.zip"

DMG_PATH=${OUTPUT_ROOT}/DialnRay-macOS.dmg
if [[ -f "${DMG_PATH}" ]]; then
  rm "${DMG_PATH}"
fi
hdiutil create -volname DialnRay -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}" >/dev/null

echo "Built ${APP_PATH}"
echo "Archive ${OUTPUT_ROOT}/DialnRay-macOS.zip"
echo "Disk image ${DMG_PATH}"
