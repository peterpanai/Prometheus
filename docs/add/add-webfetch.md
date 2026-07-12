# ADD - WebFetch 网页抓取 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：**archived** | 插件名：`webfetch`
>
> **v3.0 变更**：此 Subagent 已在 v3.0 中砍掉。WebFetch 场景由上游 LLM 兜底覆盖。本文档保留作为历史参考。

## 归档原因

1. 减少工具数量，提高路由准确率
2. 上游 LLM 兜底已覆盖网页抓取场景
3. SSRF 防护和正文提取实现复杂度高，开发量大
4. 开发资源聚焦在 5 个核心 Subagent 上

## 原始设计（参考）

详细设计见 git 历史 commit `a619c31`。核心要点：

- SSRF 双重校验（URL scheme + DNS->IP 黑名单）
- 4 种 extract_mode（auto/article/full_page/markdown）
- SQLite 缓存（TTL 60 分钟）
- 批量抓取（asyncio 并发，最多 10 个 URL）

如需恢复此 Subagent，可从 git 历史中恢复完整文档。
