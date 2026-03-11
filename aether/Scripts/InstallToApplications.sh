#!/bin/bash

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOW_UNSIGNED_INSTALL="${AETHER_ALLOW_UNSIGNED_INSTALL:-0}"

SRC_APP="${1:-}"
DEST_APP="/Applications/${APP_NAME}.app"

codesign_ok() {
  local path="$1"
  /usr/bin/codesign --verify --deep --strict "$path" >/dev/null 2>&1
}

pick_best() {
  local best=""
  local best_score=-1
  local best_m=0

  # Candidate locations.
  local candidates=(
    "${PROJECT_ROOT}/.derivedData/Build/Products/Debug/${APP_NAME}.app"
    "${PROJECT_ROOT}/.derivedData/Build/Products/Release/${APP_NAME}.app"
    "${PROJECT_ROOT}/.build/release/${APP_NAME}.app"
  )

  for p in "${candidates[@]}"; do
    [[ -d "$p" ]] || continue

    local score=0
    local m
    m="$(/usr/bin/stat -f %m "$p" 2>/dev/null || echo 0)"

    if codesign_ok "$p"; then score=$((score + 10)); fi

    # Prefer newer if scores tie.
    if [[ "$score" -gt "$best_score" || ( "$score" -eq "$best_score" && "$m" -gt "$best_m" ) ]]; then
      best="$p"
      best_score="$score"
      best_m="$m"
    fi
  done

  echo "$best"
}

if [[ -z "$SRC_APP" ]]; then
  SRC_APP="$(pick_best)"
fi

if [[ -z "$SRC_APP" || ! -d "$SRC_APP" ]]; then
  echo "Source app not found. Provide a path, e.g.:" >&2
  echo "  $0 \"${PROJECT_ROOT}/.derivedData/Build/Products/Debug/${APP_NAME}.app\"" >&2
  exit 1
fi

if ! codesign_ok "$SRC_APP" && [[ "$ALLOW_UNSIGNED_INSTALL" != "1" ]]; then
  echo "Source app is not validly signed: ${SRC_APP}" >&2
  echo "Refusing install by default to avoid TCC permission churn." >&2
  echo "If you explicitly want unsigned install, set AETHER_ALLOW_UNSIGNED_INSTALL=1." >&2
  exit 3
fi

echo "Installing:"
echo "  from: ${SRC_APP}"
echo "  to:   ${DEST_APP}"

if [[ -d "$DEST_APP" ]]; then
  echo "Removing existing: ${DEST_APP}"
  rm -rf "$DEST_APP"
fi

if ! /usr/bin/ditto "$SRC_APP" "$DEST_APP" 2>/dev/null; then
  echo "Failed to write to /Applications. Re-run with sudo:" >&2
  echo "  sudo \"$0\" \"$SRC_APP\"" >&2
  exit 2
fi

/usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" >/dev/null 2>&1 || true

echo ""
echo "codesign verify:"
if /usr/bin/codesign --verify --deep --strict "$DEST_APP" >/dev/null 2>&1; then
  echo "  OK"
else
  echo "  FAIL"
  if [[ "$ALLOW_UNSIGNED_INSTALL" != "1" ]]; then
    echo "Installed app is not validly signed; aborting." >&2
    exit 4
  fi
fi

echo ""
echo "Entitlements check:"
/usr/bin/codesign -d --entitlements :- "$DEST_APP" 2>/dev/null | /usr/bin/grep -n "audio-input\\|speech-recognition" || true

echo ""
echo "Done. Launch with:"
echo "  open -n \"$DEST_APP\""
