# Aether 项目审核报告

> 文档状态：`Historical`
> 说明：这是 2026-03-15 的阶段性审核快照，里面的结论不保证仍与当前代码一致。
> 若与当前实现冲突，请优先看源码、`PENDING_ACCEPTANCE.md`、`Phase1.5_TODO.md` 与根目录 `TODO.md`。

审核时间：2026-03-15  
审核范围：`/Volumes/SSD/Projects/Aether/App` 当前工作区代码与测试状态

## 审核结论

当前项目处于“可以构建，但整体健康度不稳定”的状态。核心问题主要集中在以下几类：

1. 语音与听写内容被明文写入日志，存在明显隐私风险。
2. DriverKit / Virtual HID 主路径并未真正打通，实际行为仍主要依赖 `CoreGraphics` fallback。
3. 已经移除的“连接锁定”能力仍保留大量入口，形成假功能。
4. HUD / Caret / Speech 的 AX 管线中存在较多强制类型转换，第三方应用异常返回值可能直接导致崩溃。
5. 测试基线当前已损坏，无法提供有效回归保护。

## 主要问题

### P1: 语音与听写内容明文写入日志

以下位置会直接记录 transcript、dictation payload、normalized 文本或最终注入文本：

- `Apps/Apps/AetherCore/Speech/DictationHandler.swift:61`
- `Apps/Apps/AetherCore/Speech/DictationHandler.swift:121`
- `Apps/Apps/AetherCore/Speech/CommandHandler.swift:29`
- `Apps/Apps/AetherCore/SpeechManager.swift:1099`
- `Apps/Apps/AetherCore/SpeechManager.swift:1144`
- `Apps/Apps/AetherCore/SpeechManager.swift:1535`
- `Apps/Apps/AetherCore/Speech/VoiceCommandRouter.swift:1331`
- `Apps/Apps/AetherCore/AetherApp.swift:2404`

影响：

- 用户口述内容会进入 Console、诊断日志和归档日志。
- 对常驻监听、听写类产品来说，这属于高敏感数据泄露面。

建议：

- 生产环境移除 transcript 原文日志。
- 必须保留时改为 `.private` 或仅记录长度、模式、状态码等非内容指标。

### P2: DriverKit / Virtual HID 主路径未真正接通

证据：

- `Apps/AetherDriver/AetherDriver.cpp:42` 的 `NewUserClient` 仍返回 `kIOReturnUnsupported`
- `Apps/Apps/AetherCore/AutomationOutput.swift:360`
- `Apps/Apps/AetherCore/AutomationOutput.swift:365`
- `Apps/Apps/AetherCore/AutomationOutput.swift:370`

现状：

- 指针移动、点击、文本注入都仍然走 `CoreGraphicsAutomationOutput`
- 文档中对 DriverKit / IPC 的完成度描述和当前实现不一致

影响：

- 项目对“虚拟 HID 驱动”的核心卖点存在实现与宣传不一致的问题。
- 一旦用户、测试或文档预期依赖 Driver 路径，行为会出现偏差。

建议：

- 如果要继续推进 DriverKit：优先完成 `IOUserClient` / IPC 主路径并补真机验证。
- 如果短期内不做：明确在文档、UI 和状态显示中标注当前为 fallback 方案。

### P2: 连接锁定功能已移除，但入口仍大量存在

证据：

- `Apps/Apps/AetherCore/ConnectionLockService.swift:4`
- `Apps/Apps/AetherCore/ConnectionLockService.swift:16`
- `Apps/Apps/AetherCore/HeadMotionManager.swift:656`
- `Apps/Apps/AetherCore/HeadMotionManager.swift:2020`
- `Apps/Apps/AetherCore/HotkeyManager.swift:176`
- `Apps/Apps/AetherCore/AetherApp.swift:2397`

现状：

- `ConnectionLockService` 已是 legacy placeholder，`lock/unlock/toggle` 全部只打日志，不做实际工作。
- 但热键、语音、HUD、追踪流程仍继续暴露和调用该功能。

影响：

- 用户会看到“连接锁定”相关交互，但实际无效果。
- 这会造成假成功反馈，增加排障成本和产品信任风险。

建议：

- 要么彻底移除所有 UI / 热键 / VoiceIntent 入口。
- 要么恢复真实实现，并补状态反馈与失败提示。

### P2: AX 管线中大量强制类型转换，存在崩溃面

证据示例：

- `Apps/Apps/AetherCore/HUD/HUDManager.swift:178`
- `Apps/Apps/AetherCore/HUD/HUDManager.swift:1280`
- `Apps/Apps/AetherCore/HUD/HUDManager.swift:1293`
- `Apps/Apps/AetherCore/HUD/CaretDetector.swift:415`
- `Apps/Apps/AetherCore/HUD/CaretDetector.swift:478`
- `Apps/Apps/AetherCore/HUD/CaretDetector.swift:637`
- `Apps/Apps/AetherCore/SpeechManager.swift:2618`
- `Apps/Apps/AetherCore/SpeechManager.swift:2715`
- `Apps/Apps/AetherCore/SpeechManager.swift:2946`

补充观察：

- HUD 与 `SpeechManager` 中的 `as! AXUIElement` / `as! AXValue` 静态扫描数量约为 39 处。

影响：

- 第三方应用，尤其是 Electron、浏览器、WebView 类目标，AX 返回值并不稳定。
- 只要出现不符合预期的类型，就可能直接触发主进程崩溃。

建议：

- 将所有 AX 读取统一改成“先校验 `CFGetTypeID`，再安全转换”的辅助方法。
- 对异常值走降级逻辑，不要直接崩溃。

### P2: 测试基线已损坏，回归保护失效

验证结果：

- `xcodebuild build -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - 结果：通过
- `xcodebuild test -project /Volumes/SSD/Projects/Aether/App/Aether.xcodeproj -scheme Aether -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
  - 结果：失败

失败原因：

- `SpeechManager.resolvedUtteranceTypingMode(...)` 和 `reconcileTypingContextWithVisibleHUD(...)` 新增了 `isUtteranceActive` 参数
- 但测试仍按旧签名调用

证据：

- `Apps/Apps/AetherCore/SpeechManager.swift:389`
- `Apps/Apps/AetherCore/SpeechManager.swift:414`
- `Apps/AetherTests/VoiceCommandRouterTests.swift:179`
- `Apps/AetherTests/VoiceCommandRouterTests.swift:215`

补充观察：

- 业务源码约 23,739 行
- 测试代码约 343 行
- 粗略测试占比约 1.44%

影响：

- 当前测试阶段已经无法作为 CI 或本地回归门禁。
- 核心语音态机变更后，缺乏稳定保护网。

建议：

- 先修复测试签名，恢复 `xcodebuild test` 可执行。
- 优先为语音态机、AX 降级逻辑、输出路由补单元测试。

## 其他观察

- `Apps/Apps/AetherCore/Speech/TypingFinalizationPlanner.swift` 为空文件，说明该模块曾被替换但未彻底清理。
- 文档中存在“功能已完成”的表述，与当前代码状态不完全一致，建议做一次文档对齐。
- 当前工作区存在未提交改动，本次审核未尝试回退或修改这些内容。

## 建议修复优先级

### 第一优先级

1. 移除或脱敏所有 transcript / dictation 明文日志。
2. 清理“连接锁定”假功能入口，避免继续暴露给用户。
3. 为 AX 访问建立统一安全封装，消除高频 `as!` 崩溃点。

### 第二优先级

1. 修复测试代码签名，恢复 `xcodebuild test`。
2. 补充语音态机和 HUD / AX 回退路径测试。

### 第三优先级

1. 明确 DriverKit 主路径是继续投入实现，还是在产品层面降级为 fallback。
2. 同步更新 README、TODO、状态描述，避免实现与对外表述不一致。

## 审核说明

本次审核基于当前工作区代码完成，包含未提交改动在内的实际状态，而非仅基于 `HEAD`。  
未进行真机 AirPods、DriverKit 安装授权和系统级交互的人工回归，因此硬件链路仍有未覆盖的残余风险。
