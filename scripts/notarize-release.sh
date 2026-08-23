#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
OUTPUT_ROOT=${DIALNRAY_OUTPUT_ROOT:-${PROJECT_DIR}/build}
APP_PATH=${OUTPUT_ROOT}/DialnRay.app
ZIP_PATH=${OUTPUT_ROOT}/DialnRay-notarization.zip
DMG_PATH=${OUTPUT_ROOT}/DialnRay-macOS.dmg

: "${CODE_SIGN_IDENTITY:?Set CODE_SIGN_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
: "${GUMROAD_PRODUCT_ID:?Set GUMROAD_PRODUCT_ID to the product ID shown in Gumroad's license-key block}"

CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY}" GUMROAD_PRODUCT_ID="${GUMROAD_PRODUCT_ID}" \
  DIALNRAY_OUTPUT_ROOT="${OUTPUT_ROOT}" "${SCRIPT_DIR}/build-app.sh"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP_PATH}"

rm -f "${DMG_PATH}"
hdiutil create -volname DialnRay -srcfolder "${APP_PATH}" -ov -format UDZO "${DMG_PATH}" >/dev/null
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_PATH}"
spctl --assess --type execute --verbose=2 "${APP_PATH}"

echo "Notarized release: ${DMG_PATH}"
