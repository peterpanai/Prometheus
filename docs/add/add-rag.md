# ADD — RAG 知识库 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`rag`

## 1. 背景

用户需要将本地文档（.md/.pdf/.txt/.docx/.csv）索引到向量数据库，并通过自然语言进行语义检索。这是个人知识管理的核心场景，数据不出设备。

## 2. 调研

### 2.1 Hermes

- **内存搜索**：`~/ws/hermes-agent/agent/memory_search.py` — Hermes 的记忆/RAG 主要针对对话记忆而非文档索引
- **文件操作**：`~/ws/hermes-agent/tools/file_tools.py` 提供 `read_file`、`write_file`、`search_files`，无内置文档向量化
- **插件**：`plugins/memory/` 提供会话记忆，非文档 RAG

### 2.2 OpenClaw

- **Memory 系统**：`~/ws/openclaw/src/memory/` — 完整的 embedding-based 搜索 + SQLite 存储
- **Memory Host SDK**：`~/ws/openclaw/src/memory-host-sdk/` — query, dreaming, events, multimodal
- **Embedding Providers**：`~/ws/openclaw/src/plugins/memory-embedding-providers.ts` — 可插拔嵌入提供商
- **Memory Search**：`~/ws/openclaw/src/agents/memory-search.ts` — 搜索配 resolution
- **工具可用性**：遵循 `ToolAvailabilitySignal` 模型

### 2.3 Codex

- **Memories 模块**：`~/ws/codex/codex-rs/memories/read/src/lib.rs` / `write/src/lib.rs` — 记忆读写
- **文件搜索**：`~/ws/codex/codex-rs/file-search/src/lib.rs` — 基于 CLI 的文件 grep
- **无内置文档向量化**：Codex 的记忆系统主要用于用户偏好，非文档 RAG

### 2.4 结论

三个代码库将"记忆"（用户偏好/情节）和"文档检索"（RAG）作为两个不同概念处理。Prometheus 继承这一分层：Memory Subagent 管用户记忆，RAG Subagent 管文档索引检索。

## 3. 设计决策

### 3.1 嵌入模型选择

| 候选 | 维度 | 本地运行 | 中文支持 | 资源需求 |
|------|------|---------|---------|---------|
| BGE-M3 | 1024 | CPU/GPU | 优秀 | ~2GB |
| text2vec-large-chinese | 1024 | CPU | 优秀 | ~1.3GB |
| moka-ai/m3e-base | 768 | CPU | 良好 | ~500MB |

**决策**：BGE-M3（多语言，1024d，支持稀疏+稠密混合检索，HuggingFace MTEB 排名最高）

### 3.2 分段策略

```
策略：按标题 + 段落分割
- Markdown: 按 ## 标题分段，子段按空行切分
- PDF: pdfplumber 提取文本后按连续段落分段
- TXT: 按空行 + 字符数（max 512）分段
- DOCX: python-docx 按段落分段，合并短段
- CSV: 每行一个 chunk，列名作为 metadata

chunk_size: 512 tokens (中文约 350 字)
overlap: 64 tokens
```

### 3.3 检索增强

- **混合检索**：稠密向量（BGE-M3）+ BM25 稀疏检索，RRF 融合排序
- **知识图谱扩展**：检索结果关联知识图谱节点，返回双向链接的关联文档

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "rag",
  "version": "1.0.0",
  "description": "RAG 知识库 Subagent — 文档索引与语义检索",
  "enabled": true,
  "priority": 5,
  "requires": {
    "packages": ["chromadb>=0.5", "sentence-transformers>=2.7", "pdfplumber>=0.10", "python-docx>=1.0"]
  },
  "provides": {
    "tools": ["rag_search", "rag_ingest", "rag_status"],
    "engines": ["rag_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["找一下", "搜索", "查一下", "导入知识库", "知识库状态"],
    "trigger_patterns": ["帮我找.*", "搜索.*文档", "导入.*到知识库"],
    "match_priority": "normal"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.1，3 个工具：`rag_search`、`rag_ingest`、`rag_status`。

### 4.3 Python 引擎接口

```python
# rag_engine.py
def search(query: str, top_k: int = 5, source_filter: str = None) -> dict
def ingest(path: str, recursive: bool = True) -> dict
def status() -> dict
```

## 5. 实现 Checklist

### 数据层

- [ ] RAG-001 初始化 ChromaDB Collection `documents`（1024d, cosine）
- [ ] RAG-002 初始化 ChromaDB Collection `documents_bm25`（稀疏向量）
- [ ] RAG-003 创建 SQLite 表 `documents`（id, path, file_type, title, chunk_count, ingested_at, size_bytes）

### 文档摄入

- [ ] RAG-004 实现 `.md` 分段器（按 ## 标题 + 空行）
- [ ] RAG-005 实现 `.pdf` 分段器（pdfplumber 提取文本 → 段落分段）
- [ ] RAG-006 实现 `.txt` 分段器（空行 + 字符截断）
- [ ] RAG-007 实现 `.docx` 分段器（python-docx 段落合并）
- [ ] RAG-008 实现 `.csv` 分段器（每行一个 chunk）
- [ ] RAG-009 实现 BGE-M3 嵌入生成（sentence-transformers, device=cpu）
- [ ] RAG-010 实现批量摄入 + 去重（file_hash 检测，跳过已索引文件）
- [ ] RAG-011 实现递归目录摄入

### 文档检索

- [ ] RAG-012 实现稠密向量检索（ChromaDB query）
- [ ] RAG-013 实现 BM25 稀疏检索
- [ ] RAG-014 实现 RRF 混合检索融合排序
- [ ] RAG-015 实现 source_filter（按文件类型/目录过滤）
- [ ] RAG-016 实现检索结果关联知识图谱节点（调用 graph_engine.find_related）

### Wrapper 脚本

- [ ] RAG-017 编写 `rag_search.sh`（stdin JSON → Python → stdout JSON）
- [ ] RAG-018 编写 `rag_ingest.sh`
- [ ] RAG-019 编写 `rag_status.sh`

### 测试

- [ ] RAG-020 单元测试：分段器（每种格式 3 个样本文件）
- [ ] RAG-021 单元测试：嵌入生成一致性
- [ ] RAG-022 单元测试：检索召回率（Top-5 > 90%）
- [ ] RAG-023 集成测试：ingest → search 端到端
- [ ] RAG-024 集成测试：source_filter 过滤正确性
- [ ] RAG-025 集成测试：重复摄入去重

## 6. 参考

- ChromaDB: https://docs.trychroma.com/
- BGE-M3: https://huggingface.co/BAAI/bge-m3
- OpenClaw Memory Host SDK: `~/ws/openclaw/src/memory-host-sdk/`
