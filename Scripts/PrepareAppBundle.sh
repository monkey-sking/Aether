#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_APP="${PROJECT_ROOT}/.build/release/Aether.app"

APP_PATH="${1:-$DEFAULT_APP}"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
RES_DIR="${APP_PATH}/Contents/Resources"

ICNS_SRC="${PROJECT_ROOT}/Scripts/Resources/Aether.icns"
ICNS_DST="${RES_DIR}/Aether.icns"

SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
ENTITLEMENTS_PATH="${ENTITLEMENTS_PATH:-${PROJECT_ROOT}/Apps/AetherCore/AetherCore.entitlements}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: ${APP_PATH}" >&2
  exit 1
fi

if [[ ! -f "$INFO_PLIST" ]]; then
  echo "Missing Info.plist: ${INFO_PLIST}" >&2
  exit 1
fi

mkdir -p "$RES_DIR"

if [[ ! -f "$ICNS_SRC" ]]; then
  "${PROJECT_ROOT}/Scripts/MakeIcns.sh"
fi

cp -f "$ICNS_SRC" "$ICNS_DST"

# Ensure Finder can resolve the icon even if asset catalogs are missing.
/usr/bin/plutil -replace CFBundleIconFile -string "Aether" "$INFO_PLIST"

echo "OK: embedded icon -> ${ICNS_DST}"
echo "OK: CFBundleIconFile=Aether -> ${INFO_PLIST}"

# Any changes inside the bundle invalidate the existing signature.
# For local testing we do an ad-hoc sign by default so the app launches.
echo "Refreshing code signature..."
/usr/bin/xattr -cr "$APP_PATH" >/dev/null 2>&1 || true

if [[ -n "$SIGNING_IDENTITY" ]]; then
  if [[ -f "$ENTITLEMENTS_PATH" ]]; then
    /usr/bin/codesign --force --deep --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" \
      --entitlements "$ENTITLEMENTS_PATH" \
      "$APP_PATH" >/dev/null
  else
    /usr/bin/codesign --force --deep --options runtime --timestamp \
      --sign "$SIGNING_IDENTITY" \
      "$APP_PATH" >/dev/null
  fi
else
  /usr/bin/codesign --force --deep --sign - "$APP_PATH" >/dev/null
fi

/usr/bin/codesign --verify --deep --strict "$APP_PATH" >/dev/null 2>&1
echo "OK: codesign refreshed"
