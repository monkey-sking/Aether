#!/bin/bash

# Configuration
APP_NAME="Aether"
BUILD_DIR=".build/release"
DERIVED_DATA="/tmp/aether_dev_build"

echo "🚀 Starting Rapid Dev Build... (v0.1.7+)"

# 1. Build Release (Faster than DMG)
echo "Building ${APP_NAME}..."
./Scripts/BuildRelease.sh

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Aborting deployment."
    exit 1
fi

# 2. Report built artifact
if [ -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    echo "✅ Build complete: ${BUILD_DIR}/${APP_NAME}.app"
    echo "Manual install remains explicit. Use ./Scripts/InstallToApplications.sh when needed."
else
    echo "❌ Built app not found at ${BUILD_DIR}/${APP_NAME}.app"
    exit 1
fi
