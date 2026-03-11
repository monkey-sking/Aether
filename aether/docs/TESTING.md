# Aether Testing / Acceptance Checklist

This doc is for local testing on a development machine. System Extension + DriverKit requires correct code signing and explicit user approval in System Settings.
For public release packaging and notarization, see `docs/RELEASE_DISTRIBUTION.md`.

## Where the build artifacts are

- Release `.app`: `/Volumes/SSD/Projects/Aether/.build/release/Aether.app`
- Installer DMG: `/Volumes/SSD/Projects/Aether/.build/release/Aether_Installer.dmg`
- Debug `.app` (Xcode output): `/Volumes/SSD/Projects/Aether/.derivedData/Build/Products/Debug/Aether.app`

Note: typing `Aether.app` in Terminal will not launch it. Use `open /path/to/Aether.app`.
If Finder shows a blank icon for the release build, run:
`/Volumes/SSD/Projects/Aether/Scripts/PrepareAppBundle.sh /Volumes/SSD/Projects/Aether/.build/release/Aether.app`

## Build (recommended)

1. Open `Aether.xcodeproj` in Xcode.
2. In `Apps/AetherCore` target, set `Signing & Capabilities` to your Team (Automatic).
3. Build a Release app into `.build/release`:

```bash
cd /Volumes/SSD/Projects/Aether
./Scripts/BuildRelease.sh Release
open ./.build/release/Aether.app
```

## Build for end users (Developer ID distribution)

Use this path when you want a package for non-development users:

```bash
cd /Volumes/SSD/Projects/Aether
SKIP_NOTARIZE=1 ./Scripts/ReleaseForUsers.sh
```

If notarization is configured in keychain:

```bash
cd /Volumes/SSD/Projects/Aether
NOTARY_PROFILE=YourNotaryProfile ./Scripts/ReleaseForUsers.sh
```

## First run: permissions and system extension

Important: macOS requires the host app to live in `/Applications` to activate a System Extension.
If you're running from Xcode/DerivedData or a mounted DMG volume, activation will fail.

To install the latest built app into `/Applications`:
`/Volumes/SSD/Projects/Aether/Scripts/InstallToApplications.sh`

1. **Accessibility**
   - In Aether window, click `Fix Accessibility` and grant it.
2. **Microphone**
   - Click `Fix Microphone` and allow.
3. **Speech Recognition**
   - Click `Fix Speech` and allow.
4. **System Extension (DriverKit)**
   - Click `Activate Perception` (or menu bar `Activate Driver`).
   - If it shows `Needs User Approval`, open `System Settings -> Privacy & Security` and allow the extension.

Expected after approval:
- UI `Virtual HID` becomes `Ready` (not `Idle`).
- Menu bar `Pointer Output` can show `DriverKit` when driver is available.

## Functional tests

### Pointer via AirPods IMU
1. Connect AirPods (head IMU source).
2. Menu bar: `Start Pointer`.
3. Move head: cursor moves smoothly.
4. Click `Recenter Pointer` to recalibrate center.

### Dwell click
1. Toggle `Dwell Click`.
2. Hold cursor still: triggers a left click after dwell threshold.

### Voice (PTT and always listening)
1. Hold push-to-talk hotkey (default shown in UI) and speak:
   - "click" / "点击"
   - "recenter" / "校准"
   - "undo" / "撤销"
2. Toggle `Always Listening`:
   - Say wake phrase then command (UI shows the wake phrase).
3. Dictation injection:
   - Focus a text field (Notes, TextEdit, browser input).
   - Speak a sentence; it should paste into the focused field.

## Common failures and what they mean

- `Missing entitlement com.apple.developer.system-extension.install`
  - The app is not signed with the system extension install entitlement. Fix by building from Xcode with your Team and the entitlements enabled.
- `Virtual HID: Idle`
  - Driver not activated/approved yet. Click `Activate Perception` and approve in Privacy & Security.
- `Voice: Speech Error`
  - Usually Speech or Microphone permission denied, or the speech recognizer is unavailable. Recheck permissions and try again.
