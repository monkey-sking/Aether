---
description: 在项目中配置并启用 Xcode MCP Server
---

# Xcode MCP Server 配置指南

为了让 AI 代理（Antigravity / Claude）能够直接操作 Xcode（如编译、运行、管理模拟器、添加文件等），推荐配置 `XcodeBuildMCP`。

## 1. 推荐 Server: XcodeBuildMCP

*   **开发者**: cameroncooke
*   **功能**: 提供 72 个工具，涵盖编译、运行、UI 自动化、模拟器管理、SPM 管理等。
*   **项目地址**: [https://github.com/cameroncooke/XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP)

## 2. 配置步骤 (Antigravity)

1.  打开 Antigravity 的配置文件：
    *   `/Users/runking/.gemini/antigravity/mcp_config.json`
2.  在 `mcpServers` 节点下添加以下配置（注意替换为你自己的路径）：

```json
{
  "mcpServers": {
    "xcode": {
      "command": "npx",
      "args": ["-y", "xcodebuildmcp"],
      "env": {
        "XCODE_PROJECTS_DIR": "/Volumes/SSD/Projects/Aether"
      }
    }
  }
}
```

3.  重启 Antigravity。

## 3. 验证配置

重启后，在对话框中输入 `Can you list the Xcode targets in this project?`。如果配置成功，AI 将会调用 MCP 工具列出项目 Target。

## 4. 其它备选: xcode-mcp-server (r-huijts)

如果你更侧重于 **CocoaPods** 或 **Workspace** 管理，可以使用 [r-huijts/xcode-mcp-server](https://github.com/r-huijts/xcode-mcp-server)。

配置示例：
```json
{
  "mcpServers": {
    "xcode-mgmt": {
      "command": "npx",
      "args": ["-y", "xcode-mcp-server"]
    }
  }
}
```

---
*注意：由于 DriverKit 的权限限制，某些 UI 注入工具可能需要在 macOS 系统设置中授予相应权限。*
