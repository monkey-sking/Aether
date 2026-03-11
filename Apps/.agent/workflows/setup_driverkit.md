# DriverKit 环境配置与虚拟设备激活指南

本指南帮助你在 Apple Developer 账户中配置 System Extension 权限，使 Aether 能够安装虚拟 HID 驱动。

---

## 前置条件

- [x] 付费的 Apple Developer Program 会员（$99/年）
- [x] Xcode 已安装并登录开发者账户

---

## 第一步：在 Apple Developer 网站注册 App ID

### 1.1 打开 Certificates, Identifiers & Profiles

1. 打开浏览器访问 https://developer.apple.com/account
2. 登录你的 Apple ID
3. 点击左侧菜单 **"证书、标识符和描述文件"** (Certificates, Identifiers & Profiles)

### 1.2 注册主 App ID

1. 点击左侧 **"标识符"** (Identifiers)
2. 点击右上角 **"+"** 按钮
3. 选择 **"App IDs"** → 点击 **"继续"**
4. 选择类型 **"App"** → 点击 **"继续"**
5. 填写信息：
   - **描述**: `Aether`
   - **Bundle ID**: 选择 **"Explicit"**，输入 `com.7fei.Aether`
6. 在 **"Capabilities"** 列表中勾选：
   - ✅ **System Extension**
7. 点击 **"继续"** → **"注册"**

### 1.3 注册驱动 App ID

1. 再次点击 **"+"** 按钮
2. 选择 **"App IDs"** → **"App"** → **"继续"**
3. 填写信息：
   - **描述**: `AetherDriver`
   - **Bundle ID**: 选择 **"Explicit"**，输入 `com.7fei.Aether.AetherDriver`
4. 在 **"Capabilities"** 列表中勾选：
   - ✅ **DriverKit**
5. 点击 **"继续"** → **"注册"**

---

## 第二步：创建 Provisioning Profiles

### 2.1 创建主 App 的 Profile

1. 点击左侧 **"描述文件"** (Profiles)
2. 点击右上角 **"+"** 按钮
3. 选择 **"macOS App Development"** → 点击 **"继续"**
4. 在 App ID 下拉框选择 **"Aether (com.7fei.Aether)"**
5. 选择你的开发者证书（Development Certificate）
6. 选择你要测试的设备
7. 填写 Profile 名称：`Aether Development`
8. 点击 **"生成"** → **"下载"**

### 2.2 创建驱动的 Profile

1. 再次点击 **"+"** 按钮
2. 选择 **"DriverKit App Development"** → 点击 **"继续"**
   - 如果没有这个选项，选择 **"macOS App Development"**
3. 在 App ID 下拉框选择 **"AetherDriver (com.7fei.Aether.AetherDriver)"**
4. 选择你的开发者证书
5. 选择测试设备
6. 填写 Profile 名称：`AetherDriver Development`
7. 点击 **"生成"** → **"下载"**

---

## 第三步：在 Xcode 中配置签名

### 3.1 安装 Profiles

1. 双击下载的 `.mobileprovision` 文件安装

### 3.2 配置主 App 签名

1. 打开 Xcode，选择 `AetherCore` target
2. 进入 **Signing & Capabilities** 标签
3. **取消勾选** "Automatically manage signing"
4. 在 **Provisioning Profile** 下拉框选择 `Aether Development`
5. 确认 **Team** 是你的付费开发者账户

### 3.3 配置驱动签名

1. 选择 `AetherDriver` target
2. 进入 **Signing & Capabilities** 标签
3. **取消勾选** "Automatically manage signing"
4. 在 **Provisioning Profile** 下拉框选择 `AetherDriver Development`
5. 确认 **Team** 一致

---

## 第四步：构建和测试

```bash
cd /Volumes/SSD/Projects/Aether
./Scripts/BuildRelease.sh Release
./Scripts/InstallToApplications.sh
```

打开 Aether，点击 **"激活 Perception"**。

如果提示需要用户批准，打开 **系统设置 → 隐私与安全性** 滚动到底部批准该扩展。

---

## 常见问题

### Q: 找不到 "System Extension" 或 "DriverKit" 能力选项？
A: 确保你是付费的 Apple Developer Program 会员，免费账户没有这些选项。

### Q: Profile 下载后 Xcode 找不到？
A: 双击 `.mobileprovision` 文件安装，然后重启 Xcode。

### Q: 仍然报 "Missing entitlement" 错误？
A: 检查 Xcode 签名设置是否正确选择了下载的 Profile，不要使用自动签名。

---

## 快速命令参考

```bash
# 查看已安装的 Profiles
security find-identity -v -p codesigning

# 查看 App 签名信息
codesign -dv --verbose=4 /Applications/Aether.app

# 查看已加载的 System Extensions
systemextensionsctl list
```
