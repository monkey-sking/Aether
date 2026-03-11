---
description: 完整发布流程：编译、签名、创建 DMG、公证
---

# Release Aether

此工作流使用 `ReleaseForUsers.sh` 执行完整的发布流程。

## 前置条件

- Developer ID Application 证书已安装
- Provisioning Profiles 已准备好（App + Driver）
- `NOTARY_PROFILE` 已在 Keychain 中配置（用于公证）

## 环境变量

| 变量 | 必需 | 说明 |
|---|---|---|
| `APP_PROVISION_PROFILE` | ✅ | App 的 provisioning profile 文件路径 |
| `DRIVER_PROVISION_PROFILE` | ✅ | Driver 的 provisioning profile 文件路径 |
| `NOTARY_PROFILE` | 公证时需要 | Keychain 中的 notarytool 凭据名 |
| `SKIP_NOTARIZE` | 可选 | 设为 `1` 跳过公证步骤 |
| `SIGNING_IDENTITY` | 可选 | 手动指定签名身份（默认自动检测） |
| `AETHER_UNIVERSAL` | 可选 | 设为 `1` 构建 Universal Binary（默认 1） |

## 执行

### 完整发布（含公证）

```bash
APP_PROVISION_PROFILE=path/to/app.provisionprofile \
DRIVER_PROVISION_PROFILE=path/to/driver.provisionprofile \
NOTARY_PROFILE=AC_PASSWORD \
./Scripts/ReleaseForUsers.sh
```

### 跳过公证（本地测试）

```bash
APP_PROVISION_PROFILE=path/to/app.provisionprofile \
DRIVER_PROVISION_PROFILE=path/to/driver.provisionprofile \
SKIP_NOTARIZE=1 \
./Scripts/ReleaseForUsers.sh
```

## 流程步骤

1. **查找签名身份** — 从 Profile 或 Keychain 自动匹配 Developer ID
2. **编译** — 调用 `BuildRelease.sh Release`（unsigned），生成 `.build/release/Aether.app`
3. **嵌入 Profiles** — 将 provisioning profiles 拷入 App 和 Driver 包
4. **准备签名 Entitlements** — 从 profile 补全 `application-identifier` 和 `team-identifier`
5. **代码签名** — 深度签名 Frameworks → Plugins → Driver (.dext) → App
6. **创建 DMG** — 调用 `CreateDMG.sh`，自定义背景和图标布局
7. **签名 DMG** — 对 DMG 文件本身签名
8. **公证** — 提交 DMG 到 Apple Notary Service 并 staple

## 产出文件

| 文件 | 路径 |
|---|---|
| App | `.build/release/Aether.app` |
| DMG | `.build/release/Aether_Installer.dmg` |
| ZIP | `.build/release/Aether.zip` |

## 相关脚本

- `Scripts/BuildRelease.sh` — 底层编译脚本（支持 `AETHER_UNSIGNED=1`）
- `Scripts/CreateDMG.sh` — DMG 生成器（自动品牌化背景/图标布局）
- `Scripts/DeployDev.sh` — 开发快速部署（不创建 DMG）
