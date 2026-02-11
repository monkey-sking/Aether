#!/bin/bash

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/aether_xcodebuild_deriveddata}"

CONFIGURATION="${1:-Release}"

if [[ "$CONFIGURATION" != "Release" && "$CONFIGURATION" != "Debug" ]]; then
  echo "Usage: $(basename "$0") [Release|Debug]" >&2
  exit 2
fi

mkdir -p "$BUILD_DIR"
mkdir -p "$DERIVED_DATA_PATH"

echo "Building ${APP_NAME} (${CONFIGURATION}) -> ${BUILD_DIR}"
echo "Tip: set signing in Xcode (Signing & Capabilities)."

cd "$PROJECT_ROOT"
EXTRA_BUILD_FLAGS=()
if [[ "${AETHER_UNSIGNED:-0}" == "1" ]]; then
  EXTRA_BUILD_FLAGS+=(
    "CODE_SIGNING_ALLOWED=NO"
    "CODE_SIGNING_REQUIRED=NO"
    "AD_HOC_CODE_SIGNING_ALLOWED=YES"
  )
  echo "Unsigned build: CODE_SIGNING_ALLOWED=NO"
fi

xcodebuild -project Aether.xcodeproj \
  -scheme Aether \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"}

if [[ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]]; then
  echo "Build finished but ${APP_NAME}.app not found at ${BUILD_DIR}/${APP_NAME}.app" >&2
  exit 1
fi

echo "OK: ${BUILD_DIR}/${APP_NAME}.app"
