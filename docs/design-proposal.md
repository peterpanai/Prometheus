# 普罗米修斯（Prometheus）设计方案

> 基于 MTClaw Function Router 的自我进化型个人认知智能体  
> 版本：v2.0 | 日期：2026-07-12 | 目标：HICOOL 智能体赛道

---

## 目录

1. [总体设计理念](#1-总体设计理念)
2. [功能详细设计](#2-功能详细设计)
   - 2.1 [插件系统架构](#21-插件系统架构)
   - 2.2 [RAG 知识库 Subagent](#22-rag-知识库-subagent)
   - 2.3 [记忆与反思 Subagent](#23-记忆与反思-subagent)
   - 2.4 [写作润色翻译 Subagent](#24-写作润色翻译-subagent)
   - 2.5 [数据分析 Subagent](#25-数据分析-subagent)
   - 2.6 [闲聊陪伴 Subagent](#26-闲聊陪伴-subagent)
   - 2.7 [Bash 命令行 Subagent](#27-bash-命令行-subagent)
   - 2.8 [WebFetch 网页抓取 Subagent](#28-webfetch-网页抓取-subagent)
   - 2.9 [WebSearch 网页搜索 Subagent](#29-websearch-网页搜索-subagent)
   - 2.10 [反思引擎](#210-反思引擎)
   - 2.11 [Subagent 协同机制](#211-subagent-协同机制)
3. [快：速度优势](#3-快速度)
4. [准：准确率优势](#4-准准确率)
5. [稳：可靠性优势](#5-稳可靠性)
6. [广：场景覆盖优势](#6-广场景覆盖)
7. [产品化完成度](#7-产品化完成度)
8. [商业价值](#8-商业价值)
9. [加分项](#9-加分项)
10. [评分维度对照矩阵](#10-评分维度对照矩阵)

---

## 1. 总体设计理念

### 1.1 一句话核心

**"Function Router 分而治之 + 插件化无损接入 + 后台反思自我进化"**

普罗米修斯不试图用一个巨型 Prompt 解决所有问题，而是通过 MTClaw Function Router 将用户意图精准分发到 8 个专职 Subagent，每个 Subagent 精雕细琢自己的领域；同时通过后台反思引擎，让 AI 在使用过程中持续学习用户习惯，实现"越用越懂你"。

### 1.2 三条设计原则

| 原则 | 含义 | 反模式规避 |
|------|------|-----------|
| **分治原则** | 一个 Subagent 只做一件事，做到极致 | 避免巨型 Prompt 导致延迟高、幻觉多 |
| **无损原则** | 每个 Subagent 以独立插件接入，对 MTClaw 零代码侵入 | 避免 fork 改 FR 代码导致升级困难 |
| **进化原则** | 每次交互都是训练数据，后台反思提取模式 | 避免传统 AI "用完即忘"的体验断层 |

### 1.3 架构总览

```
用户输入
  │
  ▼
Hermes Agent ──► MTClaw Function Router (:18790)
                    │
                    ├── 元数据清洗（移除 Hermes sender block 等）
                    ├── 记忆注入（memory_recall 自动注入用户画像）
                    ├── 路由模型判断（8 个 Subagent 工具定义，temperature=0.0）
                    │
                    ├─ rag_*         → RAG 知识库     (本地 ChromaDB，1-3s)
                    ├─ memory_*      → 记忆与反思     (SQLite + ChromaDB，<1s)
                    ├─ writing_*     → 写作润色翻译   (上游 LLM，10-40s)
                    ├─ data_*        → 数据分析       (上游 LLM + Pandas 沙箱，5-20s)
                    ├─ chat_light    → 闲聊陪伴       (路由模型直回，1-2s)
                    ├─ shell_*       → Bash 命令行   (subprocess 沙箱，<1-30s)
                    ├─ web_fetch_*   → WebFetch 抓取  (httpx + SSRF 防护，2-15s)
                    ├─ web_search_*  → WebSearch 搜索 (DuckDuckGo，2-10s)
                    └─ 未命中        → 上游 LLM 兜底  (15-40s)
                    │
                    ▼
              Completion Check
              ├─ TASK_COMPLETE    → 直接返回（快路径，占 80%+）
              └─ TASK_INCOMPLETE  → 转发上游 LLM（慢路径，占 20%-）

后台慢循环 (cron 每日凌晨 2:00 + 每 50 次交互触发):
  交互日志 → 反思引擎 → 提取偏好/主题/规律 → 更新记忆/图谱/策略 → 下次对话注入
```

### 1.4 调研基础

本设计基于对三个主流 AI Agent 代码库的深入调研：

| 代码库 | 路径 | 核心参考点 |
|--------|------|-----------|
| **Hermes** | `~/ws/hermes-agent` | 插件系统（plugin.yaml + register）、terminal_tool 多后端、delegate_task 子代理、web_search 7 provider 注册表 |
| **OpenClaw** | `~/ws/openclaw` | Plugin SDK（definePluginEntry + registerTool）、SSRF 防护 + readability 提取、memory host SDK（query/dream/events）、工具可用性模型（ToolAvailabilitySignal） |
| **Codex** | `~/ws/codex` | ToolRouter + ToolRegistry 分发、Orchestrator（审批+沙箱+重试分离）、multi_agents V2（spawn/send/wait 原语）、Extension API（tool_contributors） |

---

## 2. 功能详细设计

### 2.1 插件系统架构

#### 2.1.1 设计目标

8 个 Subagent 以**独立插件**形式存在，对 MTClaw Function Router **零代码侵入**。每个插件自包含工具定义、执行脚本和 Python 引擎，可独立开发、测试、启用和卸载。

#### 2.1.2 插件目录结构

```
~/.prometheus/plugins/<plugin-name>/
├── plugin.json              # 插件清单（必需）
├── functions.jsonl          # 工具定义（每行一个 JSON，MTClaw 原生格式）
├── scripts/                 # Bash Wrapper 脚本（FR 通过 subprocess 调用）
│   ├── <tool_name>.sh       # stdin JSON → stdout JSON
│   └── ...
├── engine.py                # Python 引擎模块（可选，由 .sh 调用）
└── requirements.txt         # 额外 Python 依赖（可选）
```

#### 2.1.3 plugin.json 清单规范

```json
{
  "name": "rag",
  "version": "1.0.0",
  "description": "RAG 知识库 Subagent — 文档索引与语义检索",
  "enabled": true,
  "priority": 5,
  "requires": {
    "env": ["PROMETHEUS_DATA_DIR"],
    "config": ["embedding_model"],
    "packages": ["chromadb>=0.5", "sentence-transformers>=2.7"],
    "plugins": []
  },
  "provides": {
    "tools": ["rag_search", "rag_ingest", "rag_status"],
    "engines": ["rag_engine.py"]
  },
  "lifecycle": {
    "on_load": null,
    "health_check": "scripts/health_check.sh"
  },
  "routing": {
    "trigger_keywords": ["找一下", "搜索文档", "导入知识库"],
    "trigger_patterns": ["帮我找.*", "搜索.*文档"],
    "match_priority": "normal"
  }
}
```

#### 2.1.4 插件生命周期

```
discover ──► validate ──► load ──► activate ──► run ──► deactivate ──► unload
   │            │          │         │           │          │
   │            │          │         │           │          └── 清理临时资源
   │            │          │         │           └── 处理路由请求，执行工具
   │            │          │         └── 注册到 FR，路由规则生效
   │            │          └── 执行 on_load，合并 functions.jsonl
   │            └── 校验 manifest/依赖/环境变量/脚本可执行性
   └── 扫描 ~/.prometheus/plugins/ 下所有 plugin.json
```

#### 2.1.5 无损接入 MTClaw 方案

这是整个系统最关键的设计决策——如何让 8 个 Subagent 在不修改 MTClaw 源码的前提下接入。

```
MTClaw Function Router 的启动参数：
  --functions-file <path>   ← 工具定义的 JSONL 文件
  --scripts-dir <path>      ← Bash Wrapper 脚本目录
  --config <path>           ← 主配置文件

Prometheus 的无损接入流程：
  Step 1. plugin_manager.py discover → 扫描 8 个插件目录
  Step 2. plugin_manager.py validate → 校验依赖、环境变量
  Step 3. plugin_manager.py activate →
           ├── 收集所有插件的 functions.jsonl → 合并去重
           ├── 写入 /tmp/prometheus_functions.jsonl（临时聚合文件）
           ├── 收集所有插件的 scripts/ → 统一 PATH
           └── 从各插件 routing 字段编译路由提示词
  Step 4. 启动 FR，传入聚合后的参数：
           python -m function_router.server \
             --functions-file /tmp/prometheus_functions.jsonl \
             --scripts-dir ~/.prometheus/plugins \
             --config ~/.prometheus/config/config.json
  Step 5. FR 加载工具定义 → 路由模型可调用全部 8 个 Subagent 的工具

MTClaw 完全不需要修改任何代码。Prometheus 只是一个"配置生成器"。
```

**接入方式对比**：

| 接入方式 | 是否修改 FR | 升级兼容性 | 维护成本 | Prometheus 采用 |
|---------|-----------|-----------|---------|----------------|
| Fork 改造 | 是 | 每次 FR 升级需手动合并 | 高 | ✗ |
| PR 合入上游 | 是 | 依赖上游 PR 接受 | 高 | ✗ |
| 配置文件注入 | **否** | FR 升级无影响 | 低 | **✓** |
| MCP Server | 否 | 需 FR 支持 MCP | 中 | 备选方案 |
| ACP 协议 | 否 | 需 FR 支持 ACP | 中 | 备选方案 |

#### 2.1.6 插件间依赖

```json
// writing 插件依赖 memory 插件（写作时需要注入用户偏好记忆）
{
  "requires": {
    "plugins": ["memory"],
    "reason": "writing_generate 需要调用 memory_recall 获取写作偏好"
  }
}
```

插件管理器在加载时对依赖做拓扑排序，缺失依赖的插件自动禁用并在日志中告警。

#### 2.1.7 接入实现 Checklist

- [ ] 实现 `plugin_manager.py` — discover / validate / load / activate / deactivate
- [ ] 实现 `plugin.json` JSON Schema 校验
- [ ] 实现 `functions.jsonl` 合并器（去重 + 冲突检测 + 优先级排序）
- [ ] 实现路由提示词生成器（从各插件 `routing` 字段编译 system prompt 注入）
- [ ] 实现依赖拓扑排序 + 循环检测
- [ ] 实现环境/依赖检查器（env / pip list / 脚本可执行性）
- [ ] 实现 FR 启动参数自动生成
- [ ] 实现 `prometheus plugin list/enable/disable/info/validate/install` CLI

---

### 2.2 RAG 知识库 Subagent

#### 2.2.1 功能定位

将用户的本地文档（.md / .pdf / .txt / .docx / .csv）索引到向量数据库，支持自然语言语义检索。数据全程不出设备。

#### 2.2.2 核心设计

**嵌入模型**：BAAI/bge-m3
- 维度：1024d
- 多语言（中英文均优秀），支持稠密 + 稀疏混合表征
- MTEB 检索基准排名靠前，HuggingFace 下载量 > 1000 万

**分段策略**：

| 文件类型 | 分段方法 | chunk_size | overlap |
|---------|---------|-----------|---------|
| .md | 按 `##` 标题分段，子段按空行切分 | 512 tokens (~350 中文字) | 64 tokens |
| .pdf | pdfplumber 提取文本 → 按连续段落分段 | 512 tokens | 64 tokens |
| .txt | 按空行 + 字符数上限截断 | 512 tokens | 64 tokens |
| .docx | python-docx 按段落分段，合并短段 | 512 tokens | 64 tokens |
| .csv | 每行一个 chunk，列名作为元数据 | 1 row | 0 |

**混合检索架构**：

```
用户查询 "GPU 算力对比"
  │
  ├── 稠密检索通道
  │     query → BGE-M3 向量化 (1024d) → ChromaDB cosine 检索 → Top K₁
  │
  ├── 稀疏检索通道
  │     query → BM25 分词 → ChromaDB 稀疏向量检索 → Top K₂
  │
  ├── RRF 融合排序 (Reciprocal Rank Fusion)
  │     score(doc) = Σ 1/(k + rank_i(doc))   // k=60
  │     → 合并去重，重排序 → Top K
  │
  ├── 知识图谱扩展
  │     检索结果关联知识图谱节点 → 返回双向链接的关联文档
  │     例：检索 "GPU" → 关联节点 "CUDA" / "MTT AIBOOK" / "算力测评"
  │
  └── 返回 {matches: [{source, content, score, related_nodes}]}
```

**去重机制**：摄入时计算文件 SHA256 hash，跳过已索引且未修改的文件。

#### 2.2.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `rag_search` | query, top_k=5, source_filter | 语义搜索本地文档 |
| `rag_ingest` | path, recursive=true | 导入文件/目录到知识库 |
| `rag_status` | — | 查询知识库状态 |

#### 2.2.4 接入方式

```
rag_ingest.sh 执行流程：
  stdin ← FR 传入 {"path": "/data/notes", "recursive": true}
  → python3 rag_engine.py ingest --path /data/notes --recursive
  → stdout → FR 接收 {"status": "ingested", "files": 12, "chunks": 156}
```

MTClaw FR 通过 `--functions-file` 加载 rag 的 3 个工具定义，通过 `--scripts-dir` 找到 `rag_search.sh` 等脚本。FR 调用 `rag_search` 工具时，相当于 `echo '{"query":"..."}' | bash rag_search.sh`。

#### 2.2.5 实现 Checklist

- [ ] 初始化 ChromaDB Collection `documents`（1024d, cosine 距离）
- [ ] 实现 5 种文件格式的分段器
- [ ] 实现 BGE-M3 嵌入生成（sentence-transformers, device=cpu）
- [ ] 实现稠密 + BM25 混合检索 + RRF 融合
- [ ] 实现文件去重（SHA256 hash）
- [ ] 实现 source_filter 过滤（按文件类型/目录）
- [ ] 实现检索结果关联知识图谱节点
- [ ] 编写 rag_search.sh / rag_ingest.sh / rag_status.sh
- [ ] 测试：Top-5 召回率 > 90%

---

### 2.3 记忆与反思 Subagent

#### 2.3.1 功能定位

记住用户偏好、身份、习惯和重要信息，跨会话持久化。后台反思引擎提取行为模式，实现主动推送和个性化服务。这是 Prometheus "自我进化" 的引擎。

#### 2.3.2 核心设计

**双存储模型**：

```
SQLite (结构化查询)              ChromaDB (语义检索)
─────────────────────          ─────────────────────
memories 表                    Collection: "memories"
  ├── category (preference/      ├── id: "mem_{sqlite_id}"
  │     identity/habit/note)     ├── embedding: BGE-M3 (1024d)
  ├── key (writing_format)       ├── document: "{key}: {value}"
  ├── value (markdown)           └── metadata: {category,
  ├── importance (1-5)                                importance}
  └── access_count

reminders 表                    用途：语义相似记忆检索
interaction_log 表
reflection_log 表

查询流程:
  memory_recall(context) →
    1. ChromaDB 语义检索 (context 向量化 → 相似度 Top K)
    2. SQLite 结构化补充 (importance >= 4 的记忆，无论相似度)
    3. 合并去重 → 按 importance DESC, similarity DESC 排序
    4. 返回 [{category, key, value, importance, similarity}]
```

**记忆生命周期**：

```
写入 (memory_remember)
  │
  ├── SQLite UPSERT (category + key 联合唯一)
  ├── ChromaDB upsert (同步写入向量)
  └── access_count 重置为 0

读取 (memory_recall)
  │
  ├── ChromaDB 语义检索
  ├── SQLite 高 importance 补充
  └── access_count += 1 (热记忆追踪)

衰减 (反思引擎，每日)
  │
  ├── access_count > 10 → importance 提升 1（热记忆强化）
  ├── access_count = 0 且 30 天未更新 → importance 降低 1（冷记忆衰减）
  └── importance < 2 的 note 类记忆 → 标记为可清理

清理 (手动/阈值触发)
  └── 总记忆数 > MAX_MEMORIES (1000) → 移除最低 importance 的记忆
```

#### 2.3.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `memory_remember` | category, key, value, importance=3 | 记录偏好/习惯/身份/笔记 |
| `memory_recall` | context, top_k=5, category | 语义检索相关记忆 |
| `memory_set_reminder` | content, time, repeat=once | 设置提醒 |

#### 2.3.4 接入方式

记忆 Subagent 有一个特殊之处：`memory_recall` 在**每次**用户请求前都会被 FR 自动调用，结果注入到 system prompt 中作为用户画像上下文。这是通过修改 FR 配置中的 system prompt 模板实现的，而非修改 FR 代码：

```
FR 配置中的 memory_injection:
  fr_context_history.enabled = true
  system_prompt_append = "[用户画像]\n{memory_recall_result}"

启动时，prometheus 启动器将上述配置写入 FR 的 config.json，
FR 本身不需要修改任何代码。
```

#### 2.3.5 实现 Checklist

- [ ] 创建 SQLite 表 memories / reminders / interaction_log / reflection_log + 索引
- [ ] 初始化 ChromaDB Collection `memories`
- [ ] 实现 memory_remember（SQLite UPSERT + ChromaDB 同步写入）
- [ ] 实现 memory_recall（语义检索 + 高 importance 补充 + 合并排序）
- [ ] 实现 memory_set_reminder（dateparser 解析自然语言时间）
- [ ] 实现 interaction_log 记录（每次工具调用后自动记录）
- [ ] 实现记忆衰减/强化逻辑（基于 access_count）
- [ ] 实现 memory_injector.py（请求前自动注入上下文）
- [ ] 测试：偏好召回准确率 > 90%

---

### 2.4 写作润色翻译 Subagent

#### 2.4.1 功能定位

场景化文档生成（周报/邮件/技术文档/会议纪要/文章/PPT大纲）、文本润色、多语言翻译。核心智能依赖上游 LLM，FR 的价值在于自动注入用户偏好记忆和参数标准化。

#### 2.4.2 核心设计

**模板系统**：

```
templates/
├── weekly_report.md      引导 LLM 按 "本周完成 / 下周计划 / 风险与问题" 三段式生成
├── email_formal.md       引导 LLM 按正式邮件格式（称呼/正文/签名档）生成
├── email_casual.md       引导 LLM 按非正式风格生成
├── tech_doc.md           引导 LLM 按 "概述/架构/接口/部署" 结构生成
├── meeting_minutes.md    引导 LLM 按 "议题/讨论/决议/待办" 结构生成
├── article.md            引导 LLM 按 "标题/导语/正文/结论" 结构生成
└── ppt_outline.md        引导 LLM 逐页生成 PPT 大纲
```

**偏好注入流水线**：

```
writing_generate("weekly_report", "本周工作总结") 被调用
  │
  ├── Step 1: 偏好获取
  │     memory_recall(context="writing weekly_report") →
  │       { writing_format: "markdown",
  │         preferred_language: "zh-CN",
  │         structure: "本周完成 + 下周计划 + 风险与问题",
  │         tone: "professional" }
  │
  ├── Step 2: 模板加载
  │     读取 templates/weekly_report.md → 获取三段式结构引导
  │
  ├── Step 3: Prompt 构造
  │     system_prompt = f"""
  │       你是专业的文档写作助手。
  │       用户偏好：{format}, {language}, {structure}, {tone}
  │       文档模板：{template}
  │     """
  │     user_prompt = f"主题：{topic}，要点：{key_points}"
  │
  ├── Step 4: 调用上游 LLM
  │     httpx → POST upstream_url/v1/chat/completions
  │
  └── Step 5: 返回
        {document: "## 本周完成\n...", format: "markdown"}
```

**润色的 changes_summary 机制**：

```
writing_polish(text, goal="more_concise") →
  ├── 调用上游 LLM 润色
  └── 二次调用 LLM: "对比原文和润色后，总结做了哪些修改"
       → changes_summary: "删除了 3 处冗余表达，合并了 2 个重复段落，将被动语态改为主动"
```

**参数枚举标准化**：所有参数使用 enum 约束，避免 LLM 歧义：
- `doc_type`：7 种枚举值
- `style`：4 种枚举值（formal / casual / technical / academic）
- `length`：3 种枚举值（short / medium / long）
- `goal`（润色）：5 种枚举值

#### 2.4.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `writing_generate` | doc_type, topic, key_points, style, length | 生成各类文档 |
| `writing_polish` | text, goal, target_language | 润色已有文本 |
| `writing_translate` | text, source_lang, target_lang, keep_formatting | 翻译文本 |

#### 2.4.4 接入方式

```
writing_generate.sh 执行流程：
  stdin ← FR 传入 {
    "doc_type": "weekly_report",
    "topic": "本周工作总结",
    "key_points": ["完成 API 开发", "修复 3 个 bug"],
    "style": "formal",
    "length": "medium"
  }
  → python3 writing_engine.py generate --stdin
    ├── 调用 memory_engine.recall("writing weekly_report")  // 同进程内 import
    ├── 加载模板
    ├── 构造 prompt
    ├── httpx → upstream LLM
    └── 输出到 stdout
  → stdout → FR 接收 {"document": "## 本周完成\n...", "format": "markdown"}
```

#### 2.4.5 实现 Checklist

- [ ] 创建 7 个文档模板
- [ ] 实现 writing_engine.py（generate / polish / translate）
- [ ] 实现偏好注入（import memory_engine.recall）
- [ ] 实现上游 LLM 调用（httpx → OpenAI-compatible API）
- [ ] 实现 changes_summary 生成
- [ ] 实现错误降级（上游不可用时返回友好错误）
- [ ] 测试：格式符合偏好概率 > 85%

---

### 2.5 数据分析 Subagent

#### 2.5.1 功能定位

用自然语言查询和分析本地 CSV / Excel / SQLite 数据，自动生成 pandas 代码并在沙箱中安全执行，可选生成图表。

#### 2.5.2 核心设计

**NL → Pandas 代码生成流水线**：

```
data_query("sales.csv", "按月份统计各品类销售额，画折线图")
  │
  ├── Step 1: 数据加载 + Schema 提取
  │     df = pd.read_csv("sales.csv")        # 自动检测编码
  │     schema = {dtypes, head(5), describe(), null_counts, row_count}
  │
  ├── Step 2: 代码生成 (调用上游 LLM)
  │     system: "You are a pandas expert. Generate ONLY Python code.
  │              Allowed: import pandas, matplotlib, numpy, json.
  │              Forbidden: import os, subprocess, sys, shutil, socket.
  │              Output: ONLY the Python code, no markdown, no explanation."
  │     user: f"Schema:\n{schema}\nQuery: 按月份统计各品类销售额，画折线图"
  │     → LLM 生成: df.groupby(['month','category'])['sales'].sum().unstack().plot(kind='line')
  │
  ├── Step 3: 代码安全审计 (AST 遍历)
  │     遍历 AST 节点 → 检查所有 Import/ImportFrom 语句
  │     → import os? → 拒绝执行
  │     → import subprocess? → 拒绝执行
  │     → 全部通过 → 进入沙箱
  │
  ├── Step 4: 沙箱执行
  │     restricted_globals = {'pd': df, 'plt': matplotlib, 'np': numpy}
  │     在受限 namespace 中 exec(code, restricted_globals)
  │     signal.alarm(15)  // 超时保护
  │
  ├── Step 5: 图表生成（如果 LLM 代码中包含 plot）
  │     plt.savefig("~/.prometheus/data/charts/chart_20260712_103000.png")
  │
  └── 返回 {summary: "...", chart_path: "...", row_count: 150}
```

**图表自动选择**：当 `chart_type="auto"` 时，根据查询语义和数据结构自动判断：

| 查询特征 | 数据特征 | 图表类型 |
|---------|---------|---------|
| "趋势" / "变化" / "时间" | 包含日期列 + 数值列 | line |
| "排名" / "Top" / "对比" | 包含类别列 + 数值列 | bar (横向) |
| "占比" / "比例" / "百分比" | 类别列 + 数值列 (< 8 个类别) | pie |
| "相关性" / "分布" | 两个数值列 | scatter |
| 默认（无明确指示） | — | table（不生成图表） |

**多轮工具循环示例**：

```
用户: "帮我分析 sales.csv"
  Round 1: data_schema("sales.csv") → 了解列结构、数据类型
  Round 2: data_query("sales.csv", "筛选出异常值（销售额 > 3σ）") → 数据清洗
  Round 3: data_query("sales.csv", "按月份统计趋势", chart_type="line") → 最终图表
```

**安全沙箱**：

```python
ALLOWED_IMPORTS  = {'pandas', 'matplotlib', 'numpy', 'json', 'datetime', 'collections', 'itertools'}
FORBIDDEN_IMPORTS = {'os', 'subprocess', 'sys', 'shutil', 'socket', 'requests', 'urllib'}
EXEC_TIMEOUT = 15       # 秒
MAX_OUTPUT_ROWS = 10000
MAX_OUTPUT_CHARS = 50000
```

#### 2.5.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `data_query` | file_path, query, chart_type=auto | NL 查询 + 可选图表 |
| `data_schema` | file_path | 查看数据结构和统计摘要 |

#### 2.5.4 接入方式

```
data_query.sh 执行流程：
  stdin ← FR 传入 {"file_path": "sales.csv", "query": "按月统计销售额"}
  → python3 data_engine.py query --stdin
    ├── 加载文件 → df
    ├── 构造 LLM prompt → 生成代码
    ├── AST 安全审计
    ├── 沙箱 exec
    └── 输出到 stdout
  → stdout → FR 接收 {"summary": "...", "chart_path": "..."}
```

#### 2.5.5 实现 Checklist

- [ ] 实现 CSV / Excel / SQLite 加载器
- [ ] 实现 schema 提取（dtypes, head, describe, null_count）
- [ ] 实现 NL → pandas 代码 prompt 构造 + LLM 调用
- [ ] 实现 AST 遍历安全审计
- [ ] 实现沙箱 exec（restricted globals + SIGALRM timeout）
- [ ] 实现 5 种图表模板（line / bar / pie / scatter / table）
- [ ] 实现 chart_type=auto 自动判断
- [ ] 实现输出截断
- [ ] 测试：沙箱安全性（拒绝 import os/subprocess）
- [ ] 测试：超时机制（死循环 → 15s 终止）

---

### 2.6 闲聊陪伴 Subagent

#### 2.6.1 功能定位

轻量级直回闲聊，利用路由模型的小参数、低延迟特性，零工具调用，不经过上游 LLM。延迟从 15-40s 降至 1-2s。

#### 2.6.2 核心设计

**意图识别规则**（5 条全部满足才路由到 chat_light）：

```
1. 无文件路径引用（不包含 /path/ 或 .csv/.pdf/.md 等文件扩展名）
2. 无数据查询意图（不包含 "分析" / "统计" / "图表" 等关键词）
3. 无知识检索需求（不包含 "找一下" / "搜索" / "查" 等关键词）
4. 消息长度 < 200 字（长消息通常不是闲聊）
5. 包含社交/情感/寒暄语义：
   ┌──────────────┬──────────────────────────────────────┐
   │ 问候类        │ 你好 / 嗨 / hey / 早上好 / 晚安       │
   │ 情感类        │ 开心 / 难过 / 无聊 / 好累 / 烦死了    │
   │ 娱乐类        │ 笑话 / 故事 / 谜语 / 冷笑话 / 有趣    │
   │ 简单问答      │ 今天星期几 / 你叫什么 / 天气怎么样    │
   └──────────────┴──────────────────────────────────────┘
```

**对话风格映射**（mood 参数）：

| mood | 路由模型提示词策略 | 适用场景 |
|------|-----------------|---------|
| casual | 自然日常对话，语气轻松 | 默认/日常寒暄 |
| humor | 优先讲笑话/段子/趣事，风趣幽默 | 用户请求娱乐 |
| comfort | 共情倾听，温暖安慰 | 用户表达负面情绪 |
| curious | 拓展话题，提出有趣问题 | 用户表现出好奇心 |
| auto | 从用户消息中自动判断情感基调 | 默认 |

**关键设计——误判保护**：

```
complex 类消息绝对禁止路由到 chat_light：
  - 包含 "为什么" + 专业术语 → 需要上游 LLM
  - 包含 "怎么做" + 技术动词 → 需要上游 LLM
  - 包含比较/分析类连接词（"对比" / "区别" / "优缺点"） → 需要上游 LLM
```

**记忆注入**：闲聊 Subagent 仍然注入用户画像上下文，使回复更个性化：

```
[系统注入]
你是普罗米修斯，一个友好、温暖的 AI 助手。
以下是关于当前用户的信息：
- 昵称：小明
- 兴趣：编程、篮球、科幻电影
- 最近话题：HICOOL 比赛准备（已连续讨论 3 天）
请自然地融入这些信息到对话中。
```

#### 2.6.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `chat_light` | mood=auto, memory_inject=true | 轻量闲聊直回 |

#### 2.6.4 接入方式

`chat_light` 是唯一不走上游 LLM 的 Subagent。其 wrapper 脚本直接调用路由模型的 API：

```
chat_light.sh 执行流程：
  stdin ← FR 传入 {"mood": "auto", "memory_inject": true}
  → python3 chat_engine.py
    ├── memory_engine.recall("user profile") → 用户画像
    ├── 构造 system prompt（含画像 + mood 策略）
    ├── httpx → POST <routing_model_url>/v1/chat/completions
    │     model: qwen3-30b-a3b-instruct-2507  (路由模型本身)
    │     temperature: 0.7  (闲聊需要一定随机性)
    │     max_tokens: 512
    └── 输出到 stdout
  → FR 收到响应 → Completion Check (permissive 模式，直接通过)
  → 返回给用户
```

#### 2.6.5 实现 Checklist

- [ ] 实现 5 条闲聊意图识别规则
- [ ] 实现 complex 消息误判保护
- [ ] 实现 mood 自动检测（基于关键词 + 情感词典）
- [ ] 实现路由模型直回 prompt 构造（含 mood 策略 + 用户画像）
- [ ] 实现 Completion Check permissive 模式配置
- [ ] 测试：闲聊延迟 < 2s
- [ ] 测试：complex 消息不误路由到 chat_light
- [ ] 测试：连续 10 轮闲聊不走上游 LLM

---

### 2.7 Bash 命令行 Subagent

#### 2.7.1 功能定位

安全执行本地 Bash 命令，用于文件管理、服务启停、脚本运行。支持后台进程管理。

#### 2.7.2 核心设计

**安全模型——四层防护**：

```
用户命令
  │
  ├── 第 1 层: 白名单校验
  │     允许的命令: find, grep, cat, ls, wc, head, tail, awk, sed, sort,
  │                  uniq, curl, wget, git, python3, node, npm, pip,
  │                  df, du, ps, top, free, echo, date, env, mkdir, touch, cp, mv
  │     不在白名单中 → 拒绝，提示 "命令未授权"
  │
  ├── 第 2 层: 黑名单正则匹配
  │     rm\s+(-rf?\s+)?/       → rm -rf / (绝对禁止)
  │     dd\s+if=               → dd 磁盘操作
  │     mkfs\.                 → 格式化文件系统
  │     shutdown / reboot      → 关机/重启
  │     >\s*/dev/              → 写入设备文件
  │     :\(\)\s*\{\s*:\|:&\s*\}\s*;:  → fork bomb
  │     chmod\s+777\s+/        → 危险权限
  │     匹配任一黑名单 → 拒绝，告警日志记录
  │
  ├── 第 3 层: 参数消毒
  │     检测命令注入模式: ; rm / `cmd` $(cmd) | 管道到危险命令
  │
  └── 第 4 层: 写入确认
       命令涉及文件变更（rm / mv / cp / chmod / chown / mkdir / touch）
       → 返回确认请求，需用户二次确认后执行
```

**后台进程管理**：

```sql
CREATE TABLE bash_processes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pid INTEGER NOT NULL,
    label TEXT,                  -- 用户友好的标签
    command TEXT NOT NULL,
    workdir TEXT,
    status TEXT DEFAULT 'running',  -- running / stopped / error
    exit_code INTEGER,
    started_at TEXT DEFAULT (datetime('now')),
    stopped_at TEXT
);
```

```
bash_spawn("python3 -m http.server 8080", label="dev-server")
  → subprocess.Popen() 后台启动
  → 写入 SQLite: {pid: 12345, label: "dev-server", status: "running"}
  → 返回 {pid: 12345, label: "dev-server", status: "running"}

定期监控 (每 30s):
  → 遍历 running 进程 → os.kill(pid, 0) 检查存活
  → 已停止 → 更新 status="stopped"
```

#### 2.7.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `bash_exec` | command, workdir, timeout=30 | 执行命令并返回结果 |
| `bash_spawn` | command, workdir, label | 后台启动进程 |
| `bash_status` | label | 查询后台进程状态 |

#### 2.7.4 接入方式

```
bash_exec.sh 执行流程：
  stdin ← FR 传入 {"command": "find . -name '*.py' | head -20", "timeout": 10}
  → python3 bash_engine.py exec --stdin
    ├── 第 1 层: 白名单校验 → find, head 均通过
    ├── 第 2 层: 黑名单匹配 → 无匹配
    ├── 第 3 层: 参数消毒 → 无注入模式
    ├── 第 4 层: 非写入命令，跳过确认
    ├── subprocess.run(cmd, timeout=10, capture_output=True)
    ├── 输出截断 (合并 stdout+stderr, 上限 10000 chars)
    └── 输出到 stdout
  → stdout → FR 接收 {"stdout": "...", "exit_code": 0}
```

#### 2.7.5 实现 Checklist

- [ ] 实现命令白名单校验器
- [ ] 实现黑名单正则匹配器（含 7 类危险模式）
- [ ] 实现参数消毒（防命令注入）
- [ ] 实现写入操作确认机制
- [ ] 实现 bash_exec（subprocess.run + timeout + 输出截断）
- [ ] 实现 bash_spawn（subprocess.Popen + SQLite 记录）
- [ ] 实现 bash_status / kill_process
- [ ] 实现进程存活监控
- [ ] 安全测试：rm -rf / / dd / shutdown / fork bomb 全部拒绝

---

### 2.8 WebFetch 网页抓取 Subagent

#### 2.8.1 功能定位

安全抓取网页内容并提取可读正文，将 HTML 转为 Markdown 供后续处理。支持单页抓取和批量抓取。

#### 2.8.2 核心设计

**SSRF 防护——双重校验**：

```
Step 1: URL 解析
  └── 仅允许 http/https scheme，拒绝 file:// / ftp:// / gopher://

Step 2: DNS 解析 + IP 黑名单（防 DNS rebinding）
  ├── socket.gethostbyname(hostname) → IP 地址
  ├── 检查以下 7 个 CIDR 段:
  │     127.0.0.0/8     (Loopback)
  │     10.0.0.0/8      (Private A)
  │     172.16.0.0/12   (Private B)
  │     192.168.0.0/16  (Private C)
  │     169.254.0.0/16  (Link-local)
  │     0.0.0.0/8       (Current network)
  │     ::1/128          (IPv6 loopback)
  └── 命中任一 → 拒绝，返回 "无法访问内网地址"

Step 3: HTTP 请求
  ├── httpx.get(url, follow_redirects=True, timeout=15)
  ├── 禁止自动跟随重定向到内网 IP（每跳都做 IP 检查）
  └── max_size = 5MB
```

**正文提取策略**：

```
extract_mode 选择:
  auto      → Content-Type 非 text/html? → 原文返回
              text/html? → readability-lxml 提取正文
  article   → 强制 readability-lxml（只取 <article> / <main> 内容）
  full_page → 全部 HTML → html2text 转换 Markdown（保留完整结构）
  markdown  → readability 过滤 → html2text 转换（干净 Markdown）
```

**缓存机制**：

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
```

缓存 TTL 默认 60 分钟。同一 URL 在 TTL 内重复请求直接返回缓存。

**批量抓取**：

```
web_fetch_batch([url1, url2, ..., url10]) →
  asyncio.gather(fetch_url(url1), fetch_url(url2), ...)
  最大并发 5 个，同一域名 1 req/s 速率限制
```

#### 2.8.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `web_fetch` | url, extract_mode=auto, timeout=15 | 抓取单页 |
| `web_fetch_batch` | urls[], extract_mode=auto | 批量抓取（最多 10 个） |

#### 2.8.4 接入方式

```
web_fetch.sh 执行流程：
  stdin ← FR 传入 {"url": "https://example.com/article", "extract_mode": "auto"}
  → python3 web_engine.py fetch --stdin
    ├── SSRF 双重校验（scheme + DNS + IP）
    ├── httpx 异步 GET（User-Agent 伪装）
    ├── Content-Type 检查
    ├── readability 正文提取 + html2text 转换
    ├── 缓存写入
    └── 输出到 stdout
  → stdout → FR 接收 {"url": "...", "title": "...", "content": "markdown...", "content_length": 1234}
```

#### 2.8.5 实现 Checklist

- [ ] 实现 URL scheme 检查（仅 http/https）
- [ ] 实现内网 IP 黑名单（7 个 CIDR + IPv6 loopback）
- [ ] 实现 DNS 解析后 IP 校验 + 重定向跳跳检查
- [ ] 实现 httpx 异步请求（User-Agent 伪装 + 超时）
- [ ] 实现 Content-Type 检查
- [ ] 实现 4 种 extract_mode
- [ ] 实现 SQLite 缓存表 + 读写逻辑
- [ ] 实现 fetch_batch（asyncio 并发 + 速率限制）
- [ ] 安全测试：127.0.0.1 / 192.168.x.x / file:// 全部拒绝

---

### 2.9 WebSearch 网页搜索 Subagent

#### 2.9.1 功能定位

通过搜索引擎后端在互联网上搜索信息，支持搜索+抓取二合一，将搜索结果作为上下文注入后续处理。

#### 2.9.2 核心设计

**多后端可替换架构**：

```
web_search 后端选择:
  config.web_search.backend = "duckduckgo" (默认)
      │
      ├── DuckDuckGo (免费，无需 API Key，开箱即用)
      │     └── duckduckgo-search 库 → DDGS().text(query, max_results=n)
      │
      ├── SearXNG (自部署，无需 API Key，隐私最佳)
      │     └── httpx → https://searxng.example.com/search?q=...
      │
      └── SerpAPI (付费，最快 <1s，结果最全)
            └── httpx → https://serpapi.com/search?q=...

后端 fallback 链: DuckDuckGo → SearXNG → SerpAPI
(任一后端失败时自动尝试下一个)
```

**搜索+抓取二合一（Prometheus 创新功能）**：

```
web_search_fetch("HICOOL 2026 智能体赛道", fetch_top_k=3)
  │
  ├── Step 1: 搜索
  │     web_search("HICOOL 2026 智能体赛道", num_results=6)
  │     → 6 条搜索结果 [{title, url, snippet, date}]
  │
  ├── Step 2: 并发抓取
  │     asyncio.gather(
  │         web_fetch(url1, extract_mode="article"),
  │         web_fetch(url2, extract_mode="article"),
  │         web_fetch(url3, extract_mode="article")
  │     )  // 最多 5 个并发
  │     → 3 篇完整文章内容
  │
  ├── Step 3: 去重合并
  │     检查 URL 重复 → 排除 / 检查 title 相似度 > 0.9 → 排除
  │
  ├── Step 4: 排序
  │     综合 score = search_rank_weight * 0.4 + content_length_weight * 0.3 + freshness_weight * 0.3
  │
  └── 返回 [{url, title, snippet, full_content, relevance_score}]
```

**速率限制**：

```
每分钟最多 10 次搜索请求
429 / 速率超限 → 自动退避重试 (1s → 2s → 4s → 8s, 最多 3 次)
```

**搜索结果缓存**：

搜索缓存 TTL = 30 分钟（比网页缓存 60 分钟更短，因为搜索结果对时效性更敏感）。

#### 2.9.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `web_search` | query, num_results=5, search_type=general, time_range=any | 在线搜索 |
| `web_search_fetch` | query, fetch_top_k=3, search_type=general | 搜索+抓取二合一 |

#### 2.9.4 接入方式

```
web_search.sh 执行流程：
  stdin ← FR 传入 {"query": "HICOOL 2026", "num_results": 5}
  → python3 web_engine.py search --stdin
    ├── 选择后端 (config.web_search.backend)
    ├── 调用后端 API
    ├── 标准化结果
    ├── 缓存写入 (TTL 30min)
    └── 输出到 stdout
  → stdout → FR 接收 {"query": "...", "results": [...], "total_estimated": 1234}
```

#### 2.9.5 实现 Checklist

- [ ] 实现 DuckDuckGo backend
- [ ] 实现 SearXNG backend
- [ ] 实现 SerpAPI backend
- [ ] 实现 backend fallback 链
- [ ] 实现 search_type 过滤（general / news / scholar）
- [ ] 实现 time_range 过滤（any / day / week / month / year）
- [ ] 实现 search_and_fetch 二合一（搜索 → 并发抓取 → 去重 → 排序）
- [ ] 实现速率限制 + 429 自动退避重试
- [ ] 实现搜索缓存（TTL 30min）
- [ ] 测试：多后端切换无感知

---

### 2.10 反思引擎

#### 2.10.1 功能定位

后台定时分析交互日志，提取用户行为模式和偏好变化，更新记忆和知识图谱，生成反思摘要。这是 Prometheus "自我进化" 的核心引擎。

#### 2.10.2 触发机制

| 触发方式 | 频率 | 处理范围 | 实现 |
|---------|------|---------|------|
| 定时任务 | 每日凌晨 2:00 | 前一天全部交互 | cron + Python 脚本 |
| 阈值触发 | 每 50 次交互 | 最近 50 条日志 | interaction_log 计数器 |
| 手动触发 | 用户主动要求 | 用户指定范围 | "帮我总结最近使用情况" |
| 事件触发 | 每次 rag_ingest | 新导入的文档 | 实体抽取 + 图谱自动关联 |

#### 2.10.3 反思流水线

```python
def run_reflection_cycle():
    logs = load_unprocessed_logs()  # 加载上次反思后所有新日志

    # 1. 偏好提取
    preferences = extract_preferences(logs)
    # 例：检测到 "以后都" / "我喜欢" / "不要" / "偏好" 等声明
    # 例：行为推断 → 最近 5 次翻译都是 zh→en → 更新 preferred_translation_direction
    for pref in preferences:
        memory_remember(pref.category, pref.key, pref.value, importance=pref.confidence)

    # 2. 高频主题提取
    topics = cluster_topics(logs, threshold=3)
    # 对出现 >= 3 次的主题 → 创建/更新知识图谱节点
    for topic in topics:
        ensure_graph_node(topic.label, topic.type, topic.aliases)
        link_related_documents(topic)

    # 3. 时间规律提取
    patterns = detect_temporal_patterns(logs)
    # 例：连续 3 个周五 16:00-17:00 有 "写周报" 行为
    # → 建议设置 "每周五 16:00 提醒写周报"
    for pattern in patterns:
        if pattern.confidence > 0.7:
            suggest_reminder(pattern)

    # 4. 记忆衰减/强化
    for memory in get_all_memories():
        if memory.access_count > 10:
            memory.importance = min(5, memory.importance + 1)  # 热记忆强化
        if memory.access_count == 0 and memory.days_since_update > 30:
            memory.importance = max(1, memory.importance - 1)  # 冷记忆衰减

    # 5. 生成反思摘要
    summary = format_summary(preferences, topics, patterns)

    # 6. 持久化
    save_reflection_log(summary)
    update_last_reflection_time()
    return summary
```

#### 2.10.4 反思摘要格式

反思摘要作为下次对话的 system prompt 前缀自动注入：

```
[近期发现 — 2026-07-12]
• 偏好变化：写作风格从 casual 转向 formal（最近 5 次文档生成请求均选择 formal 风格）
• 高频主题：HICOOL 智能体赛道（出现 8 次，已关联 3 篇文档）
• 时间规律：连续 3 个周五下午触发周报生成 → 已设置提醒"每周五 16:00 写周报"
• 建议关注：用户最近频繁查询 GPU 算力相关资料，可主动询问是否需要整理对比报告
```

#### 2.10.5 反思结果消费

**路径 A — 下次对话注入**：
```
新会话开始 → memory_injector 读最新反思摘要
→ 如果摘要 time < 24h → 注入 system prompt 前缀
→ FR 处理请求时自动携带反思上下文
```

**路径 B — 主动推送**：
```
用户上线 → 检查到期提醒 + 未读 insights
→ 有内容 → 主动推送 "你有 1 个提醒和 2 个新发现"
```

#### 2.10.6 实现 Checklist

- [ ] 实现 `extract_preferences()` — 偏好声明检测 + 行为推断
- [ ] 实现 `cluster_topics()` — TF-IDF + 聚类，阈值 >= 3 次
- [ ] 实现 `detect_temporal_patterns()` — 时段-行为关联分析
- [ ] 实现记忆衰减/强化逻辑
- [ ] 实现反思摘要格式化和持久化
- [ ] 实现 memory_injector（请求前自动注入）
- [ ] 实现 cron 定时 + 阈值触发调度
- [ ] 测试：跨会话偏好注入
- [ ] 测试：高频主题知识图谱节点自动创建

---

### 2.11 Subagent 协同机制

#### 2.11.1 协同模式

单个用户请求可触发多个 Subagent 协同工作：

```
用户: "搜索 HICOOL 2026 的最新消息，总结成 Markdown 笔记，然后存到知识库"

  FR 调用 web_search("HICOOL 2026 智能体赛道最新消息")
    → WebSearch Subagent 返回 5 条搜索结果

  FR 调用 web_fetch_batch([url1, url2, url3])
    → WebFetch Subagent 并发抓取 3 篇完整文章

  FR 调用 writing_generate(doc_type="article", topic="HICOOL 2026 最新动态",
          key_points=[文章1摘要, 文章2摘要, 文章3摘要])
    → 写作 Subagent 生成结构化 Markdown 笔记

  FR 调用 rag_ingest(path="/tmp/hicool_notes.md")
    → RAG Subagent 将笔记索引入库，知识图谱自动关联

  FR 调用 memory_remember(category="note", key="hicool_research",
          value="已整理 HICOOL 2026 最新动态笔记", importance=3)
    → 记忆 Subagent 记录操作

单一请求 → 5 个 Subagent 协同 → 4 轮工具调用 → 端到端完成任务
```

#### 2.11.2 FR 多轮工具调用机制

MTClaw 的 `max_tool_rounds=6` 参数决定了单次请求最多可以执行多少轮工具调用。FR 在每轮工具调用后评估 Completion Check：

- `TASK_COMPLETE` → 停止调用，返回最终结果
- `TASK_INCOMPLETE` → 继续下一轮工具调用，或转发上游 LLM

这使得跨 Subagent 的工作流编排成为可能——FR 充当 "调度器"。

#### 2.11.3 关键约束

- 同一请求内多次工具调用共享 session 上下文
- 前序工具的输出自动注入到后续工具的上下文中
- 每个工具调用独立记录到 interaction_log（供反思引擎使用）

---

## 3. 快：速度

### 3.1 分层延迟策略

不是所有请求都需要走过上游大模型。普罗米修斯根据任务类型分三层响应：

| 层级 | Subagent | 典型延迟 | 技术手段 | 占比预估 |
|------|----------|---------|---------|---------|
| **L1 即时** | 记忆、闲聊 | < 1-2s | 路由模型直回 / 本地 SQLite | ~25% |
| **L2 快速** | RAG、Shell、WebFetch、WebSearch | 1-10s | 本地向量库 / subprocess / httpx | ~40% |
| **L3 标准** | 写作、数据分析 | 10-40s | 上游 LLM（核心智能依赖） | ~20% |
| **兜底** | 通用推理 | 15-40s | 上游 LLM 全量推理 | ~15% |

**评分优势**：65% 以上的日常请求走 L1/L2 快速通道。Function Router 分治架构使"杀鸡不用牛刀"成为可能。

### 3.2 闲聊 Subagent 的秒级响应

```
传统路径：用户 "讲个笑话" → 上游 LLM (doubao/gpt-4o) → 响应 = 15-30s
Prometheus：用户 "讲个笑话" → 路由模型 (qwen3-30b) → 直回 = 1-2s

延迟降低 93%，对日常寒暄场景体感丝滑
```

### 3.3 Completion Check 快路径

```
TASK_COMPLETE   → 直接返回（快路径，目标占比 > 80%）
TASK_INCOMPLETE → 转发上游 LLM 补充（慢路径，目标占比 < 20%）

80% 的工具调用结果直接返回用户，仅 20% 的复杂场景需要上游二次加工
```

### 3.4 量化对比

| 场景 | ChatGPT 类 | Prometheus | 提升 |
|------|-----------|------------|------|
| 文档检索 | 无法检索本地文件 | 1-3s (ChromaDB 混合检索) | — |
| 偏好记忆 | 每次重新告知 | < 1s (SQLite + 自动注入) | 免告知 |
| 闲聊寒暄 | 15-30s (GPT-4o) | 1-2s (路由模型直回) | **93%↓** |
| 数据查询 | 上传文件 → 生成代码 | 5-20s (本地 Pandas 沙箱) | 免上传 |
| 网页搜索 | 需手动打开浏览器 | 2-8s (DuckDuckGo + 自动抓取) | — |
| Shell 命令 | 无法执行 | < 2s (subprocess 沙箱) | — |

---

## 4. 准：准确率

### 4.1 Function Router 精准分发

```
路由准确率保证：
  1. temperature = 0.0（确定性 function calling，零随机性）
  2. 8 个 Subagent 描述高度特化（工具描述互不重叠）
  3. 双重意图匹配：触发关键词 + 正则模式
  4. 优先级排序：记忆(P1) > WebFetch(P2) > WebSearch(P3) > 数据(P4) > ... > 闲聊(P9) > 兜底(P10)
  5. 防误判保护：complex 消息禁止路由到 chat_light

目标：50 条混合意图的自动分发准确率 > 95%
```

**评分优势**：传统方案依赖一个巨型 Prompt 处理所有场景，容易出现"理解偏差"。分治方案每个 Subagent 职责清晰，路由模型只需要做"选择题"而非"作文题"。

### 4.2 记忆注入提升个性化准确率

```
写作 Subagent 收到 "帮我写周报"
  │
  ├── 自动调用 memory_recall("writing weekly_report") →
  │     { writing_format: "markdown",
  │       language: "zh-CN",
  │       structure: "本周完成 + 下周计划 + 风险与问题" }
  │
  └── 构造 prompt 时自动注入偏好 → 生成符合用户习惯的周报

无记忆注入：LLM 生成通用格式，用户每次需手动调整
有记忆注入：格式符合用户习惯的概率 > 85%
```

### 4.3 RAG 混合检索提升召回率

```
稠密检索 (BGE-M3 语义匹配, 1024d)
        +
稀疏检索 (BM25 关键词匹配)
        ↓
RRF 融合排序 (k=60, 互补语义和字面两个维度)
        ↓
知识图谱扩展（双向链接的相关文档）
        ↓
Top-5 召回率 > 90%
```

**评分优势**：纯向量检索在专业术语、缩写、代码片段等场景失效；混合检索互补覆盖语义和字面两个维度。

### 4.4 上游 LLM 兜底保证智商

```
未命中任何 Subagent → 100% 透明转发上游 LLM
  ├── prompt 不做任何改写
  ├── 响应不做任何截断
  └── 原样流式透传

性能增益 = Subagent 命中率 × 各 Subagent 的定制优化
智商兜底 = 100% 的上游 LLM 能力（零衰减）
```

**评分优势**：Prometheus 的 Subagent 层是 "增益" 而非 "衰减"。未命中的请求完全不经过中间层处理。

---

## 5. 稳：可靠性

### 5.1 透明兜底

```
用户消息
  │
  ├── 8 个 Subagent 都不命中 → 100% 转发上游 LLM
  ├── Subagent 命中但执行失败 → 降级到上游 LLM（错误信息作为上下文注入）
  └── 元数据清洗 → 仅移除 Hermes 注入的元数据块，不影响语义

最差情况：系统退化为直接使用上游 LLM
```

### 5.2 插件级故障隔离

```
每个 Subagent = 独立 Python 子进程
  ├── stdin/stdout JSON 通信（无共享内存）
  ├── 一个插件崩溃 → FR 收到非零 exit code → 降级处理
  ├── 其他插件不受影响（RAG 崩溃不影响 Shell、写作）
  └── 独立启停（prometheus plugin disable bash → 运行时移除）
```

### 5.3 四层安全防护

| Subagent | 安全机制 | 防护目标 |
|----------|---------|---------|
| Shell | 白名单 + 黑名单 + 命令注入检测 + 写入确认 | 防止系统破坏 |
| 数据分析 | AST 审计 + import 白名单 + timeout 15s + 受限 globals | 防止代码逃逸 |
| WebFetch | URL scheme 检查 + DNS→IP 双重校验 + 7 个 CIDR 黑名单 + 逐跳检查 | 防止 SSRF 攻击 |
| WebSearch | 速率限制 10rpm + 429 自动退避重试 | 防止 API 滥用 |

### 5.4 数据本地化

```
全部数据存储于 ~/.prometheus/data/
  ├── SQLite (用户记忆、交互日志)        ← 不上传
  ├── ChromaDB (文档向量、记忆向量)       ← 不上传
  ├── JSON Graph (知识图谱)              ← 不上传
  └── 本地文件系统 (文档/附件/图表)       ← 不上传

零云端上传：隐私数据完全离线
```

---

## 6. 广：场景覆盖

### 6.1 8 个 Subagent × 8 类场景矩阵

```
  ┌──────────────┬─────────────────────┬──────────────────────────┐
  │  办公场景      │  写作 + Shell        │  周报/邮件/文件批量管理     │
  │  学习场景      │  RAG + WebSearch    │  笔记检索/在线资料搜索     │
  │  数据场景      │  数据分析            │  CSV/Excel NL 自由查询    │
  │  创作场景      │  写作 + WebFetch    │  文档生成/参考抓取         │
  │  信息检索      │  RAG + WebSearch    │  本地+互联网双检索         │
  │  日程场景      │  记忆               │  提醒设置/习惯追踪         │
  │  社交场景      │  闲聊               │  日常寒暄/情感陪伴         │
  │  开发场景      │  Shell + WebFetch   │  命令执行/API 参考抓取     │
  └──────────────┴─────────────────────┴──────────────────────────┘
```

### 6.2 跨 Subagent 协同工作流

```
单请求示例: "搜索 HICOOL 最新消息，写成 Markdown 笔记，存到知识库"

  WebSearch → WebFetch → 写作 → RAG → 记忆
  5 个 Subagent 串联 → 4 轮工具调用 → 端到端完成
```

### 6.3 多轮工具循环

```
data_query 典型流程:
  Round 1: data_schema(file)           → 了解数据结构
  Round 2: data_query(file, "筛选异常") → 数据清洗
  Round 3: data_query(file, "按月趋势", chart_type="line") → 最终图表

不是一问一答，而是多步推理执行
```

---

## 7. 产品化完成度

### 7.1 一键安装

```bash
git clone xxx && cd prometheus && ./install/install.sh
# 交互式输入路由模型/上游模型 URL + Key（6 个配置项）
# 自动完成：Python 依赖安装 → 目录创建 → DB 初始化 → cron 设置 → 服务启动
# 安装时间 < 5 分钟
```

### 7.2 预置样本数据

```
demo/sample_data/
├── sample_notes/              # 3 篇个人笔记 (GPU / HICOOL / 周报模板)
├── sample_data.csv            # 12 个月 × 5 品类销售数据
└── sample_weekly_report.md    # 周报范例
```

评委安装后可立即执行演示剧本中全部 12 轮对话。

### 7.3 健康检查与可观测性

```bash
curl :18790/health  → {"status":"ok", "tools_loaded":19, "plugins_active":8, "uptime":"2h"}
curl :18790/v1/tools | jq '.tools | length'  → 24

路由追踪面板 (Web UI):
  实时展示每次请求的路由决策 → 哪个 Subagent → 置信度 → 各阶段延迟 → Completion Check
```

### 7.4 插件管理 CLI

```bash
prometheus plugin list                # 8 个插件 + 状态
prometheus plugin info rag            # RAG 详情
prometheus plugin enable/disable X    # 运行时刻启停
prometheus plugin validate X          # 依赖校验
```

---

## 8. 商业价值

### 8.1 目标用户：知识工作者

| 痛点 | 现有方案 | Prometheus |
|------|---------|------------|
| "那份报告我放哪了" | 手动翻文件夹 | RAG 语义检索，2 秒定位 |
| "每次写周报都要重新说格式" | 复制粘贴格式要求 | 记忆自动注入偏好 |
| "分析 CSV 但我不会写 SQL" | 找同事 / 学技术 | NL 自由查询 + 自动图表 |
| "忘了今天要交代码" | 手动设闹钟 | 主动识别习惯 → 自动提醒 |

### 8.2 差异化定位

```
ChatGPT / 通用 AI              普罗米修斯
──────────────────────        ──────────────────────
会话级记忆 (用完即忘)     vs   终身学习 (跨会话持久化)
被动问答                 vs   主动推送 + 被动问答
零知识管理               vs   自组织知识图谱
版本升级依赖人工          vs   后台反思持续自主进化
单一模型                 vs   Function Router 8 Subagent 分治
通用回答                 vs   个性化 (偏好记忆注入)
```

### 8.3 飞轮效应

```
用户使用越多 → 交互数据越多 → 反思引擎提取更多模式 → AI 更懂用户 → 体验更好 → 更愿意用
                                                          ↓
                                              迁移成本递增 = 自然护城河
```

---

## 9. 加分项

### 9.1 可视化路由追踪面板

Web 页面实时展示每次请求的路由决策链路（Subagent 命中 / 置信度 / 工具输入输出 / 延迟分解 / Completion Check），通过 polling `/v1/tool_history` + `/health` 实现。

### 9.2 Router 自学习

```
反思引擎分析路由历史 →
  发现用户说 "帮我看看" 时 90% 情况是想找文档而非闲聊
  → 自动调整路由提示词，提高 "帮我看看" 在 RAG 的匹配优先级
```

### 9.3 Subagent 插件市场

标准化插件格式（plugin.json + functions.jsonl + scripts/ + engine.py）→ 任何开发者都可以贡献新 Subagent → `prometheus plugin install ./my-plugin` 一键安装。

### 9.4 跨会话进化演示（"第二天"环节）

```
[Day 1]  用户: "写周报，用 Markdown，中文，包含本周完成和下周计划"
         系统: 按详细要求生成（15s）

[Day 2]  用户: "写周报"
         系统: 自动注入偏好 → 自动生成 Markdown 中文三段式周报（12s）
         用户零额外输入 → 展示 "越用越懂你" 的核心价值
```

---

## 10. 评分维度对照矩阵

| 维度 | 关键指标 | 目标值 | 技术支撑 | 详细设计 |
|------|---------|--------|---------|---------|
| **快** | 闲聊延迟 | < 2s | 路由模型直回 | §2.6 |
| | RAG 检索延迟 | < 3s | ChromaDB + BGE-M3 本地检索 | §2.2 |
| | 记忆查询延迟 | < 1s | SQLite + ChromaDB 双存储 | §2.3 |
| | 路由决策延迟 | < 1s | temperature=0 确定性路由 | §2.1 |
| | Completion Check 命中率 | > 80% | 快路径直接返回 | §2.1 |
| **准** | 路由分发准确率 | > 95% | 8 Subagent + 优先级 + 防误判 | §2.1 |
| | RAG Top-5 召回率 | > 90% | 稠密+稀疏混合 + RRF + 图谱扩展 | §2.2 |
| | 写作格式符合率 | > 85% | memory_recall 偏好自动注入 | §2.4 |
| | 偏好召回准确率 | > 90% | 语义 + 结构化双检索 | §2.3 |
| | 通用智商 | 不退化 | 100% 透明转发上游 LLM | §2.1 |
| **稳** | 透明兜底 | 100% | 未命中 → 上游 LLM 原样透传 | §5.1 |
| | 故障隔离 | 插件级 | 独立子进程 + 独立启停 | §2.1 |
| | 安全防护 | 4 层 | 白名单+黑名单 / AST审计 / SSRF / 限速 | §2.7-2.9 |
| | 数据隐私 | 全本地 | SQLite + ChromaDB + JSON 零上传 | §5.4 |
| **广** | Subagent 数量 | 8 个 | RAG/记忆/写作/数据/闲聊/Shell/WebFetch/WebSearch | §2.2-2.9 |
| | 覆盖场景 | 8+ 类 | 办公/学习/数据/创作/检索/日程/社交/开发 | §6.1 |
| | 多轮工具循环 | 2+ | data_query / web_search_fetch | §2.5/§2.9 |
| | 跨 Subagent 协同 | 5 串联示例 | WebSearch→WebFetch→写作→RAG→记忆 | §2.11 |
| **产品化** | 安装时间 | < 5 min | 一键安装 + 交互式配置 | §7.1 |
| | 预置数据 | 3 类 | 笔记/CSV/周报 | §7.2 |
| | 健康检查 | 1 endpoint | /health + /v1/tools | §7.3 |
| | 路由追踪面板 | Web UI | 实时展示路由决策链路 | §7.3 |
| **商业** | 目标用户 | 知识工作者 | 办公/学习/数据/创作 全链路 | §8.1 |
| | 差异化 | 自我进化 | 反思引擎 + 跨会话记忆 | §2.10 |
| | 护城河 | 飞轮效应 | 越用越准 → 迁移成本递增 | §8.3 |
| **加分** | 可视化面板 | ✓ | 路由追踪 Web UI | §9.1 |
| | Router 自学习 | ✓ | 反思引擎优化路由策略 | §9.2 |
| | 插件市场 | ✓ | plugin.json 标准化 + install CLI | §9.3 |
| | 跨会话进化演示 | ✓ | "第二天" 环节 | §9.4 |

---

## 附录：与竞品架构对比

| 维度 | ChatGPT | 通用 Agent 框架 | Prometheus |
|------|---------|----------------|------------|
| 路由策略 | 单一模型 | Prompt 分岔 | **Function Router + 8 Subagent 专职** |
| 记忆 | 会话级 | 手动管理 | **自动注入 + 反思进化** |
| 工具扩展 | 插件市场 | 代码级 | **plugin.json 声明式 + 无损接入 FR** |
| 延迟优化 | 不分层 | 不分层 | **L1/L2/L3 三层策略** |
| 安全 | 通用沙箱 | 无 | **4 层针对性防护** |
| 数据隐私 | 云端 | 混合 | **全本地存储** |
| 可观测性 | 无 | 日志 | **路由追踪面板 + 交互日志** |
| 部署 | SaaS | Docker/源码 | **一键安装** |
