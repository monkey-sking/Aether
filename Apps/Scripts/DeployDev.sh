#!/bin/bash

# Configuration
APP_NAME="Aether"
BUILD_DIR=".build/release"
INSTALL_PATH="/Applications/${APP_NAME}.app"
DERIVED_DATA="/tmp/aether_dev_build"

echo "🚀 Starting Rapid Dev Deployment... (v0.1.7+)"

# 1. Kill existing process
echo "Stopping ${APP_NAME}..."
pkill -x "${APP_NAME}" || true
sleep 1

# 2. Build Release (Faster than DMG)
echo "Building ${APP_NAME}..."
./Scripts/BuildRelease.sh

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Aborting deployment."
    exit 1
fi

# 3. Synchronize to /Applications
echo "Installing to ${INSTALL_PATH}..."
# Use rsync to preserve permissions and only copy changed files
if [ -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    cp -R "${BUILD_DIR}/${APP_NAME}.app" /Applications/
else
    echo "❌ Built app not found at ${BUILD_DIR}/${APP_NAME}.app"
    exit 1
fi

# 4. Launch the app
echo "Launching ${APP_NAME}..."
open "${INSTALL_PATH}"

echo "✅ Ready for testing!"
