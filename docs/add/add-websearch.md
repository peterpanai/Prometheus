# ADD — WebSearch 网页搜索 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`websearch`

## 1. 背景

用户需要通过自然语言在互联网上搜索信息，并将搜索结果作为上下文注入后续处理（如写作、分析）。核心挑战在于搜索引擎后端可替换性和搜索+抓取二合一的体验。

## 2. 调研

### 2.1 Hermes

- **web_search_tool**：`~/ws/hermes-agent/tools/web_tools.py:619` — 同步搜索，7 个 provider
- **Provider 注册表**：Brave Search, DuckDuckGo, SearXNG, Exa, Parallel, Tavily, Firecrawl
- **返回格式**：`{success, data: {web: [{title, url, description, position}]}}`
- **配置驱动**：通过 env var 和 config 切换 provider
- **无 search+fetch 二合一**：需要单独调用 web_extract

### 2.2 OpenClaw

- **web_search 工具**：`~/ws/openclaw/src/agents/tools/web-search.ts` — 完善的搜索工具
- **参数丰富**：query, count, country, language, freshness, domain filtering
- **Provider 运行时**：`~/ws/openclaw/src/web-search/runtime.ts`
- **Provider 插件**：`~/ws/openclaw/src/plugins/web-search-providers.runtime.ts`
- **工具搜索**：`~/ws/openclaw/src/agents/tools/tool-search.ts` — 延迟加载工具

### 2.3 Codex

- **Web Search**：`~/ws/codex/codex-rs/core/src/web_search.rs` — action detail formatting
- **两种模式**：hosted (`web_search` tool spec) + standalone (extension)
- **Feature flags**：`WebSearchRequest`, `WebSearchCached`, `StandaloneWebSearch`
- **搜索过滤**：`WebSearchMode`, `WebSearchUserLocation`, `WebSearchFilters`

### 2.4 结论

三个代码库都支持多 provider 的 web search。Hermes 的 provider 注册表模式最为灵活（7 个 provider），OpenClaw 的参数最全面（country/language/freshness/domain），Codex 的双模式（hosted/standalone）提供了架构参考。Prometheus 采用 DuckDuckGo 作为默认免费后端 + 可配置升级到 SerpAPI/SearXNG，并创新地提供 search+fetch 二合一工具。

## 3. 设计决策

### 3.1 搜索引擎后端

| 后端 | 类型 | API Key | 日配额 | 延迟 |
|------|------|---------|--------|------|
| DuckDuckGo | 免费 | 不需要 | ~100 次 | 1-3s |
| SearXNG | 自部署 | 不需要 | 无限 | 1-2s |
| SerpAPI | 付费 | 需要 | 按套餐 | <1s |

**默认后端**：DuckDuckGo（零配置，开箱即用）

### 3.2 搜索+抓取二合一

`web_search_fetch` 是 Prometheus 的创新工具：

```
web_search_fetch(query, fetch_top_k=3) →
  1. web_search(query, num_results=fetch_top_k * 2) → Top 2K 搜索结果
  2. asyncio 并发调用 web_fetch(url) × K → 抓取正文
  3. 去重 + 合并 → 按相关度排序
  4. 返回 [{url, title, snippet, full_content}] 完整信息
```

### 3.3 搜索结果缓存

搜索结果缓存 30 分钟（比网页内容缓存的 60 分钟更短，因为搜索结果的时效性更重要）。

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "websearch",
  "version": "1.0.0",
  "description": "WebSearch 网页搜索 Subagent — 在线搜索 + 结果抓取二合一",
  "enabled": true,
  "priority": 3,
  "requires": {
    "plugins": ["webfetch"],
    "packages": ["duckduckgo-search>=6.0"]
  },
  "provides": {
    "tools": ["web_search", "web_search_fetch"],
    "engines": ["web_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["搜索", "搜一下", "查一下网上", "谷歌", "最新消息", "search"],
    "trigger_patterns": ["搜索.*", "查.*网上", "最新.*消息"],
    "match_priority": "high"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.8，2 个工具：`web_search`、`web_search_fetch`。

### 4.3 Python 引擎接口

```python
# web_engine.py (search 部分)
def search_web(query: str, num_results: int = 5, search_type: str = "general",
               time_range: str = "any", backend: str = "duckduckgo") -> dict
def search_and_fetch(query: str, fetch_top_k: int = 3, search_type: str = "general",
                     backend: str = "duckduckgo") -> dict
```

## 5. 实现 Checklist

### 搜索引擎集成

- [ ] WSR-001 实现 DuckDuckGo backend（duckduckgo-search 库）
- [ ] WSR-002 实现 SearXNG backend（httpx → SearXNG API）
- [ ] WSR-003 实现 SerpAPI backend（httpx → SerpAPI）
- [ ] WSR-004 实现 backend 自动 fallback（DuckDuckGo → SearXNG → SerpAPI）
- [ ] WSR-005 实现 backend 配置读取（config.json `web_search.backend`）

### 搜索功能

- [ ] WSR-006 实现 `search_web()` — 调用后端搜索 API
- [ ] WSR-007 实现 search_type 过滤（general / news / image / scholar）
- [ ] WSR-008 实现 time_range 过滤（any / day / week / month / year）
- [ ] WSR-009 实现结果标准化（各后端统一为 `{title, url, snippet, date}`）
- [ ] WSR-010 实现结果缓存（SQLite `web_search_cache` 表，TTL 30min）

### 搜索+抓取二合一

- [ ] WSR-011 实现 `search_and_fetch()` — 搜索 → 并发抓取 → 合并
- [ ] WSR-012 实现结果去重（URL + title 相似度）
- [ ] WSR-013 实现相关度排序（搜索 rank + 抓取内容长度 加权）
- [ ] WSR-014 实现并发控制（asyncio.Semaphore，最多 5 个并发抓取）

### 速率限制

- [ ] WSR-015 实现速率限制（每分钟 10 次请求，可配置）
- [ ] WSR-016 实现 429 响应自动退避重试

### Wrapper 脚本

- [ ] WSR-017 编写 `web_search.sh`
- [ ] WSR-018 编写 `web_search_fetch.sh`

### 测试

- [ ] WSR-019 单元测试：DuckDuckGo 搜索返回正确格式
- [ ] WSR-020 单元测试：search_type 过滤
- [ ] WSR-021 单元测试：time_range 过滤
- [ ] WSR-022 单元测试：backend fallback 逻辑
- [ ] WSR-023 单元测试：结果缓存命中/过期
- [ ] WSR-024 单元测试：速率限制触发
- [ ] WSR-025 集成测试：web_search 端到端
- [ ] WSR-026 集成测试：web_search_fetch 端到端（搜索 + 抓取合并）
- [ ] WSR-027 集成测试：并发抓取控制

## 6. 参考

- Hermes Web Search: `~/ws/hermes-agent/tools/web_tools.py:619`
- Hermes Web Search Registry: `~/ws/hermes-agent/tools/web_tools.py` (7 providers)
- OpenClaw Web Search: `~/ws/openclaw/src/agents/tools/web-search.ts`
- OpenClaw Web Search Runtime: `~/ws/openclaw/src/web-search/runtime.ts`
- Codex Web Search: `~/ws/codex/codex-rs/core/src/web_search.rs`
- duckduckgo-search: https://github.com/deedy5/duckduckgo_search
- SearXNG API: https://docs.searxng.org/dev/search_api.html
