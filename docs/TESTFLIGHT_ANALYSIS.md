# Aether 项目 TestFlight 分发可行性分析报告

## 1. 核心结论
项目 **可以** 上架 TestFlight (TF)，但需要完成从“非沙盒应用”到“沙盒应用”的权限迁移，并对冗余的驱动组件进行清理。

## 2. AetherDriver.dext 使用情况审计
*   **审计结果**：**未使用**。
*   **详细说明**：
    *   代码中虽定义了驱动的 Bundle ID，但主程序 `AetherCore` 中没有任何激活或通信的代码。
    *   当前的头部追踪（Head Motion）完全依赖苹果官方的 `CoreMotion` 框架。
*   **建议方案**：在提交 App Store 审核前，建议移除 `AetherDriver` 目标 (Target)，以避免不必要的驱动特殊权限申请和人工审核。

## 3. 开启 App Sandbox (沙盒) 的影响评估
上架 TF 必须开启沙盒（目前为关闭状态），以下是受影响的功能预测及对策：

| 功能模块 | 受影响程度 | 解决方案建议 |
| :--- | :--- | :--- |
| **语音识别/麦克风** | 低 | 在沙盒配置文件中勾选 `Microphone` 权限。 |
| **头部追踪 (Motion)** | 无 | 使用系统原生 API，不受沙盒限制。 |
| **全局快捷键 (Carbon)** | 中 | 必须通过 `com.apple.security.temporary-exception.apple-events` 配合辅助功能（Accessibility）授权。 |
| **媒体控制 (MediaRemote)** | 高 | 沙盒严限私有 API 控制系统播放。建议评估是否迁移至 `MPNowPlayingInfoCenter` 或申请特定授权。 |
| **文件访问** | 低 | 改用系统原生的 `Open/Save Panel` 进行交互。 |

## 4. 下一步行动建议 (Next Steps)
1.  **环境准备**：在开发者中心 (Apple Developer Portal) 配置项目的 App 管理记录。
2.  **沙盒配置**：
    *   在 Xcode 中启用 `App Sandbox`。
    *   将 `com.apple.security.app-sandbox` 设为 `true`。
3.  **驱动清理**：从主项目的 `Dependencies` 和 `Embed Foundation Extensions` 中解除驱动绑定。
4.  **功能验证**：开启沙盒后，重点测试“全局快捷键”和“音乐播控”是否异常。

---
*报告生成日期：2026-03-16*
