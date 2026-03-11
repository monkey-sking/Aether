#!/bin/bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_PNG="${PROJECT_ROOT}/Apps/AetherCore/Assets.xcassets/AppIcon.appiconset/icon_512@2x.png"
OUT_DIR="${PROJECT_ROOT}/Scripts/Resources"
OUT_ICNS="${OUT_DIR}/Aether.icns"

if [[ ! -f "$SRC_PNG" ]]; then
  echo "Missing source PNG: ${SRC_PNG}" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# `iconutil` rejects some iconsets in constrained environments; `sips` can write a valid `.icns` directly.
/usr/bin/sips -s format icns "$SRC_PNG" --out "$OUT_ICNS" >/dev/null

echo "OK: ${OUT_ICNS}"
