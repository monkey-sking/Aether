---
name: build_aether
description: Builds the Aether macOS application with dynamic versioning and embedded driver.
---

# Build Aether App

This skill documents the procedure to build the **Aether** application, ensuring the System Extension (Driver) is correctly embedded and the version number is dynamically updated.

## Prerequisites
- macOS 15.0+
- Xcode 16+
- Valid Developer ID Application Certificate
- **Provisioning Profiles** installed:
  - `Aether Development` (or Release)
  - `AetherDriver Development` (or Release)

---

## 🏗️ Build Commands

### 1. Standard Release Build
To build the application in **Release** mode for local verification:

```bash
./Scripts/BuildRelease.sh Release
```

### 2. Full User Release (Recommended for Distribution)
To build, sign, and package the app for users (includes DMG and ZIP):

```bash
./Scripts/ReleaseForUsers.sh
```
> [!TIP]
> Use `SKIP_NOTARIZE=1 ./Scripts/ReleaseForUsers.sh` if you want to skip the notarization step for quick testing.

---

## 📂 Output

- **App Bundle**: `.build/release/Aether.app`
- **DMG Installer**: `.build/release/Aether_Installer.dmg`
- **ZIP Package**: `.build/release/Aether.zip`

---

## ✅ Verification Steps

### 1. Dynamic Versioning
Check that the build version is the current timestamp:
```bash
defaults read $(pwd)/.build/release/Aether.app/Contents/Info CFBundleVersion
```

### 2. Code Signature
Ensure the app is validly signed:
```bash
codesign -vvv --deep --strict .build/release/Aether.app
```

---

## 🛠️ Troubleshooting

### "Invalid Info.plist" or Crash on Launch
This usually means the `UpdateVersion.sh` script modified the plist *after* signing but failed to re-sign.
**Fix**: Ensure `EXPANDED_CODE_SIGN_IDENTITY` is correctly passed to the script during the build.

### "System Extension Not Found"
The driver (`.dext`) was not copied into the app bundle.
**Fix**: Check the `Embed AetherDriver` build phase in Xcode.
