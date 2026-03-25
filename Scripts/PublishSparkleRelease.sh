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
# Generate deltas for the latest update from recent versions (smaller downloads).
# Set to 0 to disable deltas.
SPARKLE_MAX_DELTAS="${SPARKLE_MAX_DELTAS:-2}"
WEBSITE_ROOT="${WEBSITE_ROOT:-${DEFAULT_WEBSITE_ROOT}}"
APP_PATH="${APP_PATH:-${DEFAULT_APP_PATH}}"
DMG_PATH="${DMG_PATH:-${DEFAULT_DMG_PATH}}"
ZIP_PATH="${ZIP_PATH:-${DEFAULT_ZIP_PATH}}"
TRACKING_GATEWAY_BASE="${TRACKING_GATEWAY_BASE:-https://auth.aether.7caifei.com}"
CHANNEL=""
SHORT_VERSION=""
BUILD_VERSION=""
PUBLIC_LABEL="${PUBLIC_LABEL:-}"

log() { echo "[sparkle-publish] $*"; }
err() { echo "[sparkle-publish] ERROR: $*" >&2; exit 1; }

fallback_public_build_label() {
  local raw="$1"
  local digits="${raw//[^0-9]/}"
  if [[ ${#digits} -eq 14 ]]; then
    echo "${digits:4:4}-${digits:8:6}"
    return
  fi
  if [[ ${#digits} -eq 12 ]]; then
    echo "${digits:2:4}-${digits:6:6}"
    return
  fi
  echo "$raw"
}

next_public_build_label() {
  if [[ -n "$PUBLIC_LABEL" ]]; then
    echo "$PUBLIC_LABEL"
    return
  fi

  if [[ "$CHANNEL" == "beta" && -d "${WEBSITE_ROOT}/.git" ]]; then
    local published_count
    published_count="$(
      git -C "$WEBSITE_ROOT" log --format='%s' \
        | awk '/^(chore\(beta\): publish |chore: publish beta )/ { count++ } END { print count + 0 }'
    )"
    echo "b$((published_count + 1))"
    return
  fi

  fallback_public_build_label "$BUILD_VERSION"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") --channel stable|beta [--app PATH] [--zip PATH] [--dmg PATH] [--website-root PATH]
                         [--account NAME] [--short-version X.Y.Z] [--build-version N] [--public-label LABEL]

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
    --public-label)
      PUBLIC_LABEL="${2:-}"; shift 2 ;;
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
    DOWNLOAD_URL_PREFIX="${TRACKING_GATEWAY_BASE}/aether/"
    ;;
  beta)
    DMG_DEST_DIR="${WEBSITE_ROOT}/public/beta"
    UPDATE_DIR="${WEBSITE_ROOT}/public/aether-beta"
    DOWNLOAD_URL_PREFIX="${TRACKING_GATEWAY_BASE}/aether-beta/"
    ;;
esac

mkdir -p "$UPDATE_DIR"

PUBLIC_BUILD_LABEL="$(next_public_build_label)"
ZIP_NAME="${APP_NAME}_${SHORT_VERSION}_${PUBLIC_BUILD_LABEL}.zip"
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

# Sparkle's generator may keep historical delta files under "old_updates" while still
# leaving stale <sparkle:deltas> entries pointing at the public root. This causes 404s.
# Keep the feed self-consistent: only reference delta files that exist next to appcast.xml.
python3 - "$LEGACY_FEED_PATH" "$UPDATE_DIR" <<'PY'
import os
import sys
from urllib.parse import urlparse
import xml.etree.ElementTree as ET
from pathlib import Path

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle_ns)

feed_path = Path(sys.argv[1])
update_dir = Path(sys.argv[2])

tree = ET.parse(feed_path)
root = tree.getroot()

channel = root.find("channel")
if channel is None:
    sys.exit(0)

changed = False

for item in channel.findall("item"):
    deltas = item.find(f"{{{sparkle_ns}}}deltas")
    if deltas is None:
        continue
    for enc in list(deltas.findall("enclosure")):
        url = enc.get("url") or ""
        name = os.path.basename(urlparse(url).path or url)
        if not name:
            continue
        if not (update_dir / name).exists():
            deltas.remove(enc)
            changed = True
    if not list(deltas.findall("enclosure")):
        item.remove(deltas)
        changed = True

if changed:
    tree.write(feed_path, encoding="utf-8", xml_declaration=True)
PY

python3 - "$LEGACY_FEED_PATH" <<'PY'
import os
import re
import sys
from urllib.parse import urlparse
import xml.etree.ElementTree as ET
from pathlib import Path

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
aether_ns = "https://aether.7caifei.com/xml-namespaces/aether"
ET.register_namespace("sparkle", sparkle_ns)
ET.register_namespace("aether", aether_ns)

feed_path = Path(sys.argv[1])
tree = ET.parse(feed_path)
root = tree.getroot()

channel = root.find("channel")
if channel is None:
    sys.exit(0)

label_tag = f"{{{aether_ns}}}publicVersionLabel"
version_tag = f"{{{sparkle_ns}}}version"
short_version_tag = f"{{{sparkle_ns}}}shortVersionString"
changed = False

def fallback_public_label(raw):
    digits = "".join(ch for ch in raw if ch.isdigit())
    if len(digits) == 14:
        return f"{digits[4:8]}-{digits[8:14]}"
    if len(digits) == 12:
        return f"{digits[2:6]}-{digits[6:12]}"
    return None

def extract_public_label(url, build_version):
    name = os.path.basename(urlparse(url).path or url)
    if name.lower().endswith(".zip"):
        stem = name[:-4]
        candidate = stem.split("_")[-1]
        if re.fullmatch(r"[bB]\d+", candidate):
            return candidate
    return fallback_public_label(build_version)

for item in channel.findall("item"):
    enclosure = item.find("enclosure")
    if enclosure is None:
        continue

    build_version = item.findtext(version_tag, default="")
    label = extract_public_label(enclosure.get("url") or "", build_version)
    if not label:
        continue

    existing = item.find(label_tag)
    if existing is not None:
        if (existing.text or "") != label:
            existing.text = label
            changed = True
        continue

    element = ET.Element(label_tag)
    element.text = label

    anchor = item.find(short_version_tag)
    if anchor is None:
        anchor = item.find(version_tag)
    if anchor is not None:
        children = list(item)
        item.insert(children.index(anchor) + 1, element)
    else:
        item.insert(0, element)
    changed = True

if changed:
    tree.write(feed_path, encoding="utf-8", xml_declaration=True)
PY

python3 - "$LEGACY_FEED_PATH" "$TRACKING_GATEWAY_BASE" "$CHANNEL" "$SHORT_VERSION" <<'PY'
import sys
from urllib.parse import parse_qsl, urlencode, urlparse, urlunparse
import xml.etree.ElementTree as ET
from pathlib import Path

sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle_ns)

feed_path = Path(sys.argv[1])
tracking_origin = sys.argv[2].rstrip("/")
channel = sys.argv[3]
fallback_short_version = sys.argv[4]

tree = ET.parse(feed_path)
root = tree.getroot()
channel_node = root.find("channel")
if channel_node is None:
    sys.exit(0)

short_version_tag = f"{{{sparkle_ns}}}shortVersionString"
changed = False

def tracked_url(raw_url: str, version: str) -> str:
    parsed = urlparse(raw_url)
    origin = urlparse(tracking_origin)
    query = dict(parse_qsl(parsed.query, keep_blank_values=True))
    query["source"] = "update"
    query["channel"] = channel
    query["version"] = version
    return urlunparse((
        origin.scheme,
        origin.netloc,
        parsed.path,
        "",
        urlencode(query),
        "",
    ))

for item in channel_node.findall("item"):
    short_version = item.findtext(short_version_tag, default=fallback_short_version).strip() or fallback_short_version

    main_enclosure = item.find("enclosure")
    if main_enclosure is not None:
        raw_url = main_enclosure.get("url") or ""
        rewritten = tracked_url(raw_url, short_version)
        if rewritten != raw_url:
            main_enclosure.set("url", rewritten)
            changed = True

    deltas = item.find(f"{{{sparkle_ns}}}deltas")
    if deltas is None:
        continue
    for enclosure in deltas.findall("enclosure"):
        raw_url = enclosure.get("url") or ""
        rewritten = tracked_url(raw_url, short_version)
        if rewritten != raw_url:
            enclosure.set("url", rewritten)
            changed = True

if changed:
    tree.write(feed_path, encoding="utf-8", xml_declaration=True)
PY

log "Done."
log "ZIP: ${ZIP_DEST_PATH}"
log "Appcast: ${UPDATE_DIR}/appcast.xml"
log "Version: ${SHORT_VERSION} (${PUBLIC_BUILD_LABEL}; internal ${BUILD_VERSION})"
