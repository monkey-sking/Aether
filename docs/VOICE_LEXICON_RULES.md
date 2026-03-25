# 语音词库与自定义规则说明

> 文档状态：`Current`
> 说明：这是当前语音词库、自定义 App 规则和未来 App 打开/切换边界的规则文档。

本文档定义 Aether 当前“语音词库”和“自定义 App 规则”的边界、数据来源、覆盖规则与禁止硬编码要求。后续任何相关变更，都应先更新本文档，再改代码。

## 1. 范围划分

### 1.1 语音词库

语音词库指 `AetherVoiceLexicon`，当前只包含两类数据：

1. `commandOverrides`
作用：为内建命令配置语音别名。

示例：
```json
{
  "localeIdentifier": "zh-CN",
  "commandID": "paste",
  "aliases": ["粘贴", "贴上"]
}
```

2. `languageTermsOverrides`
作用：为某个语言配置语言级词条。

示例：
```json
{
  "localeIdentifier": "zh-CN",
  "wakeWords": ["艾瑟", "以太"],
  "commandPrefixes": ["命令"],
  "dictationPrefixes": ["输入"]
}
```

字段含义：
- `wakeWords`：唤醒词。
- `commandPrefixes`：一次性强制按命令解析的前缀。
- `dictationPrefixes`：一次性强制按原文输入的前缀。

### 1.2 自定义 App 规则

自定义 App 规则不是语音词库的一部分。它们属于 `CustomAppShortcutRule`，用于给某个具体 App 补充额外命令和快捷键映射。

典型例子：
- 某个聊天 App 里，“确认发送”映射到一个快捷键。
- 某个 IDE 里，“打开命令面板”映射到一个特定快捷键。

结论：
- 语音词库解决“这句话怎么被识别和路由”。
- 自定义 App 规则解决“某个 App 下这句话具体执行什么快捷键”。

### 1.3 未来功能：App 打开 / 切换

“打开某个 App” / “切换到某个 App” 是后续计划中的独立能力，但它也不属于当前 `AetherVoiceLexicon`，也不能直接塞进 `CustomAppShortcutRule`。

原因：
- 这类能力首先要解决的是“App 实体识别”，不是“命令 alias 覆盖”。
- 它的内部主键应是 `bundleIdentifier`，而不是某个 locale 下的一组展示词。
- 同一个 App 需要同时接受中文名、英文名、缩写、拼音或用户自定义别名，因此不能简单复用当前按 locale 分桶的词库过滤策略。

未来应拆为两层：
1. 动作词层：识别 `打开` / `切到` / `回到` / `open` / `launch` / `switch to` 等语义。
2. App 目标层：把余下的 target 解析到某个 `bundleIdentifier`，再由执行层决定是激活已运行实例还是冷启动。

边界：
- 它不是“当前 App 快捷键面板”的一部分。
- 它不是“某个 App 内执行一个快捷键”的自定义规则。
- 它未来应是独立的 `AppTargetResolver` / `AppAliasStore` 一类能力。

## 2. 数据来源与优先级

### 2.1 默认值来源

默认语音词库必须来自资源文件，当前主来源是：

- `Apps/Apps/AetherCore/Resources/VoiceLexiconDefaults.json`

运行时加载入口：

- `Apps/Apps/AetherCore/Speech/VoiceLexiconDefaults.swift`

如果主资源文件不存在或无法解析，才允许退回本地化资源中的兜底模板：

- `voice_lexicon.default_config`

这个兜底模板也属于资源，不属于业务代码硬编码。

### 2.2 运行时优先级

当前规则优先级：

1. 用户 override
2. 默认资源 `VoiceLexiconDefaults.json`

也就是说，运行时“最终生效值”可能来自用户输入，也可能来自默认资源回退。

补充说明：
- 上述优先级只适用于当前语音词库。
- 未来如果引入 App alias / resolver 数据，其优先级必须单独定义，不能直接套用 `VoiceLexiconDefaults.json` 的 locale 规则。

## 3. 当前覆盖语义

### 3.1 命令别名 `commandOverrides`

- 用户编辑某个命令的别名后，优先使用用户配置。
- 如果该命令没有用户配置，则回退到默认资源。

### 3.2 语言级词条 `languageTermsOverrides`

- `wakeWords`
  - 当前只要该 locale 有 override 条目，就使用 override 中的 `wakeWords`。
- `commandPrefixes`
  - 只要该 locale 有 override 条目，就使用 override。
  - 如果 override 中该数组为空，则视为显式禁用，不再回退默认资源。
- `dictationPrefixes`
  - 只要该 locale 有 override 条目，就使用 override。
  - 如果 override 中该数组为空，则视为显式禁用，不再回退默认资源。

### 3.3 当前“清空输入框”的真实语义

这一点必须明确：

- 对 `commandPrefixes` / `dictationPrefixes` 而言，当前输入框清空，就表示显式禁用。
- 只有用户点击“恢复默认”时，才会把默认前缀重新写回。

因此：
- UI 必须显示当前真实生效值。
- 输入框为空时，运行时也必须真的不生效。
- 不允许再出现“输入框看起来是空的，但实际上仍然生效”的情况。

### 3.4 未来 App alias 的覆盖语义

这部分尚未实现，但先确定约束，避免未来误入当前词库模型：

- App alias 应以 `bundleIdentifier` 为主键。
- 同一个 App 的 alias 列表可以同时包含中文、英文、缩写和拼音回退项。
- App alias 不能按 `localeIdentifier` 强制裁剪为“只保留中文”或“只保留英文”。
- 当前 `VoiceLexiconSupport.isDefaultTerm(...)` 这套过滤语义不适合直接用于 App 名解析。
- 用户为某个 App 添加 alias 后，应只覆盖该 App 的目标解析，不应污染全局命令别名。

## 4. UI 约束

设置页中，语音词库编辑 UI 必须满足：

1. 输入框展示的是“当前真实生效值”，不能展示伪空值。
2. 对前缀项，`恢复默认` 的语义是“恢复默认资源”。
3. 对唤醒词和命令别名，`清空` 的语义是显式禁用该项。
4. 前缀输入框清空后，运行时必须同步禁用。
5. 用户可直接编辑：
   - 唤醒词
   - 强制命令前缀
   - 强制输入前缀
   - 各命令别名
6. 从剪贴板导入语音词库时，当前采用“合并”策略，不直接覆盖现有自定义。

### 4.1 词库页面布局

语音词库设置页应优先按使用频率组织，避免把所有命令平铺在一页：

1. `基础词条`
   - 唤醒词
   - 强制命令前缀
   - 强制输入前缀
2. `常用命令`
   - 高频控制命令，默认展开
3. `全部命令`
   - 低频命令，默认折叠

另外：
- `撤销`、`粘贴` 这类编辑动作优先走当前 App 快捷键面板提供的能力，不再占用内置词库主区域。

### 4.2 未来 App alias / resolver UI 约束

该能力落地时，UI 应与语音词库分开：

1. 不要把 App 名 alias 混进按语言编辑的 `Voice Lexicon` 页面。
2. App alias 应以“App 实体”为中心编辑，而不是以 locale 为中心编辑。
3. UI 上应明确区分：
   - 内建控制命令别名
   - 自定义 App 快捷键规则
   - App 打开 / 切换的目标别名
4. 允许从当前运行中的 regular apps 预填候选项，但不应默认展示 helper / agent app。

## 5. 输入模式相关语义

当前输入模式的语音路由规则：

1. 不带前缀：默认按听写处理。
2. 带 `commandPrefixes`：本句临时按命令处理，执行完后继续保持输入模式。
3. 带 `dictationPrefixes`：本句强制按原文输入。
4. `命令 xxx` 未命中时：
   - 不能偷偷当普通文本打进输入框。
   - 应明确提示“未匹配命令”。

未来“打开 / 切换 App”落地时，也必须遵守同样的输入态安全约束：
- 在输入框里，`打开 Chrome 官网` 这类自然语言不应直接触发 App 切换。
- 只有显式命令前缀或明确的 command bias 才允许执行 `open/switch app`。
- `命令 打开 Xcode` 如果没有解析到目标 App，不能回退为普通听写。

## 6. 禁止硬编码要求

以下内容不允许直接写死在业务代码里：

- 面向用户的提示文案
- AI 提示词正文
- 语音词库默认配置
- 导入导出 JSON 模板
- 语音前缀、唤醒词、默认命令别名

未来补充：
- App 显示名到目标 App 的默认 alias 映射
- 动作词层的默认触发词（如 `打开` / `切到` / `open` / `switch to`）

必须放在：

- `Localizable.strings`
- 资源文件，例如 `VoiceLexiconDefaults.json`

如果后续为 App alias / resolver 引入单独资源文件，也必须把默认映射放在资源层，而不是业务代码里维护散落常量。

代码只负责：

- 读取资源
- 替换占位符
- 合并用户 override
- 把“最终生效值”正确反映到 UI

## 7. 当前代码锚点

与本文档直接对应的核心文件：

- `Apps/Apps/AetherCore/Speech/VoiceLexiconDefaults.swift`
- `Apps/Apps/AetherCore/Resources/VoiceLexiconDefaults.json`
- `Apps/Apps/AetherCore/Speech/WakeWordDetector.swift`
- `Apps/Apps/AetherCore/Speech/VoiceCommandRouter.swift`
- `Apps/Apps/AetherCore/AetherApp.swift`
- `Apps/Apps/AetherCore/SettingsModules.swift`

未来若实现 App 打开 / 切换能力，应补充新的代码锚点，例如：
- `AppTargetResolver`
- `AppAliasStore`
- `VoiceIntent.openApp / switchApp`

## 8. 后续修改要求

以后凡是涉及以下变更，必须同步更新本文档：

- 新增或删除语音词库字段
- 修改前缀、唤醒词、命令别名的默认来源
- 修改“空值 / 重置 / 合并 / 覆盖”的语义
- 把某类规则从语音词库迁出或迁入
- 修改输入模式下的“临时命令”路由行为
- 新增或调整 App 打开 / 切换能力的数据模型、默认 alias 来源或输入态安全规则
