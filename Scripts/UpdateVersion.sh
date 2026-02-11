#!/bin/bash
# Get current date in YYYYMMDDHHMM format (e.g., 202402091530)
BUILD_NUMBER=$(date +%Y%m%d%H%M)

echo "Configuration: $CONFIGURATION"
echo "Target Build Dir: $TARGET_BUILD_DIR"
echo "Info Plist Path: $INFOPLIST_PATH"

# Path to the BUILT Info.plist
PLIST_PATH="$TARGET_BUILD_DIR/$INFOPLIST_PATH"

if [ -f "$PLIST_PATH" ]; then
    echo "Updating $PLIST_PATH with version $BUILD_NUMBER"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST_PATH"
else
    echo "Error: Info.plist not found at $PLIST_PATH"
    exit 1
fi

# Optional: Update dSYM Info.plist if it exists
DSYM_PLIST="$DWARF_DSYM_FOLDER_PATH/$DWARF_DSYM_FILE_NAME/Contents/Info.plist"
if [ -f "$DSYM_PLIST" ]; then
    echo "Updating dSYM Info.plist with version $BUILD_NUMBER"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$DSYM_PLIST"
fi

# CRITICAL: Re-sign the application after modifying Info.plist
# Because this script runs after the compiled binary is signed (or invalidates it),
# we must manually re-sign to ensure the app can launch.
if [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then
    echo "Re-signing with identity: $EXPANDED_CODE_SIGN_IDENTITY"
    codesign -f -s "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags --generate-entitlement-der "$TARGET_BUILD_DIR/$WRAPPER_NAME"
    echo "Re-signing complete."
else
    echo "Warning: No code signing identity found (EXPANDED_CODE_SIGN_IDENTITY is empty). App may not launch."
fi
