#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IME_ROOT="$ROOT_DIR/InputMethod/AetherIME"
SRC_DIR="$IME_ROOT/Sources"
BUILD_DIR="$ROOT_DIR/.build/ime"
APP_DIR="$BUILD_DIR/AetherIME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/module-cache"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_DIR="${AETHER_IME_INSTALL_DIR:-$HOME/Library/Input Methods}"
BUILD_ONLY="${1:-}"
IME_SIGN_IDENTITY="${IME_SIGN_IDENTITY:-}"
IME_SIGN_KEYCHAIN="${IME_SIGN_KEYCHAIN:-}"

echo "Building AetherIME..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$MODULE_CACHE_DIR"
cp "$IME_ROOT/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -f "$ROOT_DIR/Scripts/Resources/MenuBarIcon.png" ]]; then
  # Keep a fixed-size icon for Input Source list/menu to avoid oversized rendering.
  sips -z 16 16 "$ROOT_DIR/Scripts/Resources/MenuBarIcon.png" --out "$RESOURCES_DIR/ime_icon.png" >/dev/null
fi
if [[ -d "$IME_ROOT/Resources" ]]; then
  cp -R "$IME_ROOT/Resources/." "$RESOURCES_DIR/"
fi

swiftc \
  -O \
  -sdk "$SDK_PATH" \
  -module-name "AetherIME" \
  -module-cache-path "$MODULE_CACHE_DIR" \
  -framework Cocoa \
  -framework InputMethodKit \
  "$SRC_DIR/main.swift" \
  "$SRC_DIR/AetherInputController.swift" \
  -o "$MACOS_DIR/AetherIME"

# Sign bundle.
if [[ -n "$IME_SIGN_IDENTITY" ]]; then
  echo "Signing IME with identity: $IME_SIGN_IDENTITY"
  SIGN_ARGS=(--force --deep --options runtime --timestamp --sign "$IME_SIGN_IDENTITY")
  if [[ -n "$IME_SIGN_KEYCHAIN" ]]; then
    SIGN_ARGS+=(--keychain "$IME_SIGN_KEYCHAIN")
  fi
  /usr/bin/codesign "${SIGN_ARGS[@]}" "$APP_DIR"
else
  echo "Signing IME with ad-hoc identity (-)."
  /usr/bin/codesign --force --deep --sign - "$APP_DIR"
fi

/usr/bin/codesign --verify --deep --strict "$APP_DIR"

if [[ "$BUILD_ONLY" == "--build-only" ]]; then
  echo "Build only mode complete: $APP_DIR"
  exit 0
fi

echo "Installing to: $TARGET_DIR"
mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_DIR/AetherIME.app"
cp -R "$APP_DIR" "$TARGET_DIR/AetherIME.app"

echo "Done."
echo "Next:"
echo "1) Log out/in or reboot."
echo "2) System Settings -> Keyboard -> Input Sources -> add 'Aether IME'."
