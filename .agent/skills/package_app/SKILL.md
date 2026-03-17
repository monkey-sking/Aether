---
name: package_app
description: Builds, packages, and releases the Aether macOS application for distribution and local testing.
---

# Package & Release Aether App

This skill provides the standard procedure to build, package, sign, notarize, and release the **Aether** application.

## Prerequisites
- macOS 15.0+
- Xcode 16+
- Developer ID Certificate installed
- `create-dmg` installed (`brew install create-dmg`)

---

## 🚀 Release Build (Production)

### ⚠️ Pre-Release Checklist (CRITICAL)

Before running the release script, **YOU MUST** verify the following:

1.  **Version Bump**:
    *   [ ] Verify `CFBundleShortVersionString` in `Apps/Aether/Info.plist`.
2.  **Git Check**:
    *   [ ] Ensure all project code changes are committed `git status`.

### Full Packaging Script
For a complete signed and packaged DMG:

```bash
./Scripts/ReleaseForUsers.sh
```

### Local Development Deployment
To build and deploy to `/Applications` for testing:

```bash
./Scripts/DeployDev.sh
```

---

## 🌐 Deploy to Website

After release build, deploy to **aether.7caifei.com** via Vercel (if applicable).

---

## 🔍 Troubleshooting

### Script Permission
```bash
chmod +x Scripts/*.sh
```

### Clean Build
```bash
rm -rf .build/release
```
