# ChromaDB 混合检索调研报告

> 调研日期：2026-07-13 | 版本：v1.0 | 项目：Prometheus HICOOL 智能体赛道

---

## 目录

1. [ChromaDB 概述](#1-chromadb-概述)
2. [架构与存储](#2-架构与存储)
3. [稠密向量检索](#3-稠密向量检索)
4. [BM25 稀疏检索实现](#4-bm25-稀疏检索实现)
5. [RRF 融合排序算法](#5-rrf-融合排序算法)
6. [与其他向量数据库对比](#6-与其他向量数据库对比)
7. [性能分析](#7-性能分析)
8. [元数据过滤](#8-元数据过滤)
9. [Collection 设计](#9-collection-设计)
10. [Prometheus 集成方案](#10-prometheus-集成方案)

---

## 1. ChromaDB 概述

### 1.1 基本信息

| 属性 | 值 |
|------|-----|
| 开发方 | Chroma（trychroma.com） |
| 开源许可证 | Apache 2.0 |
| GitHub | https://github.com/chroma-core/chroma |
| 语言 | Python（核心）+ Rust（底层） |
| 当前版本 | 0.5.x |
| 定位 | 轻量级、本地优先的向量数据库 |
| 适用场景 | 原型开发、中小规模应用（< 1M 向量） |

### 1.2 核心特性

- **零配置**：`pip install chromadb` 即用，无需独立服务
- **持久化**：自动持久化到本地磁盘（SQLite + DuckDB 后端）
- **内置嵌入**：默认使用 sentence-transformers，可自定义嵌入函数
- **元数据过滤**：支持 `where` 条件过滤
- **HNSW 索引**：近似最近邻搜索，对数级查询复杂度

### 1.3 为什么选择 ChromaDB

| 理由 | 说明 |
|------|------|
| 本地优先 | 数据存储在本地磁盘，不上传云端，契合 Prometheus 隐私定位 |
| 零配置 | 不需要部署独立服务，`pip install` 即用 |
| 轻量级 | 依赖少，内存占用低 |
| Python 原生 | 与 Prometheus Python 引擎无缝集成 |
| 社区活跃 | GitHub 17k+ stars，文档齐全 |

---

## 2. 架构与存储

### 2.1 存储架构

```
ChromaDB 持久化目录
├── chroma.sqlite3          # SQLite 数据库（元数据、文档文本、关系）
└── <collection_id>/        # 每个 Collection 的向量索引
    ├── header.bin          # HNSW 索引头
    ├── data_level0.bin     # HNSW 索引数据
    └── link_lists.bin      # HNSW 图结构
```

### 2.2 后端数据库

| 组件 | 用途 | 说明 |
|------|------|------|
| SQLite | 元数据存储 | Collection 信息、文档 ID、文档文本、元数据 |
| DuckDB | 分析查询 | 复杂过滤查询优化（内部使用，对用户透明） |
| HNSW | 向量索引 | 近似最近邻搜索，基于图的索引结构 |

### 2.3 持久化方式

```python
import chromadb

# 持久化模式（Prometheus 使用）
client = chromadb.PersistentClient(path="~/.prometheus/data/chroma")

# 内存模式（测试用）
client = chromadb.Client()

# 服务器模式（多进程共享，Prometheus 不需要）
# 需要先启动 chroma server
```

---

## 3. 稠密向量检索

### 3.1 HNSW 算法

ChromaDB 使用 HNSW（Hierarchical Navigable Small World）算法进行近似最近邻搜索：

```
HNSW 索引结构:
  ├── Layer 0: 所有节点（完整图）
  ├── Layer 1: 部分节点（稀疏图）
  ├── Layer 2: 更少节点
  └── Layer L: 最少节点（顶层）

搜索过程:
  1. 从顶层开始，贪心搜索最近节点
  2. 逐层下降，每层缩小搜索范围
  3. 在 Layer 0 精确搜索 Top-K

时间复杂度: O(log N) 查询
```

### 3.2 距离度量

```python
# 创建 Collection 时指定距离度量
collection = client.create_collection(
    name="documents",
    metadata={
        "hnsw:space": "cosine",      # 余弦相似度（推荐用于 BGE-M3）
        # "hnsw:space": "l2",        # 欧氏距离
        # "hnsw:space": "ip",        # 内积
        "hnsw:construction_ef": 200,  # 构建时搜索宽度（默认 100）
        "hnsw:search_ef": 100,        # 查询时搜索宽度（默认 10）
        "hnsw:M": 16,                 # 图的连接度（默认 16）
    }
)
```

**推荐配置**：
- 距离度量：`cosine`（BGE-M3 输出已归一化，cosine 等价于内积）
- `hnsw:M`：16（默认值，10K-100K 文档足够）
- `hnsw:search_ef`：100（提高召回率，代价是稍慢）

### 3.3 查询 API

```python
# 按文本查询（ChromaDB 自动嵌入）
results = collection.query(
    query_texts=["GPU 算力"],
    n_results=5,
    where={"file_type": "md"},     # 元数据过滤
    include=["documents", "metadatas", "distances"]
)

# 按向量查询（手动嵌入，跳过 ChromaDB 嵌入）
results = collection.query(
    query_embeddings=[[0.1, 0.2, ...]],  # 1024d 向量
    n_results=5
)
```

---

## 4. BM25 稀疏检索实现

### 4.1 问题：ChromaDB 不原生支持稀疏检索

ChromaDB 是纯稠密向量数据库，不支持 BM25 稀疏检索。要实现混合检索，需要自建 BM25 索引。

### 4.2 方案：rank_bm25 + jieba

```python
from rank_bm25 import BM25Okapi
import jieba
import json
import os

class BM25Index:
    """BM25 稀疏检索索引"""

    def __init__(self, index_path="~/.prometheus/data/bm25_index.json"):
        self.index_path = os.path.expanduser(index_path)
        self.documents = []     # 原始文档
        self.doc_ids = []       # 文档 ID
        self.tokenized_docs = [] # 分词后的文档
        self.bm25 = None

    def add_documents(self, doc_ids, documents):
        """添加文档到索引"""
        for doc_id, doc in zip(doc_ids, documents):
            if doc_id not in self.doc_ids:
                self.doc_ids.append(doc_id)
                self.documents.append(doc)
                self.tokenized_docs.append(list(jieba.cut(doc)))

        # 重建 BM25 索引
        self.bm25 = BM25Okapi(self.tokenized_docs)
        self._save()

    def search(self, query, top_k=10):
        """BM25 搜索"""
        if not self.bm25:
            return []

        tokenized_query = list(jieba.cut(query))
        scores = self.bm25.get_scores(tokenized_query)

        # 按分数排序，取 Top-K
        ranked = sorted(
            enumerate(scores),
            key=lambda x: x[1],
            reverse=True
        )[:top_k]

        return [(self.doc_ids[i], score) for i, score in ranked]

    def _save(self):
        """持久化到 JSON 文件"""
        data = {
            "doc_ids": self.doc_ids,
            "documents": self.documents,
            "tokenized_docs": self.tokenized_docs
        }
        with open(self.index_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False)

    def load(self):
        """从 JSON 文件加载"""
        if os.path.exists(self.index_path):
            with open(self.index_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            self.doc_ids = data["doc_ids"]
            self.documents = data["documents"]
            self.tokenized_docs = data["tokenized_docs"]
            self.bm25 = BM25Okapi(self.tokenized_docs)
```

### 4.3 中文分词优化

```python
# 添加自定义词典（专业术语）
jieba.add_word("GPU")
jieba.add_word("CUDA")
jieba.add_word("Function Router")
jieba.add_word("MTClaw")

# 或加载自定义词典文件
jieba.load_userdict("~/.prometheus/config/user_dict.txt")
```

---

## 5. RRF 融合排序算法

### 5.1 算法原理

Reciprocal Rank Fusion（RRF）是一种简单的排名融合方法，不需要校准分数：

```
RRF_score(doc) = Σ 1 / (k + rank_i(doc))

其中:
  k = 60（平滑参数，通常 60 是最佳值）
  rank_i(doc) = 文档 doc 在第 i 个检索器中的排名（从 1 开始）
```

### 5.2 为什么选择 RRF

| 方法 | 优势 | 劣势 |
|------|------|------|
| RRF | 简单、无需分数校准、效果稳定 | 不考虑分数大小，只看排名 |
| Weighted Sum | 可调权重 | 需要校准不同检索器的分数范围 |
| RRF + Weighted | 兼顾排名和分数 | 复杂度高 |

**选择 RRF 的理由**：稠密检索的 cosine similarity（0-1）和 BM25 的 TF-IDF 分数（0-∞）量纲不同，直接加权需要复杂的校准。RRF 只用排名，避免了这个问题。

### 5.3 实现代码

```python
def rrf_fusion(dense_results, sparse_results, top_k=5, k=60):
    """
    RRF 融合稠密和稀疏检索结果。

    Args:
        dense_results: [(doc_id, score), ...] - 稠密检索结果
        sparse_results: [(doc_id, score), ...] - 稀疏检索结果
        top_k: 返回 Top-K
        k: RRF 平滑参数（默认 60）

    Returns:
        [(doc_id, rrf_score), ...] - 融合后排序结果
    """
    scores = {}

    # 稠密检索贡献
    for rank, (doc_id, _) in enumerate(dense_results, 1):
        scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank)

    # 稀疏检索贡献
    for rank, (doc_id, _) in enumerate(sparse_results, 1):
        scores[doc_id] = scores.get(doc_id, 0) + 1 / (k + rank)

    # 排序并取 Top-K
    sorted_results = sorted(scores.items(), key=lambda x: x[1], reverse=True)
    return sorted_results[:top_k]
```

### 5.4 效果预期

根据公开研究，RRF 融合稠密 + 稀疏检索通常比单一检索提升 5-15% 的 Top-K 召回率：

| 方法 | Top-5 召回率 [推测] |
|------|-------------------|
| 仅稠密检索 | ~80% |
| 仅 BM25 稀疏检索 | ~75% |
| RRF 融合 | ~85-90% |

> **注意**：以上为公开研究的一般性结论，非 Prometheus 实测。

---

## 6. 与其他向量数据库对比

| 维度 | ChromaDB | FAISS | Milvus | Qdrant | Weaviate |
|------|----------|-------|--------|--------|----------|
| 定位 | 本地优先向量库 | 向量检索库 | 分布式向量数据库 | 向量搜索引擎 | 全功能向量数据库 |
| 部署复杂度 | 极低（pip install） | 低 | 高（需 etcd + MinIO） | 中 | 中 |
| 持久化 | 自动（SQLite） | 需手动管理 | 自动 | 自动 | 自动 |
| 元数据过滤 | ✅（where 条件） | ❌ | ✅ | ✅ | ✅（GraphQL） |
| 嵌入函数 | ✅（内置） | ❌ | ❌ | ❌ | ✅（内置模块） |
| 稀疏检索 | ❌ | ❌ | ✅（2.4+） | ✅ | ✅ |
| 多租户 | ❌ | ❌ | ✅ | ✅ | ✅ |
| 最大规模 | ~1M 向量 | ~1B 向量 | ~10B 向量 | ~1B 向量 | ~1B 向量 |
| 内存占用 | 低（可磁盘换页） | 高（全内存） | 中 | 中 | 中 |
| Python 友好度 | ✅✅✅ | ✅✅ | ✅ | ✅✅ | ✅✅ |

**Prometheus 选择 ChromaDB 的理由**：
1. 本地优先，零配置部署
2. 个人知识库场景（< 100K 文档片段），ChromaDB 足够
3. Python 原生，与 Prometheus 引擎无缝集成
4. 元数据过滤满足需求（按文件类型/目录过滤）
5. 稀疏检索缺失通过 rank_bm25 补充

---

## 7. 性能分析

### 7.1 查询性能

> 以下数据来自 ChromaDB 官方 benchmark 和社区测试，非 Prometheus 实测。

| 文档数 | 向量维度 | 索引大小 | 查询延迟（Top-5） |
|--------|---------|---------|-----------------|
| 1,000 | 1024 | ~8MB | < 5ms |
| 10,000 | 1024 | ~80MB | < 10ms |
| 100,000 | 1024 | ~800MB | < 50ms |
| 1,000,000 | 1024 | ~8GB | ~200ms |

**Prometheus 场景**：
- 预估文档数：100-10,000 篇
- 每篇文档分段后约 10-50 个 chunk
- 总向量数：1,000-500,000 个
- 查询延迟预期：< 50ms（不含嵌入时间）
- 嵌入时间：~50-200ms（BGE-M3 CPU 推理）
- **总检索延迟预期：~100-300ms** [推测]

### 7.2 写入性能

| 操作 | 吞吐量 |
|------|--------|
| 单条添加 | ~1,000 条/s |
| 批量添加（batch_size=100） | ~10,000 条/s |

**Prometheus 场景**：
- 10 篇文档（~200 个 chunk）摄入预期：< 1s（不含嵌入时间）
- 嵌入时间：~10-40s（BGE-M3 CPU 推理）
- **总摄入延迟预期：~10-40s**（嵌入是瓶颈，不是 ChromaDB）

---

## 8. 元数据过滤

### 8.1 支持的过滤条件

```python
# 等值过滤
results = collection.query(
    query_texts=["GPU"],
    where={"file_type": "md"}
)

# 范围过滤
results = collection.query(
    query_texts=["GPU"],
    where={"chunk_index": {"$gte": 0, "$lte": 5}}
)

# 多条件
results = collection.query(
    query_texts=["GPU"],
    where={
        "$and": [
            {"file_type": "md"},
            {"source_dir": "notes"}
        ]
    }
)

# Or 条件
results = collection.query(
    query_texts=["GPU"],
    where={
        "$or": [
            {"file_type": "md"},
            {"file_type": "txt"}
        ]
    }
)
```

### 8.2 操作符

| 操作符 | 含义 | 示例 |
|--------|------|------|
| `$eq` | 等于（默认） | `{"file_type": "md"}` |
| `$ne` | 不等于 | `{"file_type": {"$ne": "csv"}}` |
| `$gt` | 大于 | `{"size": {"$gt": 1000}}` |
| `$gte` | 大于等于 | `{"size": {"$gte": 1000}}` |
| `$lt` | 小于 | `{"size": {"$lt": 1000}}` |
| `$lte` | 小于等于 | `{"size": {"$lte": 1000}}` |
| `$in` | 在列表中 | `{"file_type": {"$in": ["md", "txt"]}}` |
| `$and` | 且 | `{"$and": [...]}` |
| `$or` | 或 | `{"$or": [...]}` |

### 8.3 Prometheus 中的过滤场景

```python
# 按文件类型过滤
where={"file_type": "md"}

# 按目录过滤
where={"source_dir": "notes"}

# 按文件名过滤
where={"source_path": "/data/notes/gpu_report.md"}

# 组合过滤
where={
    "$and": [
        {"file_type": {"$in": ["md", "txt"]}},
        {"ingested_at": {"$gte": "2026-07-01"}}
    ]
}
```

---

## 9. Collection 设计

### 9.1 分离 vs 共享

| 方案 | 优势 | 劣势 | Prometheus 选择 |
|------|------|------|----------------|
| 单 Collection（共享） | 跨域检索方便 | 不同数据类型的元数据混乱 | ❌ |
| 多 Collection（分离） | 数据隔离、查询高效 | 跨域检索需要多次查询 | ✅ |

### 9.2 Prometheus 的 Collection 设计

```
ChromaDB
├── Collection: "documents"       # RAG 文档向量
│   ├── 向量: BGE-M3 1024d
│   ├── 元数据: source_path, file_type, chunk_index, title, ingested_at
│   └── 距离度量: cosine
│
└── Collection: "memories"        # 用户记忆向量
    ├── 向量: BGE-M3 1024d
    ├── 元数据: memory_id, category, importance
    └── 距离度量: cosine
```

### 9.3 为什么分离

1. **查询效率**：RAG 检索只查 `documents`，不需要过滤掉 memories
2. **元数据隔离**：文档有 `source_path`，记忆有 `category`，字段不同
3. **嵌入内容不同**：文档嵌入的是文本片段，记忆嵌入的是 `"{key}: {value}"`
4. **维护方便**：可以独立重建索引、独立清理过期数据

---

## 10. Prometheus 集成方案

### 10.1 完整检索流程

```
用户查询 "GPU 算力"
  │
  ├── Step 1: 嵌入查询
  │     query → BGE-M3 → 1024d 稠密向量
  │     query → jieba 分词 → BM25 查询
  │
  ├── Step 2: 稠密检索
  │     ChromaDB collection.query(query_embeddings=[...], n_results=10)
  │     → Top-10 稠密结果 [(doc_id, cosine_score)]
  │
  ├── Step 3: 稀疏检索
  │     BM25Index.search(query, top_k=10)
  │     → Top-10 稀疏结果 [(doc_id, bm25_score)]
  │
  ├── Step 4: RRF 融合
  │     rrf_fusion(dense_results, sparse_results, top_k=5, k=60)
  │     → Top-5 融合结果 [(doc_id, rrf_score)]
  │
  ├── Step 5: 元数据补充
  │     从 ChromaDB 获取 doc_id 对应的文档文本和元数据
  │
  └── Step 6: 返回结果
        [{source, content, score, metadata}]
```

### 10.2 初始化代码

```python
import chromadb
from chromadb.utils import embedding_functions
from rank_bm25 import BM25Okapi
import jieba
import os

class HybridSearchEngine:
    """Prometheus 混合检索引擎"""

    def __init__(self, data_dir="~/.prometheus/data"):
        self.data_dir = os.path.expanduser(data_dir)
        self.chroma_path = os.path.join(self.data_dir, "chroma")
        self.bm25_path = os.path.join(self.data_dir, "bm25_index.json")

        # ChromaDB 客户端
        self.client = chromadb.PersistentClient(path=self.chroma_path)

        # 嵌入函数
        self.ef = embedding_functions.SentenceTransformerEmbeddingFunction(
            model_name="BAAI/bge-m3",
            device="cpu"
        )

        # 文档 Collection
        self.collection = self.client.get_or_create_collection(
            name="documents",
            embedding_function=self.ef,
            metadata={"hnsw:space": "cosine"}
        )

        # BM25 索引
        self.bm25_index = BM25Index(self.bm25_path)
        self.bm25_index.load()

    def search(self, query, top_k=5, source_filter=None):
        """混合检索"""
        # 稠密检索
        where = {"file_type": source_filter} if source_filter else None
        dense_results = self.collection.query(
            query_texts=[query],
            n_results=top_k * 2,
            where=where
        )

        # 稀疏检索
        sparse_results = self.bm25_index.search(query, top_k=top_k * 2)

        # RRF 融合
        fused = rrf_fusion(
            dense_results=list(zip(
                dense_results['ids'][0],
                dense_results['distances'][0]
            )),
            sparse_results=sparse_results,
            top_k=top_k
        )

        # 补充文档内容
        results = []
        for doc_id, score in fused:
            meta = self.collection.get(ids=[doc_id])
            results.append({
                "doc_id": doc_id,
                "content": meta['documents'][0] if meta['documents'] else "",
                "source": meta['metadatas'][0].get('source_path', '') if meta['metadatas'] else '',
                "score": score
            })

        return results
```

### 10.3 依赖清单

```txt
chromadb>=0.5
sentence-transformers>=2.7
rank_bm25>=0.2.2
jieba>=0.42.1
```

---

## 附录：性能测试脚本

```python
#!/usr/bin/env python3
"""ChromaDB 混合检索性能测试"""
import time
import chromadb
from chromadb.utils import embedding_functions

# 初始化
ef = embedding_functions.SentenceTransformerEmbeddingFunction(
    model_name="BAAI/bge-m3", device="cpu"
)
client = chromadb.PersistentClient(path="/tmp/chroma_test")
collection = client.get_or_create_collection(
    name="test", embedding_function=ef,
    metadata={"hnsw:space": "cosine"}
)

# 插入测试数据
docs = [f"测试文档内容 {i}" for i in range(1000)]
ids = [f"doc_{i}" for i in range(1000)]
metadatas = [{"index": i} for i in range(1000)]

t0 = time.time()
collection.add(documents=docs, ids=ids, metadatas=metadatas)
print(f"插入 1000 条耗时: {time.time() - t0:.2f}s")

# 查询测试
t0 = time.time()
results = collection.query(query_texts=["测试文档"], n_results=5)
print(f"查询耗时: {(time.time() - t0) * 1000:.0f}ms")
print(f"结果数: {len(results['ids'][0])}")

# 过滤查询
t0 = time.time()
results = collection.query(
    query_texts=["测试文档"],
    n_results=5,
    where={"index": {"$gte": 500}}
)
print(f"过滤查询耗时: {(time.time() - t0) * 1000:.0f}ms")
```
