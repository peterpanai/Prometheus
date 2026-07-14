# SQLite 数据模型设计调研报告

> **报告编号**：12  
> **项目**：Prometheus（普罗米修斯）— 基于 MTClaw Function Router 的自我进化型个人认知智能体  
> **日期**：2026-07-14  
> **状态**：调研完成  
> **数据来源**：`docs/spec.md` §5、`docs/design-proposal.md` §2.2/§2.4/§2.6、`docs/add/add-memory.md`、`docs/add/add-schedule.md`、`docs/add/add-router-learning.md`、`docs/add/add-rag.md`、`docs/CHECKLIST.md`、Hermes holographic memory store 参考实现

---

## 目录

1. [调研概述](#1-调研概述)
2. [数据库总体架构](#2-数据库总体架构)
3. [表结构设计](#3-表结构设计)
   - 3.1 [memories — 用户偏好与记忆](#31-memories--用户偏好与记忆)
   - 3.2 [reminders — 提醒](#32-reminders--提醒)
   - 3.3 [interaction_log — 交互日志](#33-interaction_log--交互日志)
   - 3.4 [events — 日程事件](#34-events--日程事件)
   - 3.5 [tasks — 待办任务](#35-tasks--待办任务)
   - 3.6 [辅助表（reflection_log / documents / Router 自学习表）](#36-辅助表reflection_log--documents--router-自学习表)
4. [索引设计](#4-索引设计)
5. [查询模式分析](#5-查询模式分析)
6. [与 ChromaDB 的数据同步](#6-与-chromadb-的数据同步)
7. [并发安全](#7-并发安全)
8. [备份策略](#8-备份策略)
9. [参考系统调研](#9-参考系统调研)
10. [问题与改进建议](#10-问题与改进建议)

---

## 1. 调研概述

### 1.1 调研目标

对 Prometheus 项目的 SQLite 数据模型进行全面调研，覆盖以下维度：

- 4 张核心表（memories / reminders / interaction_log / events + tasks）的表结构设计
- 索引设计与查询路径匹配度
- 主要查询模式（QPS 预估、读写比、查询类型）
- SQLite 与 ChromaDB 双存储的数据同步机制
- 并发安全（WAL 模式、连接管理、锁竞争）
- 备份策略与灾难恢复

### 1.2 数据库定位

Prometheus 使用 SQLite 作为**关系型元数据存储**，承担以下职责：

| 职责 | 表 | 说明 |
|------|------|------|
| 用户偏好持久化 | `memories` | 结构化存储 category/key/value/importance/access_count |
| 提醒管理 | `reminders` | 到期触发、重复模式 |
| 交互审计 | `interaction_log` | 每次工具调用的完整记录，供偏好引擎分析 |
| 反思记录 | `reflection_log` | 每日维护摘要 |
| 日程管理 | `events` | 日历事件，含提醒 |
| 待办管理 | `tasks` | 任务追踪，含子任务、优先级、标签 |
| 文档索引元数据 | `documents` | RAG 已索引文件的信息（ChromaDB 存向量） |
| Router 自学习 | `routing_decisions` 等 6 张表 | 路由决策记录、修正反馈、策略动态调整 |

### 1.3 存储路径

```
~/.prometheus/
├── data/
│   ├── prometheus.db          # 主 SQLite 数据库（memories/reminders/interaction_log/events/tasks）
│   ├── router_learning.db     # Router 自学习数据库（routing_decisions 等 6 张表）
│   ├── chroma/                # ChromaDB 持久化目录（documents + memories 两个 Collection）
│   └── reflections.json       # 反思历史（JSON 格式，与 reflection_log 表互补）
├── config/
│   ├── config.json
│   └── functions.jsonl
```

> **注意**：spec.md §5.3 将 Router 自学习数据放在 `~/.prometheus/router_learning.db`，与主库 `prometheus.db` 分离。分库的理由是 Router 自学习数据高频写入、可独立重置（`prometheus router reset`），与用户核心数据隔离。

---

## 2. 数据库总体架构

### 2.1 双存储模型

Prometheus 采用 **SQLite（结构化）+ ChromaDB（语义化）** 双存储模型：

```
                     ┌─────────────────────────────────────────────────┐
                     │              用户请求                              │
                     └────────────────────┬────────────────────────────┘
                                          │
                    ┌─────────────────────┴──────────────────────┐
                    │                                            │
                    ▼                                            ▼
           ┌──────────────┐                            ┌───────────────┐
           │   SQLite     │                            │   ChromaDB    │
           │ prometheus.db│                            │  (persist)    │
           ├──────────────┤                            ├───────────────┤
           │ memories     │◄──── 双向同步 ───────────►│ Collection:   │
           │ reminders    │     (memory_remember/      │  "memories"   │
           │ interaction_ │      memory_recall)        │  (BGE-M3      │
           │ log          │                            │   1024d 向量)  │
           │ events       │                            │               │
           │ tasks        │                            │ Collection:   │
           │ documents    │◄──── 单向同步 ───────────►│  "documents"  │
           │              │     (rag_ingest/           │  (BGE-M3      │
           │              │      rag_search)            │   1024d 向量)  │
           └──────────────┘                            └───────────────┘
```

**设计理由**：
- SQLite 擅长结构化查询（WHERE category='preference' AND importance >= 4），但不支持向量相似度搜索
- ChromaDB 擅长语义检索（余弦相似度 Top-K），但不适合复杂结构化过滤
- 两者互补：SQLite 管"是什么"（元数据），ChromaDB 管"像什么"（语义相似度）

### 2.2 数据库文件布局

| 数据库文件 | 表数量 | 用途 | 写入频率 |
|-----------|--------|------|---------|
| `prometheus.db` | 6 张（memories, reminders, interaction_log, reflection_log, events, tasks）+ documents（RAG 元数据） | 用户核心数据 | 中-高（每次对话至少 1 条 interaction_log） |
| `router_learning.db` | 6 张（routing_decisions, routing_corrections, routing_keyword_weights, routing_prompt_fragments, subagent_priority, routing_thresholds） | 路由自学习数据 | 高（每次路由决策 1 条 + 修正记录） |

---

## 3. 表结构设计

### 3.1 memories — 用户偏好与记忆

#### 3.1.1 完整表定义

```sql
CREATE TABLE memories (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    category        TEXT NOT NULL CHECK(category IN ('preference','identity','habit','note')),
    key             TEXT NOT NULL,
    value           TEXT NOT NULL,
    importance      INTEGER DEFAULT 3 CHECK(importance BETWEEN 1 AND 5),
    source_session  TEXT,
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now')),
    access_count    INTEGER DEFAULT 0,
    UNIQUE(category, key)
);
```

#### 3.1.2 字段说明

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | INTEGER | PK AUTOINCREMENT | 自增主键，同时作为 ChromaDB 中的 `mem_{id}` 标识 |
| `category` | TEXT | NOT NULL, CHECK IN 4 值 | 偏好类别：preference/identity/habit/note |
| `key` | TEXT | NOT NULL, UNIQUE(category, key) | 记忆键名（如 `writing_format`、`preferred_language`） |
| `value` | TEXT | NOT NULL | 记忆值（如 `markdown`、`zh-CN`） |
| `importance` | INTEGER | DEFAULT 3, CHECK 1-5 | 重要程度，1(最低)~5(最高)，影响召回优先级 |
| `source_session` | TEXT | 可空 | 记忆来源会话 ID，用于追溯 |
| `created_at` | TEXT | DEFAULT datetime('now') | 创建时间，ISO 8601 格式 |
| `updated_at` | TEXT | DEFAULT datetime('now') | 更新时间，UPSERT 时刷新 |
| `access_count` | INTEGER | DEFAULT 0 | 访问次数，用于热记忆追踪和衰减/强化 |

#### 3.1.3 设计要点

**UNIQUE(category, key) 联合唯一约束**：
- 同一类别下不允许重复 key，`memory_remember` 对相同 (category, key) 执行 UPSERT
- 这保证了偏好不会重复堆积（用户说 3 次"以后都用 Markdown"只存一条）
- UPSERT 实现方式：`INSERT INTO memories (...) VALUES (...) ON CONFLICT(category, key) DO UPDATE SET value=excluded.value, importance=excluded.importance, updated_at=datetime('now'), access_count=0`

**CHECK 约束**：
- `category` 仅允许 4 种值，防止脏数据
- `importance` 限制在 1-5 范围，防止偏好引擎衰减/强化逻辑越界

**access_count 的生命周期**：
- 写入（`remember`）：重置为 0
- 读取（`recall`）：+1（热记忆追踪）
- 衰减（每日维护）：access_count > 10 → importance +1（强化）；access_count = 0 且 30 天未更新 → importance -1（衰减）

**与 ChromaDB 的映射关系**：

| SQLite memories 表 | ChromaDB Collection "memories" |
|---------------------|--------------------------------|
| `id` = 42 | `id` = "mem_42" |
| `category` = "preference" | `metadata.category` = "preference" |
| `key` = "writing_format" | `document` = "writing_format: markdown" |
| `value` = "markdown" | （嵌入到 document 文本中） |
| `importance` = 4 | `metadata.importance` = 4 |
| — | `embedding` = BGE-M3("writing_format: markdown") [1024d] |

#### 3.1.4 时间字段设计

使用 `TEXT DEFAULT (datetime('now'))` 而非 `TIMESTAMP`，原因：
- SQLite 没有原生 DATETIME 类型，TEXT 存储的 ISO 8601 字符串可直接排序和比较
- `datetime('now')` 返回 UTC 时间 `YYYY-MM-DD HH:MM:SS` 格式
- spec.md §3.2 早期版本使用 `TIMESTAMP DEFAULT CURRENT_TIMESTAMP`，§5.1 正式版统一改为 `TEXT DEFAULT (datetime('now'))`

> **潜在问题**：`datetime('now')` 返回 UTC 时间，而 add-schedule.md 中 dateparser 设置 `TIMEZONE: Asia/Shanghai`。时间不一致可能导致跨时区比较出错。建议统一使用 UTC 存储，展示时转换。

---

### 3.2 reminders — 提醒

#### 3.2.1 完整表定义

```sql
CREATE TABLE reminders (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    content         TEXT NOT NULL,
    trigger_at      TEXT NOT NULL,
    repeat_pattern  TEXT DEFAULT 'once',
    active          INTEGER DEFAULT 1,
    triggered       INTEGER DEFAULT 0,
    created_at      TEXT DEFAULT (datetime('now'))
);
```

#### 3.2.2 字段说明

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | INTEGER | PK AUTOINCREMENT | 自增主键 |
| `content` | TEXT | NOT NULL | 提醒内容文本 |
| `trigger_at` | TEXT | NOT NULL | 触发时间，ISO 8601 格式（dateparser 解析自然语言后存入） |
| `repeat_pattern` | TEXT | DEFAULT 'once' | 重复模式：once/daily/weekly/monthly |
| `active` | INTEGER | DEFAULT 1 | 是否激活（1=活跃, 0=已停用），软删除标记 |
| `triggered` | INTEGER | DEFAULT 0 | 是否已触发（0=未触发, 1=已触发），用于一次性提醒 |
| `created_at` | TEXT | DEFAULT datetime('now') | 创建时间 |

#### 3.2.3 设计要点

**软删除 vs 硬删除**：
- `active` 字段实现软删除（设置为 0 而非 DELETE），保留历史记录供反思引擎分析
- 一次性提醒触发后 `triggered=1`，但记录不删除，便于审计

**重复提醒处理**：
- `repeat_pattern` 支持 once/daily/weekly/monthly 四种模式
- 重复提醒触发后需要更新 `trigger_at` 为下次触发时间（daily → +1天，weekly → +7天）
- 一次性提醒触发后设置 `triggered=1` 且 `active=0`

**查询模式**：
```sql
-- 查询到期提醒（核心查询）
SELECT * FROM reminders 
WHERE active = 1 AND triggered = 0 AND trigger_at <= datetime('now');

-- 重复提醒下次触发时间更新
UPDATE reminders SET trigger_at = datetime(trigger_at, '+1 day') 
WHERE id = ? AND repeat_pattern = 'daily';
```

#### 3.2.4 与 events 表的关系

`reminders` 和 `events` 都有提醒功能，但定位不同：

| 维度 | reminders | events |
|------|-----------|--------|
| 来源 | 用户通过 `memory_set_reminder` 直接创建 | 用户通过 `schedule_create_event` 创建日程 |
| 关联 | 独立的提醒 | 日程事件附带提醒（`reminder_minutes` 字段） |
| 数据模型 | content + trigger_at + repeat_pattern | title + start_time + end_time + location + category + ... |
| 触发后行为 | 更新 triggered/trigger_at | 更新 status |
| 协同 | events 到期时调用 `memory_engine.set_reminder()` 联动 | — |

> **潜在重复**：events 的 `reminder_minutes` 和 reminders 表功能有重叠。add-schedule.md §3.3 说明 events 到期时调用 `memory_engine.set_reminder()` 创建 reminders 记录，形成联动。但这也意味着一个日程提醒会在两张表中各存一份。

---

### 3.3 interaction_log — 交互日志

#### 3.3.1 完整表定义

```sql
CREATE TABLE interaction_log (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id              TEXT NOT NULL,
    user_message            TEXT,
    subagent                TEXT,
    tool_name               TEXT,
    tool_input              TEXT,
    tool_result             TEXT,
    latency_ms              REAL,
    route_decision          TEXT,
    completion_check_result TEXT,
    timestamp               TEXT DEFAULT (datetime('now'))
);
```

#### 3.3.2 字段说明

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | INTEGER | PK AUTOINCREMENT | 自增主键 |
| `session_id` | TEXT | NOT NULL | 会话 ID，用于跨会话分析和按会话分组查询 |
| `user_message` | TEXT | 可空 | 用户原始消息文本 |
| `subagent` | TEXT | 可空 | 命中的 Subagent 名称（rag/memory/writing/schedule/chat） |
| `tool_name` | TEXT | 可空 | 执行的工具名（如 `rag_search`、`memory_remember`） |
| `tool_input` | TEXT | 可空 | 工具输入参数（JSON 字符串） |
| `tool_result` | TEXT | 可空 | 工具输出结果（JSON 字符串） |
| `latency_ms` | REAL | 可空 | 工具执行延迟（毫秒） |
| `route_decision` | TEXT | 可空 | 路由决策信息（与 router_learning.db 的 routing_decisions 表关联） |
| `completion_check_result` | TEXT | 可空 | Completion Check 结果（TASK_COMPLETE / TASK_INCOMPLETE） |
| `timestamp` | TEXT | DEFAULT datetime('now') | 记录时间 |

#### 3.3.3 设计要点

**spec.md §3.2 vs §5.1 字段差异**：

spec.md 中 interaction_log 出现了两个版本：

| 字段 | §3.2（Subagent 规格） | §5.1（数据模型正式版） | 差异 |
|------|----------------------|---------------------|------|
| `tool_input` | 无 | 有 | §5.1 新增，记录工具输入参数 |
| `route_decision` | 无 | 有 | §5.1 新增，记录路由决策 |
| `completion_check_result` | 无 | 有 | §5.1 新增，记录 Completion Check 结果 |
| `timestamp` | `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | `TEXT DEFAULT (datetime('now'))` | 类型统一 |

以 §5.1 正式版为准。

**高写入频率表**：
- 每次用户对话、每次工具调用都会写入一条记录
- 预估写入频率：活跃使用时 10-50 条/小时
- 是写入量最大的表，需要关注数据膨胀

**数据生命周期**：
- 设计文档未明确定义清理策略
- 偏好引擎通过 `get_recent_interactions(limit=100)` 加载最近日志
- 建议：定期归档（如 90 天前的日志移至归档表或删除）

**无 CHECK 约束**：
- `subagent` 和 `tool_name` 字段没有枚举约束，允许任意值
- 优点：灵活，新增 Subagent 无需改 schema
- 缺点：可能存在拼写不一致的脏数据

#### 3.3.4 查询模式

```sql
-- 偏好引擎加载最近交互
SELECT * FROM interaction_log 
ORDER BY timestamp DESC LIMIT 100;

-- 按会话查询交互历史
SELECT * FROM interaction_log 
WHERE session_id = ? 
ORDER BY timestamp ASC;

-- 按 Subagent 统计调用频率（偏好引擎分析用）
SELECT subagent, COUNT(*) as freq, AVG(latency_ms) as avg_latency
FROM interaction_log 
WHERE timestamp >= datetime('now', '-7 days')
GROUP BY subagent;

-- 按 Subagent + 时间范围查询（索引覆盖）
SELECT * FROM interaction_log 
WHERE subagent = 'rag' AND timestamp >= datetime('now', '-1 day')
ORDER BY timestamp DESC;
```

---

### 3.4 events — 日程事件

#### 3.4.1 完整表定义

```sql
CREATE TABLE events (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    title            TEXT NOT NULL,
    description      TEXT,
    start_time       TEXT NOT NULL,          -- ISO 8601
    end_time         TEXT,                    -- 可选，全天事件为 NULL
    location         TEXT,
    category         TEXT DEFAULT 'general',  -- work/personal/study/meeting/other
    reminder_minutes INTEGER DEFAULT 15,      -- 提前提醒分钟数
    status           TEXT DEFAULT 'pending',  -- pending/completed/cancelled
    created_at       TEXT DEFAULT (datetime('now')),
    source           TEXT DEFAULT 'user'      -- user(用户创建)/system(系统推断)
);
```

#### 3.4.2 字段说明

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | INTEGER | PK AUTOINCREMENT | 自增主键 |
| `title` | TEXT | NOT NULL | 事件标题 |
| `description` | TEXT | 可空 | 事件描述 |
| `start_time` | TEXT | NOT NULL | 开始时间，ISO 8601 格式（dateparser 解析后存入） |
| `end_time` | TEXT | 可空 | 结束时间，全天事件为 NULL |
| `location` | TEXT | 可空 | 地点 |
| `category` | TEXT | DEFAULT 'general' | 分类：work/personal/study/meeting/other |
| `reminder_minutes` | INTEGER | DEFAULT 15 | 提前提醒分钟数 |
| `status` | TEXT | DEFAULT 'pending' | 状态：pending/completed/cancelled |
| `created_at` | TEXT | DEFAULT datetime('now') | 创建时间 |
| `source` | TEXT | DEFAULT 'user' | 来源：user(用户创建)/system(系统推断，如偏好引擎建议) |

#### 3.4.3 spec.md vs add-schedule.md 差异

两个文档对 events 表的字段定义略有不同：

| 字段 | spec.md §5.1 | add-schedule.md §3.1 | 建议采纳 |
|------|-------------|---------------------|---------|
| `category` 默认值 | 'general' | 'general' | 一致 |
| `category` 枚举 | work/personal/study/meeting/other | work/personal/health/social/other | spec.md 版本 |
| `status` 枚举 | pending/completed/cancelled | pending/confirmed/cancelled/completed | add-schedule.md 版本（含 confirmed） |
| `source` 默认值 | 'user' | 'manual' | spec.md 版本 |
| `source` 枚举 | user/system | manual/memory_import/voice | 需统一 |
| CHECK 约束 | 无 | 无 | 建议添加 |

> **建议**：统一 category 枚举为 `work/personal/study/meeting/other`，status 枚举为 `pending/confirmed/completed/cancelled`，source 枚举为 `user/system`。

#### 3.4.4 查询模式

```sql
-- 查询今日日程（核心查询，索引覆盖）
SELECT * FROM events 
WHERE start_time >= ? AND start_time <= ? 
  AND status != 'cancelled'
ORDER BY start_time ASC;

-- 查询本周日程
SELECT * FROM events 
WHERE start_time >= ? AND start_time <= ? 
  AND status = 'pending'
ORDER BY start_time ASC;

-- 按类别过滤
SELECT * FROM events 
WHERE category = 'meeting' AND start_time >= ?
ORDER BY start_time ASC;

-- 到期提醒检查
SELECT * FROM events 
WHERE status = 'pending' 
  AND reminder_minutes > 0
  AND datetime(start_time, '-' || reminder_minutes || ' minutes') <= datetime('now');
```

---

### 3.5 tasks — 待办任务

#### 3.5.1 完整表定义

```sql
CREATE TABLE tasks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    title           TEXT NOT NULL,
    description     TEXT,
    priority        INTEGER DEFAULT 3,       -- 1(低) ~ 5(紧急)
    status          TEXT DEFAULT 'pending',  -- pending/in_progress/completed/cancelled
    due_date        TEXT,                     -- ISO 8601, 可空
    tags            TEXT,                     -- 逗号分隔的标签
    parent_task_id  INTEGER,                  -- 支持子任务
    created_at      TEXT DEFAULT (datetime('now')),
    completed_at    TEXT,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);
```

#### 3.5.2 字段说明

| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `id` | INTEGER | PK AUTOINCREMENT | 自增主键 |
| `title` | TEXT | NOT NULL | 任务标题 |
| `description` | TEXT | 可空 | 任务描述 |
| `priority` | INTEGER | DEFAULT 3 | 优先级 1(低)~5(紧急) |
| `status` | TEXT | DEFAULT 'pending' | 状态：pending/in_progress/completed/cancelled |
| `due_date` | TEXT | 可空 | 截止日期，ISO 8601 |
| `tags` | TEXT | 可空 | 标签，逗号分隔（如 "urgent,backend"） |
| `parent_task_id` | INTEGER | FK → tasks(id) | 父任务 ID，支持子任务层级 |
| `created_at` | TEXT | DEFAULT datetime('now') | 创建时间 |
| `completed_at` | TEXT | 可空 | 完成时间 |

#### 3.5.3 设计要点

**子任务支持**：
- `parent_task_id` 外键引用自身（自引用外键），实现任务层级
- 查询子任务：`SELECT * FROM tasks WHERE parent_task_id = ?`
- SQLite 默认不强制外键约束，需要 `PRAGMA foreign_keys = ON;` 才会生效

**tags 存储方式**：
- 逗号分隔字符串存储，而非关联表
- 优点：简单，单表查询即可获取标签
- 缺点：标签过滤需要 `LIKE '%tag%'` 或字符串函数，效率低且可能误匹配
- add-schedule.md §4.2 提到 tags 参数类型为 `array`，但存储为逗号分隔字符串
- 过滤查询示例：`SELECT * FROM tasks WHERE tags LIKE '%urgent%'`

**priority 与 memories.importance 的区别**：
- `tasks.priority`：任务紧急程度（1-5），用户主观设定
- `memories.importance`：记忆重要程度（1-5），由系统根据 access_count 动态调整

#### 3.5.4 查询模式

```sql
-- 列出未完成任务（核心查询，索引覆盖）
SELECT * FROM tasks 
WHERE status != 'completed' 
ORDER BY priority DESC, due_date ASC;

-- 按优先级过滤
SELECT * FROM tasks 
WHERE status = 'pending' AND priority = ?
ORDER BY due_date ASC;

-- 按标签过滤（低效，LIKE 匹配）
SELECT * FROM tasks 
WHERE status = 'pending' AND tags LIKE ?
ORDER BY priority DESC;

-- 子任务查询
SELECT * FROM tasks WHERE parent_task_id = ?;

-- 完成任务
UPDATE tasks SET status = 'completed', completed_at = datetime('now') 
WHERE id = ?;
```

---

### 3.6 辅助表（reflection_log / documents / Router 自学习表）

#### 3.6.1 reflection_log — 反思记录

```sql
CREATE TABLE reflection_log (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    summary             TEXT NOT NULL,
    preferences_updated INTEGER DEFAULT 0,
    created_at          TEXT DEFAULT (datetime('now'))
);
```

- 每日凌晨 2:00 cron 任务执行后写入一条
- `summary` 为 Markdown 格式的反思摘要
- `preferences_updated` 记录本次维护中调整的偏好数量
- 与 `reflections.json` 文件互补（JSON 文件用于快速读取，表用于结构化查询）

#### 3.6.2 documents — RAG 文档元数据

```sql
CREATE TABLE documents (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    path         TEXT NOT NULL,
    file_type    TEXT,
    title        TEXT,
    chunk_count  INTEGER,
    ingested_at  TEXT DEFAULT (datetime('now')),
    size_bytes   INTEGER
);
```

- RAG Subagent 的元数据表，记录已索引文件信息
- ChromaDB 的 `documents` Collection 存储向量嵌入和文本片段
- 文件去重基于 SHA256 hash（add-rag.md §3.3），但 documents 表无 hash 字段，建议添加

#### 3.6.3 Router 自学习表（6 张表，独立数据库）

位于 `router_learning.db`，6 张表构成完整的路由自学习数据模型：

| 表名 | 用途 | 关键字段 |
|------|------|---------|
| `routing_decisions` | 所有路由决策记录 | session_id, user_input, input_features, top1_route, top1_confidence, top2_route, final_route, routing_layer |
| `routing_corrections` | 用户修正记录 | decision_id, original_route, corrected_route, correction_type |
| `routing_keyword_weights` | 关键词权重（动态） | keyword, subagent, weight, hit_count |
| `routing_prompt_fragments` | 提示词片段（动态） | pattern_hash, fragment_text, hit_count |
| `subagent_priority` | 优先级调整（动态） | subagent, base_priority, dynamic_adjustment |
| `routing_thresholds` | 置信度阈值（动态校准） | threshold_name, value, last_calibrated |

**分库理由**：
1. Router 自学习数据高频写入（每次路由决策），与用户核心数据物理隔离
2. `prometheus router reset` 可独立重置学习数据，不影响 memories/events/tasks
3. 独立备份/导出：`prometheus router export` 只导出学习数据

---

## 4. 索引设计

### 4.1 完整索引清单

#### prometheus.db

```sql
-- memories 表索引
CREATE INDEX idx_memories_category ON memories(category);
CREATE INDEX idx_memories_updated ON memories(updated_at);

-- reminders 表索引
CREATE INDEX idx_reminders_active ON reminders(active, trigger_at);

-- interaction_log 表索引
CREATE INDEX idx_interaction_session ON interaction_log(session_id, timestamp);
CREATE INDEX idx_interaction_subagent ON interaction_log(subagent, timestamp);

-- events 表索引
CREATE INDEX idx_events_start ON events(start_time);
CREATE INDEX idx_events_status ON events(status);

-- tasks 表索引
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_due ON tasks(due_date);
CREATE INDEX idx_tasks_priority ON tasks(priority);
```

#### router_learning.db

```sql
-- routing_decisions 索引
CREATE INDEX idx_rd_timestamp ON routing_decisions(timestamp);
CREATE INDEX idx_rd_session ON routing_decisions(session_id);

-- routing_corrections 索引
CREATE INDEX idx_rc_corrected_route ON routing_corrections(corrected_route);
```

### 4.2 索引分析

#### memories 表

| 索引 | 查询场景 | 评估 |
|------|---------|------|
| `idx_memories_category` | `WHERE category = 'preference'` | ✅ 合理，memory_recall 按 category 过滤是常见查询 |
| `idx_memories_updated` | `ORDER BY updated_at DESC`（衰减逻辑） | ✅ 合理，每日维护按 updated_at 排序 |
| — (UNIQUE(category, key)) | UPSERT 去重 | ✅ 联合唯一约束自动创建索引 |
| **缺失** | `WHERE importance >= 4` | ⚠️ recall 中有"高 importance 补充"查询，但无 importance 索引。数据量小（≤1000）可接受全表扫描 |

#### reminders 表

| 索引 | 查询场景 | 评估 |
|------|---------|------|
| `idx_reminders_active` (active, trigger_at) | `WHERE active = 1 AND triggered = 0 AND trigger_at <= now` | ✅ 复合索引合理，先按 active 过滤再按 trigger_at 范围扫描 |
| **缺失** | `triggered` 字段 | ⚠️ 查询包含 `triggered = 0` 条件，但索引未覆盖。可在复合索引中扩展为 (active, triggered, trigger_at) |

#### interaction_log 表

| 索引 | 查询场景 | 评估 |
|------|---------|------|
| `idx_interaction_session` (session_id, timestamp) | `WHERE session_id = ? ORDER BY timestamp` | ✅ 合理，按会话查询历史 |
| `idx_interaction_subagent` (subagent, timestamp) | `WHERE subagent = ? AND timestamp >= ?` | ✅ 合理，按 Subagent 统计分析 |
| **缺失** | `ORDER BY timestamp DESC LIMIT 100` | ⚠️ 偏好引擎的 `get_recent_interactions(limit=100)` 是全表倒序，无索引覆盖。数据量大时需要 `idx_interaction_timestamp` |

#### events 表

| 索引 | 查询场景 | 评估 |
|------|---------|------|
| `idx_events_start` (start_time) | `WHERE start_time BETWEEN ? AND ?` | ✅ 核心查询，按时间范围查日程 |
| `idx_events_status` (status) | `WHERE status = 'pending'` | ✅ 过滤已取消事件 |
| **缺失** | (status, start_time) 复合索引 | ⚠️ 常见查询 `WHERE status = 'pending' AND start_time BETWEEN ? AND ?`，两个单列索引需要索引合并或全表扫描 |

#### tasks 表

| 索引 | 查询场景 | 评估 |
|------|---------|------|
| `idx_tasks_status` (status) | `WHERE status != 'completed'` | ✅ 核心查询，过滤未完成任务 |
| `idx_tasks_due` (due_date) | `ORDER BY due_date ASC` | ✅ 按截止日期排序 |
| `idx_tasks_priority` (priority) | `WHERE priority = ?` 或 `ORDER BY priority DESC` | ✅ 按优先级过滤/排序 |
| **缺失** | (status, priority, due_date) 复合索引 | ⚠️ 核心查询 `WHERE status = 'pending' ORDER BY priority DESC, due_date ASC` 无完美覆盖 |

### 4.3 索引优化建议

1. **reminders 复合索引扩展**：`(active, triggered, trigger_at)` → 替代当前 `(active, trigger_at)`
2. **events 复合索引**：`(status, start_time)` → 覆盖最常见的日程查询
3. **tasks 复合索引**：`(status, priority, due_date)` → 覆盖待办列表排序
4. **interaction_log 时间索引**：`(timestamp)` → 覆盖 `get_recent_interactions` 的倒序查询
5. **documents 表索引**：`path` 字段添加唯一索引或普通索引，支持文件去重查询

> **注意**：Prometheus 是单用户本地应用，数据量有限（memories ≤ 1000，events/tasks 预估 < 10000，interaction_log 可能较大但可定期清理）。索引优化对性能影响有限，但好习惯应从设计阶段养成。

---

## 5. 查询模式分析

### 5.1 各表读写特性

| 表 | 读/写比 | 写入频率 | 典型查询 | 延迟目标 |
|------|--------|---------|---------|---------|
| memories | 10:1（读多写少） | 低（偏好声明时写入） | recall 语义检索 + importance 补充 | <1s [目标] |
| reminders | 100:1（极少写入） | 极低（用户设置提醒时） | 到期检查（轮询） | <100ms |
| interaction_log | 1:10（写多读少） | 高（每次对话写入） | 最近 N 条 + 统计分析 | <500ms |
| events | 5:1 | 低（创建日程时） | 时间范围查询 | <500ms [目标] |
| tasks | 3:1 | 低（创建任务时） | 状态过滤 + 排序 | <500ms |
| routing_decisions | 1:20（写多读少） | 高（每次路由写入） | 修正分析 + 统计 | <100ms |

### 5.2 核心查询路径

#### 路径 1：memory_recall（每次对话触发）

```
memory_recall(context) ->
  1. ChromaDB 语义检索 Top K（BGE-M3 向量化 → cosine 检索）
  2. SQLite 高 importance 补充：
     SELECT * FROM memories WHERE importance >= 4;
  3. 合并去重 → 按 importance DESC, similarity DESC 排序
  4. UPDATE memories SET access_count = access_count + 1 WHERE id IN (...);
```

涉及表：`memories`  
索引使用：`idx_memories_category`（可选 category 过滤）、UNIQUE(category, key)  
写操作：access_count 自增（每次 recall 都写入）

#### 路径 2：schedule_query（日程查询）

```
schedule_query(time_range='today') ->
  计算 today_start, today_end ->
  SELECT * FROM events 
  WHERE start_time >= today_start AND start_time <= today_end
    AND status != 'cancelled'
  ORDER BY start_time ASC;
```

涉及表：`events`  
索引使用：`idx_events_start`

#### 路径 3：偏好引擎每日维护

```
run_daily_maintenance() ->
  1. 全表扫描 memories：
     SELECT * FROM memories;
  2. 逐条判断：access_count > 10 → importance +1; access_count = 0 且 30 天未更新 → importance -1
  3. 批量 UPDATE
  4. 交互统计：
     SELECT subagent, COUNT(*) FROM interaction_log 
     WHERE timestamp >= datetime('now', '-1 day') GROUP BY subagent;
  5. 写入 reflection_log
```

涉及表：`memories`、`interaction_log`、`reflection_log`  
索引使用：`idx_memories_updated`、`idx_interaction_subagent`  
写操作：memories 批量 UPDATE、reflection_log INSERT

#### 路径 4：到期提醒检查（轮询）

```
get_due_reminders() ->
  SELECT * FROM reminders 
  WHERE active = 1 AND triggered = 0 AND trigger_at <= datetime('now');

get_due_events() ->
  SELECT * FROM events 
  WHERE status = 'pending' AND reminder_minutes > 0
    AND datetime(start_time, '-' || reminder_minutes || ' minutes') <= datetime('now');
```

涉及表：`reminders`、`events`  
索引使用：`idx_reminders_active`、`idx_events_start` + `idx_events_status`

### 5.3 事务边界

| 操作 | 事务范围 | 说明 |
|------|---------|------|
| `memory_remember` | SQLite UPSERT + ChromaDB upsert | 需要跨存储一致性（见 §6） |
| `memory_recall` | SQLite SELECT + access_count UPDATE | 读+写在同一事务中 |
| `create_event` | events INSERT + memories INSERT（协同） | 跨表事务 |
| `complete_task` | tasks UPDATE（单行） | 单语句事务 |
| `log_interaction` | interaction_log INSERT（单行） | 单语句事务 |
| 每日维护 | memories 批量 UPDATE + reflection_log INSERT | 建议单事务，保证原子性 |

---

## 6. 与 ChromaDB 的数据同步

### 6.1 同步架构

```
┌─────────────────────────────────────────────────────────┐
│                    memory_remember()                     │
│                                                          │
│  Step 1: SQLite UPSERT                                   │
│    INSERT INTO memories (...) VALUES (...)               │
│    ON CONFLICT(category, key) DO UPDATE SET ...          │
│    → 获取 memory_id                                      │
│                                                          │
│  Step 2: ChromaDB upsert (同步)                          │
│    collection.upsert(                                    │
│      ids=["mem_{memory_id}"],                            │
│      documents=["{key}: {value}"],                       │
│      embeddings=[BGE-M3("{key}: {value}")],              │
│      metadatas=[{category, importance}]                  │
│    )                                                     │
│                                                          │
│  Step 3: access_count 重置为 0                           │
│    (已在 Step 1 的 UPSERT 中完成)                        │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    memory_recall()                       │
│                                                          │
│  Step 1: ChromaDB 语义检索                               │
│    query_embedding = BGE-M3(context)                     │
│    results = collection.query(                           │
│      query_embeddings=[query_embedding],                 │
│      n_results=top_k                                     │
│    )                                                     │
│    → 返回 [{id, document, distance, metadata}]           │
│                                                          │
│  Step 2: SQLite 高 importance 补充                       │
│    SELECT * FROM memories WHERE importance >= 4           │
│    → 合并去重                                            │
│                                                          │
│  Step 3: access_count 自增                               │
│    UPDATE memories SET access_count = access_count + 1   │
│    WHERE id IN (matched_ids)                             │
│                                                          │
│  Step 4: 合并排序返回                                    │
│    按 importance DESC, similarity DESC 排序              │
└─────────────────────────────────────────────────────────┘
```

### 6.2 同步策略

| 操作 | SQLite | ChromaDB | 同步方式 | 一致性保证 |
|------|--------|----------|---------|-----------|
| `memory_remember` | UPSERT | upsert | 同步双写 | SQLite 先写，ChromaDB 后写；SQLite 成功后 ChromaDB 失败则记录不一致 |
| `memory_recall` | SELECT + UPDATE | query | 读双存储 | 语义检索走 ChromaDB，结构化补充走 SQLite |
| `memory_set_reminder` | INSERT | 不涉及 | 仅 SQLite | — |
| `rag_ingest` | INSERT (documents) | add (documents collection) | 同步双写 | 同上 |
| `rag_search` | 不涉及 | query | 仅 ChromaDB | — |
| 每日维护（衰减/强化） | UPDATE importance | update metadata | 同步更新 | 需同步更新 ChromaDB metadata 中的 importance |
| 清理（删除低 importance 记忆） | DELETE | delete | 同步双删 | — |

### 6.3 一致性挑战

#### 问题 1：双写不一致

SQLite 和 ChromaDB 是两个独立的存储系统，无法跨系统事务。如果 SQLite UPSERT 成功但 ChromaDB upsert 失败（如磁盘满、进程崩溃），会导致数据不一致。

**缓解方案**：
1. **先 SQLite 后 ChromaDB**：保证结构化数据不丢失，ChromaDB 可重建
2. **ChromaDB 可重建**：ChromaDB 的向量和文档可以从 SQLite 的 memories 表完全重建（`"{key}: {value}"` → BGE-M3 → 向量）
3. **定期一致性检查**：每日维护时比对 SQLite memories 和 ChromaDB memories Collection 的记录数，发现不一致时触发重建
4. **错误日志**：ChromaDB 操作失败时记录日志，不阻断 SQLite 写入

#### 问题 2：importance 更新同步

每日维护修改 SQLite 的 `importance` 字段后，需要同步更新 ChromaDB metadata 中的 `importance`。

**实现**：
```python
# 每日维护中，每条 importance 变化的记忆
for memory in changed_memories:
    chroma_collection.update(
        ids=[f"mem_{memory.id}"],
        metadatas=[{"category": memory.category, "importance": memory.importance}]
    )
```

#### 问题 3：删除同步

清理低 importance 记忆时，需要同时从 SQLite 和 ChromaDB 删除。

**实现**：
```python
# 清理逻辑
for memory in to_delete:
    sqlite_conn.execute("DELETE FROM memories WHERE id = ?", (memory.id,))
    chroma_collection.delete(ids=[f"mem_{memory.id}"])
```

### 6.4 ChromaDB Collection 设计

#### Collection: "memories"

```python
{
    "id": "mem_42",                    # 对应 SQLite memories.id
    "embedding": [0.12, -0.34, ...],   # BGE-M3 1024d
    "document": "writing_format: markdown",  # "{key}: {value}"
    "metadata": {
        "memory_id": 42,               # SQLite memories.id
        "category": "preference",
        "importance": 4
    }
}
```

#### Collection: "documents"（RAG）

```python
{
    "id": "doc_{file_hash}_{chunk_id}",
    "embedding": [0.12, -0.34, ...],   # BGE-M3 1024d
    "document": "原始文本片段",
    "metadata": {
        "source_path": "/path/to/file.md",
        "file_type": "md",
        "chunk_index": 0,
        "title": "提取的标题",
        "ingested_at": "2026-07-11T10:00:00"
    }
}
```

#### Collection: "documents_bm25"（稀疏检索）

add-rag.md §5 提到 RAG-002 "初始化 ChromaDB Collection `documents_bm25`（稀疏向量）"，用于 BM25 稀疏检索通道。与稠密检索结果通过 RRF 融合。

---

## 7. 并发安全

### 7.1 并发场景分析

Prometheus 在 MTT AIBOOK 上单进程运行，但存在以下并发来源：

| 并发来源 | 场景 | 争用程度 |
|---------|------|---------|
| MTClaw Function Router | 多个 Subagent 工具可能并行执行（FR 的 tool execution） | 中 |
| 每日维护 cron | 凌晨 2:00 执行维护脚本，与正在进行的对话并行 | 低（凌晨低峰期） |
| Python GIL | Python 的 GIL 限制了真正的多线程并行，但 SQLite 操作可能在不同线程 | 低 |
| 路由追踪面板 | route_tracer.html 轮询 `/v1/tool_history`，读操作 | 低（只读） |

### 7.2 SQLite 并发模型

#### WAL 模式（推荐）

```python
# 数据库初始化时启用 WAL
conn = sqlite3.connect(db_path, check_same_thread=False, timeout=10.0)
conn.execute("PRAGMA journal_mode = WAL")
conn.execute("PRAGMA synchronous = NORMAL")  # WAL 模式下的推荐设置
```

**WAL 模式优势**：
- **读写不互斥**：多个读操作可以同时进行，读操作不阻塞写操作
- **写入串行化**：多个写操作仍然串行执行，但通过 `busy_timeout` 等待而非直接报错
- **崩溃恢复**：WAL 文件提供更好的崩溃恢复能力

**Hermes 参考实现**（holographic store.py）：
- Hermes 的 MemoryStore 使用 `check_same_thread=False` 允许跨线程访问
- `isolation_level=None`（autocommit 模式）：每条语句是独立事务，避免悬挂事务
- 进程内共享连接 + RLock 串行化：所有实例共享一个连接和一个可重入锁
- WAL fallback：NFS/SMB/FUSE 挂载的目录可能不支持 WAL，需要 fallback 到 DELETE 模式

```python
# Hermes holographic store.py 的并发设计（参考）
class MemoryStore:
    _shared: dict = {}        # 进程级共享连接注册表
    _shared_guard = threading.Lock()

    def __init__(self, db_path):
        # 所有实例对同一 DB 文件共享一个连接 + 一个 RLock
        self._key = str(Path(db_path).resolve())
        with MemoryStore._shared_guard:
            entry = MemoryStore._shared.get(self._key)
            if entry is None:
                conn = sqlite3.connect(
                    self._key,
                    check_same_thread=False,
                    timeout=10.0,
                    isolation_level=None,  # autocommit
                )
                entry = {"conn": conn, "lock": threading.RLock(), "refs": 0}
                MemoryStore._shared[self._key] = entry
            entry["refs"] += 1
            self._conn = entry["conn"]
            self._lock = entry["lock"]
```

#### Prometheus 推荐并发策略

```python
# prometheus 数据库连接管理（建议参考 Hermes 实现）
import sqlite3
import threading
from pathlib import Path

class PrometheusDB:
    """进程级共享 SQLite 连接管理器"""
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, db_path=None):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._init(db_path)
        return cls._instance

    def _init(self, db_path):
        self.db_path = Path(db_path or "~/.prometheus/data/prometheus.db").expanduser()
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(
            str(self.db_path),
            check_same_thread=False,
            timeout=10.0,
            isolation_level=None,  # autocommit
        )
        self._conn.row_factory = sqlite3.Row
        self._conn_lock = threading.RLock()
        self._init_pragmas()
        self._init_schema()

    def _init_pragmas(self):
        self._conn.execute("PRAGMA journal_mode = WAL")
        self._conn.execute("PRAGMA synchronous = NORMAL")
        self._conn.execute("PRAGMA foreign_keys = ON")
        self._conn.execute("PRAGMA busy_timeout = 10000")  # 10s

    def execute(self, sql, params=()):
        with self._conn_lock:
            return self._conn.execute(sql, params)

    def executemany(self, sql, params):
        with self._conn_lock:
            return self._conn.executemany(sql, params)
```

### 7.3 关键并发配置

| PRAGMA | 推荐值 | 说明 |
|--------|--------|------|
| `journal_mode` | `WAL` | 读写不互斥，更好的并发性能 |
| `synchronous` | `NORMAL` | WAL 模式下 NORMAL 足够安全，性能优于 FULL |
| `foreign_keys` | `ON` | 启用外键约束（tasks.parent_task_id） |
| `busy_timeout` | `10000` (10s) | 写锁争用时等待 10s 而非立即报错 |
| `cache_size` | `-2000` (2MB) | 适当增大缓存，减少磁盘 I/O |

### 7.4 并发风险点

1. **MTClaw FR 多工具并行执行**：如果 FR 并行调用多个工具（如 memory_recall + schedule_query），多个线程同时写入 SQLite。需要确保连接管理器串行化写操作。

2. **每日维护与对话并发**：每日维护批量 UPDATE memories 时，如果用户同时触发 memory_recall，可能读到部分更新的数据。建议使用单事务执行维护，保证原子性。

3. **ChromaDB 并发**：ChromaDB 的 Python SDK 不是线程安全的。如果多线程同时调用 memory_remember，需要对 ChromaDB 客户端加锁。

4. **跨进程访问**：如果 Prometheus CLI（如 `prometheus router stats`）和 FR 服务同时访问数据库，WAL 模式支持多进程并发读，但写仍然串行。

### 7.5 WAL 模式兼容性

Hermes 的 `apply_wal_with_fallback` 函数处理了 WAL 模式在网络文件系统上的兼容性问题：

- **NFS/SMB/FUSE**：不支持 WAL 模式（ mmap 操作失败），需要 fallback 到 DELETE 模式
- **检测方式**：尝试 `PRAGMA journal_mode = WAL`，如果返回值不是 `wal` 则 fallback
- **MTT AIBOOK**：本地存储，大概率支持 WAL。但如果用户的 `~/.prometheus/data/` 挂载在网络文件系统上，需要 fallback

---

## 8. 备份策略

### 8.1 数据价值评估

| 数据 | 价值 | 重建难度 | 备份优先级 |
|------|------|---------|-----------|
| memories（用户偏好） | 高 — 用户长期积累的个性化数据 | 不可重建（需要用户重新声明） | **最高** |
| events/tasks | 高 — 用户日程和待办 | 不可重建 | **最高** |
| interaction_log | 中 — 偏好引擎分析数据 | 可从无重建（但丢失历史分析素材） | 中 |
| routing_decisions 等 | 中 — 路由学习数据 | 可通过重新使用重建（但需时间） | 中 |
| ChromaDB documents | 中 — 可从原始文件重新索引 | 可重建（需要原始文件 + 重新嵌入） | 低 |
| ChromaDB memories | 低 — 可从 SQLite 重建 | 可重建（需要重新嵌入） | 低 |

### 8.2 备份方案

#### 方案 1：SQLite Online Backup API（推荐）

```python
import sqlite3
import shutil
from datetime import datetime

def backup_prometheus_db():
    """使用 SQLite Online Backup API 进行热备份"""
    source = sqlite3.connect("~/.prometheus/data/prometheus.db")
    backup_path = f"~/.prometheus/backups/prometheus_{datetime.now().strftime('%Y%m%d_%H%M%S')}.db"
    dest = sqlite3.connect(backup_path)
    
    source.backup(dest)
    dest.close()
    source.close()
    
    # 清理旧备份（保留最近 7 天）
    cleanup_old_backups("~/.prometheus/backups/", days=7)
```

**优势**：
- 热备份：不需要停止服务，在备份期间数据库可正常读写
- 一致性快照：备份的是某个时间点的一致性快照
- SQLite 内置 API，跨平台可靠

#### 方案 2：VACUUM INTO（SQLite 3.27+）

```python
def backup_vacuum_into():
    """使用 VACUUM INTO 创建一致性副本"""
    conn = sqlite3.connect("~/.prometheus/data/prometheus.db")
    conn.execute(f"VACUUM INTO '~/.prometheus/backups/prometheus_{timestamp}.db'")
    conn.close()
```

**优势**：
- 自动整理碎片（VACUUM）
- 同样是一致性快照
- 单语句，更简洁

#### 方案 3：文件复制（简单但不推荐）

```bash
# 注意：直接复制 .db 文件可能得到不一致的快照
# 至少需要先 checkpoint WAL
sqlite3 ~/.prometheus/data/prometheus.db "PRAGMA wal_checkpoint(TRUNCATE);"
cp ~/.prometheus/data/prometheus.db ~/.prometheus/backups/prometheus_$(date +%Y%m%d).db
cp ~/.prometheus/data/prometheus.db-wal ~/.prometheus/backups/ 2>/dev/null || true
```

**风险**：复制时如果有写入操作，可能得到损坏的数据库文件。不推荐生产使用。

### 8.3 备份策略建议

#### 日常备份

```bash
# cron 任务：每日凌晨 3:00 备份（在偏好维护之后）
0 3 * * * python3 ~/.prometheus/scripts/backup_db.py

# backup_db.py 核心逻辑：
# 1. 备份 prometheus.db（SQLite Online Backup API）
# 2. 备份 router_learning.db（同上）
# 3. tar 压缩 ChromaDB 目录
# 4. 清理 7 天前的旧备份
# 5. 保留最近 4 个周备份 + 12 个月备份
```

#### 备份保留策略

| 备份类型 | 频率 | 保留数量 | 说明 |
|---------|------|---------|------|
| 日备份 | 每日 | 7 个 | 最近 7 天的每日备份 |
| 周备份 | 每周 | 4 个 | 每周日的备份 |
| 月备份 | 每月 | 12 个 | 每月 1 日的备份 |

#### 灾难恢复

```bash
# 恢复流程
1. 停止 Prometheus 服务
2. 备份当前损坏的数据库（用于后续分析）
3. 恢复最近的完好备份：
   cp ~/.prometheus/backups/prometheus_20260713.db ~/.prometheus/data/prometheus.db
4. 如果 ChromaDB 也损坏，从 SQLite 重建：
   python3 ~/.prometheus/scripts/rebuild_chroma.py
   # rebuild_chroma.py:
   #   1. 遍历 SQLite memories 表
   #   2. 对每条记录 BGE-M3 嵌入
   #   3. upsert 到 ChromaDB memories Collection
   #   4. 遍历 SQLite documents 表
   #   5. 重新读取原始文件、分段、嵌入
   #   6. upsert 到 ChromaDB documents Collection
5. 重启 Prometheus 服务
```

### 8.4 数据导出与迁移

add-router-learning.md §3.8 提到 `prometheus router export` 命令导出路由学习数据为 JSON，支持迁移到其他设备。建议同样为用户核心数据提供导出/导入功能：

```bash
prometheus export <path>     # 导出全部数据为 JSON
prometheus import <path>     # 从 JSON 导入（合并模式）
```

---

## 9. 参考系统调研

### 9.1 Hermes — holographic memory store

**文件**：`~/ws/hermes-agent/plugins/memory/holographic/store.py`

**借鉴点**：

| 特性 | Hermes 实现 | Prometheus 可借鉴 |
|------|-----------|-------------------|
| WAL 模式 | `apply_wal_with_fallback()` 处理 NFS 兼容性 | ✅ 需要同样的 fallback 机制 |
| 连接共享 | 进程级单连接 + RLock 串行化 | ✅ 参考实现 PrometheusDB 连接管理器 |
| autocommit | `isolation_level=None` 避免悬挂事务 | ✅ 采纳 |
| check_same_thread | `False` 允许跨线程 | ✅ 采纳 |
| FTS5 全文检索 | `CREATE VIRTUAL TABLE facts_fts USING fts5(content, ...)` | ⚠️ 可选：为 memories.value 添加 FTS5 |
| 触发器同步 | `AFTER INSERT/UPDATE/DELETE` 触发器维护 FTS 索引 | ⚠️ 可选 |
| trust_score | 类似 importance 的信任评分 + 衰减逻辑 | ✅ 已有 importance + access_count |
| retrieval_count | 类似 access_count | ✅ 已有 |
| schema 迁移 | `PRAGMA table_info` 检查列是否存在，动态 ALTER TABLE | ✅ 需要版本迁移机制 |

**Hermes 的教训**（store.py 注释）：
> "每个 MemoryStore 实例曾经各自打开连接，用各自的 RLock 保护。多个 provider 在同一进程中（主 agent + 每个 delegate_task subagent）作为独立的 WAL 写入者竞争。加上写操作出错时不回滚，一个连接可能留下未关闭的写事务，锁住写锁，导致所有其他连接的写操作在完整的 busy timeout 期间失败。"

**教训对 Prometheus 的启示**：
1. 全进程共享一个 SQLite 连接，不要每个 Subagent 引擎各自打开连接
2. 写操作出错时必须回滚（autocommit 模式下每条语句是独立事务，不会悬挂）
3. 使用 RLock 而非 Lock（允许同一线程内嵌套调用）

### 9.2 OpenClaw — memory host SDK

**文件**：`~/ws/openclaw/src/memory-host-sdk/`

**借鉴点**：
- query / dream / events / multimodal 四个接口，Prometheus 借鉴了 query（recall）和 dream（reflection）
- embedding providers 可插拔设计
- cron 系统的存储和服务分离设计

### 9.3 Codex — memories

**文件**：`~/ws/codex/codex-rs/memories/`

**借鉴点**：
- Multi-phase memory writing（phase1.rs / phase2.rs）with guard checks
- 记忆写入有防护检查，避免错误信息被写入
- Prometheus 的偏好引擎可借鉴：写入前验证 category/key/value 的有效性

---

## 10. 问题与改进建议

### 10.1 发现的问题

| 编号 | 严重度 | 问题 | 影响 | 涉及文档 |
|------|--------|------|------|---------|
| P-01 | 中 | events 表 category 枚举值在 spec.md 和 add-schedule.md 中不一致 | 开发时可能采用错误的枚举值 | spec.md §5.1 vs add-schedule.md §3.1 |
| P-02 | 中 | events 表 source 字段默认值和枚举值不一致（'user' vs 'manual'） | 同上 | spec.md §5.1 vs add-schedule.md §3.1 |
| P-03 | 低 | events 表 status 枚举值不一致（spec 无 confirmed，add-schedule 有） | 状态机不完整 | 同上 |
| P-04 | 低 | interaction_log 表在 spec.md §3.2 和 §5.1 中字段不同 | §5.1 正式版新增 3 个字段，但 §3.2 未同步更新 | spec.md |
| P-05 | 低 | reminders 表查询包含 `triggered = 0` 条件，但复合索引 `(active, trigger_at)` 未覆盖 | 到期检查查询可能需要额外过滤 | spec.md §5.1 |
| P-06 | 低 | tasks 表 tags 字段使用逗号分隔字符串存储，标签过滤需要 LIKE | 标签查询效率低，可能误匹配 | add-schedule.md §3.1 |
| P-07 | 低 | documents 表无 file_hash 字段 | add-rag.md §3.3 提到基于 SHA256 去重，但表结构无对应字段 | add-rag.md vs spec.md |
| P-08 | 低 | 时间字段使用 `datetime('now')` 返回 UTC，但 dateparser 设置 Asia/Shanghai 时区 | 跨时区比较可能出错 | spec.md §5.1, add-schedule.md §3.2 |
| P-09 | 低 | 未定义 interaction_log 的数据清理策略 | 长期运行后数据膨胀 | 全部文档 |
| P-10 | 低 | 未定义数据库 schema 版本管理和迁移机制 | 后续 schema 变更需要手动 ALTER TABLE | 全部文档 |
| P-11 | 低 | SQLite 和 ChromaDB 双写无事务保证，可能不一致 | 崩溃时数据不一致（可重建缓解） | add-memory.md §3.1 |
| P-12 | 低 | 未启用 `PRAGMA foreign_keys = ON`，tasks.parent_task_id 外键不生效 | 子任务引用不存在的父任务 | spec.md §5.1 |

### 10.2 改进建议

#### 建议 1：统一 events 表定义

```sql
CREATE TABLE events (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    title            TEXT NOT NULL,
    description      TEXT,
    start_time       TEXT NOT NULL,
    end_time         TEXT,
    location         TEXT,
    category         TEXT DEFAULT 'general' 
                     CHECK(category IN ('work','personal','study','meeting','other')),
    reminder_minutes INTEGER DEFAULT 15,
    status           TEXT DEFAULT 'pending'
                     CHECK(status IN ('pending','confirmed','completed','cancelled')),
    created_at       TEXT DEFAULT (datetime('now')),
    source           TEXT DEFAULT 'user'
                     CHECK(source IN ('user','system'))
);
```

#### 建议 2：添加 schema 版本管理

```sql
CREATE TABLE IF NOT EXISTS schema_version (
    version    INTEGER PRIMARY KEY,
    applied_at TEXT DEFAULT (datetime('now')),
    description TEXT
);

INSERT INTO schema_version (version, description) VALUES (1, 'Initial schema');
```

每次启动时检查版本，执行必要的迁移脚本。

#### 建议 3：添加 documents 表的 file_hash 字段

```sql
CREATE TABLE documents (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    path         TEXT NOT NULL,
    file_hash    TEXT,                    -- SHA256, 用于去重
    file_type    TEXT,
    title        TEXT,
    chunk_count  INTEGER,
    ingested_at  TEXT DEFAULT (datetime('now')),
    size_bytes   INTEGER,
    UNIQUE(path)
);

CREATE INDEX idx_documents_hash ON documents(file_hash);
```

#### 建议 4：interaction_log 定期归档

```python
# 每月维护任务
def archive_old_interactions():
    """将 90 天前的交互日志移至归档表"""
    conn.execute("""
        INSERT INTO interaction_log_archive 
        SELECT * FROM interaction_log 
        WHERE timestamp < datetime('now', '-90 days')
    """)
    conn.execute("""
        DELETE FROM interaction_log 
        WHERE timestamp < datetime('now', '-90 days')
    """)
```

#### 建议 5：考虑为 memories 添加 FTS5 全文检索

借鉴 Hermes holographic store 的设计，为 memories.value 添加 FTS5 虚拟表，支持中文全文搜索（作为 ChromaDB 语义检索的补充）：

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts
    USING fts5(category, key, value, content=memories, content_rowid=id);

CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
    INSERT INTO memories_fts(rowid, category, key, value)
        VALUES (new.id, new.category, new.key, new.value);
END;

CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, category, key, value)
        VALUES ('delete', old.id, old.category, old.key, old.value);
END;

CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
    INSERT INTO memories_fts(memories_fts, rowid, category, key, value)
        VALUES ('delete', old.id, old.category, old.key, old.value);
    INSERT INTO memories_fts(rowid, category, key, value)
        VALUES (new.id, new.category, new.key, new.value);
END;
```

> FTS5 的中文分词需要额外配置 tokenizer（如 `simple` 或 jieba 分词），否则中文搜索效果有限。可作为 v2.0 增强。

#### 建议 6：统一时区处理

```python
# 所有时间统一使用 UTC 存储，展示时转换
def store_time(dt_str: str) -> str:
    """将 dateparser 解析的时间转为 UTC ISO 8601 存储"""
    import dateparser
    from datetime import timezone
    dt = dateparser.parse(dt_str, settings={'TIMEZONE': 'Asia/Shanghai', 'RETURN_AS_TIMEZONE_AWARE': True})
    return dt.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')

def display_time(utc_str: str) -> str:
    """将 UTC 时间转为本地时间展示"""
    # 从 SQLite 读取后转换
    ...
```

---

## 附录 A：完整建表 SQL（整合建议后的版本）

```sql
-- ============================================
-- Prometheus 主数据库: prometheus.db
-- 版本: 1.0
-- 日期: 2026-07-14
-- ============================================

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA busy_timeout = 10000;

-- Schema 版本管理
CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER PRIMARY KEY,
    applied_at  TEXT DEFAULT (datetime('now')),
    description TEXT
);
INSERT INTO schema_version (version, description) VALUES (1, 'Initial schema');

-- 用户记忆
CREATE TABLE IF NOT EXISTS memories (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    category        TEXT NOT NULL CHECK(category IN ('preference','identity','habit','note')),
    key             TEXT NOT NULL,
    value           TEXT NOT NULL,
    importance      INTEGER DEFAULT 3 CHECK(importance BETWEEN 1 AND 5),
    source_session  TEXT,
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now')),
    access_count    INTEGER DEFAULT 0,
    UNIQUE(category, key)
);

-- 提醒
CREATE TABLE IF NOT EXISTS reminders (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    content         TEXT NOT NULL,
    trigger_at      TEXT NOT NULL,
    repeat_pattern  TEXT DEFAULT 'once' CHECK(repeat_pattern IN ('once','daily','weekly','monthly')),
    active          INTEGER DEFAULT 1 CHECK(active IN (0,1)),
    triggered       INTEGER DEFAULT 0 CHECK(triggered IN (0,1)),
    created_at      TEXT DEFAULT (datetime('now'))
);

-- 交互日志
CREATE TABLE IF NOT EXISTS interaction_log (
    id                      INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id              TEXT NOT NULL,
    user_message            TEXT,
    subagent                TEXT,
    tool_name               TEXT,
    tool_input              TEXT,
    tool_result             TEXT,
    latency_ms              REAL,
    route_decision          TEXT,
    completion_check_result TEXT,
    timestamp               TEXT DEFAULT (datetime('now'))
);

-- 交互日志归档表（90 天前的数据）
CREATE TABLE IF NOT EXISTS interaction_log_archive (
    id                      INTEGER PRIMARY KEY,
    session_id              TEXT NOT NULL,
    user_message            TEXT,
    subagent                TEXT,
    tool_name               TEXT,
    tool_input              TEXT,
    tool_result             TEXT,
    latency_ms              REAL,
    route_decision          TEXT,
    completion_check_result TEXT,
    timestamp               TEXT
);

-- 反思记录
CREATE TABLE IF NOT EXISTS reflection_log (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    summary             TEXT NOT NULL,
    preferences_updated INTEGER DEFAULT 0,
    created_at          TEXT DEFAULT (datetime('now'))
);

-- 日程事件
CREATE TABLE IF NOT EXISTS events (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    title            TEXT NOT NULL,
    description      TEXT,
    start_time       TEXT NOT NULL,
    end_time         TEXT,
    location         TEXT,
    category         TEXT DEFAULT 'general'
                     CHECK(category IN ('work','personal','study','meeting','other')),
    reminder_minutes INTEGER DEFAULT 15,
    status           TEXT DEFAULT 'pending'
                     CHECK(status IN ('pending','confirmed','completed','cancelled')),
    created_at       TEXT DEFAULT (datetime('now')),
    source           TEXT DEFAULT 'user'
                     CHECK(source IN ('user','system'))
);

-- 待办任务
CREATE TABLE IF NOT EXISTS tasks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    title           TEXT NOT NULL,
    description     TEXT,
    priority        INTEGER DEFAULT 3 CHECK(priority BETWEEN 1 AND 5),
    status          TEXT DEFAULT 'pending'
                    CHECK(status IN ('pending','in_progress','completed','cancelled')),
    due_date        TEXT,
    tags            TEXT,
    parent_task_id  INTEGER,
    created_at      TEXT DEFAULT (datetime('now')),
    completed_at    TEXT,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);

-- RAG 文档元数据
CREATE TABLE IF NOT EXISTS documents (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    path         TEXT NOT NULL UNIQUE,
    file_hash    TEXT,
    file_type    TEXT,
    title        TEXT,
    chunk_count  INTEGER,
    ingested_at  TEXT DEFAULT (datetime('now')),
    size_bytes   INTEGER
);

-- ============================================
-- 索引
-- ============================================

-- memories
CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(category);
CREATE INDEX IF NOT EXISTS idx_memories_updated ON memories(updated_at);
CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance);

-- reminders
CREATE INDEX IF NOT EXISTS idx_reminders_active ON reminders(active, triggered, trigger_at);

-- interaction_log
CREATE INDEX IF NOT EXISTS idx_interaction_session ON interaction_log(session_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_interaction_subagent ON interaction_log(subagent, timestamp);
CREATE INDEX IF NOT EXISTS idx_interaction_timestamp ON interaction_log(timestamp);

-- events
CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE INDEX IF NOT EXISTS idx_events_status_start ON events(status, start_time);

-- tasks
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tasks_due ON tasks(due_date);
CREATE INDEX IF NOT EXISTS idx_tasks_priority ON tasks(priority);
CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_task_id);

-- documents
CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents(file_hash);
```

---

## 附录 B：Router 自学习数据库建表 SQL

```sql
-- ============================================
-- Router 自学习数据库: router_learning.db
-- 版本: 1.0
-- ============================================

PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 10000;

-- 路由决策记录
CREATE TABLE IF NOT EXISTS routing_decisions (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp         TEXT DEFAULT (datetime('now')),
    session_id        TEXT NOT NULL,
    user_input        TEXT NOT NULL,
    input_features    TEXT,          -- JSON
    top1_route        TEXT,
    top1_confidence   REAL,
    top2_route        TEXT,
    top2_confidence   REAL,
    final_route       TEXT,
    routing_layer     TEXT,          -- L1_auto / L1_low_confidence / L2_confirm
    correction_type   TEXT           -- L2_confirm / L1_correct / user_initiated / none
);

-- 用户修正记录
CREATE TABLE IF NOT EXISTS routing_corrections (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    decision_id         INTEGER,
    timestamp           TEXT DEFAULT (datetime('now')),
    original_route      TEXT NOT NULL,
    corrected_route     TEXT NOT NULL,
    correction_type     TEXT NOT NULL,
    applied_adjustments TEXT,         -- JSON
    FOREIGN KEY (decision_id) REFERENCES routing_decisions(id)
);

-- 关键词权重（动态）
CREATE TABLE IF NOT EXISTS routing_keyword_weights (
    keyword      TEXT NOT NULL,
    subagent     TEXT NOT NULL,
    weight       REAL DEFAULT 1.0,
    hit_count    INTEGER DEFAULT 0,
    last_updated TEXT DEFAULT (datetime('now')),
    PRIMARY KEY (keyword, subagent)
);

-- 提示词片段（动态）
CREATE TABLE IF NOT EXISTS routing_prompt_fragments (
    pattern_hash  TEXT PRIMARY KEY,
    fragment_text TEXT NOT NULL,
    hit_count     INTEGER DEFAULT 0,
    created_at    TEXT DEFAULT (datetime('now')),
    last_used     TEXT DEFAULT (datetime('now'))
);

-- Subagent 优先级（动态）
CREATE TABLE IF NOT EXISTS subagent_priority (
    subagent            TEXT PRIMARY KEY,
    base_priority       INTEGER NOT NULL,
    dynamic_adjustment  INTEGER DEFAULT 0,
    last_updated        TEXT DEFAULT (datetime('now'))
);

-- 置信度阈值（动态校准）
CREATE TABLE IF NOT EXISTS routing_thresholds (
    threshold_name   TEXT PRIMARY KEY,
    value            REAL NOT NULL,
    last_calibrated  TEXT DEFAULT (datetime('now')),
    calibration_reason TEXT
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_rd_timestamp ON routing_decisions(timestamp);
CREATE INDEX IF NOT EXISTS idx_rd_session ON routing_decisions(session_id);
CREATE INDEX IF NOT EXISTS idx_rc_corrected_route ON routing_corrections(corrected_route);
```

---

## 附录 C：ChromaDB 同步伪代码

```python
"""
memory_engine.py — SQLite + ChromaDB 双存储同步实现
"""

import sqlite3
import chromadb
from sentence_transformers import SentenceTransformer

class MemoryEngine:
    def __init__(self, db_path, chroma_path, embedding_model="BAAI/bge-m3"):
        # SQLite 连接（单例，WAL 模式，autocommit）
        self.conn = sqlite3.connect(db_path, check_same_thread=False, 
                                     timeout=10.0, isolation_level=None)
        self.conn.execute("PRAGMA journal_mode = WAL")
        self.conn.execute("PRAGMA foreign_keys = ON")
        
        # ChromaDB 客户端
        self.chroma = chromadb.PersistentClient(path=chroma_path)
        self.memories_collection = self.chroma.get_or_create_collection("memories")
        
        # 嵌入模型
        self.embedder = SentenceTransformer(embedding_model)
        
        # 线程锁（保护 ChromaDB 操作）
        import threading
        self._lock = threading.RLock()

    def remember(self, category, key, value, importance=3, source_session=None):
        """写入记忆：SQLite UPSERT + ChromaDB upsert（同步双写）"""
        with self._lock:
            # Step 1: SQLite UPSERT
            cursor = self.conn.execute("""
                INSERT INTO memories (category, key, value, importance, source_session)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(category, key) DO UPDATE SET
                    value = excluded.value,
                    importance = excluded.importance,
                    updated_at = datetime('now'),
                    access_count = 0
            """, (category, key, value, importance, source_session))
            memory_id = cursor.lastrowid
            
            # Step 2: ChromaDB upsert
            doc_text = f"{key}: {value}"
            embedding = self.embedder.encode(doc_text).tolist()
            self.memories_collection.upsert(
                ids=[f"mem_{memory_id}"],
                embeddings=[embedding],
                documents=[doc_text],
                metadatas=[{"memory_id": memory_id, "category": category, 
                            "importance": importance}]
            )
            # 注：ChromaDB 失败不回滚 SQLite（可从 SQLite 重建 ChromaDB）
            
            return {"id": memory_id, "category": category, "key": key, "value": value}

    def recall(self, context, top_k=5, category=None):
        """检索记忆：ChromaDB 语义检索 + SQLite 高 importance 补充"""
        with self._lock:
            # Step 1: ChromaDB 语义检索
            query_embedding = self.embedder.encode(context).tolist()
            where_filter = {"category": category} if category else None
            chroma_results = self.memories_collection.query(
                query_embeddings=[query_embedding],
                n_results=top_k,
                where=where_filter
            )
            
            # Step 2: SQLite 高 importance 补充
            sql = "SELECT id, category, key, value, importance FROM memories WHERE importance >= 4"
            if category:
                sql += " AND category = ?"
                high_imp = self.conn.execute(sql, (category,)).fetchall()
            else:
                high_imp = self.conn.execute(sql).fetchall()
            
            # Step 3: 合并去重
            seen_ids = set()
            results = []
            # 先加入 ChromaDB 结果（有相似度分数）
            for i, doc_id in enumerate(chroma_results["ids"][0]):
                mem_id = int(doc_id.replace("mem_", ""))
                if mem_id not in seen_ids:
                    seen_ids.add(mem_id)
                    results.append({
                        "id": mem_id,
                        "category": chroma_results["metadatas"][0][i]["category"],
                        "document": chroma_results["documents"][0][i],
                        "importance": chroma_results["metadatas"][0][i]["importance"],
                        "similarity": 1 - chroma_results["distances"][0][i]
                    })
            # 再加入高 importance 补充
            for row in high_imp:
                if row[0] not in seen_ids:
                    seen_ids.add(row[0])
                    results.append({
                        "id": row[0], "category": row[1], "key": row[2],
                        "value": row[3], "importance": row[4], "similarity": 0.0
                    })
            
            # Step 4: 排序（importance DESC, similarity DESC）
            results.sort(key=lambda x: (x["importance"], x["similarity"]), reverse=True)
            
            # Step 5: access_count 自增
            if seen_ids:
                placeholders = ",".join("?" * len(seen_ids))
                self.conn.execute(
                    f"UPDATE memories SET access_count = access_count + 1 WHERE id IN ({placeholders})",
                    tuple(seen_ids)
                )
            
            return results[:top_k]

    def rebuild_chroma(self):
        """从 SQLite 重建 ChromaDB memories Collection"""
        with self._lock:
            self.chroma.delete_collection("memories")
            self.memories_collection = self.chroma.get_or_create_collection("memories")
            
            rows = self.conn.execute(
                "SELECT id, category, key, value, importance FROM memories"
            ).fetchall()
            
            batch_size = 100
            for i in range(0, len(rows), batch_size):
                batch = rows[i:i+batch_size]
                ids = [f"mem_{r[0]}" for r in batch]
                docs = [f"{r[2]}: {r[3]}" for r in batch]
                embeddings = self.embedder.encode(docs).tolist()
                metadatas = [{"memory_id": r[0], "category": r[1], "importance": r[4]} 
                             for r in batch]
                self.memories_collection.upsert(
                    ids=ids, embeddings=embeddings, 
                    documents=docs, metadatas=metadatas
                )
```

---

## 附录 D：数据流总览图

```
┌─────────────────────────────────────────────────────────────────────┐
│                         用户交互                                      │
│                    "以后都用 Markdown 写周报"                          │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    MTClaw Function Router                             │
│  ┌──────────────┐  ┌──────────────────┐  ┌────────────────────┐    │
│  │ 即时偏好检测   │  │ memory_recall    │  │ 路由模型判断        │    │
│  │ (规则匹配)    │  │ (注入用户画像)    │  │ → memory_remember  │    │
│  └──────┬───────┘  └────────┬─────────┘  └─────────┬──────────┘    │
└─────────┼───────────────────┼──────────────────────┼────────────────┘
          │                   │                      │
          ▼                   ▼                      ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐
│ memory_remember │  │ memory_recall   │  │ interaction_log         │
│  (写入偏好)      │  │  (读取记忆)      │  │  (记录交互)              │
└────────┬────────┘  └────────┬────────┘  └───────────┬─────────────┘
         │                    │                       │
    ┌────┴────┐          ┌────┴────┐                  │
    ▼         ▼          ▼         ▼                  │
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐           │
│ SQLite │ │ChromaDB│ │ SQLite │ │ChromaDB│           │
│memories│ │memories│ │memories│ │memories│           │
│ UPSERT │ │ upsert │ │SELECT  │ │ query  │           │
│  +ACC=0│ │        │ │+ACC+1  │ │        │           │
└────────┘ └────────┘ └────────┘ └────────┘           │
                                                         │
                               ┌─────────────────────────┘
                               ▼
                    ┌─────────────────────┐
                    │  interaction_log    │
                    │  INSERT (每次对话)   │
                    └─────────────────────┘
                               │
                    ┌──────────┴──────────┐
                    │  每日维护 (cron 2:00) │
                    │  · 记忆衰减/强化      │
                    │  · 交互统计           │
                    │  · reflection_log    │
                    └─────────────────────┘
```

---

*报告结束*
