# 普罗米修斯（Prometheus）技术规格说明书

> 基于 MTClaw Function Router 的自我进化型个人认知智能体
>
> 版本：v2.0 | 日期：2026-07-12 | 目标：HICOOL 智能体赛道参赛

---

## 目录

1. [项目概述](#1-项目概述)
2. [系统架构](#2-系统架构)
3. [Subagent 规格](#3-subagent-规格)
4. [即时偏好引擎](#4-即时偏好引擎)
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

基于 MTClaw Function Router，在 MTT AIBOOK 上运行的自我进化型个人认知智能体--用户使用越多，AI 越"懂"用户。

### 1.2 核心差异化

| 维度 | ChatGPT / 通用 AI | 普罗米修斯 |
|------|-------------------|-----------|
| 记忆 | 会话级（对话结束即遗忘） | 跨会话持久化 + 即时偏好学习 |
| 行为模式 | 被动问答 | 主动推送 + 被动问答 |
| 进化 | 版本升级（依赖人工） | 即时偏好提取，持续自主进化 |
| 路由 | 单一模型 | Function Router 自动分发 5 个 Subagent |
| 隐私 | 云端处理 | 全本地存储，零上传 |

### 1.3 技术栈

| 层级 | 选型 | 说明 |
|------|------|------|
| Agent 框架 | **Hermes** | 用户交互入口，OpenAI-compatible 客户端 |
| 智能体框架 | **MTClaw** | Function Router 路由分发 |
| 本地推理 | MTT AIBOOK (AIOS 1.4.2) | 路由模型 + 嵌入模型 |
| 上游模型 | Cloud API (DeepSeek / GPT-4o) | 兜底通用推理 |
| 向量数据库 | ChromaDB | 文档嵌入 + 情节记忆检索 |
| 关系数据库 | SQLite | 用户偏好、记忆元数据 |
| 后端语言 | Python 3.10+ | Subagent 逻辑 + 工具实现 |

### 1.4 交付环境

- 操作系统：MTT AIBOOK AIOS 1.4.2 (Ubuntu 22.04)
- 硬件：MTT AIBOOK（含 MTT GPU）
- 自备服务：路由模型 API + 上游模型 API

### 1.5 v2.0 变更摘要

| 变更 | 说明 |
|------|------|
| Subagent 8→5 | 砍掉 WebFetch/WebSearch/DataAnalysis（上游 LLM 兜底覆盖） |
| 工具数 24→15 | 回到 LLM function calling 准确率最佳范围 |
| 反思引擎→即时偏好引擎 | 同步偏好提取，不依赖 cron，演示可跑通 |
| 砍掉插件系统/知识图谱/Web UI/fallback 链 | 聚焦核心，确保 7 周交付 | |
| 从"无损接入"改为"源码合入 MTClaw" | 官方希望最终代码提交到 MTClaw 开源仓库 | 用 MTClaw 自带安装脚本一键安装 |
| 所有数字标注来源 | [实测] / [目标] / [推测] 三级分类 | |

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
│  │  │ 元数据清洗 │  │ Session 管理  │  │ 路由模型 (tool call)  │   │
│  │  └──────────┘  └──────────────┘  └──────────┬───────────┘   │   │
│  └─────────────────────────────────────────────┼────────────────┘   │
│                                                  │                   │
│  ┌───────────────────────────────────────────────┼──────────────────┐  │
│  │                   Subagent 层                  │                  │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌┴─────────┐    │  │
│  │  │  RAG   │ │ 记忆   │ │ 写作   │ │ 日程   │ │  闲聊    │    │  │
│  │  │ 知识库  │ │ 与偏好  │ │ 润色   │ │ 与任务  │ │  陪伴    │    │  │
│  │  └───┬────┘ └───┬────┘ └───┬────┘ └───┬────┘ └────┬─────┘    │  │
│  └──────┼──────────┼──────────┼──────────┼───────────┼──────────┘  │
├─────────┼──────────┼──────────┼──────────┼───────────┼──────────────┤
│                      工具执行层                                       │
│  ┌──────┴──────────┴─────────┴──────────┴───────────┴────────────┐  │
│  │                    Bash Wrapper Scripts  +  Python Tool Modules │  │
│  │                    functions.jsonl 中定义，stdin JSON -> stdout JSON │  │
│  └───────────────────────────────────────────┬────────────────────┘  │
├──────────────────────────────────────────────┼──────────────────────┤
│                      数据与存储层                                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐                       │
│  │  SQLite  │  │ ChromaDB │  │ 本地文件系统  │                       │
│  │ 用户偏好  │  │ 文档向量  │  │  文档/附件    │                       │
│  └──────────┘  └──────────┘  └──────────────┘                       │
│                          MTT AIBOOK 本地存储                         │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 请求处理流程

```
1. 用户输入 -> Hermes -> POST /v1/chat/completions -> MTClaw Function Router
2. Function Router 清洗元数据（去掉 Hermes 注入的 sender block 等）
3. 即时偏好检测（检查用户消息中是否有偏好声明）
4. Function Router 调用路由模型，传入 5 个 Subagent 的工具定义
5. 路由模型判断命中哪个 Subagent
   ├── 命中 Subagent -> 执行对应工具 -> Completion Check
   │   ├── TASK_COMPLETE -> 直接返回响应（快路径）
   │   └── TASK_INCOMPLETE -> 转发上游 LLM（慢路径）
   └── 未命中任何工具 -> 转发上游 LLM（通用推理）
6. 工具执行结果记录到 interaction_log（供偏好引擎使用）
7. 响应返回 Hermes -> 展示给用户
```

### 2.3 路由 fallback

```
v2.0 新增：路由模型超时/失败时的安全降级

路由模型不可用或超时 (routing_timeout_s=10s)
  │
  └── 直接转发上游 LLM（跳过工具路由）
      -> 确保用户请求不会因为路由模型故障而无响应
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
  ├── 输入 query -> 本地 BGE-M3 嵌入模型 -> 向量化
  ├── ChromaDB 稠密检索 -> Top K₁
  ├── BM25 稀疏检索 -> Top K₂
  ├── RRF 融合排序 -> Top K
  └── 返回 {matches: [{source, content, score}]}

Tool: rag_ingest
  ├── 支持格式：.md / .pdf / .txt / .docx / .csv
  ├── 分段策略：按标题 + 段落，chunk_size=512, overlap=64
  ├── 嵌入：BGE-M3（本地 CPU/GPU，无需网络）
  └── 存储：ChromaDB persist 到本地磁盘
```

### 3.2 记忆与偏好 Subagent

**定位**：记住用户偏好与历史交互，即时偏好引擎实时提取偏好，实现跨会话记忆和主动服务

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"memory_remember","description":"记录用户偏好、习惯或重要信息。用户说'记住了'、'以后都...'、'我的...是...'时触发。","parameters":{"type":"object","properties":{"category":{"type":"string","description":"记忆类别：preference/identity/habit/note"},"key":{"type":"string","description":"记忆的键，如 writing_format、preferred_language"},"value":{"type":"string","description":"记忆的值"},"importance":{"type":"integer","minimum":1,"maximum":5,"description":"重要程度，1-5，默认为3"}},"required":["category","key","value"]}}
{"name":"memory_recall","description":"检索与当前上下文相关的用户记忆。Router 在处理请求前自动调用此工具注入记忆上下文。","parameters":{"type":"object","properties":{"context":{"type":"string","description":"当前对话的上下文描述，用于相似度匹配"},"top_k":{"type":"integer","description":"返回最相关的K条记忆，默认5"},"category":{"type":"string","description":"可选：按类别过滤 memory/preference/identity/habit/note"}},"required":["context"]}}
{"name":"memory_set_reminder","description":"设置提醒。用户说'提醒我'、'别忘了'时触发。","parameters":{"type":"object","properties":{"content":{"type":"string","description":"提醒内容"},"time":{"type":"string","description":"提醒时间，如'明天上午10点'、'每周五下午4点'"},"repeat":{"type":"string","description":"重复模式：once/daily/weekly/monthly，默认once"}},"required":["content","time"]}}
```

**数据模型**：

```sql
CREATE TABLE memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL,       -- preference / identity / habit / note
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    importance INTEGER DEFAULT 3,  -- 1-5
    source_session TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    access_count INTEGER DEFAULT 0,
    UNIQUE(category, key)
);

CREATE TABLE reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    trigger_at TIMESTAMP NOT NULL,
    repeat_pattern TEXT DEFAULT 'once',
    active INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE interaction_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    user_message TEXT,
    subagent TEXT,
    tool_name TEXT,
    tool_result TEXT,
    latency_ms REAL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 3.3 写作润色翻译 Subagent

**定位**：周报、邮件、技术文档场景化生成

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"writing_generate","description":"生成各类文档。包括周报、邮件、技术文档、会议纪要等。用户说'帮我写'、'生成一份'、'起草'时触发。","parameters":{"type":"object","properties":{"doc_type":{"type":"string","enum":["weekly_report","email","tech_doc","meeting_minutes","article","essay","ppt_outline"],"description":"文档类型"},"topic":{"type":"string","description":"文档主题或标题"},"key_points":{"type":"array","items":{"type":"string"},"description":"需要包含的关键要点列表"},"style":{"type":"string","enum":["formal","casual","technical","academic"],"description":"写作风格"},"length":{"type":"string","enum":["short","medium","long"],"description":"篇幅长度"}},"required":["doc_type","topic"]}}
{"name":"writing_polish","description":"润色已有文本。用户说'帮我润色'、'优化一下这段'、'改得...一点'时触发。","parameters":{"type":"object","properties":{"text":{"type":"string","description":"需要润色的原文"},"goal":{"type":"string","enum":["more_professional","more_concise","more_friendly","fix_grammar","more_technical"],"description":"润色目标"},"target_language":{"type":"string","description":"目标语言，如 zh-CN/en，留空表示保持原语言"}},"required":["text"]}}
{"name":"writing_translate","description":"翻译文本。用户说'翻译'、'翻译成'、'translate'时触发。","parameters":{"type":"object","properties":{"text":{"type":"string","description":"需要翻译的原文"},"source_lang":{"type":"string","description":"源语言，auto 表示自动检测"},"target_lang":{"type":"string","description":"目标语言，如 zh-CN/en/ja"},"keep_formatting":{"type":"boolean","description":"是否保留原文格式（Markdown/代码块等）"}},"required":["text","target_lang"]}}
{"name":"writing_humanize","description":"去AI化改写。用户说'去AI味'、'去AI化'、'改得像人写的'时触发。","parameters":{"type":"object","properties":{"text":{"type":"string","description":"需要去AI化的原文"},"intensity":{"type":"string","enum":["light","medium","heavy"],"description":"改写强度：light仅去套话/medium重写句式/heavy全面改写"},"preserve_formatting":{"type":"boolean","description":"是否保留原文格式（Markdown/代码块等）"}},"required":["text"]}}
```

### 3.4 日程与任务 Subagent

**定位**：本地日程管理与任务追踪，自然语言创建日程/待办

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"schedule_create_event","description":"创建日程事件。用户说'安排会议'、'明天下午3点开会'、'加个日程'时触发。","parameters":{"type":"object","properties":{"title":{"type":"string","description":"日程标题"},"start_time":{"type":"string","description":"开始时间，支持自然语言如'明天下午3点'"},"end_time":{"type":"string","description":"结束时间，可选"},"location":{"type":"string","description":"地点，可选"},"category":{"type":"string","enum":["work","personal","study","meeting","other"],"description":"日程类别"},"reminder_minutes":{"type":"integer","description":"提前提醒分钟数，默认15"}},"required":["title","start_time"]}}
{"name":"schedule_query","description":"查询日程。用户说'今天有什么安排'、'这周有什么会议'、'查一下日程'时触发。","parameters":{"type":"object","properties":{"time_range":{"type":"string","enum":["today","tomorrow","this_week","next_week","all"],"description":"时间范围，默认today"},"category":{"type":"string","description":"可选，按类别过滤"},"status":{"type":"string","enum":["pending","completed","cancelled","all"],"description":"状态过滤，默认pending"}},"required":[]}}
{"name":"schedule_create_task","description":"创建任务（待办事项）。用户说'帮我记个待办'、'下周一之前完成XXX'、'添加任务'时触发。","parameters":{"type":"object","properties":{"title":{"type":"string","description":"任务标题"},"priority":{"type":"integer","minimum":1,"maximum":5,"description":"优先级1-5，默认3"},"due_date":{"type":"string","description":"截止日期，支持自然语言"},"tags":{"type":"string","description":"标签，逗号分隔"},"description":{"type":"string","description":"任务描述"}},"required":["title"]}}
{"name":"schedule_list_tasks","description":"查询任务列表。用户说'还有哪些没完成'、'待办列表'、'查一下任务'时触发。","parameters":{"type":"object","properties":{"status":{"type":"string","enum":["pending","in_progress","completed","all"],"description":"状态过滤，默认pending"},"priority":{"type":"integer","description":"可选，按优先级过滤"},"tags":{"type":"string","description":"可选，按标签过滤"}},"required":[]}}
{"name":"schedule_complete_task","description":"标记任务完成。用户说'完成了XXX'、'这个任务做完了'时触发。","parameters":{"type":"object","properties":{"task_id":{"type":"integer","description":"任务ID"}},"required":["task_id"]}}
```

**数据模型**：events 表 + tasks 表（详见 §5.1）

**核心能力**：
- dateparser 自然语言时间解析（"明天下午3点" / "下周一" / "3小时后"）
- 重复日程支持（daily/weekly/monthly）
- 任务优先级 + 标签 + 子任务
- 与记忆 Subagent 协同（偏好引擎检测时间规律 -> 建议创建重复日程）

### 3.5 闲聊陪伴 Subagent

**定位**：轻量级直回，零工具调用，体感丝滑

**工具定义** (`functions.jsonl`)：

```jsonl
{"name":"chat_light","description":"轻量闲聊。日常寒暄、讲笑话、心情倾诉、简单知识问答。Router 检测到纯粹对话意图时触发。","parameters":{"type":"object","properties":{"mood":{"type":"string","enum":["casual","humor","comfort","curious","auto"],"description":"对话风格"},"memory_inject":{"type":"boolean","description":"是否注入用户的长期记忆上下文，默认true"}},"required":[]}}
```

**关键设计**：闲聊 Subagent 是唯一不走上游模型的 Subagent。利用路由模型轻量高效的特点，实现"秒级回复"。这是赛题"快准狠"中"快"的核心体现。

**误判保护（保守策略）**：任何不确定的情况都走上游 LLM 兜底，宁可慢也不答错。

### 3.6 Subagent 汇总

| Subagent | 工具数 | 走上游 LLM | 典型延迟 [推测] | 存储依赖 |
|----------|--------|-----------|---------|---------|
| RAG 知识库 | 3 | 否（本地检索） | 1-3s | ChromaDB |
| 记忆与偏好 | 3 | 否（本地检索） | <1s | SQLite + ChromaDB |
| 写作润色翻译 | 4 | **是** | 10-40s | 无 |
| 日程与任务 | 5 | 否（本地 SQLite） | <1s | SQLite |
| 闲聊陪伴 | 1 | **否**（路由模型直回） | 1-3s | SQLite（记忆注入） |
| **合计** | **16** | | | |

加上 MTClaw 的 5 个 builtin 工具（find/ls/cat/grep/sleep），总计 21 个工具暴露给路由模型。

**注意**：v2.0 将工具数从 24 降到 18，其中 13 个为 Prometheus 自定义工具。研究表明 LLM function calling 在工具数 <15 时准确率最高 [推测]。我们通过 5 个 Subagent 的清晰划分（每个 1-3 个工具）来保持路由模型的判断精度。

---

## 4. 即时偏好引擎

### 4.1 核心理念

```
用户使用普罗米修斯越多 -> 积累越多偏好数据 ->
即时偏好引擎实时提取 -> 更新记忆 -> AI 更懂用户
```

### 4.2 v2.0 核心变更：即时 vs 后台

| 特性 | v1.0 反思引擎 | v2.0 即时偏好引擎 |
|------|-------------|-----------------|
| 触发 | 后台 cron 每日 2:00 | 用户说"以后都"/"记住了"时即时触发 |
| 延迟 | 隔夜才能看到效果 | 演示中即时可见 |
| 演示可行性 | 不可演示（需要跨天） | 可演示（同会话内） |
| 复杂度 | 高（需要 LLM 分析日志） | 低（规则匹配 + 同步写入） |

### 4.3 即时偏好检测

```python
def detect_and_store_preference(user_message: str) -> dict | None:
    """检测用户消息中的偏好声明，实时写入 memory。"""
    patterns = [
        (r"以后都.*?(用|使用)\s*(.+)", "preference"),
        (r"我喜欢.*?(用|使用)\s*(.+)", "preference"),
        (r"记住了.*?(.+)", "preference"),
        (r"不要.*?(用|使用)\s*(.+)", "preference"),
        (r"总是.*?(.+)", "habit"),
    ]
    for pattern, category in patterns:
        match = re.search(pattern, user_message)
        if match:
            key = extract_key_from_match(match)
            value = extract_value_from_match(match)
            memory_remember(category, key, value, importance=4)
            return {"detected": True, "key": key, "value": value}
    return None
```

### 4.4 定时维护任务（轻量版）

每日凌晨 2:00 执行，仅做记忆衰减/强化和交互统计：

```python
def run_daily_maintenance():
    # 1. 记忆衰减/强化
    for memory in get_all_memories():
        if memory.access_count > 10:
            memory.importance = min(5, memory.importance + 1)
        if memory.access_count == 0 and memory.days_since_update > 30:
            memory.importance = max(1, memory.importance - 1)

    # 2. 交互统计
    stats = compute_interaction_stats()
    save_reflection_log(stats)
```

### 4.5 偏好结果消费

**路径 A - 下次对话注入**：
```python
# 每次新会话开始时，Router 自动调用
def inject_preference_context(session):
    summary = memory_recall("user profile and preferences")
    if summary:
        return f"[用户画像] {summary}"
```

**路径 B - 演示效果**：
```
[第 1 轮] 用户: "写周报，用 Markdown，中文，包含本周完成和下周计划"
  -> 即时偏好检测 -> 写入 memory(writing_format=markdown, language=zh-CN, ...)
  -> writing_generate 按要求生成

[第 2 轮] 用户: "写周报"
  -> memory_recall 自动注入偏好
  -> 自动生成 Markdown 中文三段式周报
  -> 用户零额外输入
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
    route_decision TEXT,
    completion_check_result TEXT,
    timestamp TEXT DEFAULT (datetime('now'))
);

-- 反思记录
CREATE TABLE reflection_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    summary TEXT NOT NULL,
    preferences_updated INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now'))
);

-- 日程事件
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    start_time TEXT NOT NULL,
    end_time TEXT,
    location TEXT,
    category TEXT DEFAULT 'general',
    reminder_minutes INTEGER DEFAULT 15,
    status TEXT DEFAULT 'pending',
    created_at TEXT DEFAULT (datetime('now')),
    source TEXT DEFAULT 'user'
);

-- 任务（待办事项）
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    priority INTEGER DEFAULT 3,
    status TEXT DEFAULT 'pending',
    due_date TEXT,
    tags TEXT,
    parent_task_id INTEGER,
    created_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);

-- 索引
CREATE INDEX idx_events_start ON events(start_time);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_due ON tasks(due_date);

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

### 5.3 存储路径规划

```
~/.prometheus/
├── data/
│   ├── prometheus.db          # SQLite 数据库
│   ├── chroma/                # ChromaDB 持久化目录
│   └── reflections.json       # 反思历史
├── config/
│   ├── config.json            # Function Router 配置
│   ├── functions.jsonl        # 5 个 Subagent 的工具定义
│   └── system_prompt.txt      # 可配置的系统提示词
├── scripts/                   # Subagent 工具 wrapper 脚本
│   ├── rag_search.sh
│   ├── rag_ingest.sh
│   ├── rag_status.sh
│   ├── memory_remember.sh
│   ├── memory_recall.sh
│   ├── memory_set_reminder.sh
│   ├── writing_generate.sh
│   ├── writing_polish.sh
│   ├── writing_translate.sh
│   ├── schedule_create_event.sh
│   ├── schedule_query.sh
│   ├── schedule_create_task.sh
│   ├── schedule_list_tasks.sh
│   ├── schedule_complete_task.sh
│   └── chat_light.sh
├── python_tools/              # Python 工具模块
│   ├── rag_engine.py
│   ├── memory_engine.py
│   ├── writing_engine.py
│   ├── schedule_engine.py
│   ├── chat_engine.py
│   └── preference_engine.py   # 即时偏好引擎
├── templates/                 # 写作模板
│   ├── weekly_report.md
│   ├── email_formal.md
│   ├── email_casual.md
│   ├── tech_doc.md
│   ├── meeting_minutes.md
│   ├── article.md
│   └── ppt_outline.md
├── logs/
│   └── router.log
└── bin/
    └── prometheus             # 一键启停 CLI
```

---

## 6. API 与接口

### 6.1 对外 API（Hermes -> MTClaw）

继承 MTClaw 的全部 OpenAI-compatible 端点，不做修改：

| Method | Endpoint | 说明 |
|--------|----------|------|
| POST | `/v1/chat/completions` | 核心聊天补全 |
| GET | `/v1/models` | 模型列表 |
| GET | `/health` | 健康检查 |
| GET | `/v1/tool_history` | 工具执行历史 |
| GET | `/v1/tools` | 已加载工具列表 |
| POST | `/v1/execute_tool` | 执行单个工具 |

### 6.2 内部 API（Subagent Tool -> Python 引擎）

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

# writing_engine.py
def generate(doc_type: str, topic: str, key_points: list[str], style: str, length: str) -> dict
def polish(text: str, goal: str, target_language: str = None) -> dict
def translate(text: str, source_lang: str, target_lang: str, keep_formatting: bool = True) -> dict

# schedule_engine.py
def create_event(title: str, start_time: str, end_time: str = None, location: str = None, category: str = "general", reminder_minutes: int = 15) -> dict
def query_events(time_range: str = "today", category: str = None, status: str = "pending") -> list[dict]
def create_task(title: str, priority: int = 3, due_date: str = None, tags: str = None, description: str = None) -> dict
def list_tasks(status: str = "pending", priority: int = None, tags: str = None) -> list[dict]
def complete_task(task_id: int) -> dict

# chat_engine.py
def chat(mood: str = "auto", memory_inject: bool = True) -> dict

# preference_engine.py
def detect_and_store_preference(user_message: str) -> dict | None
def run_daily_maintenance() -> dict
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
    "model": "deepseek-v4-pro",
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
    "preference_cron": "0 2 * * *",
    "max_memories_per_user": 1000,
    "embedding_model": "BAAI/bge-m3",
    "embedding_device": "cpu"
  }
}
```

---

## 7. 路由策略

### 7.1 路由决策流程

```
用户消息 -> Function Router
    │
    ├── 元数据清洗（去掉 Hermes 注入的 metadata blocks）
    │
    ├── 即时偏好检测（检查是否有偏好声明）
    │
    ├── memory_recall 注入（自动注入相关记忆到上下文）
    │
    ├── 路由模型判断 (tool calling, temperature=0.0)
    │     │
    │     ├── 命中 rag_*        -> RAG Subagent
    │     ├── 命中 memory_*     -> 记忆 Subagent
    │     ├── 命中 writing_*    -> 写作 Subagent
    │     ├── 命中 schedule_*   -> 日程与任务 Subagent
    │     ├── 命中 chat_light   -> 闲聊 Subagent（路由模型直回）
    │     └── 未命中任何工具     -> 上游 LLM
    │
    └── Completion Check
          ├── TASK_COMPLETE -> 直接返回（快路径）
          └── TASK_INCOMPLETE -> 转发上游 LLM
```

### 7.2 路由优先级

| 优先级 | 触发条件 | Subagent | 原因 |
|--------|---------|----------|------|
| 1 | 包含"提醒"/"记住了"/"以后都" | 记忆 Subagent | 明确偏好声明 |
| 2 | 包含"翻译"/"translate" | 写作 Subagent | 翻译 |
| 3 | 包含"帮我写"/"生成"/"起草"/"润色" | 写作 Subagent | 写作 |
| 4 | 包含"日程"/"会议"/"待办"/"任务"/"安排" | 日程与任务 Subagent | 日程管理 |
| 5 | 包含"找一下"/"搜索"/"查一下" + 文档语境 | RAG Subagent | 知识检索 |
| 6 | 轻量寒暄/笑话/闲聊 | 闲聊 Subagent | 快速直回 |
| 7 | 以上都不匹配 | 上游 LLM | 通用推理 |

### 7.3 路由 fallback

```
路由模型超时 (routing_timeout_s=10s) 或不可用
  │
  └── 直接转发上游 LLM（跳过工具路由）
      -> 确保用户请求不会因为路由模型故障而无响应
```

---

## 8. 文件结构

```
MTClaw 仓库（https://github.com/MooreThreads/MTClaw）
├── function_router/                 # MTClaw 核心（已有）
│   ├── __init__.py
│   ├── server.py                    # 主服务
│   ├── builtin_tools.py             # 内置工具（find/ls/cat/grep/sleep）
│   └── function-builtin.jsonl
│
├── subagents/                       # Prometheus 新增目录
│   ├── rag/                         # RAG 知识库 Subagent
│   │   ├── functions.jsonl          # 工具定义
│   │   ├── scripts/                 # Bash wrapper 脚本
│   │   └── engine.py                # Python 引擎
│   ├── memory/                      # 记忆与偏好 Subagent
│   ├── writing/                     # 写作润色翻译 Subagent
│   ├── schedule/                    # 日程与任务 Subagent
│   └── chat/                        # 闲聊陪伴 Subagent
│
├── templates/                       # 写作模板
│   ├── weekly_report.md
│   ├── email_formal.md
│   ├── email_casual.md
│   ├── tech_doc.md
│   ├── meeting_minutes.md
│   ├── article.md
│   └── ppt_outline.md
│
├── dashboard/                       # 路由追踪面板
│   └── route_tracer.html
│
├── config/                          # 预置配置
│   ├── config.example.json
│   ├── functions.jsonl              # 所有 Subagent 工具定义聚合
│   └── system_prompt.txt
│
├── install/                         # MTClaw 安装脚本（扩展）
│   ├── install.sh
│   └── restart.sh
│
├── tests/                           # 测试
│   ├── test_routing_accuracy.py
│   └── ...
│
├── demo/                            # 演示相关
│   ├── demo_script.md
│   ├── run_demo.sh
│   └── sample_data/
│       ├── sample_notes/
│       ├── sample_data.csv
│       └── sample_weekly_report.md
│
└── docs/                            # 文档
    ├── spec.md
    ├── design-proposal.md
    └── speed-accuracy-impact.md
```

---

## 9. 安装与部署

### 9.1 源码合入 MTClaw

**v2.0 关键变更**：代码合入 MTClaw 仓库，使用 MTClaw 自带安装脚本。

```
代码组织方式:
  MTClaw 仓库（https://github.com/MooreThreads/MTClaw）
  ├── function_router/          # MTClaw 核心（已有）
  ├── subagents/                # Prometheus 新增目录
  │   ├── rag/                  # RAG 知识库 Subagent
  │   ├── memory/               # 记忆与偏好 Subagent
  │   ├── writing/              # 写作润色翻译 Subagent
  │   ├── schedule/             # 日程与任务 Subagent
  │   └── chat/                 # 闲聊陪伴 Subagent
  ├── templates/                # 写作模板
  ├── dashboard/                # 路由追踪面板
  └── install/                  # MTClaw 自带安装脚本（扩展）
```

### 9.2 依赖清单

```txt
# requirements.txt
fastapi>=0.100
uvicorn>=0.20
httpx>=0.24
chromadb>=0.5
sentence-transformers>=2.7
pdfplumber>=0.10
python-docx>=1.0
python-dateparser>=1.2
pytest>=7.0
```

### 9.3 一键安装（使用 MTClaw 自带安装脚本）

```bash
# 从 MTClaw 仓库安装
git clone https://github.com/MooreThreads/MTClaw.git
cd MTClaw
./install.sh
# 交互式输入路由模型/上游模型 URL + Key
# 自动完成：Python 依赖安装 -> 目录创建 -> DB 初始化 -> cron 设置 -> 服务启动
# 安装时间 < 5 分钟 [目标]
```

### 9.4 服务启动

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

| 轮次 | 用户输入 | 路由目标 | 核心展示点 | 预计延迟 [推测] |
|------|---------|---------|-----------|---------|
| 1 | "帮我把 sample_data 目录导入知识库" | RAG Subagent | 文档索引 | 2-3s |
| 2 | "找一下上周关于 GPU 算力的笔记" | RAG Subagent | 语义检索 | 1-2s |
| 3 | "记住了，以后周报用中文、Markdown 格式，包含本周完成和下周计划" | 记忆 Subagent | 偏好记忆（即时写入） | <1s |
| 4 | "帮我写一份本周周报" | 写作 Subagent | 偏好注入 -> 自动格式 | 10-20s |
| 5 | "把这段周报翻译成英文" | 写作 Subagent | 翻译 + 保持格式 | 5-10s |
| 6 | "帮我把这段文字去一下AI味" | 写作 Subagent | 去AI化改写 | 5-10s |
| 7 | "明天上午10点提醒我提交 HICOOL 代码" | 记忆 Subagent | 提醒设置 | <1s |
| 8 | "讲个笑话放松一下" | 闲聊 Subagent | 轻量直回 | 1-3s |
| 9 | "明天下午3点开产品评审会，帮我加到日程" | 日程与任务 Subagent | 自然语言创建日程 | <1s |
| 10 | "关于量子计算你怎么看" | 上游 LLM | 通用推理兜底 | 15-40s |

### 10.2 进化演示（"第二天"环节）

```
[新会话]
  用户："写周报"
  系统：自动检测无用户消息中的格式指示
        -> memory_recall 自动注入：{writing_format: "markdown", language: "zh-CN", structure: "本周完成+下周计划"}
        -> 自动生成符合偏好的周报
```

### 10.3 路由追踪展示

演示时双屏展示：

```
左屏: Hermes 对话窗口
右屏: 路由追踪面板（route_tracer.html 实时刷新）
```

路由追踪面板通过轮询 `/v1/tool_history` API 展示路由决策链路：

```json
{
  "timestamp": "2026-07-12T15:30:00",
  "user_message": "找一下关于 GPU 算力的笔记",
  "route": "rag_search",
  "tool_rounds": 1,
  "latency_ms": 1800,
  "status": "task_complete"
}
```

颜色标记：绿(TASK_COMPLETE) / 黄(TASK_INCOMPLETE) / 红(错误)，帮助评委直观理解 Router 分发逻辑。

---

## 11. 里程碑计划

### Phase 1：核心框架搭建（第 1-2 周）

```
□ Fork MTClaw，建立 prometheus 仓库
□ 搭建 5 个 Subagent 的 functions.jsonl 工具定义（13 条）
□ 实现 wrapper 脚本骨架（13 个 .sh）
□ 实现 Python 引擎模块：
  ├── rag_engine.py (ingest + search + status)
  ├── memory_engine.py (remember + recall + set_reminder)
  ├── writing_engine.py (generate + polish + translate)
  ├── schedule_engine.py (create_event + query + create_task + list_tasks + complete_task)
  └── chat_engine.py (chat)
□ 配置 Hermes -> MTClaw 联通
□ 端到端验证：单轮对话 5 种领域路由
□ **路由准确率测试：50 条混合意图，输出实测数据**
```

### Phase 2：即时偏好引擎（第 3-4 周）

```
□ 实现 preference_engine.py（即时偏好检测 + 同步写入）
□ 实现 memory_injector（请求前自动注入记忆）
□ SQLite 数据模型建表 + 索引
□ ChromaDB Collection 初始化
□ 每日维护 cron 任务（记忆衰减/强化 + 交互统计）
□ 跨会话记忆验证
□ 提醒触发验证
□ **BGE-M3 嵌入延迟实测**
□ **RAG Top-5 召回率实测**
```

### Phase 3：演示准备（第 5-6 周）

```
□ 演示剧本排练（9 轮连续对话 + 进化演示）
□ 样本数据准备（笔记/数据/周报）
□ 写作模板创建（7 个）
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

> 实现任务追踪见 `docs/CHECKLIST.md`。本节是面向赛题评分维度的验收标准。

### 快（速度）

- [ ] 闲聊 Subagent 走路由模型直回，延迟 < 3s [目标]
- [ ] RAG 检索本地 ChromaDB，延迟 < 3s [目标]
- [ ] 记忆 Subagent 本地 SQLite 查询，延迟 < 1s [目标]
- [ ] 日程与任务 Subagent 查询延迟 < 500ms [目标]
- [ ] 路由决策本身延迟 < 1s [目标]
- [ ] Completion Check 命中率 > 70% [目标]
- [ ] MTClaw 参考加速比 4.99x~6.85x [推测，MTClaw 团队在系统控制垂域测试，非 Prometheus 实测]

### 准（准确率）

- [ ] 路由分发测试：50 条混合意图，分发准确率 > 90% [目标]
- [ ] RAG 检索：Top-5 召回率 > 85% [目标]
- [ ] 写作 Subagent：格式符合用户记忆偏好的概率 > 80% [目标]
- [ ] 记忆 Subagent：偏好召回准确率 > 85% [目标]
- [ ] 通用 Benchmark：智商不退化（全部走上游 LLM 兜底）[设计保证]

### 稳（可靠性）

- [ ] 未命中工具的通用请求 100% 透明转发上游 LLM [设计保证]
- [ ] 上游 LLM 响应不做任何改动（原样流式透传）[设计保证]
- [ ] 元数据清洗不影响请求语义 [设计保证]
- [ ] 路由模型超时/不可用时直接转发上游 LLM [设计保证]
- [ ] 端到端 120s 超时保护 [设计保证]

### 广（场景覆盖）

- [ ] 5 个 Subagent 覆盖 5+ 场景（办公/学习/日程/社交/开发）[设计保证]
- [ ] 每个 Subagent 至少 1 个可演示的完整任务 [设计保证]
- [ ] 至少 1 个 Subagent 包含多轮工具循环 [设计保证]
- [ ] 通用兜底覆盖所有不命中场景 [设计保证]

### 产品化完成度

- [ ] 一键安装脚本可用（`./install.sh`）[目标]
- [ ] 一键卸载脚本可用 [目标]
- [ ] 健康检查正常 [目标]
- [ ] 安装后立即可用的样本数据 [目标]
- [ ] 清晰的 README（含截图/录屏）[目标]
- [ ] 50 条路由准确率测试套件 [目标]

### 商业价值

- [ ] 明确的目标用户画像（知识工作者）[设计保证]
- [ ] 真实场景痛点（跨文档检索 + 长期记忆 + 主动提醒）[设计保证]
- [ ] 清晰的差异化定位（本地隐私 + 即时偏好 vs ChatGPT 无记忆）[设计保证]

### 加分项

- [ ] 路由准确率实测数据（50 条测试集，非编造）[目标]
- [ ] 即时偏好学习演示（演示中即时可见）[设计保证]
- [ ] 路由 fallback 安全网（路由故障永不无响应）[设计保证]

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
| `writing_humanize` | 写作 | 3 (text, intensity, preserve_formatting) | 是 | 否 |
| `schedule_create_event` | 日程与任务 | 6 (title, start_time, end_time, location, category, reminder_minutes) | 否 | 是 |
| `schedule_query` | 日程与任务 | 3 (time_range, category, status) | 否 | 否 |
| `schedule_create_task` | 日程与任务 | 5 (title, priority, due_date, tags, description) | 否 | 是 |
| `schedule_list_tasks` | 日程与任务 | 3 (status, priority, tags) | 否 | 否 |
| `schedule_complete_task` | 日程与任务 | 1 (task_id) | 否 | 是 |
| `chat_light` | 闲聊 | 2 (mood, memory_inject) | 否 | 否 |

**工具总数**：15（含 5 个 MTClaw builtin tools 则共 20 个）

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
| python-dateparser | 1.2 | 自然语言时间解析 |

## 附录 C：安全注意事项

1. **日程输入校验**：SQLite 参数化查询防止 SQL 注入，时间解析失败时返回友好错误
2. **文件访问控制**：RAG ingest 仅读取，不做任何写入或执行
3. **API Key 保护**：配置文件中的密钥使用 `${ENV_VAR}` 引用，不直接存储明文
4. **数据隐私**：所有数据存储于本地 `~/.prometheus/data/`，不上传云端
5. **脚本执行限制**：工具 wrapper 通过路径白名单校验，防止目录遍历
