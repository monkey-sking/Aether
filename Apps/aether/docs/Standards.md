# Documentation & Contributing Standards

## 1. 文档优先原则 (Documentation First)
任何代码变更前，必须**先更新**对应的文档（PRD 或 Roadmap）。
*   **Feature**: 更新 `PRD.md` 和 `Roadmap.md`。
*   **Fix**: 如果涉及逻辑变更，更新对应的设计部分。

## 2. 目录结构规范
*   `docs/`: 存放长效文档。
*   `docs/archive/`: 存放已废弃的历史版本。
*   `.agent/workflows/`: 存放自动化操作手册 (Agent Skills)。

## 3. Git 提交规范 (Conventional Commits)
格式: `<type>(<scope>): <subject>`

*   **feat**: 新功能 (Feature)
*   **fix**: 修复 Bug
*   **docs**: 仅文档变更
*   **style**: 格式调整 (不影响逻辑)
*   **refactor**: 重构 (无新功能或Bug修复)
*   **test**: 测试相关
*   **chore**: 构建/工具变更

示例:
```
docs(prd): merge v2.1 lid angle features into v3.0
feat(driver): initial implementation of virtual mouse
```

## 4. 语言规范
*   **正文**: 简体中文 (Simplified Chinese)。
*   **术语**: 严格使用英文原词 (e.g., DriverKit, gPTP, HID Descriptor)，不要强行翻译。
