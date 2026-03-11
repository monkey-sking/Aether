# Aether 权限排障手册（macOS）

本文用于排查以下典型问题：

- App 内显示麦克风/辅助功能未授权，但系统里看起来已授权
- App 内麦克风状态为 `denied`，系统“麦克风”列表没有 `Aether`
- HUD 与设置页权限状态不一致

## 1. 先确认运行的到底是哪一个 App

```bash
ps -axo pid,command | rg "Aether.app/Contents/MacOS/Aether" | rg -v rg
lsappinfo info -bundleid com.7fei.Aether
codesign -dv --verbose=4 /Applications/Aether.app 2>&1 | rg "Identifier=|TeamIdentifier=|Executable="
```

预期：

- 路径是 `/Applications/Aether.app`
- Bundle ID 是 `com.7fei.Aether`
- TeamIdentifier 是 `4Z7654KAZZ`

## 2. 检查签名权限（entitlements）

```bash
codesign -d --entitlements :- /Applications/Aether.app 2>/dev/null
```

必须包含：

- `com.apple.security.device.audio-input = true`
- `com.apple.security.personal-information.speech-recognition = true`

如果缺失，优先修复签名与打包流程；否则系统可能不创建麦克风授权条目。

## 3. 检查 Info.plist 用途说明

```bash
/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" /Applications/Aether.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Print :NSSpeechRecognitionUsageDescription" /Applications/Aether.app/Contents/Info.plist
```

如果为空或不存在，系统不会正确弹授权框。

## 4. 标准修复流程（用户机器）

```bash
tccutil reset Microphone com.7fei.Aether
tccutil reset SpeechRecognition com.7fei.Aether
killall Aether || true
open /Applications/Aether.app
```

然后在 App 设置页点击 `Allow`，按系统弹窗授权。

## 5. UI 逻辑约束（开发规范）

- 权限不足时，不隐藏模式 UI；在 UI 内展示引导信息。
- `Allow` 行为：
  - `notDetermined`：先请求系统授权（不应立即跳系统设置，避免打断弹窗）
  - `denied/restricted`：打开系统设置，并允许在 App 内执行恢复流程
- 设置页与 HUD 的权限判断必须使用同一实时系统来源。

## 6. 回归清单

- 设置页中三项权限状态和系统面板一致
- HUD 不再出现与设置页冲突的权限提示
- 麦克风授权后，快捷键可正常出字
- 切换触发方式（PTT / 唤醒词 / 直接指令）即时生效
