#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/.build/release"
IME_BUILD_APP="${PROJECT_ROOT}/.build/ime/AetherIME.app"
PKG_ROOT="${PROJECT_ROOT}/.build/pkgroot-ime"
SCRIPTS_DIR="${PROJECT_ROOT}/Scripts/Installer/IME"
OUTPUT_PKG="${BUILD_DIR}/AetherIME.pkg"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
INSTALLER_SIGN_KEYCHAIN="${INSTALLER_SIGN_KEYCHAIN:-}"

mkdir -p "${BUILD_DIR}"
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}/Library/Input Methods"

echo "Building IME app bundle..."
"${PROJECT_ROOT}/Scripts/BuildInstallIME.sh" --build-only

if [[ ! -d "${IME_BUILD_APP}" ]]; then
  echo "IME build missing: ${IME_BUILD_APP}" >&2
  exit 1
fi

echo "Staging payload..."
/usr/bin/ditto --norsrc "${IME_BUILD_APP}" "${PKG_ROOT}/Library/Input Methods/AetherIME.app"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${IME_BUILD_APP}/Contents/Info.plist" 2>/dev/null || echo "1")"

echo "Creating pkg..."
pkgbuild \
  --root "${PKG_ROOT}" \
  --identifier "com.7fei.aether.ime.pkg" \
  --version "${VERSION}" \
  --ownership recommended \
  --install-location "/" \
  --scripts "${SCRIPTS_DIR}" \
  "${OUTPUT_PKG}"

if [[ -n "${INSTALLER_SIGN_IDENTITY}" ]]; then
  SIGNED_PKG="${BUILD_DIR}/AetherIME-signed.pkg"
  echo "Signing pkg with identity: ${INSTALLER_SIGN_IDENTITY}"
  PRODUCTSIGN_ARGS=(--sign "${INSTALLER_SIGN_IDENTITY}")
  if [[ -n "${INSTALLER_SIGN_KEYCHAIN}" ]]; then
    PRODUCTSIGN_ARGS+=(--keychain "${INSTALLER_SIGN_KEYCHAIN}")
  fi
  productsign "${PRODUCTSIGN_ARGS[@]}" "${OUTPUT_PKG}" "${SIGNED_PKG}"
  mv -f "${SIGNED_PKG}" "${OUTPUT_PKG}"
fi

/usr/sbin/pkgutil --check-signature "${OUTPUT_PKG}" || true

echo "✅ IME pkg ready: ${OUTPUT_PKG}"
