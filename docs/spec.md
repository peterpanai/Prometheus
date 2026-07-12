# 普罗米修斯（Prometheus）技术规格说明书

> 基于 MTClaw Function Router 的自我进化型个人认知智能体
>
> 版本：v1.0 | 日期：2026-07-11 | 目标：HICOOL 智能体赛道参赛

---

## 目录

1. [项目概述](#1-项目概述)
2. [系统架构](#2-系统架构)
3. [Subagent 规格](#3-subagent-规格)
4. [自我进化引擎](#4-自我进化引擎)
5. [数据模型](#5-数据模型)
6. [API 与接口](#6-api-与接口)
7. [路由策略](#7-路由策略)
8. [文件结构](#8-文件结构)
9. [安装与部署](#9-安装与部署)
10. [演示剧本](#10-演示剧本)
11. [里程碑计划](#11-里程碑计划)
12. [评估维度自检清单](#12-评估维度自检清单)

---

## 1. 项目概述

### 1.1 一句话定义

基于 MTClaw Function Router，在 MTT AIBOOK 上运行的自我进化型个人认知智能体——用户使用越多，AI 越"懂"用户。

### 1.2 核心差异化

| 维度 | ChatGPT / 通用 AI | 普罗米修斯 |
|------|-------------------|-----------|
| 记忆 | 会话级（对话结束即遗忘） | 终身学习，跨会话持久化 |
| 行为模式 | 被动问答 | 主动推送 + 被动问答 |
| 知识管理 | 无 | 自组织知识图谱，推理检索 |
| 进化 | 版本升级（依赖人工） | 后台反思，持续自主进化 |
| 路由 | 单一模型 | Function Router 自动分发 8 个 Subagent |

### 1.3 技术栈

| 层级 | 选型 | 说明 |
|------|------|------|
| Agent 框架 | **Hermes** | 用户交互入口，OpenAI-compatible 客户端 |
| 智能体框架 | **MTClaw** | Function Router 路由分发 |
| 本地推理 | MTT AIBOOK (AIOS 1.4.2) | 路由模型 + 嵌入模型 |
| 上游模型 | Cloud API (Doubao / GPT-4o) | 兜底通用推理 |
| 向量数据库 | ChromaDB | 文档嵌入 + 情节记忆检索 |
| 关系数据库 | SQLite | 用户偏好、记忆元数据 |
| 知识图谱 | 自研 JSON Graph | 双向链接，增量更新 |
| 后端语言 | Python 3.10+ | Subagent 逻辑 + 工具实现 |
| 前端 | Web UI (可选) | 路由追踪面板 |

### 1.4 交付环境

- 操作系统：MTT AIBOOK AIOS 1.4.2 (Ubuntu 22.04)
- 硬件：MTT AIBOOK（含 MTT GPU）
- 自备服务：路由模型 API + 上游模型 API

---

## 2. 系统架构

### 2.1 架构总图

```
┌─────────────────────────────────────────────────────────────────────┐
│                          用户交互层                                   │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Hermes Agent                               │   │
│  │          (OpenAI-compatible client, base_url = FR)            │   │
│  └───────────────────────────┬──────────────────────────────────┘   │
├──────────────────────────────┼──────────────────────────────────────┤
│                    智能体核心层                                       │
│  ┌───────────────────────────▼──────────────────────────────────┐   │
│  │               MTClaw Function Router (:18790)                 │   │
│  │  ┌──────────┐  ┌──────────────┐  ┌──────────────────────┐   │   │
│  │  │ 元数据清洗 │  │ Session 管理  │  │ 路由模型 (tool call)  │   │   │
│  │  └──────────┘  └──────────────┘  └──────────┬───────────┘   │   │
│  └─────────────────────────────────────────────┼────────────────┘   │
│                                                  │                   │
│  ┌───────────────────────────────────────────────┼──────────────────────────────────────┐  │
│  │                   Subagent 层                  │                                      │  │
│  │  ┌────────┐ ┌────────┐ ┌──────┐ ┌────────┐ ┌─┴──────────┐ ┌────────┐ ┌────────┐ ┌────────┐ │
│  │  │  RAG   │ │ 记忆   │ │ 写作 │ │ 数据   │ │   闲聊     │ │ Bash   │ │WebFetch│ │WebSearch│ │
│  │  │ 知识库  │ │ 与反思  │ │ 润色 │ │ 分析   │ │   陪伴     │ │ 命令行 │ │ 网页抓取│ │ 网页搜索│ │
│  │  └───┬────┘ └───┬────┘ └──┬───┘ └───┬────┘ └────┬───────┘ └───┬────┘ └───┬────┘ └───┬────┘ │
│  └──────┼──────────┼─────────┼──────────┼──────────┼─────────────┼──────────┼──────────┼──────┘  │
├─────────┼──────────┼─────────┼──────────┼──────────┼─────────────┼──────────┼──────────┼──────────┤
│                      工具执行层                                       │
│  ┌──────┴──────────┴─────────┴──────────┴──────────┴──────┴──────────┴──────────┴────────────┐  │
│  │                    Bash Wrapper Scripts  +  Python Tool Modules                            │  │
│  │                    functions.jsonl 中定义，stdin JSON → stdout JSON                          │  │
│  └───────────────────────────────────────────┬────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────┼──────────────────────────────────────────────────┤
│                      数据与存储层                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │  SQLite  │  │ ChromaDB │  │  JSON Graph  │  │ 本地文件系统   │    │
│  │ 用户偏好  │  │ 情节记忆  │  │  知识图谱     │  │  文档/附件    │    │
│  └──────────┘  └──────────┘  └──────────────┘  └──────────────┘    │
│                          MTT AIBOOK 本地存储                         │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 请求处理流程

```
1. 用户输入 → Hermes → POST /v1/chat/completions → MTClaw Function Router
2. Function Router 清洗元数据（去掉 Hermes 注入的 sender block 等）
3. Function Router 调用路由模型，传入 8 个 Subagent 的工具定义
4. 路由模型判断命中哪个 Subagent
   ├── 命中 Subagent → 执行对应工具 → Completion Check
   │   ├── TASK_COMPLETE → 直接返回响应（快路径，5-8s）
   │   └── TASK_INCOMPLETE → 转发上游 LLM（慢路径，15-40s）
   └── 未命中任何工具 → 转发上游 LLM（通用推理）
5. 工具执行结果记录到 Memory Subagent（供反思引擎使用）
6. 响应返回 Hermes → 展示给用户
```

### 2.3 慢循环（后台反思）

```
后台定时任务（每 N 小时 / 每日凌晨）
     │
     ├── 读取当日所有 tool_history 记录
     ├── 提取用户行为模式
     │     ├── 偏好变化（格式、风格、习惯）
     │     ├── 高频主题（重复搜索/查询的主题）
     │     └── 时间规律（特定时段的行为类型）
     ├── 更新 SQLite 用户偏好表
     ├── 更新 JSON 知识图谱（新增节点/边）
     └── 生成"反思摘要" → 下次对话时注入上下文
```

---

## 3. Subagent 规格

### 3.1 RAG 知识库 Subagent

**定位**：个人文档/笔记/PDF 的索引与检索，数据不出设备

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"rag_search","description":"在本地知识库中搜索相关文档片段。用户问'我之前写的XXX'、'帮我找一下关于YYY的笔记'时触发。","parameters":{"type":"object","properties":{"query":{"type":"string","description":"搜索查询，自然语言描述用户想找的内容"},"top_k":{"type":"integer","description":"返回最相关的K个结果，默认5"},"source_filter":{"type":"string","description":"可选：按文件类型过滤（md/pdf/txt/docx）或按目录过滤"}},"required":["query"]}}
{"name":"rag_ingest","description":"将本地文件或目录导入知识库。用户说'把这个文件加入知识库'、'索引这个目录'时触发。","parameters":{"type":"object","properties":{"path":{"type":"string","description":"要导入的文件或目录路径"},"recursive":{"type":"boolean","description":"是否递归处理子目录，导入目录时默认true"}},"required":["path"]}}
{"name":"rag_status","description":"查询知识库状态：已索引文档数、存储大小、最近更新时间。","parameters":{"type":"object","properties":{}}}
```

**技术实现**：

```
Tool: rag_search
  ├── 输入 query → 本地 BGE-M3 嵌入模型 → 向量化
  ├── ChromaDB 相似度检索 → Top K 文档片段
  ├── 附带知识图谱中的关联节点（双向链接扩展）
  └── 返回 {matches: [{source, content, score, related_knowledge}]}

Tool: rag_ingest
  ├── 支持格式：.md / .pdf / .txt / .docx / .csv
  ├── PDF → pdfplumber 提取文本
  ├── .docx → python-docx 提取文本
  ├── 分段策略：按标题 + 段落，chunk_size=512, overlap=64
  ├── 嵌入：BGE-M3（本地 CPU/GPU，无需网络）
  └── 存储：ChromaDB persist 到本地磁盘
```

**依赖**：
```txt
chromadb>=0.5
sentence-transformers>=2.7
pdfplumber>=0.10
python-docx>=1.0
```

### 3.2 记忆与反思 Subagent

**定位**：记住用户偏好与历史交互，后台反思提取模式，实现跨会话记忆和主动服务

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"memory_remember","description":"记录用户偏好、习惯或重要信息。用户说'记住了'、'以后都...'、'我的...是...'时触发。","parameters":{"type":"object","properties":{"category":{"type":"string","description":"记忆类别：preference/identity/habit/note"},"key":{"type":"string","description":"记忆的键，如 writing_format、preferred_language"},"value":{"type":"string","description":"记忆的值"},"importance":{"type":"integer","minimum":1,"maximum":5,"description":"重要程度，1-5，默认为3"}},"required":["category","key","value"]}}
{"name":"memory_recall","description":"检索与当前上下文相关的用户记忆。Router 在处理请求前自动调用此工具注入记忆上下文。","parameters":{"type":"object","properties":{"context":{"type":"string","description":"当前对话的上下文描述，用于相似度匹配"},"top_k":{"type":"integer","description":"返回最相关的K条记忆，默认5"},"category":{"type":"string","description":"可选：按类别过滤 memory/preference/identity/habit/note"}},"required":["context"]}}
{"name":"memory_set_reminder","description":"设置提醒。用户说'提醒我'、'别忘了'时触发。","parameters":{"type":"object","properties":{"content":{"type":"string","description":"提醒内容"},"time":{"type":"string","description":"提醒时间，如'明天上午10点'、'每周五下午4点'"},"repeat":{"type":"string","description":"重复模式：once/daily/weekly/monthly，默认once"}},"required":["content","time"]}}
```

**数据模型**：

```sql
-- SQLite: 用户记忆表
CREATE TABLE memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,       -- preference / identity / habit / note
    key TEXT NOT NULL,             -- writing_format, preferred_language, etc.
    value TEXT NOT NULL,           -- markdown, zh-CN, etc.
    importance INTEGER DEFAULT 3,  -- 1-5
    source_session TEXT,           -- 来源会话 ID
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 0
);

CREATE TABLE reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    trigger_at TIMESTAMP NOT NULL,
    repeat_pattern TEXT DEFAULT 'once',  -- once/daily/weekly/monthly
    active INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE interaction_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    user_message TEXT,
    subagent TEXT,                -- 命中的 Subagent
    tool_name TEXT,               -- 调用的工具名
    tool_result TEXT,             -- 工具执行结果（JSON）
    latency_ms REAL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**技术实现**：

```
Tool: memory_remember
  ├── SQLite UPSERT (key, category) 对去重
  ├── 同时写入 ChromaDB（用于语义检索）
  └── 返回 {"status": "stored", "key": key}

Tool: memory_recall
  ├── 将 context 向量化 → ChromaDB 语义检索
  ├── 附带 SQLite 中高 importance 的记忆
  └── 返回 [{category, key, value, importance, last_updated}]

Tool: memory_set_reminder
  ├── 写入 SQLite reminders 表
  ├── 解析自然语言时间 → Python dateparser → Unix timestamp
  └── 返回 {"status": "set", "trigger_at": "2026-07-12T10:00:00"}
```

**慢循环反思**（后台脚本 `scripts/reflection_loop.sh`）：

```python
# 伪代码
for session in get_today_sessions():
    tools_used = get_tool_history(session)
    user_messages = get_user_messages(session)

    # 1. 检测偏好声明
    if "以后都" in messages or "记住了" in messages:
        extract_preference() → memory_remember()

    # 2. 检测高频主题（同一主题出现 3+ 次）
    themes = cluster_topics(user_messages)
    for theme in themes where theme.count >= 3:
        create_knowledge_node(theme)

    # 3. 检测时间规律
    if same_action_at_same_time_across_days():
        suggest_reminder()

    # 4. 知识图谱更新
    for document_ingested:
        extract_entities(document)
        find_and_link_related_nodes()
```

### 3.3 写作润色翻译 Subagent

**定位**：周报、邮件、技术文档场景化生成

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"writing_generate","description":"生成各类文档。包括周报、邮件、技术文档、会议纪要等。用户说'帮我写'、'生成一份'、'起草'时触发。","parameters":{"type":"object","properties":{"doc_type":{"type":"string","enum":["weekly_report","email","tech_doc","meeting_minutes","article","essay","ppt_outline"],"description":"文档类型"},"topic":{"type":"string","description":"文档主题或标题"},"key_points":{"type":"array","items":{"type":"string"},"description":"需要包含的关键要点列表"},"style":{"type":"string","enum":["formal","casual","technical","academic"],"description":"写作风格"},"length":{"type":"string","enum":["short","medium","long"],"description":"篇幅长度"}},"required":["doc_type","topic"]}}
{"name":"writing_polish","description":"润色已有文本。用户说'帮我润色'、'优化一下这段'、'改得...一点'时触发。","parameters":{"type":"object","properties":{"text":{"type":"string","description":"需要润色的原文"},"goal":{"type":"string","enum":["more_professional","more_concise","more_friendly","fix_grammar","more_technical"],"description":"润色目标"},"target_language":{"type":"string","description":"目标语言，如 zh-CN/en，留空表示保持原语言"}},"required":["text"]}}
{"name":"writing_translate","description":"翻译文本。用户说'翻译'、'翻译成'、'translate'时触发。","parameters":{"type":"object","properties":{"text":{"type":"string","description":"需要翻译的原文"},"source_lang":{"type":"string","description":"源语言，auto 表示自动检测"},"target_lang":{"type":"string","description":"目标语言，如 zh-CN/en/ja"},"keep_formatting":{"type":"boolean","description":"是否保留原文格式（Markdown/代码块等）"}},"required":["text","target_lang"]}}
```

**技术实现**：

```
Tool: writing_generate
  ├── 调用 memory_recall 获取用户写作偏好（格式/风格/语言）
  ├── 构造 prompt：偏好上下文 + doc_type + topic + key_points + style
  ├── 调用上游 LLM 生成（核心能力依赖大模型，FR 做路由+参数适配）
  └── 返回 {"document": "...", "format": "markdown"}

Tool: writing_polish
  ├── 调用 memory_recall 获取用户偏好
  ├── 构造 prompt：原文 + goal + 偏好 → 上游 LLM
  └── 返回 {"polished": "...", "changes_summary": "..."}

Tool: writing_translate
  ├── 构造 prompt：原文 + 源语言 + 目标语言 + 格式保持要求
  ├── 调用上游 LLM
  └── 返回 {"translated": "...", "source_lang_detected": "..."}
```

**注**：写作类 Subagent 的核心"智能"来自上游 LLM，Function Router 的价值在于：
1. 自动注入用户记忆（偏好格式/风格）
2. 参数标准化（doc_type / style / length 枚举，减少 LLM 歧义）
3. 快速路由（不用每次都走通用对话链路）

### 3.4 数据分析 Subagent

**定位**：自然语言驱动本地数据分析，Pandas/SQL → 图表

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"data_query","description":"用自然语言查询和分析本地 CSV/Excel/SQLite 数据文件。用户说'分析数据'、'统计一下'、'画个图'时触发。","parameters":{"type":"object","properties":{"file_path":{"type":"string","description":"数据文件路径（CSV/Excel/SQLite）"},"query":{"type":"string","description":"自然语言描述的分析需求，如'按月份统计销售额''前10名客户的订单量'"},"chart_type":{"type":"string","enum":["bar","line","pie","scatter","table","auto"],"description":"图表类型，auto 表示自动选择"}},"required":["file_path","query"]}}
{"name":"data_schema","description":"查看数据文件的列结构和统计摘要，用于快速了解数据概况。","parameters":{"type":"object","properties":{"file_path":{"type":"string","description":"数据文件路径"}},"required":["file_path"]}}
```

**技术实现**：

```python
# Python Tool (不从 bash wrapper 调用上游 LLM)
def execute_data_query(file_path: str, query: str, chart_type: str) -> dict:
    # 1. 加载数据
    if file_path.endswith('.csv'):
        df = pd.read_csv(file_path)
    elif file_path.endswith(('.xls', '.xlsx')):
        df = pd.read_excel(file_path)
    elif file_path.endswith('.db'):
        conn = sqlite3.connect(file_path)
        # schema 检查 + SQL 安全校验（只允许 SELECT）

    # 2. 自然语言 → pandas 代码（调用上游 LLM)
    prompt = f"Schema:\n{df.dtypes}\n{df.head(3)}\n\nQuery: {query}\nGenerate Python pandas code:"
    code = call_llm(prompt)

    # 3. 沙箱执行（仅允许 pandas/matplotlib/numpy）
    result = sandbox_exec(code, locals={'df': df})

    # 4. 如果需要图表
    if chart_type != 'table':
        chart_path = generate_chart(result, chart_type)
        return {"summary": str(result), "chart_path": chart_path}

    return {"summary": str(result), "row_count": len(df)}
```

**安全约束**：
- 只允许 import pandas / matplotlib / numpy / json
- 禁止 import os / subprocess / sys / shutil
- 执行超时 15 秒
- 输出数据量上限 10,000 行

### 3.5 闲聊陪伴 Subagent

**定位**：轻量级直回，零工具调用，体感丝滑

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"chat_light","description":"轻量闲聊。日常寒暄、讲笑话、心情倾诉、简单知识问答。Router 检测到纯粹对话意图时触发。","parameters":{"type":"object","properties":{"mood":{"type":"string","enum":["casual","humor","comfort","curious","auto"],"description":"对话风格"},"memory_inject":{"type":"boolean","description":"是否注入用户的长期记忆上下文，默认true"}},"required":[]}}
```

**技术实现**：

```
Tool: chat_light
  ├── 路由模型判断为纯闲聊 → 直接走此 Subagent
  ├── 调用 memory_recall 注入用户上下文（昵称、兴趣等）
  ├── 使用路由模型直接生成回复（不走上游大模型！）
  │   路由模型对闲聊场景足够，latency 从 15-40s 降至 1-2s
  └── Completion Check → permissive 模式，直接返回
```

**关键设计**：闲聊 Subagent 是唯一不走上游模型的 Subagent。利用路由模型轻量高效的特点，实现"秒级回复"。这是赛题"快准狠"中"快"的核心体现。

### 3.6 Bash 命令行 Subagent

**定位**：安全执行本地 Bash 命令，用于文件管理、系统操作、脚本运行等

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"bash_exec","description":"在当前工作目录执行一个 Bash 命令并返回结果。用户说'运行'、'执行'、'查看文件'、'ls'、'cat'时触发。仅用于只读或安全的本地操作。","parameters":{"type":"object","properties":{"command":{"type":"string","description":"要执行的 bash 命令"},"workdir":{"type":"string","description":"工作目录，默认为当前项目目录"},"timeout":{"type":"integer","description":"超时秒数，默认30，最大120"}},"required":["command"]}}
{"name":"bash_spawn","description":"在后台启动一个长时间运行的服务或进程。用户说'启动服务'、'后台运行'时触发。","parameters":{"type":"object","properties":{"command":{"type":"string","description":"要后台执行的命令"},"workdir":{"type":"string","description":"工作目录"},"label":{"type":"string","description":"进程标签，方便后续查询和管理"}},"required":["command"]}}
{"name":"bash_status","description":"查询当前 Bash Subagent 管理的后台进程状态。","parameters":{"type":"object","properties":{"label":{"type":"string","description":"可选，按标签过滤"}},"required":[]}}
```

**技术实现**：

```
Tool: bash_exec
  ├── 白名单校验：允许 find/grep/cat/ls/wc/head/tail/awk/sed/sort/uniq/curl/wget/git/python3/node/npm/pip/df/du/ps/top/free
  ├── 黑名单拦截：禁止 rm -rf / fork bomb / dd / mkfs / shutdown / reboot / chmod 777
  ├── subprocess.run() 沙箱执行，timeout 默认 30s，硬上限 120s
  ├── 输出截断：stdout+stderr 合并，上限 10000 字符
  └── 返回 {"stdout": "...", "stderr": "...", "exit_code": 0, "workdir": "..."}

Tool: bash_spawn
  ├── subprocess.Popen() 后台启动，PID 写入 SQLite 进程表
  ├── 返回 {"pid": 12345, "label": "dev-server", "status": "running"}
  └── 定期检查进程存活状态

Tool: bash_status
  ├── 查询 SQLite 进程表
  └── 返回 [{"pid": 12345, "label": "dev-server", "status": "running", "uptime": "2h 15m"}]
```

**安全约束**：
- 命令白名单 + 黑名单双重校验
- 绝对禁止：`rm -rf /`、`dd`、`mkfs`、`shutdown`、`reboot`、`chmod 777 /`、fork bomb
- 写入操作需确认（`rm`、`mv`、`cp` 等）
- 输出截断防止上下文溢出
- 不在沙箱中使用 `--no-sandbox` 类参数

**数据库扩展**：

```sql
-- 后台进程表
CREATE TABLE bash_processes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pid INTEGER NOT NULL,
    label TEXT,
    command TEXT NOT NULL,
    workdir TEXT,
    status TEXT DEFAULT 'running',
    started_at TEXT DEFAULT (datetime('now')),
    stopped_at TEXT
);
```

### 3.7 WebFetch 网页抓取 Subagent

**定位**：安全抓取网页内容并提取可读文本，支持 Markdown 转换

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"web_fetch","description":"抓取指定 URL 的网页内容并提取正文（转为 Markdown）。用户说'帮我看看这个网页'、'抓取这个链接'、'读一下这篇文章'时触发。","parameters":{"type":"object","properties":{"url":{"type":"string","format":"uri","description":"要抓取的网页 URL"},"extract_mode":{"type":"string","enum":["auto","article","full_page","markdown"],"description":"提取模式：auto 自动判断 / article 仅正文 / full_page 全文 / markdown 转Markdown后返回"},"timeout":{"type":"integer","description":"超时秒数，默认15，最大30"}},"required":["url"]}}
{"name":"web_fetch_batch","description":"批量抓取多个 URL。用户说'帮我把这几个链接都抓下来'时触发。","parameters":{"type":"object","properties":{"urls":{"type":"array","items":{"type":"string","format":"uri"},"description":"URL 列表，最多 10 个"},"extract_mode":{"type":"string","enum":["auto","article","full_page","markdown"],"description":"提取模式，默认 auto"}},"required":["urls"]}}
```

**技术实现**：

```
Tool: web_fetch
  ├── httpx 异步请求，User-Agent 伪装为浏览器
  ├── 响应判断：Content-Type 检查（仅处理 text/html, application/json, text/plain）
  ├── HTML → Markdown 转换（html2text / markdownify）
  ├── 正文提取：readability-lxml 算法（extract_mode=article 时）
  ├── 结果缓存：URL + 响应 → SQLite 缓存表，TTL 1 小时
  ├── 大小限制：单页最大 5MB
  └── 返回 {"url": "...", "title": "...", "content": "markdown...", "content_length": 1234, "fetched_at": "..."}
```

**安全约束**：
- 禁止访问内网 IP（127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16）
- DNS 解析后再校验 IP，防止 DNS rebinding
- 禁止 file:// 协议
- 请求超时上限 30s
- 速率限制：同一域名 1 次/秒

**依赖**：
```txt
httpx>=0.24
readability-lxml>=0.8
html2text>=2024
```

### 3.8 WebSearch 网页搜索 Subagent

**定位**：搜索引擎整合，将搜索结果作为上下文注入后续处理

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"web_search","description":"在互联网上搜索信息，返回相关网页摘要。用户说'搜索一下'、'查一下网上关于'、'谷歌一下'、'最新消息'时触发。","parameters":{"type":"object","properties":{"query":{"type":"string","description":"搜索查询词"},"num_results":{"type":"integer","description":"返回结果数，默认5，最大10"},"search_type":{"type":"string","enum":["general","news","image","scholar"],"description":"搜索类型：general 通用 / news 新闻 / image 图片 / scholar 学术"},"time_range":{"type":"string","enum":["any","day","week","month","year"],"description":"时间范围过滤"}},"required":["query"]}}
{"name":"web_search_fetch","description":"搜索并自动抓取前 N 篇结果的内容。搜索+抓取二合一，适合需要深入阅读的场景。","parameters":{"type":"object","properties":{"query":{"type":"string","description":"搜索查询词"},"fetch_top_k":{"type":"integer","description":"自动抓取前K篇结果的全文，默认3，最大5"},"search_type":{"type":"string","enum":["general","news","scholar"],"description":"搜索类型"}},"required":["query"]}}
```

**技术实现**：

```
Tool: web_search
  ├── 搜索引擎后端可配置：DuckDuckGo (免费) / SerpAPI (付费) / SearXNG (自部署)
  ├── 默认使用 DuckDuckGo Instant Answer API（无需 API Key）
  ├── 搜索结果：{title, url, snippet, date}
  ├── 可选：调用 web_fetch 抓取 Top 3 结果正文
  └── 返回 {"query": "...", "results": [...], "total_estimated": 1234}

Tool: web_search_fetch
  ├── 先执行 web_search 获取 Top K 结果
  ├── 并发调用 web_fetch 抓取每篇正文
  ├── 去重 + 合并，按相关度排序
  └── 返回 {"query": "...", "results": [{"url":..., "title":..., "snippet":..., "full_content": "..."}], "fetched": 5}
```

**搜索引擎后端配置**：

```json
{
  "web_search": {
    "backend": "duckduckgo",
    "serpapi_key": null,
    "searxng_url": null,
    "rate_limit_rpm": 10,
    "max_results": 10,
    "cache_ttl_minutes": 30
  }
}
```

**依赖**：
```txt
duckduckgo-search>=6.0
```

### 3.9 Subagent 汇总

| Subagent | 工具数 | 走上游 LLM | 典型延迟 | 存储依赖 |
|----------|--------|-----------|---------|---------|
| RAG 知识库 | 3 | 否（本地检索） | 1-3s | ChromaDB |
| 记忆与反思 | 3 | 否（本地检索） | <1s | SQLite + ChromaDB |
| 写作润色翻译 | 3 | **是** | 10-40s | 无 |
| 数据分析 | 2 | **是**（生成代码） | 5-20s | 无 |
| 闲聊陪伴 | 1 | **否**（路由模型直回） | 1-2s | SQLite（记忆注入） |
| Bash 命令行 | 3 | 否（本地执行） | <1-30s | SQLite（进程管理） |
| WebFetch 网页抓取 | 2 | 否（本地请求） | 2-15s | SQLite（缓存） |
| WebSearch 网页搜索 | 2 | 否（搜索 API） | 2-10s | 无 |

---

## 4. 自我进化引擎

### 4.1 核心理念

```
用户使用普罗米修斯越多 → 积累越多交互数据 →
后台反思引擎提取模式 → 更新记忆/图谱/策略 →
AI 更懂用户 → 用户更愿意使用 → 飞轮效应
```

### 4.2 双循环架构

```
┌─────────────────────────────────────────────────────────┐
│                    快循环（前台，实时）                     │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │ 用户输入  │ → │ Router 路由   │ → │ Subagent 响应 │    │
│  │          │   │ + memory注入  │   │ (1-40s)      │    │
│  └──────────┘   └──────────────┘   └──────────────┘    │
│                                                         │
│                    慢循环（后台，定时）                     │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │ 交互日志  │ → │ 反思模型分析  │ → │ 更新记忆+图谱  │    │
│  │ (全天积累) │   │ (每日/每小时)  │   │ (持久化存储)  │    │
│  └──────────┘   └──────────────┘   └──────────────┘    │
└─────────────────────────────────────────────────────────┘
```

### 4.3 反思触发条件

| 触发方式 | 频率 | 处理内容 | 实现 |
|---------|------|---------|------|
| 定时任务 | 每日凌晨 2:00 | 前一天所有交互记录 | cron + Python 脚本 |
| 阈值触发 | 每 50 次交互 | 增量反思 | interaction_log 计数 |
| 手动触发 | 用户主动要求 | "帮我总结一下最近的使用情况" | chat_light + memory_recall |
| 新文件摄入 | 每次 rag_ingest | 实体抽取 + 图谱关联 | 同步执行 |

### 4.4 反思摘要生成

```python
# scripts/reflection_loop.py

def run_reflection():
    # 1. 加载最近未处理日志
    logs = load_logs_since(last_reflection_time)

    # 2. 提取候选人提醒
    reminders = extract_reminder_candidates(logs)
    # 例：用户连续 3 个周五下午写周报 → "每周五 16:00 提醒写周报？"

    # 3. 提取偏好更新
    preferences = extract_preference_changes(logs)
    # 例：最近 5 次翻译请求都是中→英 → 更新 preferred_translation_direction

    # 4. 提取高频主题 → 知识图谱节点
    hot_topics = extract_hot_topics(logs, threshold=3)
    for topic in hot_topics:
        ensure_knowledge_node(topic)
        link_related_documents(topic)

    # 5. 生成摘要文本
    summary = format_summary(reminders, preferences, hot_topics)

    # 6. 持久化
    save_interaction_summary(summary)  # 下次对话注入上下文
    update_last_reflection_time()

    return summary
```

### 4.5 反思结果消费

反思结果通过两种路径被消费：

**路径 A — 下次对话注入**：
```python
# 每次新会话开始时，Router 自动调用
def inject_reflection_context(session):
    summary = get_latest_reflection_summary()
    if summary and summary.age < 24h:
        # 在 system_prompt 中注入反思结果
        return f"[近期发现] {summary}"
```

**路径 B — 主动推送**：
```python
# 用户上线时
def check_proactive_push():
    reminders_due = get_due_reminders()
    new_insights = get_unread_insights()
    if reminders_due or new_insights:
        return format_push_message(reminders_due, new_insights)
```

---

## 5. 数据模型

### 5.1 SQLite 数据库

```sql
-- File: ~/.prometheus/data/prometheus.db

-- 用户记忆
CREATE TABLE memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL CHECK(category IN ('preference','identity','habit','note')),
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    importance INTEGER DEFAULT 3 CHECK(importance BETWEEN 1 AND 5),
    source_session TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    access_count INTEGER DEFAULT 0,
    UNIQUE(category, key)
);

-- 提醒
CREATE TABLE reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    trigger_at TEXT NOT NULL,
    repeat_pattern TEXT DEFAULT 'once',
    active INTEGER DEFAULT 1,
    triggered INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

-- 交互日志
CREATE TABLE interaction_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    user_message TEXT,
    subagent TEXT,
    tool_name TEXT,
    tool_input TEXT,
    tool_result TEXT,
    latency_ms REAL,
    route_decision TEXT,          -- function/upstream/fallback
    completion_check_result TEXT, -- task_complete/task_incomplete
    timestamp TEXT DEFAULT (datetime('now'))
);

-- 反思记录
CREATE TABLE reflection_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    summary TEXT NOT NULL,
    reminders_found INTEGER DEFAULT 0,
    preferences_updated INTEGER DEFAULT 0,
    nodes_created INTEGER DEFAULT 0,
    links_created INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

-- 索引
CREATE INDEX idx_memories_category ON memories(category);
CREATE INDEX idx_memories_updated ON memories(updated_at);
CREATE INDEX idx_reminders_active ON reminders(active, trigger_at);
CREATE INDEX idx_interaction_session ON interaction_log(session_id, timestamp);
CREATE INDEX idx_interaction_subagent ON interaction_log(subagent, timestamp);
```

### 5.2 ChromaDB Collection

```python
# Collection: "documents"
# 存储文档片段嵌入
{
    "id": "doc_{file_hash}_{chunk_id}",
    "embedding": [...],            # BGE-M3 嵌入向量 (1024d)
    "document": "原始文本片段",
    "metadata": {
        "source_path": "/path/to/file.md",
        "file_type": "md",
        "chunk_index": 0,
        "title": "提取的标题",
        "ingested_at": "2026-07-11T10:00:00"
    }
}

# Collection: "memories"
# 存储用户记忆的语义嵌入
{
    "id": "mem_{memory_id}",
    "embedding": [...],
    "document": "{key}: {value}",
    "metadata": {
        "memory_id": 42,
        "category": "preference",
        "importance": 4
    }
}
```

### 5.3 知识图谱 (JSON)

```json
{
  "version": 1,
  "updated_at": "2026-07-11T10:00:00",
  "nodes": {
    "n1": {
      "id": "n1",
      "label": "HICOOL 智能体赛道",
      "type": "topic",
      "aliases": ["HICOOL 2026", "HICOOL比赛"],
      "source_sessions": ["sess_abc123"],
      "created_at": "2026-07-11T09:00:00"
    },
    "n2": {
      "id": "n2",
      "label": "MTClaw Function Router",
      "type": "technology",
      "aliases": ["MTClaw", "Function Router"],
      "source_sessions": ["sess_abc123", "sess_def456"]
    }
  },
  "edges": {
    "e1": {
      "id": "e1",
      "source": "n1",
      "target": "n2",
      "relation": "depends_on",
      "label": "赛题要求使用",
      "weight": 1.0,
      "source_sessions": ["sess_abc123"]
    }
  },
  "index": {
    "by_type": {
      "topic": ["n1"],
      "technology": ["n2"]
    }
  }
}
```

### 5.4 存储路径规划

```
~/.prometheus/
├── data/
│   ├── prometheus.db          # SQLite 数据库
│   ├── chroma/                # ChromaDB 持久化目录
│   ├── knowledge_graph.json   # 知识图谱
│   └── reflections.json       # 反思历史
├── config/
│   ├── config.json            # Function Router 配置
│   ├── functions.jsonl        # 8 个 Subagent 的工具定义
│   └── system_prompt.txt      # 可配置的系统提示词
├── scripts/                   # Subagent 工具 wrapper 脚本
│   ├── rag_search.sh
│   ├── rag_ingest.sh
│   ├── memory_remember.sh
│   ├── memory_recall.sh
│   ├── memory_set_reminder.sh
│   ├── writing_generate.sh
│   ├── writing_polish.sh
│   ├── writing_translate.sh
│   ├── data_query.sh
│   ├── data_schema.sh
│   ├── bash_exec.sh
│   ├── bash_spawn.sh
│   ├── bash_status.sh
│   ├── web_fetch.sh
│   ├── web_fetch_batch.sh
│   ├── web_search.sh
│   ├── web_search_fetch.sh
│   └── chat_light.sh
├── python_tools/              # Python 工具模块
│   ├── rag_engine.py          # 文档索引 + 检索
│   ├── memory_engine.py       # 记忆存储 + 检索
│   ├── graph_engine.py        # 知识图谱操作
│   ├── data_engine.py         # 数据分析沙箱
│   ├── bash_engine.py         # Bash 执行沙箱 + 进程管理
│   ├── web_engine.py           # WebFetch + WebSearch 引擎
│   └── reflection_engine.py   # 反思循环
├── logs/
│   ├── router.log             # Function Router 主日志
│   ├── router.debug.log       # Debug 日志
│   └── reflection.log         # 反思引擎日志
└── bin/
    └── prometheus             # 一键启停 CLI
```

---

## 6. API 与接口

### 6.1 对外 API（Hermes → MTClaw）

继承 MTClaw 的全部 OpenAI-compatible 端点，不做修改：

| Method | Endpoint | 说明 |
|--------|----------|------|
| POST | `/v1/chat/completions` | 核心聊天补全 |
| GET | `/v1/models` | 模型列表 |
| GET | `/health` | 健康检查 |
| GET | `/v1/tool_history` | 工具执行历史 |
| GET | `/v1/tools` | 已加载工具列表 |
| POST | `/v1/execute_tool` | 执行单个工具 |

### 6.2 内部 API（Subagent Tool → Python 引擎）

Subagent 的 bash wrapper 通过以下方式调用 Python 引擎：

```bash
# 示例：memory_remember.sh
#!/bin/bash
set -euo pipefail
INPUT=$(cat)
echo "$INPUT" | python3 "$HOME/.prometheus/python_tools/memory_engine.py" remember
```

Python 引擎模块接口：

```python
# rag_engine.py
def search(query: str, top_k: int = 5, source_filter: str = None) -> list[dict]
def ingest(path: str, recursive: bool = True) -> dict
def status() -> dict

# memory_engine.py
def remember(category: str, key: str, value: str, importance: int = 3) -> dict
def recall(context: str, top_k: int = 5, category: str = None) -> list[dict]
def set_reminder(content: str, time_str: str, repeat: str = 'once') -> dict
def get_due_reminders() -> list[dict]
def log_interaction(session_id: str, user_message: str, subagent: str, tool_name: str, tool_input: str, tool_result: str, latency_ms: float) -> None
def get_recent_interactions(limit: int = 100) -> list[dict]

# graph_engine.py
def add_node(label: str, node_type: str, aliases: list[str] = None) -> str
def add_edge(source_id: str, target_id: str, relation: str, label: str = "") -> str
def find_related(node_id: str, depth: int = 1) -> list[dict]
def search_nodes(query: str) -> list[dict]
def export_visualization() -> dict  # 用于前端展示

# bash_engine.py
def exec_cmd(command: str, workdir: str = ".", timeout: int = 30) -> dict
def spawn_process(command: str, workdir: str = ".", label: str = "") -> dict
def list_processes(label: str = None) -> list[dict]
def kill_process(pid: int) -> dict

# web_engine.py
def fetch_url(url: str, extract_mode: str = "auto", timeout: int = 15) -> dict
def fetch_batch(urls: list[str], extract_mode: str = "auto") -> list[dict]
def search_web(query: str, num_results: int = 5, search_type: str = "general", time_range: str = "any") -> dict
def search_and_fetch(query: str, fetch_top_k: int = 3, search_type: str = "general") -> dict

# reflection_engine.py
def run_reflection_cycle() -> dict   # 反思摘要
def get_latest_summary() -> str | None
def extract_reminder_candidates(logs: list[dict]) -> list[dict]
def extract_preference_changes(logs: list[dict]) -> list[dict]
def extract_hot_topics(logs: list[dict]) -> list[str]
```

### 6.3 配置示例

```json
{
  "listen_host": "127.0.0.1",
  "listen_port": 18790,
  "routing": {
    "base_url": "https://your-routing-model-api/v1",
    "model": "qwen3-30b-a3b-instruct-2507",
    "api_key": "${ROUTING_API_KEY}"
  },
  "upstream": {
    "base_url": "https://your-upstream-model-api/v1",
    "model": "doubao-seed-2-0-pro-260215",
    "api_key": "${UPSTREAM_API_KEY}"
  },
  "functions_file": "~/.prometheus/config/functions.jsonl",
  "scripts_dir": "~/.prometheus/scripts",
  "max_tool_rounds": 6,
  "tool_exec_timeout_s": 30,
  "routing_timeout_s": 10.0,
  "fr_completion_check": {
    "enabled": true,
    "mode": "permissive"
  },
  "fr_context_history": {
    "enabled": true
  },
  "delegate_tools_to_openclaw": false,
  "debug_logging": {
    "enabled": true
  },
  "prometheus": {
    "data_dir": "~/.prometheus/data",
    "reflection_interval_hours": 6,
    "reflection_cron": "0 2 * * *",
    "max_memories_per_user": 1000,
    "max_documents_per_user": 10000,
    "embedding_model": "BAAI/bge-m3",
    "embedding_device": "cpu",
    "graph_max_nodes": 5000,
    "data_analysis_timeout_s": 15,
    "data_analysis_max_rows": 10000,
    "bash_whitelist": ["find","grep","cat","ls","wc","head","tail","awk","sed","sort","uniq","curl","wget","git","python3","node","npm","pip","df","du","ps","top","free"],
    "bash_blacklist": ["rm -rf /","dd","mkfs","shutdown","reboot","chmod 777 /",":(){ :|:& };:"],
    "bash_timeout_s": 30,
    "bash_max_output_chars": 10000,
    "web_search_backend": "duckduckgo",
    "web_fetch_timeout_s": 15,
    "web_fetch_max_size_mb": 5,
    "web_fetch_cache_ttl_minutes": 60
  }
}
```

---

## 7. 路由策略

### 7.1 路由决策流程

```
用户消息 → Function Router
    │
    ├── 元数据清洗（去掉 Hermes 注入的 metadata blocks）
    │
    ├── memory_recall 注入（自动注入相关记忆到上下文）
    │
    ├── 路由模型判断 (tool calling, temperature=0.0)
    │     │
    │     ├── 命中 rag_*                                  → RAG Subagent
    │     ├── 命中 memory_*                               → 记忆 Subagent
    │     ├── 命中 writing_*                              → 写作 Subagent
    │     ├── 命中 data_*                                 → 数据分析 Subagent
    │     ├── 命中 bash_*                                 → Bash Subagent
    │     ├── 命中 web_fetch_*                            → WebFetch Subagent
    │     ├── 命中 web_search_*                           → WebSearch Subagent
    │     ├── 命中 chat_light（闲聊/心情/笑话/简单知识）     → 闲聊 Subagent
    │     │                                                  (路由模型直回，不走上游)
    │     └── 未命中任何工具                               → 上游 LLM
    │
    └── Completion Check
          ├── TASK_COMPLETE → 直接返回（快路径）
          └── TASK_INCOMPLETE → 转发上游 LLM
```

### 7.2 路由优先级

| 优先级 | 触发条件 | Subagent | 原因 |
|--------|---------|----------|------|
| 1 | 包含"提醒"/"记住了"/"以后都" | 记忆 Subagent | 明确偏好声明 |
| 2 | 包含 URL + "抓取"/"看看"/"读一下" | WebFetch Subagent | 网页内容抓取 |
| 3 | 包含"搜索"/"查一下网上"/"最新" + 外部信息 | WebSearch Subagent | 在线搜索 |
| 4 | 包含文件路径 + "分析"/"统计"/"图表" | 数据分析 Subagent | 数据操作 |
| 5 | 包含"翻译"/"translate" | 写作 Subagent | 翻译 |
| 6 | 包含"帮我写"/"生成"/"起草"/"润色" | 写作 Subagent | 写作 |
| 7 | 包含"找一下"/"搜索"/"查一下" + 文档语境 | RAG Subagent | 知识检索 |
| 8 | 包含"运行"/"执行" + Bash 命令 | Bash Subagent | 命令行操作 |
| 9 | 轻量寒暄/笑话/闲聊 | 闲聊 Subagent | 快速直回 |
| 10 | 以上都不匹配 | 上游 LLM | 通用推理 |

### 7.3 Hermes 配置

```json
{
  "models": {
    "providers": {
      "prometheus": {
        "baseUrl": "http://127.0.0.1:18790/v1",
        "apiKey": "any",
        "api": "openai-completions",
        "models": [{ "id": "function-router", "name": "Prometheus" }]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "prometheus/function-router"
      }
    }
  }
}
```

---

## 8. 文件结构

```
prometheus/                          # Git 仓库根目录
├── README.md                        # 项目说明
├── LICENSE                          # MIT
├── spec.md                          # 本文档
├── requirements.txt                 # Python 依赖
├── pyproject.toml                   # 包配置
│
├── function_router/                 # MTClaw 核心（继承 + 扩展）
│   ├── __init__.py
│   ├── server.py                    # 主服务（扩展：注入 memory_recall）
│   ├── builtin_tools.py             # 内置工具（保留 find/ls/cat/grep/sleep）
│   └── function-builtin.jsonl
│
├── prometheus/                      # 普罗米修斯新增模块
│   ├── __init__.py
│   ├── engine/
│   │   ├── __init__.py
│   │   ├── rag_engine.py            # 文档索引 + 检索
│   │   ├── memory_engine.py         # 记忆管理 + 交互日志
│   │   ├── graph_engine.py          # 知识图谱操作
│   │   ├── data_engine.py           # 数据分析沙箱
│   │   ├── bash_engine.py           # Bash 执行沙箱 + 进程管理
│   │   ├── web_engine.py             # WebFetch + WebSearch 引擎
│   │   └── reflection_engine.py     # 反思循环
│   ├── context/
│   │   ├── __init__.py
│   │   └── memory_injector.py       # 请求前自动注入记忆上下文
│   └── cli/
│       ├── __init__.py
│       └── prometheus_cli.py        # 命令行管理工具
│
├── config/                          # 预置配置
│   ├── config.example.json          # 配置模板
│   ├── functions.jsonl              # 8 个 Subagent 的工具定义（~20 条）
│   └── system_prompt.txt            # 可配置系统提示词
│
├── scripts/                         # Subagent Wrapper 脚本
│   ├── rag_search.sh
│   ├── rag_ingest.sh
│   ├── rag_status.sh
│   ├── memory_remember.sh
│   ├── memory_recall.sh
│   ├── memory_set_reminder.sh
│   ├── writing_generate.sh
│   ├── writing_polish.sh
│   ├── writing_translate.sh
│   ├── data_query.sh
│   ├── data_schema.sh
│   ├── bash_exec.sh
│   ├── bash_spawn.sh
│   ├── bash_status.sh
│   ├── web_fetch.sh
│   ├── web_fetch_batch.sh
│   ├── web_search.sh
│   ├── web_search_fetch.sh
│   ├── chat_light.sh
│   └── reflection_loop.sh           # 反思循环入口（后台 cron 调用）
│
├── install/                         # 安装与部署
│   ├── install.sh                   # 一键安装脚本
│   ├── uninstall.sh                 # 卸载脚本
│   └── restart.sh                   # 重启脚本
│
├── tests/                           # 测试
│   ├── __init__.py
│   ├── test_rag_engine.py
│   ├── test_memory_engine.py
│   ├── test_graph_engine.py
│   ├── test_data_engine.py
│   ├── test_bash_engine.py
│   ├── test_web_engine.py
│   ├── test_reflection_engine.py
│   └── test_integration.py          # 集成测试
│
├── demo/                            # 演示相关
│   ├── demo_script.md               # 演示剧本（4+ 领域连续对话）
│   └── sample_data/                 # 预置样本数据（用于演示）
│       ├── sample_notes/            # 模拟个人笔记
│       ├── sample_data.csv          # 模拟数据文件
│       └── sample_weekly_report.md  # 模拟周报
│
└── docs/                            # 文档
    ├── spec.md                      # 本规格文档（链接到项目根目录）
    ├── MTClaw-深度调研报告.md
    ├── 普罗米修斯商业计划书.md
    └── 演示剧本.md                   # 演示详细稿
```

---

## 9. 安装与部署

### 9.1 依赖清单

```txt
# requirements.txt
fastapi>=0.100
uvicorn>=0.20
httpx>=0.24
chromadb>=0.5
sentence-transformers>=2.7
pdfplumber>=0.10
python-docx>=1.0
pandas>=2.0
matplotlib>=3.7
openpyxl>=3.1
python-dateparser>=1.2
readability-lxml>=0.8
html2text>=2024
duckduckgo-search>=6.0
pytest>=7.0
```

### 9.2 一键安装

```bash
#!/bin/bash
# install/install.sh
set -euo pipefail

echo "=== 普罗米修斯 Prometheus 安装 ==="

# 1. 检查 Python 版本
python3 --version | grep -q "3.10\|3.11\|3.12" || {
    echo "需要 Python 3.10+"; exit 1;
}

# 2. 安装 Python 依赖
pip install -r requirements.txt
pip install -e .

# 3. 创建目录结构
mkdir -p ~/.prometheus/{data,config,scripts,python_tools,logs,bin}

# 4. 交互式配置
echo ""
echo "── 配置路由模型 ──"
read -r -p "路由模型 base_url: " ROUTING_URL
read -r -p "路由模型名称: " ROUTING_MODEL
read -r -p "路由模型 API key: " ROUTING_KEY

echo ""
echo "── 配置上游模型 ──"
read -r -p "上游模型 base_url: " UPSTREAM_URL
read -r -p "上游模型名称: " UPSTREAM_MODEL
read -r -p "上游模型 API key: " UPSTREAM_KEY

# 5. 写入配置
cp config/config.example.json ~/.prometheus/config/config.json
# patch 配置...

# 6. 复制工具定义和脚本
cp config/functions.jsonl ~/.prometheus/config/functions.jsonl
cp scripts/*.sh ~/.prometheus/scripts/
chmod +x ~/.prometheus/scripts/*.sh

# 7. 复制 Python 工具
cp -r prometheus/ ~/.prometheus/python_tools/

# 8. 初始化数据库
python3 -c "
from prometheus.engine.memory_engine import init_db
from prometheus.engine.rag_engine import init_chroma
init_db()
init_chroma()
"

# 9. 设置后台反思 cron
(crontab -l 2>/dev/null; echo "0 2 * * * ~/.prometheus/scripts/reflection_loop.sh") | crontab -

# 10. 启动服务
./install/restart.sh

echo ""
echo "=== 安装完成 ==="
echo "健康检查: curl http://127.0.0.1:18790/health"
echo "已加载工具: curl http://127.0.0.1:18790/v1/tools | jq '.tools | length'"
```

### 9.3 服务启动

```bash
#!/bin/bash
# install/restart.sh

# 停止旧进程
pkill -f "function_router/server.py" 2>/dev/null || true
sleep 1

# 启动 Function Router
nohup python3 -m function_router.server \
    --config ~/.prometheus/config/config.json \
    > ~/.prometheus/logs/router.log 2>&1 &

echo "普罗米修斯已启动 (PID: $!)"

# 等待健康检查
for i in {1..10}; do
    if curl -s http://127.0.0.1:18790/health > /dev/null 2>&1; then
        TOOLS=$(curl -s http://127.0.0.1:18790/health | python3 -c "import sys,json; print(json.load(sys.stdin)['tools_loaded'])")
        echo "✓ 健康检查通过 (已加载 $TOOLS 个工具)"
        exit 0
    fi
    sleep 1
done

echo "✗ 启动超时"
tail -20 ~/.prometheus/logs/router.log
exit 1
```

---

## 10. 演示剧本

### 10.1 演示流程总览

| 轮次 | 用户输入 | 路由目标 | 核心展示点 | 预计延迟 |
|------|---------|---------|-----------|---------|
| 1 | "帮我把 sample_data 目录导入知识库" | RAG Subagent | 文档索引 | 2-3s |
| 2 | "找一下上周关于 GPU 算力的笔记" | RAG Subagent | 语义检索 + 图谱关联 | 1-2s |
| 3 | "记住了，以后周报用中文、Markdown 格式，包含本周完成和下周计划" | 记忆 Subagent | 偏好记忆 | <1s |
| 4 | "帮我写一份本周周报" | 写作 Subagent | 记忆注入 → 自动格式 | 10-20s |
| 5 | "把这段周报翻译成英文" | 写作 Subagent | 翻译 + 保持格式 | 5-10s |
| 6 | "分析一下 sample_data.csv，按月份统计销售额" | 数据分析 Subagent | NL → Python → 图表 | 5-15s |
| 7 | "明天上午10点提醒我提交 HICOOL 代码" | 记忆 Subagent | 提醒设置 | <1s |
| 8 | "讲个笑话放松一下" | 闲聊 Subagent | 轻量直回（1-2s vs 上游 20s） | 1-2s |
| 9 | "帮我查一下当前目录下有哪些 Python 文件" | Bash Subagent | 命令行安全执行 | <1s |
| 10 | "抓取这个网页的内容 https://example.com/article" | WebFetch Subagent | 网页抓取 + Markdown 转换 | 2-5s |
| 11 | "搜索一下 HICOOL 2026 智能体赛道最新消息" | WebSearch Subagent | 在线搜索 + 结果抓取 | 3-8s |
| 12 | "关于量子计算你怎么看" | 上游 LLM | 通用推理兜底 | 15-40s |

### 10.2 进化演示（"第二天"环节）

可选：演示跨会话记忆。用不同 session_id 发起请求，展示系统记住偏好：

```
[新会话]
  用户："写周报"
  系统：自动检测无用户消息中的格式指示
        → memory_recall 自动注入：{writing_format: "markdown", language: "zh-CN", structure: "本周完成+下周计划"}
        → 自动生成符合偏好的周报
```

### 10.3 路由追踪面板（可选加分项）

演示时打开本地 Web 页面（`http://127.0.0.1:18790/dashboard`），实时展示：

```
上次请求：
  用户输入："找一下关于 GPU 算力的笔记"
  元数据清洗：✓ (移除 3 个 metadata block)
  路由决策：RAG Subagent (rag_search)
  匹配置信度：0.94
  工具调用：rag_search({"query": "GPU 算力", "top_k": 5})
  检索结果：3 篇文档，平均相似度 0.82
  图谱关联：发现 2 个关联节点 (MTT AIBOOK / CUDA 对比)
  Completion Check：TASK_COMPLETE
  总延迟：1.8s (路由: 0.3s / 检索: 0.8s / 响应生成: 0.7s)
```

---

## 11. 里程碑计划

### Phase 1：核心框架搭建（第 1-2 周）

```
□ Fork MTClaw，建立 prometheus 仓库
□ 搭建 8 个 Subagent 的 functions.jsonl 工具定义
□ 实现 wrapper 脚本骨架（20 个 .sh）
□ 实现 Python 引擎模块：
  ├── rag_engine.py (ingest + search + status)
  ├── memory_engine.py (remember + recall + set_reminder)
  ├── graph_engine.py (add_node + add_edge + find_related)
  ├── data_engine.py (query + schema)
  ├── bash_engine.py (exec + spawn + status)
  └── web_engine.py (fetch + search)
□ 配置 Hermes → MTClaw 联通
□ 端到端验证：单轮对话 8 种领域路由
```

### Phase 2：自我进化引擎（第 3-4 周）

```
□ 实现 reflection_engine.py（反思循环）
□ 实现 memory_injector.py（请求前自动注入记忆）
□ SQLite 数据模型建表 + 索引
□ ChromaDB Collection 初始化
□ 知识图谱 JSON 初始化 + 自动关联
□ 后台 cron 反思任务调度
□ 跨会话记忆验证
□ 主动推送提醒验证
```

### Phase 3：演示准备（第 5-6 周）

```
□ 演示剧本排练（12 轮连续对话）
□ 样本数据准备（笔记/数据/周报）
□ 路由追踪面板（可选，加分项）
□ 一键安装脚本调试
□ 安装/卸载/重启流程验证
□ Bug 修复 + 边缘 case 测试
□ 演示录屏备份
```

### Phase 4：交付（第 7 周）

```
□ 代码压缩打包
□ README + 安装说明
□ 演示视频录制（备用）
□ 提交 HICOOL
```

---

## 12. 评估维度自检清单

### 快（速度）

- [ ] 闲聊 Subagent 走路由模型直回，延迟 < 2s
- [ ] RAG 检索本地 ChromaDB，延迟 < 3s
- [ ] 记忆 Subagent 本地 SQLite 查询，延迟 < 1s
- [ ] Bash Subagent 命令执行延迟 < 2s（常规命令）
- [ ] WebFetch 网页抓取延迟 < 5s（常规网页）
- [ ] 路由决策本身延迟 < 1s
- [ ] Completion Check 命中率 > 80%（避免不必要的上游调用）

### 准（准确率）

- [ ] 路由分发测试：50 条混合意图，分发准确率 > 95%
- [ ] RAG 检索：Top-5 召回率 > 90%
- [ ] 写作 Subagent：格式符合用户记忆偏好的概率 > 85%
- [ ] 记忆 Subagent：偏好召回准确率 > 90%
- [ ] 通用 Benchmark：智商不退化（全部走上游 LLM 兜底）

### 稳（智商不变低）

- [ ] 未命中工具的通用请求 100% 透明转发上游 LLM
- [ ] 上游 LLM 响应不做任何改动（原样流式透传）
- [ ] 元数据清洗不影响请求语义

### 广（场景覆盖）

- [ ] 8 个 Subagent 覆盖 8+ 场景（办公/学习/数据/创作/闲聊/日程/命令行/信息检索）
- [ ] 每个 Subagent 至少 1 个可演示的完整任务
- [ ] 至少 1 个 Subagent 包含多轮工具循环

### 产品化完成度

- [ ] 一键安装脚本可用（`./install.sh`）
- [ ] 一键卸载脚本可用（`./install/uninstall.sh`）
- [ ] 健康检查正常
- [ ] 安装后立即可用的样本数据
- [ ] 清晰的 README（含截图/录屏）

### 商业价值

- [ ] 明确的目标用户画像（知识工作者）
- [ ] 真实场景痛点（跨文档检索 + 长期记忆 + 主动提醒）
- [ ] 清晰的差异化定位（自我进化 vs ChatGPT 无记忆）
- [ ] 可展示的商业计划（已有完整文档）

### 加分项

- [ ] 可视化路由追踪面板
- [ ] Router 自学习（反思引擎根据用户习惯优化策略）
- [ ] 一键安装包 + 预置 Subagent 市场

---

## 附录 A：工具定义汇总

| 工具名 | Subagent | 参数数 | 走上游 | 写操作 |
|--------|---------|--------|--------|--------|
| `rag_search` | RAG | 3 (query, top_k, source_filter) | 否 | 否 |
| `rag_ingest` | RAG | 2 (path, recursive) | 否 | 是 |
| `rag_status` | RAG | 0 | 否 | 否 |
| `memory_remember` | 记忆 | 4 (category, key, value, importance) | 否 | 是 |
| `memory_recall` | 记忆 | 3 (context, top_k, category) | 否 | 否 |
| `memory_set_reminder` | 记忆 | 3 (content, time, repeat) | 否 | 是 |
| `writing_generate` | 写作 | 6 (doc_type, topic, key_points, style, length) | 是 | 否 |
| `writing_polish` | 写作 | 3 (text, goal, target_language) | 是 | 否 |
| `writing_translate` | 写作 | 4 (text, source_lang, target_lang, keep_formatting) | 是 | 否 |
| `data_query` | 数据分析 | 3 (file_path, query, chart_type) | 是 | 否 |
| `data_schema` | 数据分析 | 1 (file_path) | 否 | 否 |
| `chat_light` | 闲聊 | 2 (mood, memory_inject) | 否 | 否 |
| `bash_exec` | Shell | 3 (command, workdir, timeout) | 否 | 否 |
| `bash_spawn` | Shell | 3 (command, workdir, label) | 否 | 是 |
| `bash_status` | Shell | 1 (label) | 否 | 否 |
| `web_fetch` | WebFetch | 3 (url, extract_mode, timeout) | 否 | 否 |
| `web_fetch_batch` | WebFetch | 2 (urls, extract_mode) | 否 | 否 |
| `web_search` | WebSearch | 4 (query, num_results, search_type, time_range) | 否 | 否 |
| `web_search_fetch` | WebSearch | 3 (query, fetch_top_k, search_type) | 否 | 否 |

**工具总数**：19（含 5 个 MTClaw builtin tools 则共 24 个）

## 附录 B：关键依赖版本

| 包名 | 最低版本 | 用途 |
|------|---------|------|
| fastapi | 0.100 | Web 框架 |
| uvicorn | 0.20 | ASGI 服务器 |
| httpx | 0.24 | HTTP 客户端 |
| chromadb | 0.5 | 向量数据库 |
| sentence-transformers | 2.7 | 嵌入模型（BGE-M3） |
| pdfplumber | 0.10 | PDF 文本提取 |
| python-docx | 1.0 | DOCX 文本提取 |
| pandas | 2.0 | 数据分析 |
| matplotlib | 3.7 | 图表生成 |
| openpyxl | 3.1 | Excel 读取 |
| python-dateparser | 1.2 | 自然语言时间解析 |
| readability-lxml | 0.8 | 网页正文提取 |
| html2text | 2024 | HTML → Markdown 转换 |
| duckduckgo-search | 6.0 | DuckDuckGo 搜索 API |

## 附录 C：安全注意事项

1. **数据分析沙箱**：Python exec 仅允许 import pandas/matplotlib/numpy/json，禁止 os/subprocess/sys
2. **Bash 命令安全**：白名单 + 黑名单双重校验，禁止 rm -rf / / dd / mkfs / shutdown / reboot / fork bomb
3. **文件访问控制**：RAG ingest 仅读取，不做任何写入或执行
4. **API Key 保护**：配置文件中的密钥使用 `${ENV_VAR}` 引用，不直接存储明文
5. **数据隐私**：所有数据存储于本地 `~/.prometheus/data/`，不上传云端
6. **网页抓取安全**：禁止内网 IP 访问（防 SSRF），DNS 解析后二次校验 IP，禁止 file:// 协议
7. **脚本执行限制**：工具 wrapper 通过路径白名单校验，防止目录遍历
