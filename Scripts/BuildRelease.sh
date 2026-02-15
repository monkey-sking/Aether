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

resolve_destination() {
  local preferred_arch="${AETHER_BUILD_ARCH:-$(uname -m)}"
  local destinations
  destinations="$(xcodebuild -project Aether.xcodeproj -scheme Aether -showdestinations 2>/dev/null || true)"

  if [[ "$destinations" == *"platform:macOS, arch:${preferred_arch}"* ]]; then
    echo "platform=macOS,arch=${preferred_arch}"
    return
  fi

  if [[ "$destinations" == *"platform:macOS, arch:arm64"* ]]; then
    echo "platform=macOS,arch=arm64"
    return
  fi

  if [[ "$destinations" == *"platform:macOS, arch:x86_64"* ]]; then
    echo "platform=macOS,arch=x86_64"
    return
  fi

  echo "platform=macOS"
}

DESTINATION="${AETHER_DESTINATION:-$(resolve_destination)}"
echo "Using destination: ${DESTINATION}"

run_xcodebuild() {
  xcodebuild -project Aether.xcodeproj \
    -scheme Aether \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    STRIP_INSTALLED_PRODUCT=NO \
    ${1+"$@"}
}

set +e
run_xcodebuild ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"}
build_status=$?
set -e

if [[ $build_status -ne 0 && "${AETHER_UNSIGNED:-0}" != "1" ]]; then
  echo "Signed build failed. Retrying unsigned build..."
  set +e
  run_xcodebuild \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    AD_HOC_CODE_SIGNING_ALLOWED=YES
  build_status=$?
  set -e
fi

if [[ $build_status -ne 0 ]]; then
  exit $build_status
fi

if [[ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]]; then
  echo "Build finished but ${APP_NAME}.app not found at ${BUILD_DIR}/${APP_NAME}.app" >&2
  exit 1
fi

echo "OK: ${BUILD_DIR}/${APP_NAME}.app"
