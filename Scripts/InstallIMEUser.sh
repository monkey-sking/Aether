#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IME_APP="${PROJECT_ROOT}/.build/ime/AetherIME.app"
TARGET_DIR="${HOME}/Library/Input Methods"
TARGET_APP="${TARGET_DIR}/AetherIME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
SOURCE_ENTRY='{ "Bundle ID" = "com.sevenfei.inputmethod.aether"; InputSourceKind = "Keyboard Input Method"; }'

echo "Building IME app bundle..."
"${PROJECT_ROOT}/Scripts/BuildInstallIME.sh" --build-only

mkdir -p "${TARGET_DIR}"
rm -rf "${TARGET_APP}"
cp -R "${IME_APP}" "${TARGET_APP}"

echo "Refreshing input source cache..."
"${LSREGISTER}" -f -R -trusted "${TARGET_APP}" || true
/usr/bin/killall TextInputMenuAgent || true

echo "Adding Aether IME to enabled input sources..."
if ! defaults read com.apple.HIToolbox AppleInputSourceHistory 2>/dev/null | grep -q "com.sevenfei.inputmethod.aether"; then
  defaults write com.apple.HIToolbox AppleInputSourceHistory -array-add "${SOURCE_ENTRY}" || true
fi
if ! defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q "com.sevenfei.inputmethod.aether"; then
  defaults write com.apple.HIToolbox AppleEnabledInputSources -array-add "${SOURCE_ENTRY}" || true
fi
defaults write com.apple.HIToolbox AppleSelectedInputSources -array "${SOURCE_ENTRY}" || true
/usr/bin/killall cfprefsd || true
/usr/bin/killall TextInputMenuAgent || true

echo "✅ User-level IME installed: ${TARGET_APP}"
echo "Open: System Settings -> Keyboard -> Input Sources"
