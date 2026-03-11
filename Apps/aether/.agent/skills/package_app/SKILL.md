---
name: package_app
description: Builds, packages, and releases the Aion macOS application for distribution and local testing.
---

# Package & Release Aion App

This skill provides the standard procedure to build, package, sign, notarize, and release the **Aion** application.

## Prerequisites
- macOS 14.0+
- Xcode 15+ / Swift 5.9+
- Developer ID Certificate installed
- `create-dmg` installed (`brew install create-dmg`)

---

## 🔧 Local Testing (Development)

For quick local testing during development:

```bash
./Scripts/PackageAion.sh
```

This script:
- Builds with `xcodebuild` (Aion scheme)
- Signs with development certificate
- Installs to `/Applications/Aion.app`
- Launches the app

---

## 🚀 Release Build (Production)

### ⚠️ Pre-Release Checklist (CRITICAL)

Before running the release script, **YOU MUST** verify the following:

1.  **Version Bump**:
    *   [ ] Increment `CFBundleShortVersionString` and `CFBundleVersion` in `Sources/Aion/Info.plist`.
    *   [ ] Verify the new version is **higher** than the live version (check `Website/src/data/changelog.ts`).
2.  **Helper Tool Version** (If you touched `HelperTool`):
    *   [ ] Increment `CFBundleVersion` in `Sources/HelperTool/Helper-Info.plist`.
    *   [ ] Update `AionHelperVersion` in `Sources/Aion/Info.plist` to match.
    *   [ ] Update the fallback version string in `Sources/HelperTool/main.swift`.
3.  **Changelog**:
    *   [ ] Add the new version entry to `Website/src/data/changelog.ts`.
4.  **Git Check**:
    *   [ ] Ensure all project code changes are committed `git status`.

For production release with notarization:

```bash
./Scripts/Notarize.sh
```

This script:
- Builds with Release configuration
- Signs with **Developer ID** certificate
- Embeds Developer ID Provisioning Profile (for iCloud/App Groups entitlements)
- Creates DMG with custom background
- Notarizes with Apple
- Generates Sparkle update ZIP
- Updates `appcast.xml`
- Outputs files to `Website/public/`

### Output Files

| File | Path | Purpose |
|------|------|---------|
| DMG | `Website/public/download/Aion_X.X.X.dmg` | Website download |
| ZIP | `Website/public/aion/Aion_X.X.X.zip` | Sparkle auto-update |
| Appcast | `Website/public/aion/appcast.xml` | Sparkle feed |

---

## 🌐 Deploy to Website

After release build, deploy to **aion.7caifei.com** via Vercel:

```bash
cd Website
git add .
git commit -m "Release Aion vX.X.X"
git push origin main
```

Vercel auto-deploys on push to `main`.

### Critical URLs

| URL | Purpose |
|-----|---------|
| `https://aion.7caifei.com/download/Aion.dmg` | Download link (symlink to latest) |
| `https://aion.7caifei.com/aion/appcast.xml` | Sparkle feed URL |
| `https://aion.7caifei.com/aion/Aion_X.X.X.zip` | Update package |
| `https://aion.7caifei.com/aion/Tips.json` | Tips hot-update |
| `https://aion.7caifei.com/aion/rules/app_variants.v1.json` | AppVariants rules |

---

## 📝 App Configuration

### Sparkle Feed URL (Info.plist)
```xml
<key>SUFeedURL</key>
<string>https://aion.7caifei.com/aion/appcast.xml</string>
```

### Remote Resources (Swift)
- **TipsManager**: `https://aion.7caifei.com/aion/Tips.json`
- **RuleUpdateManager**: `https://aion.7caifei.com/aion/rules/app_variants.v1.json`

---

## 🔍 Troubleshooting

### Script Permission
```bash
chmod +x Scripts/PackageAion.sh Scripts/ReleaseAion.sh
```

### Clean Build
```bash
rm -rf .build/dd ~/Library/Developer/Xcode/DerivedData/ProcessZero-*
```

### Sparkle Framework Missing
If app crashes with "Library not loaded: Sparkle.framework":
1. Clean derived data
2. Rebuild from Xcode (Cmd+Shift+K, then Cmd+B)
3. Check Embed Frameworks in Build Phases

### Notarization Fails
Check Apple ID credentials in Keychain:
```bash
xcrun notarytool store-credentials "AC_PASSWORD" --apple-id "your@email.com" --team-id "TEAMID"
```
