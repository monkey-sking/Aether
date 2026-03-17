#!/bin/bash

# ============================================================
# CreateDMG.sh - Aether Branded DMG Generator
# ============================================================
# This script creates a professional-looking DMG installer:
#   1. Creates a temporary disk image
#   2. Sets up the Applications shortcut
#   3. Applies custom background and icon layout
#   4. Converts to compressed read-only DMG
# ============================================================

set -euo pipefail

# --- Configuration ---
APP_NAME="Aether"
DMG_NAME="${APP_NAME}_Installer"
VOLUME_NAME="${APP_NAME}"
BACKGROUND_IMAGE="${PROJECT_ROOT:-$(dirname "$0")/..}/Scripts/Resources/dmg_background.png"
ICON_SIZE=128
WINDOW_WIDTH=600
WINDOW_HEIGHT=400
ICON_X=150
ICON_Y=200
APPS_X=450
APPS_Y=200

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_OUTPUT="${BUILD_DIR}/${DMG_NAME}.dmg"
TEMP_DMG="${BUILD_DIR}/temp_${DMG_NAME}.dmg"
MOUNT_POINT="/Volumes/${VOLUME_NAME}"
ATTACH_DEV=""

# --- Helper Functions ---
log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✅ $1"
}

log_error() {
    echo "❌ $1" >&2
    exit 1
}

cleanup() {
    log_info "Cleaning up..."
    if [[ -n "${ATTACH_DEV}" ]]; then
        hdiutil detach "${ATTACH_DEV}" -force -quiet 2>/dev/null || true
    fi
    hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null || true
    rm -f "$TEMP_DMG"
}

trap cleanup EXIT

check_app() {
    if [[ ! -d "$APP_PATH" ]]; then
        log_error "App not found at ${APP_PATH}. Run Scripts/BuildRelease.sh first."
    fi
}

create_temp_dmg() {
    log_info "Creating temporary disk image..."
    
    local SIZE_MB=100
    
    hdiutil create -size ${SIZE_MB}m -fs HFS+ -volname "$VOLUME_NAME" "$TEMP_DMG"
    ATTACH_DEV="$(hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse | awk 'NR==1{print $1}')"
    
    log_success "Temporary DMG mounted at ${MOUNT_POINT}"
}

copy_contents() {
    log_info "Copying app and creating Applications link..."
    
    # Only "prepare" (embed .icns + ad-hoc re-sign) when the build lacks asset catalogs,
    # otherwise we would invalidate a proper Xcode/DeveloperID signature.
    if [[ "${AETHER_PREPARE_BUNDLE:-0}" == "1" || ! -f "${APP_PATH}/Contents/Resources/Assets.car" ]]; then
        "${PROJECT_ROOT}/Scripts/PrepareAppBundle.sh" "$APP_PATH" >/dev/null || true
    fi

    cp -R "$APP_PATH" "${MOUNT_POINT}/"
    ln -s /Applications "${MOUNT_POINT}/Applications"
    
    log_success "Contents copied."
}

setup_background() {
    log_info "Setting up background image..."
    
    mkdir -p "${MOUNT_POINT}/.background"
    
    if [[ -f "$BACKGROUND_IMAGE" ]]; then
        cp "$BACKGROUND_IMAGE" "${MOUNT_POINT}/.background/background.png"
    else
        log_info "No background image found at ${BACKGROUND_IMAGE}, skipping..."
    fi
}

configure_view() {
    log_info "Configuring Finder view options..."
    
    # Use AppleScript to set view options
    osascript << EOF || true
tell application "Finder"
    try
        tell disk "${VOLUME_NAME}"
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {100, 100, 100 + ${WINDOW_WIDTH}, 100 + ${WINDOW_HEIGHT}}
            set viewOptions to the icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to ${ICON_SIZE}
            
            -- Set icon positions
            set position of item "${APP_NAME}.app" of container window to {${ICON_X}, ${ICON_Y}}
            set position of item "Applications" of container window to {${APPS_X}, ${APPS_Y}}
            
            -- Set background if exists
            if exists file ".background:background.png" then
                set background picture of viewOptions to file ".background:background.png"
            end if
            
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end try
end tell
EOF
    
    # Set volume icon if available
    # For now we use the app icon itself if explicit .icns resource not present
    if [[ -f "${PROJECT_ROOT}/Scripts/Resources/Aether.icns" ]]; then
        cp "${PROJECT_ROOT}/Scripts/Resources/Aether.icns" "${MOUNT_POINT}/.VolumeIcon.icns"
        SetFile -c icnC "${MOUNT_POINT}/.VolumeIcon.icns"
        SetFile -a C "${MOUNT_POINT}"
    fi

    log_success "Finder view configured."
}

finalize_dmg() {
    log_info "Finalizing DMG..."
    
    # Sync and unmount
    sync
    # Finder/Spotlight can keep the volume busy; detach with retries and force if needed.
    for i in 1 2 3 4 5; do
        if hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null; then
            break
        fi
        if [[ -n "${ATTACH_DEV}" ]] && hdiutil detach "${ATTACH_DEV}" -quiet 2>/dev/null; then
            break
        fi
        sleep 1
        if hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null; then
            break
        fi
        if [[ -n "${ATTACH_DEV}" ]] && hdiutil detach "${ATTACH_DEV}" -force -quiet 2>/dev/null; then
            break
        fi
    done
    
    # Convert to compressed read-only DMG
    rm -f "$DMG_OUTPUT"
    hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUTPUT"
    
    log_success "DMG created at ${DMG_OUTPUT}"
}

# --- Main Execution ---
main() {
    echo ""
    echo "========================================"
    echo "   Aether DMG Creator"
    echo "========================================"
    echo ""
    
    check_app
    create_temp_dmg
    copy_contents
    setup_background
    configure_view
    finalize_dmg
    
    echo ""
    log_success "🎉 DMG ready for distribution: ${DMG_OUTPUT}"
    echo ""
}

main "$@"
