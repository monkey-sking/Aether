#!/bin/bash

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_WEBSITE_ROOT="${PROJECT_ROOT}/../Website"
DEFAULT_APP_PATH="${PROJECT_ROOT}/.build/release/${APP_NAME}.app"
DEFAULT_DMG_PATH="${PROJECT_ROOT}/.build/release/${APP_NAME}_Installer.dmg"
DEFAULT_ZIP_PATH="${PROJECT_ROOT}/.build/release/${APP_NAME}.zip"
DOWNLOAD_NAME="${APP_NAME}.dmg"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-aether}" # Ed25519 private key is stored in Keychain under this account.
# Preserve latest + 2 older full packages by default (3 total).
SPARKLE_MAX_VERSIONS="${SPARKLE_MAX_VERSIONS:-3}"
# Default to no deltas; set >0 when you want delta updates.
SPARKLE_MAX_DELTAS="${SPARKLE_MAX_DELTAS:-0}"
WEBSITE_ROOT="${WEBSITE_ROOT:-${DEFAULT_WEBSITE_ROOT}}"
APP_PATH="${APP_PATH:-${DEFAULT_APP_PATH}}"
DMG_PATH="${DMG_PATH:-${DEFAULT_DMG_PATH}}"
ZIP_PATH="${ZIP_PATH:-${DEFAULT_ZIP_PATH}}"
CHANNEL=""
SHORT_VERSION=""
BUILD_VERSION=""

log() { echo "[sparkle-publish] $*"; }
err() { echo "[sparkle-publish] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") --channel stable|beta [--app PATH] [--zip PATH] [--dmg PATH] [--website-root PATH]
                         [--account NAME] [--short-version X.Y.Z] [--build-version N]

Copies update archives into the website repo and uses Sparkle's generate_appcast
to update the matching appcast feed and generate delta updates.

Notes:
- Sparkle auto-update uses a versioned ZIP (not DMG).
- Website manual download can still use a fixed-name DMG (optional).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-}"; shift 2 ;;
    --app)
      APP_PATH="${2:-}"; shift 2 ;;
    --zip)
      ZIP_PATH="${2:-}"; shift 2 ;;
    --dmg)
      DMG_PATH="${2:-}"; shift 2 ;;
    --website-root)
      WEBSITE_ROOT="${2:-}"; shift 2 ;;
    --account)
      SPARKLE_ACCOUNT="${2:-}"; shift 2 ;;
    --short-version)
      SHORT_VERSION="${2:-}"; shift 2 ;;
    --build-version)
      BUILD_VERSION="${2:-}"; shift 2 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      err "Unknown argument: $1"
      ;;
  esac
done

[[ -n "$CHANNEL" ]] || err "--channel is required."
case "$CHANNEL" in
  stable|beta) ;;
  *) err "--channel must be 'stable' or 'beta'." ;;
esac

[[ -d "$APP_PATH" ]] || err "App bundle not found: $APP_PATH"
[[ -f "$ZIP_PATH" ]] || err "ZIP not found: $ZIP_PATH"
[[ -d "$WEBSITE_ROOT" ]] || err "Website root not found: $WEBSITE_ROOT"

if [[ -z "$SHORT_VERSION" ]]; then
  SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
fi
if [[ -z "$BUILD_VERSION" ]]; then
  BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
fi

GENERATE_APPCAST_BIN=""
find_generate_appcast() {
  local candidate
  candidate="$(find "${PROJECT_ROOT}/.build" -type f -name "generate_appcast" -path "*sparkle*" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return
  fi
  candidate="$(find "${PROJECT_ROOT}/.build" -type f -name "generate-appcast" -path "*sparkle*" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return
  fi
  return 1
}

GENERATE_APPCAST_BIN="$(find_generate_appcast || true)"
[[ -x "$GENERATE_APPCAST_BIN" ]] || err "Sparkle generate_appcast not found or not executable under ${PROJECT_ROOT}/.build. Build the app once to fetch Sparkle artifacts."

case "$CHANNEL" in
  stable)
    DMG_DEST_DIR="${WEBSITE_ROOT}/public/download"
    UPDATE_DIR="${WEBSITE_ROOT}/public/aether"
    DOWNLOAD_URL_PREFIX="https://aether.7caifei.com/aether/"
    ;;
  beta)
    DMG_DEST_DIR="${WEBSITE_ROOT}/public/beta"
    UPDATE_DIR="${WEBSITE_ROOT}/public/aether-beta"
    DOWNLOAD_URL_PREFIX="https://aether.7caifei.com/aether-beta/"
    ;;
esac

mkdir -p "$UPDATE_DIR"

ZIP_NAME="${APP_NAME}_${SHORT_VERSION}_${BUILD_VERSION}.zip"
ZIP_DEST_PATH="${UPDATE_DIR}/${ZIP_NAME}"

log "Copying update ZIP to: ${ZIP_DEST_PATH}"
cp "$ZIP_PATH" "$ZIP_DEST_PATH"

# Optional: keep website manual download paths stable.
if [[ -f "$DMG_PATH" ]]; then
  DMG_DEST_PATH="${DMG_DEST_DIR}/${DOWNLOAD_NAME}"
  mkdir -p "$DMG_DEST_DIR"
  log "Copying DMG to website download path: ${DMG_DEST_PATH}"
  cp "$DMG_PATH" "$DMG_DEST_PATH"
fi

FULL_RELEASE_NOTES_URL="https://aether.7caifei.com/changelog"
PRODUCT_LINK="https://aether.7caifei.com/download"

LEGACY_FEED_PATH="${UPDATE_DIR}/appcast.xml"
if [[ -f "$LEGACY_FEED_PATH" ]]; then
  # generate_appcast re-uses and updates an existing feed file. Ensure the feed declares the
  # Sparkle namespace, otherwise it may become invalid after inserting <sparkle:...> elements.
  if ! grep -q "xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"" "$LEGACY_FEED_PATH" \
    && ! grep -q "xmlns:ns0=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"" "$LEGACY_FEED_PATH"; then
    log "Existing appcast.xml is missing Sparkle namespace; resetting feed for ${CHANNEL}."
    rm -f "$LEGACY_FEED_PATH"
  fi
fi

if [[ -f "$LEGACY_FEED_PATH" ]]; then
  # We no longer publish DMG-based Sparkle updates. If any legacy DMG items exist in the feed,
  # remove them so Sparkle doesn't see an invalid update archive type.
  python3 - "$LEGACY_FEED_PATH" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle_ns)

feed_path = Path(sys.argv[1])
raw = feed_path.read_text(encoding="utf-8", errors="ignore")
needs_prefix_fix = f'xmlns:ns0="{sparkle_ns}"' in raw
tree = ET.parse(feed_path)
root = tree.getroot()

channel = root.find("channel")
if channel is None:
    sys.exit(0)

items = list(channel.findall("item"))
removed = 0
for item in items:
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue
    url = (enclosure.get("url") or "").lower()
    if ".dmg" in url:
        channel.remove(item)
        removed += 1

if removed:
    tree.write(feed_path, encoding="utf-8", xml_declaration=True)
elif needs_prefix_fix:
    # Preserve the well-known 'sparkle:' prefix. Some tooling expects this prefix instead
    # of an auto-generated one (e.g. ns0), even though the namespace URI is identical.
    tree.write(feed_path, encoding="utf-8", xml_declaration=True)
PY
fi

log "Generating appcast + deltas in: ${UPDATE_DIR}"
"$GENERATE_APPCAST_BIN" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --full-release-notes-url "$FULL_RELEASE_NOTES_URL" \
  --link "$PRODUCT_LINK" \
  --maximum-versions "$SPARKLE_MAX_VERSIONS" \
  --maximum-deltas "$SPARKLE_MAX_DELTAS" \
  "$UPDATE_DIR"

log "Done."
log "ZIP: ${ZIP_DEST_PATH}"
log "Appcast: ${UPDATE_DIR}/appcast.xml"
log "Version: ${SHORT_VERSION} (${BUILD_VERSION})"
