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
UNIVERSAL_BUILD="${AETHER_UNIVERSAL:-1}"

APP_ENTITLEMENTS="${PROJECT_ROOT}/Apps/AetherCore/AetherCore.entitlements"
DRIVER_ENTITLEMENTS="${PROJECT_ROOT}/Drivers/AetherDriver/AetherDriver.entitlements"
APP_PROFILE_PLIST="${BUILD_DIR}/app_profile.plist"
DRIVER_PROFILE_PLIST="${BUILD_DIR}/driver_profile.plist"
APP_SIGN_ENTITLEMENTS="${BUILD_DIR}/app-sign.entitlements"
DRIVER_SIGN_ENTITLEMENTS="${BUILD_DIR}/driver-sign.entitlements"
HOST_ARCH="$(uname -m)"
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
  HOST_ARCH="arm64"
fi
FULL_FEATURE_DISTRIBUTION=0

log() { echo "[release] $*"; }
err() { echo "[release] ERROR: $*" >&2; exit 1; }

find_signing_identity() {
  if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "$SIGNING_IDENTITY"
    return
  fi

  if [[ -n "${APP_PROVISION_PROFILE:-}" && -f "${APP_PROVISION_PROFILE}" ]]; then
    mkdir -p "${BUILD_DIR}"
    local profile_cert_b64 profile_cert_der profile_sha1 matched
    profile_cert_b64="$(security cms -D -i "${APP_PROVISION_PROFILE}" | plutil -extract DeveloperCertificates.0 raw -o - - 2>/dev/null || true)"
    if [[ -n "${profile_cert_b64}" ]]; then
      profile_cert_der="${BUILD_DIR}/profile_cert.der"
      echo "${profile_cert_b64}" | base64 -D > "${profile_cert_der}" 2>/dev/null || true
      if [[ -f "${profile_cert_der}" ]]; then
        profile_sha1="$(openssl x509 -inform der -in "${profile_cert_der}" -noout -fingerprint -sha1 2>/dev/null | awk -F= '{print $2}' | tr -d ':')"
        matched="$(security find-identity -v -p codesigning | awk -v sha="${profile_sha1}" '$2 == sha {print $2; exit}' || true)"
        if [[ -n "${matched}" ]]; then
          echo "${matched}"
          return
        fi
      fi
    fi
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
  if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    export AETHER_UNIVERSAL=1
    unset AETHER_BUILD_ARCH || true
  else
    export AETHER_BUILD_ARCH="$HOST_ARCH"
  fi
  AETHER_UNSIGNED=1 "${PROJECT_ROOT}/Scripts/BuildRelease.sh" Release
  [[ -d "$APP_PATH" ]] || err "Build succeeded but app not found: ${APP_PATH}"
}

configure_distribution_mode() {
  if [[ -n "${APP_PROVISION_PROFILE:-}" && -f "${APP_PROVISION_PROFILE}" && -n "${DRIVER_PROVISION_PROFILE:-}" && -f "${DRIVER_PROVISION_PROFILE}" ]]; then
    FULL_FEATURE_DISTRIBUTION=1
    log "Distribution mode: full-feature package with embedded app + driver profiles."
  else
    FULL_FEATURE_DISTRIBUTION=0
    log "Distribution mode: compatibility package without system extension payload."
  fi
}

embed_profiles_if_provided() {
  [[ "$FULL_FEATURE_DISTRIBUTION" == "1" ]] || return 0

  local dext
  dext="$(find "${APP_PATH}/Contents/Library/SystemExtensions" -name "*.dext" -type d | head -n 1 || true)"
  [[ -n "$dext" ]] || err "SystemExtension (.dext) not found in app bundle."

  log "Embedding app provisioning profile..."
  cp "${APP_PROVISION_PROFILE}" "${APP_PATH}/Contents/embedded.provisionprofile"

  log "Embedding driver provisioning profile..."
  cp "${DRIVER_PROVISION_PROFILE}" "${dext}/embedded.provisionprofile"

  security cms -D -i "${APP_PROVISION_PROFILE}" > "${APP_PROFILE_PLIST}"
  security cms -D -i "${DRIVER_PROVISION_PROFILE}" > "${DRIVER_PROFILE_PLIST}"
}

prepare_sign_entitlements() {
  local base_entitlements="$1"
  local profile_plist="$2"
  local output_entitlements="$3"

  cp "${base_entitlements}" "${output_entitlements}"

  local app_id team_id
  app_id="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "${profile_plist}" 2>/dev/null || true)"
  team_id="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "${profile_plist}" 2>/dev/null || true)"

  [[ -n "${app_id}" ]] || err "Missing com.apple.application-identifier in ${profile_plist}"
  [[ -n "${team_id}" ]] || err "Missing com.apple.developer.team-identifier in ${profile_plist}"

  /usr/libexec/PlistBuddy -c "Delete :com.apple.application-identifier" "${output_entitlements}" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${app_id}" "${output_entitlements}"

  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.team-identifier" "${output_entitlements}" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${team_id}" "${output_entitlements}"

  /usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "${output_entitlements}" >/dev/null 2>&1 || true
  if /usr/libexec/PlistBuddy -c "Print :Entitlements:keychain-access-groups:0" "${profile_plist}" >/dev/null 2>&1; then
    local group idx=0
    /usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" "${output_entitlements}"
    while true; do
      group="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:keychain-access-groups:${idx}" "${profile_plist}" 2>/dev/null || true)"
      [[ -n "${group}" ]] || break
      /usr/libexec/PlistBuddy -c "Add :keychain-access-groups:${idx} string ${group}" "${output_entitlements}"
      idx=$((idx + 1))
    done
  fi
}

prepare_compatibility_bundle() {
  [[ "$FULL_FEATURE_DISTRIBUTION" == "0" ]] || return 0

  log "Preparing compatibility bundle..."
  rm -f "${APP_PATH}/Contents/embedded.provisionprofile"
  rm -rf "${APP_PATH}/Contents/Library/SystemExtensions"

  cp "${APP_ENTITLEMENTS}" "${APP_SIGN_ENTITLEMENTS}"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.system-extension.install" "${APP_SIGN_ENTITLEMENTS}" >/dev/null 2>&1 || true
}

sign_app_bundle() {
  local identity="$1"
  local app_codesign_args=(--force --options runtime --timestamp --sign "$identity")
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
        --entitlements "${DRIVER_SIGN_ENTITLEMENTS}" \
        --sign "$identity" "$item"
    done
  fi

  if [[ -n "${APP_SIGN_ENTITLEMENTS:-}" && -f "${APP_SIGN_ENTITLEMENTS}" ]]; then
    app_codesign_args+=(--entitlements "${APP_SIGN_ENTITLEMENTS}")
  fi

  codesign "${app_codesign_args[@]}" "$APP_PATH"

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

sign_dmg() {
  local identity="$1"
  [[ -f "$DMG_PATH" ]] || err "DMG not found: ${DMG_PATH}"
  log "Signing DMG with identity: ${identity}"
  codesign --force --timestamp --sign "$identity" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
}

notarize() {
  if [[ "$SKIP_NOTARIZE" == "1" ]]; then
    log "Skipping notarization (SKIP_NOTARIZE=1)."
    return
  fi

  if [[ -z "$NOTARY_PROFILE" ]]; then
    err "NOTARY_PROFILE is required unless SKIP_NOTARIZE=1."
  fi

  log "Submitting DMG to notary service..."
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  log "Stapling tickets..."
  # Ticket is guaranteed for the submitted artifact (DMG).
  # App stapling is best-effort when users also distribute the raw .app.
  xcrun stapler staple "$APP_PATH" || true
  xcrun stapler staple "$DMG_PATH"
}

main() {
  cd "$PROJECT_ROOT"
  local identity
  identity="$(find_signing_identity)"
  configure_distribution_mode
  build_unsigned
  embed_profiles_if_provided
  if [[ "$FULL_FEATURE_DISTRIBUTION" == "1" ]]; then
    prepare_sign_entitlements "${APP_ENTITLEMENTS}" "${APP_PROFILE_PLIST}" "${APP_SIGN_ENTITLEMENTS}"
    prepare_sign_entitlements "${DRIVER_ENTITLEMENTS}" "${DRIVER_PROFILE_PLIST}" "${DRIVER_SIGN_ENTITLEMENTS}"
  else
    prepare_compatibility_bundle
  fi
  sign_app_bundle "$identity"
  package_outputs
  sign_dmg "$identity"
  notarize
  log "Done. Outputs:"
  log "App: ${APP_PATH}"
  log "DMG: ${DMG_PATH}"
  log "ZIP: ${ZIP_PATH}"
}

main "$@"
