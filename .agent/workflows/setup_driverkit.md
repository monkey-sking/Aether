---
description: DriverKit 环境配置与虚拟设备激活指南
---

# DriverKit Setup & Activation Skill

本技能包含创建、配置及激活 Aether 虚拟 HID 驱动的标准流程。

## 1. 权限申请 (Entitlements)
在 Apple Developer Portal 申请两项关键权限：
1. `com.apple.developer.driverkit`
2. `com.apple.developer.driverkit.family.hid.virtual.device` (需额外说明使用场景)

## 2. 驱动配置 (Target Setup)
在 Xcode 中：
- 创建 Target: `DriverKit Extension`
- Bundle ID: `com.yourname.Aether.driver`
- Info.plist:
  - `IOUserServerName`: `com.yourname.Aether.driver`
  - `IOKitPersonalities`: 定义 `IOUserClient` 匹配规则。

## 3. 激活脚本 (Activation)
运行以下命令检查驱动状态：

```bash
# 查看已加载的系统扩展
systemextensionsctl list

# 重置扩展（如果遇到签名/加载问题）
systemextensionsctl reset
```

## 4. 常见问题 (Troubleshooting)
- **Error**: `System Extension Blocked`
  - **Fix**: 在 "System Settings > Privacy & Security" 中手动允许。
- **Error**: `Signature Validation Failed`
  - **Fix**: 确保 SIP 已关闭 (开发机) 或使用正确的 Developer ID Application 证书签名。
