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

## 🏗️ Build Command

To build the application in **Release** mode:

```bash
./Scripts/BuildRelease.sh Release
```

### What this script does:
1.  **Sets Environment**: Configures build directories to `.build/release`.
2.  **Builds Driver**: Compiles `AetherDriver` (DriverKit) and `AetherDriver.dext`.
3.  **Builds App**: Compiles `Aether.app`.
4.  **Updates Version**: Triggers `Scripts/UpdateVersion.sh` (Xcode Build Phase) to:
    -   Set `CFBundleVersion` to the current timestamp (e.g., `202402091545`).
    -   **Re-sign** the app bundle to validate the modified `Info.plist`.

## 📂 Output

-   **App Bundle**: `.build/release/Aether.app`
-   **Driver Extension**: Inside `Aether.app/Contents/Library/SystemExtensions/`

---

## ✅ Verification Steps

After building, verify the following:

### 1. Dynamic Versioning
Check that the build version is the current timestamp:
```bash
defaults read .build/release/Aether.app/Contents/Info CFBundleVersion
# Expected output: YYYYMMDDHHMM (e.g. 202402091545)
```

### 2. Code Signature
Ensure the re-signing process worked and the app is valid:
```bash
codesign -vvv --deep --strict .build/release/Aether.app
# Expected output: valid on disk / satisfies its Designated Requirement
```

### 3. Driver Presence
Ensure the System Extension is embedded:
```bash
ls -l .build/release/Aether.app/Contents/Library/SystemExtensions/
# Should show: com.7fei.Aether.AetherDriver.dext
```

---

## 🛠️ Troubleshooting

### "Invalid Info.plist" or Crash on Launch
This usually means the `UpdateVersion.sh` script modified the plist *after* signing but failed to re-sign.
**Fix**: Ensure `EXPANDED_CODE_SIGN_IDENTITY` is correctly passed to the script during the build. Check the build logs for "Re-signing with identity".

### "System Extension Not Found"
The driver (`.dext`) was not copied into the app bundle.
**Fix**: Check the `Embed AetherDriver` build phase in Xcode.
