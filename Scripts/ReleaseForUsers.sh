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
PUBLISH_SPARKLE="${PUBLISH_SPARKLE:-0}"
SPARKLE_CHANNEL="${SPARKLE_CHANNEL:-stable}"
WEBSITE_ROOT="${WEBSITE_ROOT:-${PROJECT_ROOT}/../Website}"
PUBLIC_VERSION_LABEL="${PUBLIC_VERSION_LABEL:-}"

APP_ENTITLEMENTS="${PROJECT_ROOT}/Apps/AetherCore/AetherCore.entitlements"
APP_SIGN_ENTITLEMENTS="${BUILD_DIR}/app-sign.entitlements"
HOST_ARCH="$(uname -m)"
if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
  HOST_ARCH="arm64"
fi

log() { echo "[release] $*"; }
err() { echo "[release] ERROR: $*" >&2; exit 1; }

compute_public_version_label() {
  if [[ -n "$PUBLIC_VERSION_LABEL" ]]; then
    echo "$PUBLIC_VERSION_LABEL"
    return
  fi

  if [[ "$PUBLISH_SPARKLE" == "1" && "$SPARKLE_CHANNEL" == "beta" && -d "${WEBSITE_ROOT}/.git" ]]; then
    local published_count
    published_count="$(
      git -C "$WEBSITE_ROOT" log --format='%s' \
        | awk '/^(chore\(beta\): publish |chore: publish beta )/ { count++ } END { print count + 0 }'
    )"
    echo "b$((published_count + 1))"
    return
  fi

  echo ""
}

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
  if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
    export AETHER_UNIVERSAL=1
    unset AETHER_BUILD_ARCH || true
  else
    export AETHER_BUILD_ARCH="$HOST_ARCH"
  fi
  AETHER_UNSIGNED=1 "${PROJECT_ROOT}/Scripts/BuildRelease.sh" Release
  [[ -d "$APP_PATH" ]] || err "Build succeeded but app not found: ${APP_PATH}"
}

prepare_release_bundle() {
  log "Preparing app bundle..."
  rm -f "${APP_PATH}/Contents/embedded.provisionprofile"
  rm -rf "${APP_PATH}/Contents/Library/SystemExtensions"

  cp "${APP_ENTITLEMENTS}" "${APP_SIGN_ENTITLEMENTS}"
}

stamp_public_version_label() {
  local label="$1"
  local plist="${APP_PATH}/Contents/Info.plist"

  /usr/libexec/PlistBuddy -c "Delete :AetherPublicVersionLabel" "$plist" >/dev/null 2>&1 || true
  if [[ -n "$label" ]]; then
    /usr/libexec/PlistBuddy -c "Add :AetherPublicVersionLabel string $label" "$plist"
    log "Stamped public version label: ${label}"
  fi
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
  local sign_log
  sign_log="$(mktemp)"
  if ! codesign --force --timestamp --sign "$identity" "$DMG_PATH" 2>"$sign_log"; then
    if grep -qi "timestamp service is not available" "$sign_log"; then
      log "Timestamp service unavailable; retrying DMG codesign without timestamp..."
      codesign --force --timestamp=none --sign "$identity" "$DMG_PATH"
    else
      cat "$sign_log" >&2
      rm -f "$sign_log"
      err "Failed to codesign DMG."
    fi
  fi
  rm -f "$sign_log"
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

publish_sparkle_assets() {
  if [[ "$PUBLISH_SPARKLE" != "1" ]]; then
    log "Skipping Sparkle publish (PUBLISH_SPARKLE != 1)."
    return
  fi

  log "Publishing Sparkle assets to website repo..."
  "${PROJECT_ROOT}/Scripts/PublishSparkleRelease.sh" \
    --channel "$SPARKLE_CHANNEL" \
    --app "$APP_PATH" \
    --zip "$ZIP_PATH" \
    --dmg "$DMG_PATH" \
    --public-label "$PUBLIC_VERSION_LABEL" \
    --website-root "$WEBSITE_ROOT"
}

main() {
  cd "$PROJECT_ROOT"
  local identity
  PUBLIC_VERSION_LABEL="$(compute_public_version_label)"
  identity="$(find_signing_identity)"
  build_unsigned
  prepare_release_bundle
  stamp_public_version_label "$PUBLIC_VERSION_LABEL"
  sign_app_bundle "$identity"
  package_outputs
  sign_dmg "$identity"
  notarize
  publish_sparkle_assets
  log "Done. Outputs:"
  log "App: ${APP_PATH}"
  log "DMG: ${DMG_PATH}"
  log "ZIP: ${ZIP_PATH}"
}

main "$@"
