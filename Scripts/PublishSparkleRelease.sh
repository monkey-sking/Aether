#!/bin/bash

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_WEBSITE_ROOT="${PROJECT_ROOT}/../Website"
DEFAULT_APP_PATH="${PROJECT_ROOT}/.build/release/${APP_NAME}.app"
DEFAULT_DMG_PATH="${PROJECT_ROOT}/.build/release/${APP_NAME}_Installer.dmg"
DEFAULT_SPARKLE_BIN="${PROJECT_ROOT}/.build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
DOWNLOAD_NAME="${APP_NAME}.dmg"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-aether}"
WEBSITE_ROOT="${WEBSITE_ROOT:-${DEFAULT_WEBSITE_ROOT}}"
APP_PATH="${APP_PATH:-${DEFAULT_APP_PATH}}"
DMG_PATH="${DMG_PATH:-${DEFAULT_DMG_PATH}}"
SPARKLE_BIN="${SPARKLE_BIN:-${DEFAULT_SPARKLE_BIN}}"
CHANNEL=""
SHORT_VERSION=""
BUILD_VERSION=""

log() { echo "[sparkle-publish] $*"; }
err() { echo "[sparkle-publish] ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") --channel stable|beta [--app PATH] [--dmg PATH] [--website-root PATH]
                         [--sparkle-bin PATH] [--account NAME] [--short-version X.Y.Z]
                         [--build-version N]

Copies the release DMG into the website repo, signs it with Sparkle, and rewrites
the matching appcast feed.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --channel)
      CHANNEL="${2:-}"; shift 2 ;;
    --app)
      APP_PATH="${2:-}"; shift 2 ;;
    --dmg)
      DMG_PATH="${2:-}"; shift 2 ;;
    --website-root)
      WEBSITE_ROOT="${2:-}"; shift 2 ;;
    --sparkle-bin)
      SPARKLE_BIN="${2:-}"; shift 2 ;;
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

[[ -f "$DMG_PATH" ]] || err "DMG not found: $DMG_PATH"
[[ -d "$APP_PATH" ]] || err "App bundle not found: $APP_PATH"
[[ -x "$SPARKLE_BIN" ]] || err "Sparkle signer not found or not executable: $SPARKLE_BIN"
[[ -d "$WEBSITE_ROOT" ]] || err "Website root not found: $WEBSITE_ROOT"

if [[ -z "$SHORT_VERSION" ]]; then
  SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
fi
if [[ -z "$BUILD_VERSION" ]]; then
  BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
fi

case "$CHANNEL" in
  stable)
    DEST_DIR="${WEBSITE_ROOT}/public/download"
    FEED_PATH="${WEBSITE_ROOT}/public/aether/appcast.xml"
    DOWNLOAD_URL="https://auth.aether.7caifei.com/download/${DOWNLOAD_NAME}?source=update&channel=stable&version=${SHORT_VERSION}"
    ;;
  beta)
    DEST_DIR="${WEBSITE_ROOT}/public/beta"
    FEED_PATH="${WEBSITE_ROOT}/public/aether-beta/appcast.xml"
    DOWNLOAD_URL="https://auth.aether.7caifei.com/beta/${DOWNLOAD_NAME}?source=update&channel=beta&version=${SHORT_VERSION}"
    ;;
esac

DEST_PATH="${DEST_DIR}/${DOWNLOAD_NAME}"
mkdir -p "$DEST_DIR"

log "Copying DMG to website asset path..."
cp "$DMG_PATH" "$DEST_PATH"

log "Signing copied DMG with Sparkle account: ${SPARKLE_ACCOUNT}"
SIGNATURE="$("$SPARKLE_BIN" --account "$SPARKLE_ACCOUNT" -p "$DEST_PATH")"
[[ -n "$SIGNATURE" ]] || err "Sparkle signer did not return a signature."

log "Verifying Sparkle signature..."
"$SPARKLE_BIN" --account "$SPARKLE_ACCOUNT" --verify "$DEST_PATH" "$SIGNATURE" >/dev/null

DMG_SIZE="$(stat -f%z "$DEST_PATH")"

log "Updating appcast: ${FEED_PATH}"
python3 - "$FEED_PATH" "$DOWNLOAD_URL" "$BUILD_VERSION" "$SHORT_VERSION" "$DMG_SIZE" "$SIGNATURE" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

feed_path = Path(sys.argv[1])
download_url = sys.argv[2]
build_version = sys.argv[3]
short_version = sys.argv[4]
length = sys.argv[5]
signature = sys.argv[6]

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle_ns)

tree = ET.parse(feed_path)
root = tree.getroot()
channel = root.find("channel")
if channel is None:
    raise SystemExit("appcast is missing <channel>")
item = channel.find("item")
if item is None:
    raise SystemExit("appcast is missing <item>")

title = item.find("title")
if title is None:
    title = ET.SubElement(item, "title")
title.text = f"Aether {short_version}"

version = item.find(f"{{{sparkle_ns}}}version")
if version is None:
    version = ET.SubElement(item, f"{{{sparkle_ns}}}version")
version.text = str(build_version)

short = item.find(f"{{{sparkle_ns}}}shortVersionString")
if short is None:
    short = ET.SubElement(item, f"{{{sparkle_ns}}}shortVersionString")
short.text = short_version

enclosure = item.find("enclosure")
if enclosure is None:
    enclosure = ET.SubElement(item, "enclosure")
enclosure.set("url", download_url)
enclosure.set("length", str(length))
enclosure.set("type", "application/octet-stream")
enclosure.set(f"{{{sparkle_ns}}}edSignature", signature)

tree.write(feed_path, encoding="utf-8", xml_declaration=True)
PY

log "Done."
log "DMG: ${DEST_PATH}"
log "Feed: ${FEED_PATH}"
log "Version: ${SHORT_VERSION} (${BUILD_VERSION})"
