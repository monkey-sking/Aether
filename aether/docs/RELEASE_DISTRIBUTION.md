# Aether 发布与公证指南

本文用于生成“普通用户可安装”的正式发布包（Developer ID 签名 + Notarization + Staple）。

## 1. 前置条件

- 本机钥匙串已安装 `Developer ID Application` 证书（Team: `4Z7654KAZZ`）。
- 已配置 notarytool 凭据（`NOTARY_PROFILE`）。
- 已安装 Xcode Command Line Tools。

## 2. 配置 NOTARY_PROFILE（仅首次）

```bash
xcrun notarytool store-credentials "AetherNotary" \
  --apple-id "你的AppleID邮箱" \
  --team-id "4Z7654KAZZ" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

验证凭据：

```bash
xcrun notarytool history --keychain-profile "AetherNotary"
```

## 3. 出正式发布包

```bash
cd /Volumes/SSD/Projects/Aether
NOTARY_PROFILE=AetherNotary ./Scripts/ReleaseForUsers.sh
```

脚本会执行：

- 无签名构建 App（避免开发证书阻塞）
- 用 `Developer ID Application` 重签 App 和 DEXT
- 生成 DMG 与 ZIP
- 对 DMG 做签名
- 提交 DMG 到 Apple Notary
- 对 App 和 DMG 执行 stapler

默认行为（无分发 profile）：

- 若未提供 `APP_PROVISION_PROFILE` 和 `DRIVER_PROVISION_PROFILE`，脚本会自动使用“兼容签名”模式。
- 兼容模式会移除 `Contents/Library/SystemExtensions`，并移除 `com.apple.developer.system-extension.install` entitlement。
- 这类包适合先分发主 App 与语音能力，不包含 DriverKit 系统扩展能力。

如需保留系统扩展能力，请显式提供 profile：

```bash
APP_PROVISION_PROFILE=/path/to/Aether.provisionprofile \
DRIVER_PROVISION_PROFILE=/path/to/AetherDriver.provisionprofile \
NOTARY_PROFILE=AetherNotary \
./Scripts/ReleaseForUsers.sh
```

产物路径：

- `.build/release/Aether.app`
- `.build/release/Aether_Installer.dmg`
- `.build/release/Aether.zip`

## 4. 本地快速验证（跳过公证）

```bash
cd /Volumes/SSD/Projects/Aether
SKIP_NOTARIZE=1 ./Scripts/ReleaseForUsers.sh
```

## 5. 验签命令（发布后）

```bash
APP="/Volumes/SSD/Projects/Aether/.build/release/Aether.app"
DMG="/Volumes/SSD/Projects/Aether/.build/release/Aether_Installer.dmg"

codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -t exec -vv "$APP"
xcrun stapler validate "$APP"

codesign --verify --verbose=4 "$DMG"
spctl -a -t open -vv --context context:primary-signature "$DMG"
spctl -a -t install -vv "$DMG"
xcrun stapler validate "$DMG"
```

关键检查（麦克风/语音识别权限）：

```bash
# 1) 必须包含以下 entitlement，否则系统可能不出现 Aether 麦克风授权项
codesign -d --entitlements :- "$APP" 2>/dev/null | \
  rg "com.apple.security.device.audio-input|com.apple.security.personal-information.speech-recognition"

# 2) 必须包含用途说明
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" "$APP/Contents/Info.plist"
```

若缺少以上任一项，优先修复签名与 entitlements，再做权限排障。

说明：

- `spctl -t open` 在部分环境会出现 `Insufficient Context`，不等于包无效。
- 以 `--context context:primary-signature` 和 `-t install` 的结果为准。

## 6. 常见问题

- `ambiguous Developer ID Application`
  - 钥匙串有多张同名证书。发布脚本已使用 SHA-1 指纹签名以规避此问题。
- `The staple and validate action failed! Error 65`
  - 通常是“提交公证的对象”和“staple 的对象”不一致。当前脚本提交的是 DMG，并对 DMG 执行 staple。
- `No profile for team ...` / 开发签名报错
  - 走发布链路不依赖 Apple Development 证书，可直接使用 `ReleaseForUsers.sh`。
- App 内显示麦克风 `denied`，但系统麦克风列表没有 `Aether`
  - 先确认上面的 entitlement 与 usage description 检查都通过。
  - 然后执行：`tccutil reset Microphone com.7fei.Aether`，重启 App 再触发一次授权。
