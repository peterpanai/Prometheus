# ADD — WebFetch 网页抓取 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`webfetch`

## 1. 背景

用户需要抓取网页内容并提取可读正文，将 HTML 转为 Markdown 供后续处理。核心挑战在于 SSRF 防护、正文提取质量和速率控制。

## 2. 调研

### 2.1 Hermes

- **web_extract_tool**：`~/ws/hermes-agent/tools/web_tools.py:743` — 异步提取 URL 内容
- **提取模式**：返回 clean page content (markdown/text)
- **分页截断**：超长页面 head+tail 截断
- **SSRF 防护**：`validate_url()` 检查 URL 安全性
- **无批量抓取**：一次一个 URL

### 2.2 OpenClaw

- **web_fetch 工具**：`~/ws/openclaw/src/agents/tools/web-fetch.ts` — 完整的 HTTP 抓取
- **SSRF 守卫**：内网 IP 拦截
- **Provider 系统**：`~/ws/openclaw/src/web-fetch/runtime.ts` — 可插拔提供商
- **Content Extractors**：`~/ws/openclaw/src/web-fetch/content-extractors.runtime.ts` — readability-based 提取
- **Provider 插件**：`~/ws/openclaw/src/plugins/web-fetch-providers.runtime.ts`
- **缓存**：内容缓存机制
- **配置**：支持 `webFetchProvider` 配置

### 2.3 Codex

- **无独立 web_fetch**：Web 抓取通过 MCP 工具实现
- **Web Search**：`codex-rs/core/src/web_search.rs` — web_search 与 fetch 分离
- **MCP 路由**：`codex-rs/core/src/tools/handlers/mcp.rs`

### 2.4 结论

OpenClaw 的 web_fetch 设计最为完善（SSRF 防护 + 可插拔提供商 + readability 提取 + 缓存）。Hermes 的 web_extract 更轻量。Codex 将 web_fetch 委托给 MCP 工具。Prometheus 参考 OpenClaw 的架构，简化 provider 层（直接用 httpx + readability-lxml），并增加批量抓取和缓存机制。

## 3. 设计决策

### 3.1 SSRF 防护

参考 OpenClaw 的 SSRF guard：

```python
import ipaddress
import socket

BLOCKED_NETWORKS = [
    ipaddress.ip_network('127.0.0.0/8'),     # Loopback
    ipaddress.ip_network('10.0.0.0/8'),      # Private A
    ipaddress.ip_network('172.16.0.0/12'),   # Private B
    ipaddress.ip_network('192.168.0.0/16'),  # Private C
    ipaddress.ip_network('169.254.0.0/16'),  # Link-local
    ipaddress.ip_network('0.0.0.0/8'),       # Current network
]

def is_safe_url(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in ('http', 'https'):
        return False
    # DNS 解析
    ip = socket.gethostbyname(parsed.hostname)
    # 检查内网 IP
    addr = ipaddress.ip_address(ip)
    for network in BLOCKED_NETWORKS:
        if addr in network:
            return False
    return True
```

### 3.2 正文提取策略

```
extract_mode:
  auto      → 自动判断（非 HTML → 原文返回；HTML → readability 提取）
  article   → 强制 readability-lxml 正文提取
  full_page → 全部 HTML → html2text Markdown 转换
  markdown  → 同 full_page，但先 readability 过滤再转换
```

### 3.3 缓存机制

```sql
CREATE TABLE web_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT NOT NULL UNIQUE,
    title TEXT,
    content TEXT,
    content_length INTEGER,
    extract_mode TEXT,
    fetched_at TEXT DEFAULT (datetime('now')),
    ttl_minutes INTEGER DEFAULT 60
);
CREATE INDEX idx_web_cache_url ON web_cache(url);
```

缓存 TTL 默认 60 分钟，可配置。

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "webfetch",
  "version": "1.0.0",
  "description": "WebFetch 网页抓取 Subagent — 安全抓取网页 + Markdown 转换",
  "enabled": true,
  "priority": 2,
  "requires": {
    "packages": ["httpx>=0.24", "readability-lxml>=0.8", "html2text>=2024"]
  },
  "provides": {
    "tools": ["web_fetch", "web_fetch_batch"],
    "engines": ["web_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["抓取", "看看这个网页", "读一下", "打开链接", "fetch"],
    "trigger_patterns": ["抓取.*http", "看看.*网页", "读.*链接"],
    "match_priority": "high"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.7，2 个工具：`web_fetch`、`web_fetch_batch`。

### 4.3 Python 引擎接口

```python
# web_engine.py (fetch 部分)
def fetch_url(url: str, extract_mode: str = "auto", timeout: int = 15) -> dict
def fetch_batch(urls: list[str], extract_mode: str = "auto") -> list[dict]
```

## 5. 实现 Checklist

### SSRF 防护

- [ ] WFT-001 实现 URL 协议检查（仅允许 http/https）
- [ ] WFT-002 实现内网 IP 黑名单（7 个 CIDR 段）
- [ ] WFT-003 实现 DNS 解析后二次 IP 校验（防 DNS rebinding）
- [ ] WFT-004 实现 file:// 协议禁止

### 网页抓取

- [ ] WFT-005 实现 httpx 异步 GET 请求（User-Agent 伪装 + 重定向跟随）
- [ ] WFT-006 实现 Content-Type 检查（仅处理 text/html, application/json, text/plain）
- [ ] WFT-007 实现响应大小限制（单页最大 5MB）
- [ ] WFT-008 实现请求超时（默认 15s，硬上限 30s）

### 正文提取

- [ ] WFT-009 实现 extract_mode=auto 自动判断逻辑
- [ ] WFT-010 实现 extract_mode=article（readability-lxml 正文提取）
- [ ] WFT-011 实现 extract_mode=full_page（html2text 全文转换）
- [ ] WFT-012 实现 extract_mode=markdown（readability 过滤 + html2text 转换）
- [ ] WFT-013 实现 title 提取（`<title>` 标签 + og:title meta）

### 缓存

- [ ] WFT-014 创建 SQLite 表 `web_cache` + 索引
- [ ] WFT-015 实现缓存读写逻辑（URL 匹配 → 未过期直接返回）
- [ ] WFT-016 实现缓存 TTL 清理调度

### 批量抓取

- [ ] WFT-017 实现 `fetch_batch()` — asyncio 并发抓取（最多 10 个 URL）
- [ ] WFT-018 实现速率限制（同一域名 1 req/s）

### Wrapper 脚本

- [ ] WFT-019 编写 `web_fetch.sh`
- [ ] WFT-020 编写 `web_fetch_batch.sh`

### 测试

- [ ] WFT-021 安全测试：内网 IP 拒绝（127.0.0.1, 192.168.x.x, 10.x.x.x）
- [ ] WFT-022 安全测试：file:// 协议拒绝
- [ ] WFT-023 安全测试：DNS rebinding 防护
- [ ] WFT-024 单元测试：4 种 extract_mode 输出正确性
- [ ] WFT-025 单元测试：Content-Type 过滤
- [ ] WFT-026 单元测试：超时处理
- [ ] WFT-027 单元测试：缓存命中/过期
- [ ] WFT-028 集成测试：fetch_url 端到端（真实外网 URL）
- [ ] WFT-029 集成测试：fetch_batch 并发控制

## 6. 参考

- OpenClaw web_fetch: `~/ws/openclaw/src/agents/tools/web-fetch.ts`
- OpenClaw SSRF Guard: `~/ws/openclaw/src/web-fetch/runtime.ts`
- OpenClaw Content Extractors: `~/ws/openclaw/src/web-fetch/content-extractors.runtime.ts`
- Hermes web_extract: `~/ws/hermes-agent/tools/web_tools.py:743`
- readability-lxml: https://github.com/buriy/python-readability
