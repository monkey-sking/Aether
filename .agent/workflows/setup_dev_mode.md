---
description: DriverKit 本地开发与调试环境配置
---

# DriverKit Developer Mode Setup

由于 DriverKit 驱动受系统严格保护，本地开发（无官方权限时）需开启 **Developer Mode**。

## 1. 开启系统扩展开发模式

在终端运行：

```bash
systemextensionsctl developer on
```

## 2. 暂时关闭 SIP (仅限 Intel Mac 或必要时)

对于某些虚拟 HID 功能，可能需要关闭 SIP 或开启特定的 Boot Args（Apple Silicon 通常只需上述命令）。

## 3. 在 Xcode 中配置

1.  **Signing & Capabilities**:
    *   主 App 和 Driver 必须使用 **同一个 Team** 签名。
    *   勾选 "Automatically manage signing"。
2.  **Bridging Header**:
    *   在 `AetherCore` Target 的 `Build Settings` 中搜索 `Objective-C Bridging Header`。
    *   填入: `Apps/AetherCore/AetherCore-Bridging-Header.h`。
3.  **App Sandbox**:
    *   主 App 的 Sandbox 中必须包含 `System Extension` 权限。

## 4. 手动加载测试

1. 运行 App。
2. 点击 "Activate Perception"。
3. 系统会弹出 "System Extension Blocked"。
4.前往 **System Settings > Privacy & Security**，滚动到底部点击 **Allow**。
