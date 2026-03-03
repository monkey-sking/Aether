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
