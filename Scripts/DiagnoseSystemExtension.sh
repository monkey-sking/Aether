#!/bin/bash

set -euo pipefail

APP_PATH="${1:-/Applications/Aether.app}"
EXT_BUNDLE_ID="${EXT_BUNDLE_ID:-com.7fei.Aether.AetherDriver}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Usage: $(basename "$0") /path/to/Aether.app" >&2
  exit 2
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
EXT_DIR="${APP_PATH}/Contents/Library/SystemExtensions"
EXT_PATH=""

tmpdir="$(mktemp -d /tmp/aether_diagnose.XXXXXX)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

echo "=== Aether System Extension Diagnose ==="
echo "App: $APP_PATH"

if [[ "$APP_PATH" != /Applications/* ]]; then
  echo "WARN: Host app must be in /Applications to activate System Extension."
fi

if [[ -f "$INFO_PLIST" ]]; then
  echo ""
  echo "-- Info.plist --"
  /usr/bin/plutil -p "$INFO_PLIST" | /usr/bin/egrep -n "CFBundleIdentifier|CFBundleExecutable|CFBundleName" || true
fi

echo ""
echo "-- Embedded extension --"
if [[ -d "$EXT_DIR" ]]; then
  EXT_PATH="$(/usr/bin/find "$EXT_DIR" -maxdepth 1 -type d -name "*.dext" -print -quit 2>/dev/null || true)"
  if [[ -n "$EXT_PATH" ]]; then
    echo "OK: $EXT_PATH"
    if [[ -f "${EXT_PATH}/Contents/Info.plist" ]]; then
      /usr/bin/plutil -p "${EXT_PATH}/Contents/Info.plist" | /usr/bin/egrep -n "CFBundleIdentifier|CFBundleName|CFBundleExecutable" || true
    fi
  else
    echo "MISSING: no .dext found under $EXT_DIR"
  fi
else
  echo "MISSING: $EXT_DIR"
fi

dump_entitlements() {
  local path="$1"
  local label="$2"
  echo ""
  echo "-- Entitlements ($label) --"
  local out="${tmpdir}/entitlements_${label}.plist"
  if /usr/bin/codesign -d --entitlements :- "$path" >"$out" 2>/dev/null; then
    if [[ ! -s "$out" ]]; then
      echo "No entitlements output (likely unsigned or signature invalid)."
      /usr/bin/codesign -dv --verbose=2 "$path" 2>&1 | sed -n '1,40p' || true
      return
    fi
    /usr/bin/plutil -p "$out" 2>/dev/null | /usr/bin/egrep -n "system-extension.install|driverkit|app-sandbox" || true
    return
  fi

  echo "Unable to read entitlements via codesign."
  /usr/bin/codesign -dv --verbose=2 "$path" 2>&1 | sed -n '1,40p' || true
}

dump_entitlements "$APP_PATH" "host_app"
if [[ -n "$EXT_PATH" && -d "$EXT_PATH" ]]; then
  dump_entitlements "$EXT_PATH" "driver_dext"
fi

echo ""
echo "-- Provisioning profile (host) --"
PROFILE="${APP_PATH}/Contents/embedded.provisionprofile"
if [[ -f "$PROFILE" ]]; then
  echo "Found: $PROFILE"
  prof_plist="${tmpdir}/profile.plist"
  if /usr/bin/security cms -D -i "$PROFILE" >"$prof_plist" 2>/dev/null; then
    /usr/bin/plutil -p "$prof_plist" | /usr/bin/egrep -n "TeamIdentifier|Entitlements|application-identifier|com\\.apple\\.developer\\.system-extension\\.install|com\\.apple\\.developer\\.driverkit" || true
    echo ""
    echo "Profile Entitlements (filtered):"
    /usr/bin/plutil -extract Entitlements xml1 -o - "$prof_plist" 2>/dev/null | /usr/bin/plutil -p - 2>/dev/null | /usr/bin/egrep -n "system-extension.install|driverkit|application-identifier" || true
  else
    echo "Unable to decode embedded.provisionprofile (security cms failed)."
  fi
else
  echo "No embedded.provisionprofile (expected for Developer ID builds)."
fi

echo ""
echo "-- Gatekeeper --"
/usr/sbin/spctl --assess --type execute --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,40p' || true

echo ""
echo "-- Summary --"
echo "If you see 'Missing entitlement com.apple.developer.system-extension.install':"
echo "1) Ensure the host app is signed with that entitlement (codesign entitlements above)."
echo "2) Ensure your Team/App ID supports System Extensions + DriverKit (paid Apple Developer Program + capability)."
echo "3) Install the signed app to /Applications, then activate."
