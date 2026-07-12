# ADD - WebSearch 网页搜索 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：**archived** | 插件名：`websearch`
>
> **v3.0 变更**：此 Subagent 已在 v3.0 中砍掉。WebSearch 场景由上游 LLM 兜底覆盖（上游 LLM 本身具备联网搜索能力）。本文档保留作为历史参考。

## 归档原因

1. 减少工具数量，提高路由准确率（工具数从 24 降到 15）
2. 上游 LLM 兜底已覆盖搜索场景
3. DuckDuckGo 免费API 不稳定，演示中可能翻车
4. 开发资源聚焦在 5 个核心 Subagent 上

## 原始设计（参考）

详细设计见 git 历史 commit `a619c31`。核心要点：

- DuckDuckGo 默认后端 + SearXNG/SerpAPI fallback
- search+fetch 二合一工具（`web_search_fetch`）
- 搜索结果缓存 30 分钟
- 速率限制 10rpm + 429 自动退避

如需恢复此 Subagent，可从 git 历史中恢复完整文档。
