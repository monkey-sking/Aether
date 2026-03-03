#!/bin/bash

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"
DMG_PATH="${BUILD_DIR}/${APP_NAME}_Installer.dmg"

TEAM_ID="${TEAM_ID:-4Z7654KAZZ}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

APP_ENTITLEMENTS="${PROJECT_ROOT}/Apps/AetherCore/AetherCore.entitlements"
DRIVER_ENTITLEMENTS="${PROJECT_ROOT}/Drivers/AetherDriver/AetherDriver.entitlements"

log() { echo "[release] $*"; }
err() { echo "[release] ERROR: $*" >&2; exit 1; }

find_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "$SIGNING_IDENTITY"
    return
  fi
  local line
  line="$(security find-identity -v -p codesigning | grep "Developer ID Application: .*(${TEAM_ID})" | head -n 1 || true)"
  if [[ -z "$line" ]]; then
    err "No Developer ID Application identity found for team ${TEAM_ID}."
  fi
  # Use SHA-1 fingerprint to avoid ambiguity when multiple same-name certs exist.
  echo "$line" | awk '{print $2}'
}

build_unsigned() {
  log "Building unsigned release app..."
  AETHER_UNSIGNED=1 "${PROJECT_ROOT}/Scripts/BuildRelease.sh" Release
  [[ -d "$APP_PATH" ]] || err "Build succeeded but app not found: ${APP_PATH}"
}

embed_profiles_if_provided() {
  if [[ -n "${APP_PROVISION_PROFILE:-}" && -f "${APP_PROVISION_PROFILE}" ]]; then
    log "Embedding app provisioning profile..."
    cp "${APP_PROVISION_PROFILE}" "${APP_PATH}/Contents/embedded.provisionprofile"
  fi

  if [[ -n "${DRIVER_PROVISION_PROFILE:-}" && -f "${DRIVER_PROVISION_PROFILE}" ]]; then
    log "Embedding driver provisioning profile..."
    local dext
    dext="$(find "${APP_PATH}/Contents/Library/SystemExtensions" -name "*.dext" -type d | head -n 1 || true)"
    if [[ -n "$dext" ]]; then
      cp "${DRIVER_PROVISION_PROFILE}" "${dext}/Contents/embedded.provisionprofile"
    fi
  fi
}

sign_app_bundle() {
  local identity="$1"
  log "Signing app with identity: ${identity}"

  xattr -cr "$APP_PATH" >/dev/null 2>&1 || true

  # Sign nested executable content first.
  if [[ -d "${APP_PATH}/Contents/Frameworks" ]]; then
    find "${APP_PATH}/Contents/Frameworks" -type f \( -name "*.dylib" -o -perm -111 \) | while read -r item; do
      codesign --force --options runtime --timestamp --sign "$identity" "$item"
    done
  fi

  if [[ -d "${APP_PATH}/Contents/PlugIns" ]]; then
    find "${APP_PATH}/Contents/PlugIns" -type d -name "*.xpc" | while read -r item; do
      codesign --force --options runtime --timestamp --sign "$identity" "$item"
    done
  fi

  if [[ -d "${APP_PATH}/Contents/Library/SystemExtensions" ]]; then
    find "${APP_PATH}/Contents/Library/SystemExtensions" -type d -name "*.dext" | while read -r item; do
      codesign --force --options runtime --timestamp \
        --entitlements "${DRIVER_ENTITLEMENTS}" \
        --sign "$identity" "$item"
    done
  fi

  codesign --force --options runtime --timestamp \
    --entitlements "${APP_ENTITLEMENTS}" \
    --sign "$identity" "$APP_PATH"

  codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null
  log "Code sign verification passed."
}

package_outputs() {
  log "Creating DMG..."
  "${PROJECT_ROOT}/Scripts/CreateDMG.sh"
  [[ -f "$DMG_PATH" ]] || err "DMG not found: ${DMG_PATH}"

  log "Creating ZIP for notarization..."
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
}

notarize() {
  if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    log "Skipping notarization (SKIP_NOTARIZE=1)."
    return
  fi

  if [[ -z "$NOTARY_PROFILE" ]]; then
    err "NOTARY_PROFILE is required unless SKIP_NOTARIZE=1."
  fi

  log "Submitting ZIP to notary service..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  log "Stapling tickets..."
  xcrun stapler staple "$APP_PATH"
  xcrun stapler staple "$DMG_PATH"
}

main() {
  cd "$PROJECT_ROOT"
  local identity
  identity="$(find_signing_identity)"
  build_unsigned
  embed_profiles_if_provided
  sign_app_bundle "$identity"
  package_outputs
  notarize
  log "Done. Outputs:"
  log "App: ${APP_PATH}"
  log "DMG: ${DMG_PATH}"
  log "ZIP: ${ZIP_PATH}"
}

main "$@"
