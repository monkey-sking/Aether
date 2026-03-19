#!/bin/bash

# Build Script for Aether
# This script:
# 1. Runs the release build and packaging script.
# 2. Leaves the built artifacts in .build/release for manual install/testing.

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
APP_SOURCE="${BUILD_DIR}/${APP_NAME}.app"

log() { echo "[build] $*"; }
error() { echo "[build] ERROR: $*" >&2; exit 1; }

# 1. Run the build script
log "Starting production build..."
# Pass current environment variables to skip notarization for speed if needed
chmod +x "${PROJECT_ROOT}/Scripts/ReleaseForUsers.sh"
SKIP_NOTARIZE=1 AETHER_UNSIGNED=1 "${PROJECT_ROOT}/Scripts/ReleaseForUsers.sh"

# 2. Check if build succeeded
if [[ ! -d "$APP_SOURCE" ]]; then
    error "Build failed or app not found at ${APP_SOURCE}"
fi

log "Build completed."
log "App: ${APP_SOURCE}"
log "DMG: ${BUILD_DIR}/${APP_NAME}_Installer.dmg"
log "ZIP: ${BUILD_DIR}/${APP_NAME}.zip"
log "Manual install remains explicit. Use Scripts/InstallToApplications.sh if needed."
