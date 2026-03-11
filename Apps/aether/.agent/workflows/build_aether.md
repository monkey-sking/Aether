---
description: 编译 Aether App 和 Driver
---

# Build Aether Project

此工作流用于使用 `xcodebuild` 命令行编译 Aether 项目，包含 App 和 DriverKit Extension。

## 1. 编译 App (AetherCore)

```bash
xcodebuild -workspace Aether.xcworkspace \
           -scheme AetherCore \
           -configuration Debug \
           -derivedDataPath build/ \
           clean build
```

## 2. 编译 Driver (AetherDriver)

通常编译 App Scheme 时会自动编译依赖的 Driver，但也可以单独编译：

```bash
xcodebuild -workspace Aether.xcworkspace \
           -scheme AetherDriver \
           -configuration Debug \
           -derivedDataPath build/ \
           clean build
```

## 3. 运行 (需手动)

由于涉及到 DriverKit 激活，建议在 Xcode 中点击 Run (Cmd+R) 以便调试器附加。
命令行运行可以使用：

```bash
open build/Build/Products/Debug/AetherCore.app
```

## 故障排查

- **Entitlement Error**: 检查 Info.plist 是否包含 `com.apple.developer.driverkit`。
- **Sign Error**: DriverKit 必须使用有效的 Developer ID 签名（或在 SIP 关闭环境下本地签名）。
