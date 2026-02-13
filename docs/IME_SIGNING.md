# IME Signing (Keychain / KC)

Use these env vars to sign Aether IME with certificates in your keychain.

## 1) Sign IME app bundle

```bash
export IME_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
# optional keychain path:
# export IME_SIGN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
./Scripts/BuildInstallIME.sh --build-only
```

## 2) Build signed installer pkg

```bash
export INSTALLER_SIGN_IDENTITY="Developer ID Installer: Your Name (TEAMID)"
# optional keychain path:
# export INSTALLER_SIGN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
./Scripts/CreateIMEPkg.sh
```

Output:

`/Volumes/SSD/Projects/Aether/.build/release/AetherIME.pkg`

If `IME_SIGN_IDENTITY` is empty, script falls back to ad-hoc signing (development only).
