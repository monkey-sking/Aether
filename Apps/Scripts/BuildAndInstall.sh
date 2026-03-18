#!/bin/bash

# Build and Install Script for Aether
# This script:
# 1. Runs the release build and packaging script.
# 2. Terminates the currently running Aether process.
# 3. Installs the new version to /Applications.
# 4. Relaunches Aether.

set -euo pipefail

APP_NAME="Aether"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
APP_SOURCE="${BUILD_DIR}/${APP_NAME}.app"
INSTALL_TARGET="/Applications/${APP_NAME}.app"

log() { echo "[install] $*"; }
error() { echo "[install] ERROR: $*" >&2; exit 1; }

# 1. Run the build script
log "Starting production build..."
# Pass current environment variables to skip notarization for speed if needed
chmod +x "${PROJECT_ROOT}/Scripts/ReleaseForUsers.sh"
SKIP_NOTARIZE=1 AETHER_UNSIGNED=1 "${PROJECT_ROOT}/Scripts/ReleaseForUsers.sh"

# 2. Check if build succeeded
if [[ ! -d "$APP_SOURCE" ]]; then
    error "Build failed or app not found at ${APP_SOURCE}"
fi

# 3. Terminate running Aether process
log "Closing running Aether processes..."
pkill -x "$APP_NAME" || log "No running $APP_NAME process found."

# Wait a moment for process to fully exit
sleep 1

# 4. Install to /Applications
log "Installing ${APP_NAME} to ${INSTALL_TARGET}..."
# Use sudo if permission is needed, but try without first as user likely has /Applications access
rm -rf "$INSTALL_TARGET"
cp -R "$APP_SOURCE" "$INSTALL_TARGET"

# 5. Relaunch Aether
log "Relaunching ${APP_NAME}..."
open "$INSTALL_TARGET"

log "🎉 Build, Install, and Restart successful!"
