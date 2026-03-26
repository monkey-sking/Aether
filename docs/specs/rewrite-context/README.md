# Rewrite Context Spec

本 Spec 定义 Aether `全文优化 / 全文纠错优化` 的上下文模型。

目标不是让系统“记住上一次调用”，而是让系统更接近用户感知中的同一件事：

- 我是不是还在改同一篇内容
- 我现在是在聊天、写邮件、写文档，还是写技术内容
- 我在这个场景下长期喜欢什么风格

本 Spec 采用结构化文档：

- `requirements.md`：产品需求与验收标准
- `design.md`：上下文模型、信号优先级、隔离规则、v1 落地策略
- `tasks.md`：后续实现与验证任务

工作流标签：`feature/rewrite-context`
