# ADD - 数据分析 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：**archived** | 插件名：`data`
>
> **v3.0 变更**：此 Subagent 已在 v3.0 中砍掉。数据分析场景由上游 LLM 兜底覆盖（用户可以上传 CSV，上游 LLM 直接分析）。本文档保留作为历史参考。

## 归档原因

1. 减少工具数量，提高路由准确率
2. 上游 LLM 兜底已覆盖数据分析场景（如 GPT-4o 的 Code Interpreter）
3. 沙箱安全实现复杂（AST 审计 + restricted globals），演示中容易出问题
4. 开发资源聚焦在 5 个核心 Subagent 上

## 原始设计（参考）

详细设计见 git 历史 commit `a619c31`。核心要点：

- NL -> Pandas 代码生成（上游 LLM 生成代码）
- AST 安全审计（import 白名单）
- 沙箱 exec（restricted globals + SIGALRM timeout）
- 5 种图表模板（line/bar/pie/scatter/table）

如需恢复此 Subagent，可从 git 历史中恢复完整文档。
