# Documentation & Contributing Standards

## 1. 文档优先原则 (Documentation First)
任何影响行为、范围、设置、命令语义、验收口径或用户可见文案的改动，都应**先更新最接近的活文档**，再改代码。

优先顺序：

1. `Current` 文档：当前事实、当前规则、当前验收口径
2. `Planned` 文档：近期规划、功能待办、专项设计
3. `Historical` 文档：仅在需要保留背景或降级旧方案时更新

补充：

* **Feature**：先更新对应的 `Current` 规则文档或 `Planned` TODO，再动代码。
* **Fix**：如果改动会影响行为、UI、命令语义或验收标准，也必须同步文档。
* **不要默认所有改动都去改 `PRD.md` / `Roadmap.md`**；只有产品方向或阶段规划变化时才更新它们。

## 2. 目录结构规范
*   `docs/`: 存放长效文档。
*   `docs/design/`: 存放设计与架构说明。
*   `docs/specs/`: 存放专项治理与设计包。
*   `docs/archive/`: 存放已归档的历史文档；在正式迁移前，历史文档也可以暂留在 `docs/` 根目录，但必须明确标记为 `Historical`。
*   `.agent/workflows/`: 存放自动化操作手册 (Agent Skills)。

## 3. 文档状态规范

核心文档开头应明确其状态，推荐使用以下三类之一：

*   `Current`: 应与当前代码和当前验收结论保持一致。
*   `Planned`: 描述未来功能、TODO 或设计方案，不代表已实现。
*   `Historical`: 保留背景、旧方案、审计快照或过期清单，不作为当前事实来源。

如果一篇旧文档还不能马上重写，也必须先降级状态，避免继续被误读成现状。

## 4. Git 提交规范 (Conventional Commits)
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

## 5. 语言规范
*   **正文**: 简体中文 (Simplified Chinese)。
*   **术语**: 严格使用英文原词 (e.g., DriverKit, gPTP, HID Descriptor)，不要强行翻译。

## 6. 禁止硬编码 (No Hardcoded Copy)
任何**面向用户**的文案、提示词、配置格式示例、导出模板，不允许写死在代码中。
*   文案与模板必须放在 `Localizable.strings` 或资源文件中，并通过 key 引用。
*   AI 提示词必须使用模板 + 占位符（如 `{{PLACEHOLDER}}`），由代码做替换。
*   任何新增或修改文案，需同步更新对应的本地化资源与文档说明。
*   语音词库、自定义 App 规则、默认前缀与覆盖语义，统一以 `docs/VOICE_LEXICON_RULES.md` 为准；改动前先更新该文档。
