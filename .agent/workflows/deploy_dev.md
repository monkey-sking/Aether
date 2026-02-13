---
description: 快速开发构建、安装并自动重启 Aether App (不创建 DMG)
---

这个工作流用于在开发过程中快速应用更改并立即进行手动验证。它会跳过慢速的 DMG 创建过程。

// turbo
1. 运行部署脚本：
```bash
./Scripts/DeployDev.sh
```

2. 脚本会自动完成以下操作：
    - 关闭当前运行的 Aether
    - 调用 `BuildRelease.sh` 进行编译和签名
    - 将生成的 `.app` 拷贝到 `/Applications` 文件夹
    - 自动打开应用
