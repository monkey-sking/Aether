#!/bin/bash

# ============================================================
# Notarize.sh - Aether Automated Notarization Script
# ============================================================
# This script handles:
#   1. Building the release version
#   2. Code signing with hardened runtime
#   3. Submitting to Apple for notarization
#   4. Stapling the ticket to the app
# ============================================================

set -euo pipefail

# --- Configuration ---
APP_NAME="Aether"
BUNDLE_ID="com.7fei.Aether"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"          # Set via environment variable
APPLE_ID="${APPLE_ID:-your@email.com}"      # Set via environment variable
APP_PASSWORD="${APP_PASSWORD:-}"            # App-specific password from App Store Connect
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"    # e.g. "Developer ID Application: Company Name (TEAMID)"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
ZIP_PATH="${BUILD_DIR}/${APP_NAME}.zip"

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

check_requirements() {
    log_info "Checking requirements..."
    
    if [[ -z "$TEAM_ID" || "$TEAM_ID" == "YOUR_TEAM_ID" ]]; then
        log_error "TEAM_ID not set. Export it as an environment variable."
    fi
    
    if [[ -z "$APPLE_ID" || "$APPLE_ID" == "your@email.com" ]]; then
        log_error "APPLE_ID not set. Export it as an environment variable."
    fi
    
    if [[ -z "$APP_PASSWORD" ]]; then
        log_error "APP_PASSWORD not set. Create an app-specific password in Apple ID settings."
    fi
    
    if ! command -v xcrun &> /dev/null; then
        log_error "Xcode command line tools not found."
    fi
    
    log_success "All requirements met."
}

build_release() {
    log_info "Building release version..."
    
    "${PROJECT_ROOT}/Scripts/BuildRelease.sh" Release
    "${PROJECT_ROOT}/Scripts/PrepareAppBundle.sh" "${APP_PATH}"
    
    log_success "Build complete."
}

create_app_bundle() {
    # xcodebuild creates the bundle, but we might need to finalize Info.plist if not fully populated
    # For Aether, xcodebuild should handle it. 
    # Just verifying existence.
    log_info "Verifying app bundle..."
    
    if [[ ! -d "$APP_PATH" ]]; then
        log_error "App bundle missing."
    fi

    log_success "App bundle verified at ${APP_PATH}"
}

code_sign() {
    log_info "Code signing with hardened runtime..."

    if [[ -z "$SIGNING_IDENTITY" ]]; then
        log_error "SIGNING_IDENTITY not set. Example: export SIGNING_IDENTITY='Developer ID Application: Company Name (${TEAM_ID})'"
    fi
    
    # Sign frameworks and plugins first (if any) inside the bundle
    # Note: --deep usually handles this, but manual signing is safer for complex structures
    
    codesign --force --deep --options runtime --timestamp \
        --sign "$SIGNING_IDENTITY" \
        --entitlements "${PROJECT_ROOT}/Apps/AetherCore/AetherCore.entitlements" \
        "$APP_PATH"

    codesign --verify --deep --strict --verbose=2 "$APP_PATH" >/dev/null
    
    log_success "Code signing complete."
}

package_for_notarization() {
    log_info "Creating ZIP for notarization..."
    
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
    
    log_success "ZIP created at ${ZIP_PATH}"
}

submit_for_notarization() {
    log_info "Submitting to Apple for notarization..."
    
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    
    log_success "Notarization submitted."
}

staple_ticket() {
    log_info "Stapling notarization ticket..."
    
    xcrun stapler staple "$APP_PATH"
    
    log_success "Ticket stapled. App is ready for distribution."
}

# --- Main Execution ---
main() {
    echo ""
    echo "========================================"
    echo "   Aether Notarization Script"
    echo "========================================"
    echo ""
    
    check_requirements
    build_release
    create_app_bundle
    code_sign
    package_for_notarization
    submit_for_notarization
    staple_ticket
    
    echo ""
    log_success "🎉 Notarization complete! App is ready at: ${APP_PATH}"
    echo ""
}

main "$@"
