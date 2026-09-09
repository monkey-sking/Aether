#!/bin/bash

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLE_RELEASE_HOME="${APPLE_RELEASE_HOME:-$HOME/apple-release}"
[[ -f "$APPLE_RELEASE_HOME/lib/artifact-verification.sh" ]] && source "$APPLE_RELEASE_HOME/lib/artifact-verification.sh"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$HOME/Library/Caches/apple-release/aether/macos-release/DerivedData}"
ALLOW_UNSIGNED_FALLBACK="${AETHER_ALLOW_UNSIGNED_FALLBACK:-0}"
CLANG_WRAPPER_PATH="${PROJECT_ROOT}/Scripts/XcodeClangWrapper.sh"
USE_CLANG_WRAPPER="${AETHER_USE_XCODEBUILD_CLANG_WRAPPER:-1}"

CONFIGURATION="${1:-Release}"

if [[ "$CONFIGURATION" != "Release" && "$CONFIGURATION" != "Debug" ]]; then
  echo "Usage: $(basename "$0") [Release|Debug]" >&2
  exit 2
fi

mkdir -p "$BUILD_DIR"
mkdir -p "$DERIVED_DATA_PATH"

if [[ "$USE_CLANG_WRAPPER" == "1" ]]; then
  chmod +x "$CLANG_WRAPPER_PATH"
fi

# Use second-resolution build numbers so repeated builds within the same minute
# still produce a unique Sparkle version.
BUILD_NUMBER=$(date +%Y%m%d%H%M%S)
UNIVERSAL_BUILD="${AETHER_UNIVERSAL:-0}"
ENABLE_APP_INTENTS_METADATA_EXTRACTION="${AETHER_ENABLE_APP_INTENTS_METADATA_EXTRACTION:-0}"

echo "Building ${APP_NAME} (${CONFIGURATION}) -> ${BUILD_DIR}"
echo "Tip: set signing in Xcode (Signing & Capabilities)."

cd "$PROJECT_ROOT"
EXTRA_BUILD_FLAGS=(
  "GCC_GENERATE_TEST_COVERAGE_FILES=NO"
  "GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO"
  "CLANG_COVERAGE_MAPPING=NO"
  "CLANG_ENABLE_CODE_COVERAGE=NO"
  "ENABLE_CODE_COVERAGE=NO"
  "ENABLE_TESTABILITY=NO"
  "CLANG_PROFILE_INSTR_GENERATE=NO"
  "GENERATE_PROFILING_CODE=NO"
  "OTHER_CFLAGS=-fno-profile-instr-generate"
  "OTHER_CPLUSPLUSFLAGS=-fno-profile-instr-generate"
  "OTHER_LDFLAGS=-fno-profile-instr-generate"
  "LLVM_LTO=NO"
  "ENABLE_PREVIEWS=NO"
  "CLANG_USE_OPTIMIZATION_PROFILE=NO"
  "ENABLE_APP_INTENTS_METADATA_EXTRACTION=${ENABLE_APP_INTENTS_METADATA_EXTRACTION}"
)

if [[ "${ENABLE_APP_INTENTS_METADATA_EXTRACTION}" != "1" ]]; then
  EXTRA_BUILD_FLAGS+=(
    'OTHER_SWIFT_FLAGS=$(inherited) -DAETHER_DISABLE_APP_INTENTS'
  )
fi
if [[ "$USE_CLANG_WRAPPER" == "1" && -z "${CC:-}" ]]; then
  # Xcode 26.4 CLI builds can deadlock in the initial `clang -v -E -dM`
  # toolchain probe unless the compiler path is routed through a wrapper.
  EXTRA_BUILD_FLAGS+=(
    "CC=${CLANG_WRAPPER_PATH}"
  )
fi
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
if [[ "$UNIVERSAL_BUILD" == "1" ]]; then
  DESTINATION="${AETHER_DESTINATION:-platform=macOS}"
  EXTRA_BUILD_FLAGS+=(
    "ARCHS=arm64 x86_64"
    "ONLY_ACTIVE_ARCH=NO"
  )
fi
echo "Using destination: ${DESTINATION}"
if [[ "${ENABLE_APP_INTENTS_METADATA_EXTRACTION}" == "1" ]]; then
  echo "App Intents metadata extraction: enabled"
else
  echo "App Intents metadata extraction: disabled"
fi

run_xcodebuild() {
  xcodebuild -project Aether.xcodeproj \
    -scheme Aether \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    STRIP_INSTALLED_PRODUCT=NO \
    ${1+"$@"}
}

set +e
run_xcodebuild ${EXTRA_BUILD_FLAGS[@]+"${EXTRA_BUILD_FLAGS[@]}"}
build_status=$?
set -e

if [[ $build_status -ne 0 && "${AETHER_UNSIGNED:-0}" != "1" ]]; then
  if [[ "$ALLOW_UNSIGNED_FALLBACK" == "1" ]]; then
    echo "Signed build failed. Retrying unsigned build because AETHER_ALLOW_UNSIGNED_FALLBACK=1..."
    set +e
    run_xcodebuild \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO \
      AD_HOC_CODE_SIGNING_ALLOWED=YES
    build_status=$?
    set -e
  else
    echo "Signed build failed. Refusing unsigned fallback by default." >&2
    echo "If you explicitly want unsigned output, set AETHER_UNSIGNED=1" >&2
    echo "or allow fallback by setting AETHER_ALLOW_UNSIGNED_FALLBACK=1." >&2
    exit $build_status
  fi
fi

if [[ $build_status -ne 0 ]]; then
  exit $build_status
fi

if [[ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]]; then
  echo "Build finished but ${APP_NAME}.app not found at ${BUILD_DIR}/${APP_NAME}.app" >&2
  exit 1
fi

if [[ "${AETHER_UNSIGNED:-0}" != "1" ]]; then
  apple_release_verify_app "${BUILD_DIR}/${APP_NAME}.app"
fi

echo "OK: ${BUILD_DIR}/${APP_NAME}.app"
