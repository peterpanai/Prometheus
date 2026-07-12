# 普罗米修斯（Prometheus）设计方案

> 基于 MTClaw Function Router 的自我进化型个人认知智能体  
> 版本：v3.0 | 日期：2026-07-12 | 目标：HICOOL 智能体赛道

---

## 目录

1. [总体设计理念](#1-总体设计理念)
2. [功能详细设计](#2-功能详细设计)
   - 2.1 [RAG 知识库 Subagent](#21-rag-知识库-subagent)
   - 2.2 [记忆与偏好 Subagent](#22-记忆与偏好-subagent)
   - 2.3 [写作润色翻译 Subagent](#23-写作润色翻译-subagent)
   - 2.4 [日程与任务 Subagent](#24-日程与任务-subagent)
   - 2.5 [闲聊陪伴 Subagent](#25-闲聊陪伴-subagent)
   - 2.6 [即时偏好引擎](#26-即时偏好引擎)
   - 2.7 [Subagent 协同机制](#27-subagent-协同机制)
3. [快：速度优势](#3-快速度优势)
4. [准：准确率优势](#4-准准确率优势)
5. [稳：可靠性优势](#5-稳可靠性优势)
6. [广：场景覆盖优势](#6-广场景覆盖优势)
7. [产品化完成度](#7-产品化完成度)
8. [商业价值](#8-商业价值)
9. [加分项](#9-加分项)
10. [评分维度对照矩阵](#10-评分维度对照矩阵)

---

## 1. 总体设计理念

### 1.1 一句话核心

**"Function Router 分而治之 + 即时偏好学习 + 本地隐私优先"**

普罗米修斯不试图用一个巨型 Prompt 解决所有问题，而是通过 MTClaw Function Router 将用户意图精准分发到 5 个专职 Subagent，每个 Subagent 精雕细琢自己的领域；同时通过即时偏好引擎，让 AI 在使用过程中实时学习用户习惯，实现"越用越懂你"。

### 1.2 三条设计原则

| 原则 | 含义 | 反模式规避 |
|------|------|-----------|
| **分治原则** | 一个 Subagent 只做一件事，做到极致 | 避免巨型 Prompt 导致延迟高、幻觉多 |
| **诚实原则** | 所有性能数字必须有实测来源，不编造 | 避免推测数字被评委追问翻车 |
| **演示优先** | 每个功能必须在演示中可跑通 | 避免做了一堆功能但演示翻车 |

### 1.3 v3.0 重大变更说明

相比 v2.0，本次修订的核心变更：

| 变更 | 原因 | 影响 |
|------|------|------|
| Subagent 从 8 个缩减到 5 个，再调整为 5 个（砍 Bash 换日程与任务） | 砍掉 WebFetch/WebSearch/DataAnalysis（上游 LLM 兜底覆盖）；砍掉 Bash（赛题不面向开发者，MTClaw builtin 已覆盖文件操作）；新增日程与任务（赛题推荐方向，面向知识工作者） | 工具数从 24 降到 15，路由准确率提升 |
| 砍掉插件系统 | 比赛不需要，直接写死配置 | 省 1 周开发时间 |
| 砍掉知识图谱 | 小数据量上无实际价值 | 省 3-5 天 |
| 砍掉模型 fallback 链 | 比赛环境不会挂 | 省 2 天 |
| 砍掉上下文压缩器 | MTClaw 已有 fr_context_history | 省 2-3 天 |
| 砍掉多搜索后端 fallback | DuckDuckGo 够用 | 省 2 天 |
| 反思引擎改为即时偏好引擎 | 演示中能即时展示"进化"效果 | 演示可跑通 |
| 所有性能数字标注来源 | 诚实化，区分"实测"和"目标" | 应对评委追问 |
| 工具数控制在 15 个以内 | LLM function calling 在 <15 工具时准确率最高 | 路由更准 |
| **加回轻量路由追踪面板** | **赛题加分项明确要求"可视化路由追踪"** | **单 HTML 文件 + 轮询 API，1 天开发量** |
| **商业价值扩写为 8 个子节** | **对齐赛题"生态和商业价值"6 个子维度** | **真实场景/产品化/商业模式/生态适配/可复用/示范带动** |
| **加分项对齐赛题原文** | **赛题明确列出 3 个加分项** | **Router 自学习 + 可视化路由追踪 + 开箱即用** |
| **评分矩阵对齐赛题维度** | **赛题原文评分维度** | **快/准/狠/生态商业价值/加分项** |

### 1.4 架构总览

```
用户输入
  │
  ▼
Hermes Agent ──► MTClaw Function Router (:18790)
                    │
                    ├── 元数据清洗（移除 Hermes sender block 等）
                    ├── 即时偏好注入（memory_recall 自动注入用户画像）
                    ├── 路由模型判断（5 个 Subagent 工具定义，temperature=0.0）
                    │
                    ├─ rag_*         -> RAG 知识库     (本地 ChromaDB，1-3s)
                    ├─ memory_*      -> 记忆与偏好     (SQLite + ChromaDB，<1s)
                    ├─ writing_*     -> 写作润色翻译   (上游 LLM，10-40s)
                    ├─ schedule_*    -> 日程与任务     (本地 SQLite，<1s)
                    ├─ chat_light    -> 闲聊陪伴       (路由模型直回，1-3s)
                    └─ 未命中        -> 上游 LLM 兜底  (15-40s)
                    │
                    ▼
              Completion Check
              ├─ TASK_COMPLETE    -> 直接返回（快路径）
              └─ TASK_INCOMPLETE  -> 转发上游 LLM（慢路径）

即时偏好引擎（前台，同步）:
  用户说"以后都用 Markdown" -> 实时写入 memory -> 下次请求自动注入
  不依赖后台 cron，演示中即时可见
```

### 1.5 调研基础

本设计基于对三个主流 AI Agent 代码库的深入调研：

| 代码库 | 路径 | 核心参考点 |
|--------|------|-----------|
| **Hermes** | `~/ws/hermes-agent` | 插件系统（plugin.yaml + register）、terminal_tool 多后端、delegate_task 子代理、web_search 7 provider 注册表 |
| **OpenClaw** | `~/ws/openclaw` | Plugin SDK（definePluginEntry + registerTool）、SSRF 防护 + readability 提取、memory host SDK（query/dream/events）、工具可用性模型（ToolAvailabilitySignal） |
| **Codex** | `~/ws/codex` | ToolRouter + ToolRegistry 分发、Orchestrator（审批+沙箱+重试分离）、multi_agents V2（spawn/send/wait 原语）、Extension API（tool_contributors） |

### 1.6 数据诚实化声明

本方案中的性能数据分为三类：

| 标记 | 含义 | 可信度 |
|------|------|--------|
| **[实测]** | Prometheus 自身有实际测试数据支撑 | 高 |
| **[目标]** | 设计目标值，尚未实测 | 中 |
| **[推测]** | 基于架构推断或引用第三方测试的估计值 | 低 |

**注意**：当前方案中所有数据均为 [目标] 或 [推测]。MTClaw 团队的测试数据标注为 [推测]，因为那是 MTClaw 在系统控制场景的测试，非 Prometheus 实测。Prometheus 自身的实测数据将在方案验证阶段产出。

---

## 2. 功能详细设计

### 2.1 RAG 知识库 Subagent

#### 2.1.1 功能定位

将用户的本地文档（.md / .pdf / .txt / .docx / .csv）索引到向量数据库，支持自然语言语义检索。数据全程不出设备。

#### 2.1.2 核心设计

**嵌入模型**：BAAI/bge-m3
- 维度：1024d
- 多语言（中英文均优秀），支持稠密 + 稀疏混合表征
- MTEB 检索基准排名靠前，HuggingFace 下载量 > 1000 万

**分段策略**：

| 文件类型 | 分段方法 | chunk_size | overlap |
|---------|---------|-----------|---------|
| .md | 按 `##` 标题分段，子段按空行切分 | 512 tokens (~350 中文字) | 64 tokens |
| .pdf | pdfplumber 提取文本 -> 按连续段落分段 | 512 tokens | 64 tokens |
| .txt | 按空行 + 字符数上限截断 | 512 tokens | 64 tokens |
| .docx | python-docx 按段落分段，合并短段 | 512 tokens | 64 tokens |
| .csv | 每行一个 chunk，列名作为元数据 | 1 row | 0 |

**混合检索架构**：

```
用户查询 "GPU 算力对比"
  │
  ├── 稠密检索通道
  │     query -> BGE-M3 向量化 (1024d) -> ChromaDB cosine 检索 -> Top K₁
  │
  ├── 稀疏检索通道
  │     query -> BM25 分词 -> ChromaDB 稀疏向量检索 -> Top K₂
  │
  ├── RRF 融合排序 (Reciprocal Rank Fusion)
  │     score(doc) = Σ 1/(k + rank_i(doc))   // k=60
  │     -> 合并去重，重排序 -> Top K
  │
  └── 返回 {matches: [{source, content, score}]}
```

**去重机制**：摄入时计算文件 SHA256 hash，跳过已索引且未修改的文件。

#### 2.1.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `rag_search` | query, top_k=5, source_filter | 语义搜索本地文档 |
| `rag_ingest` | path, recursive=true | 导入文件/目录到知识库 |
| `rag_status` | - | 查询知识库状态 |

#### 2.1.4 接入方式

```
rag_ingest.sh 执行流程：
  stdin ← FR 传入 {"path": "/data/notes", "recursive": true}
  -> python3 rag_engine.py ingest --path /data/notes --recursive
  -> stdout -> FR 接收 {"status": "ingested", "files": 12, "chunks": 156}
```

MTClaw FR 通过 `--functions-file` 加载 rag 的 3 个工具定义，通过 `--scripts-dir` 找到 `rag_search.sh` 等脚本。FR 调用 `rag_search` 工具时，相当于 `echo '{"query":"..."}' | bash rag_search.sh`。

#### 2.1.5 实现 Checklist

- [ ] 初始化 ChromaDB Collection `documents`（1024d, cosine 距离）
- [ ] 实现 5 种文件格式的分段器
- [ ] 实现 BGE-M3 嵌入生成（sentence-transformers, device=cpu）
- [ ] 实现稠密 + BM25 混合检索 + RRF 融合
- [ ] 实现文件去重（SHA256 hash）
- [ ] 实现 source_filter 过滤（按文件类型/目录）
- [ ] 编写 rag_search.sh / rag_ingest.sh / rag_status.sh
- [ ] **测试：BGE-M3 在目标硬件（MTT AIBOOK）上的嵌入延迟** [目标: <200ms/条]
- [ ] **测试：Top-5 召回率** [目标: >85%]

---

### 2.2 记忆与偏好 Subagent

#### 2.2.1 功能定位

记住用户偏好、身份、习惯和重要信息，跨会话持久化。**即时偏好引擎**在用户声明偏好时实时写入，无需等待后台任务。下次对话自动注入偏好上下文。

#### 2.2.2 核心设计

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
```

**查询流程**:

```
memory_recall(context) ->
  1. ChromaDB 语义检索 (context 向量化 -> 相似度 Top K)
  2. SQLite 结构化补充 (importance >= 4 的记忆，无论相似度)
  3. 合并去重 -> 按 importance DESC, similarity DESC 排序
  4. 返回 [{category, key, value, importance, similarity}]
```

#### 2.2.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `memory_remember` | category, key, value, importance=3 | 记录偏好/习惯/身份/笔记 |
| `memory_recall` | context, top_k=5, category | 语义检索相关记忆 |
| `memory_set_reminder` | content, time, repeat=once | 设置提醒 |

#### 2.2.4 记忆生命周期

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

衰减 (即时偏好引擎每日触发)
  │
  ├── access_count > 10 -> importance 提升 1（热记忆强化）
  ├── access_count = 0 且 30 天未更新 -> importance 降低 1（冷记忆衰减）
  └── importance < 2 的 note 类记忆 -> 标记为可清理

清理 (手动/阈值触发)
  └── 总记忆数 > MAX_MEMORIES (1000) -> 移除最低 importance 的记忆
```

#### 2.2.5 实现 Checklist

- [ ] 创建 SQLite 表 memories / reminders / interaction_log + 索引
- [ ] 初始化 ChromaDB Collection `memories`
- [ ] 实现 memory_remember（SQLite UPSERT + ChromaDB 同步写入）
- [ ] 实现 memory_recall（语义检索 + 高 importance 补充 + 合并排序）
- [ ] 实现 memory_set_reminder（dateparser 解析自然语言时间）
- [ ] 实现 interaction_log 记录（每次工具调用后自动记录）
- [ ] 实现记忆衰减/强化逻辑（基于 access_count）
- [ ] 实现即时偏好注入（请求前自动注入上下文）
- [ ] **测试：偏好召回准确率** [目标: >85%]

---

### 2.3 写作润色翻译 Subagent

#### 2.3.1 功能定位

场景化文档生成（周报/邮件/技术文档/会议纪要/文章/PPT大纲）、文本润色、多语言翻译。核心智能依赖上游 LLM，FR 的价值在于自动注入用户偏好记忆和参数标准化。

#### 2.3.2 核心设计

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
  │     memory_recall(context="writing weekly_report") ->
  │       { writing_format: "markdown",
  │         preferred_language: "zh-CN",
  │         structure: "本周完成 + 下周计划 + 风险与问题",
  │         tone: "professional" }
  │
  ├── Step 2: 模板加载
  │     读取 templates/weekly_report.md -> 获取三段式结构引导
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
  │     httpx -> POST upstream_url/v1/chat/completions
  │
  └── Step 5: 返回
        {document: "## 本周完成\n...", format: "markdown"}
```

**参数枚举标准化**：所有参数使用 enum 约束，避免 LLM 歧义：
- `doc_type`：7 种枚举值
- `style`：4 种枚举值（formal / casual / technical / academic）
- `length`：3 种枚举值（short / medium / long）
- `goal`（润色）：5 种枚举值

**去AI化改写机制**（`writing_humanize`）：

```
writing_humanize(text, intensity="medium", preserve_formatting=true)
  │
  ├── Step 1: AI 痕迹识别
  │     检测以下 AI 写作特征:
  │     ├── 过度对称的句式结构（"不仅...而且..." / "既...又..."）
  │     ├── 套话和空泛表达（"在当今时代" / "随着...的发展"）
  │     ├── 逻辑连接词堆砌（"首先...其次...最后..."）
  │     ├── 过度礼貌和平衡表达（"虽然...但是..." 万能句式）
  │     ├── 机械式总分总结构
  │     └── 标点使用模式（过度使用破折号、分号）
  │
  ├── Step 2: Prompt 构造
  │     system_prompt = f"""
  │       你是一个文本改写专家。将以下文本改写为更像人类写作的风格。
  │       要求:
  │       1. 打破对称句式，使用长短不一的句子
  │       2. 删除空泛套话，保留具体信息
  │       3. 减少逻辑连接词，让行文更自然
  │       4. 适当加入口语化表达
  │       5. 保留原文的核心观点和事实
  │       强度: {intensity}  # light(轻度) / medium(中度) / heavy(重度)
  │     """
  │
  ├── Step 3: 调用上游 LLM
  │
  └── Step 4: 返回
        {humanized: "改写后的文本", changes_summary: "移除了3处套话，打破了2处对称句式"}

intensity 级别:
  light  - 仅去除明显套话，保留原文风格
  medium - 重写句式结构，提升自然度
  heavy  - 全面改写，保留核心信息但完全改变表达方式
```

#### 2.3.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `writing_generate` | doc_type, topic, key_points, style, length | 生成各类文档 |
| `writing_polish` | text, goal, target_language | 润色已有文本 |
| `writing_translate` | text, source_lang, target_lang, keep_formatting | 翻译文本 |
| `writing_humanize` | text, intensity, preserve_formatting | 去AI化改写 |

#### 2.3.4 实现 Checklist

- [ ] 创建 7 个文档模板
- [ ] 实现 writing_engine.py（generate / polish / translate）
- [ ] 实现偏好注入（import memory_engine.recall）
- [ ] 实现上游 LLM 调用（httpx -> OpenAI-compatible API）
- [ ] 实现错误降级（上游不可用时返回友好错误）
- [ ] 实现 writing_humanize（AI痕迹识别 + 三级强度改写）
- [ ] **测试：格式符合偏好概率** [目标: >80%]
- [ ] **测试：去AI化后文本通过AI检测器的概率** [目标: >70%]

---

### 2.4 日程与任务 Subagent

#### 2.4.1 功能定位

本地日程管理与任务追踪。用户通过自然语言创建日程、查询今日待办、管理任务状态。数据全程本地 SQLite，不上传云端。赛题推荐方向"日程与任务--串联本地日历、待办、提醒"。

#### 2.4.2 核心设计

**数据模型**：

```sql
-- 日程事件
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    start_time TEXT NOT NULL,          -- ISO 8601
    end_time TEXT,                     -- 可选，全天事件为 NULL
    location TEXT,
    category TEXT DEFAULT 'general',   -- work/personal/study/meeting/other
    reminder_minutes INTEGER DEFAULT 15, -- 提前提醒分钟数
    status TEXT DEFAULT 'pending',     -- pending/completed/cancelled
    created_at TEXT DEFAULT (datetime('now')),
    source TEXT DEFAULT 'user'         -- user(用户创建)/system(系统推断)
);

-- 任务（待办事项）
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    priority INTEGER DEFAULT 3,        -- 1(低) ~ 5(紧急)
    status TEXT DEFAULT 'pending',     -- pending/in_progress/completed
    due_date TEXT,                     -- 截止日期
    tags TEXT,                         -- 逗号分隔的标签
    parent_task_id INTEGER,            -- 支持子任务
    created_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);

-- 索引
CREATE INDEX idx_events_start ON events(start_time);
CREATE INDEX idx_events_status ON events(status);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_due ON tasks(due_date);
CREATE INDEX idx_tasks_priority ON tasks(priority);
```

**自然语言时间解析**：

```
用户: "明天下午3点开产品评审会"
  -> dateparser 解析 "明天下午3点" -> 2026-07-13T15:00:00
  -> 创建 event(title="产品评审会", start_time=..., category="meeting")

用户: "下周一之前完成 HICOOL 提案"
  -> dateparser 解析 "下周一" -> 2026-07-14
  -> 创建 task(title="完成 HICOOL 提案", due_date=..., priority=4)
```

**日程视图**：

```
用户: "今天有什么安排"
  -> 查询 events WHERE start_time BETWEEN today_start AND today_end
  -> 按时间排序返回

用户: "这周还有哪些任务没完成"
  -> 查询 tasks WHERE status != 'completed' AND due_date <= this_week_end
  -> 按优先级 + 截止日期排序
```

**与记忆 Subagent 协同**：

```
即时偏好引擎检测到时间规律:
  "连续 3 个周五 16:00 写周报"
  -> 建议创建重复日程: 每周五 16:00 写周报
  -> 用户确认 -> schedule_create_event(title="写周报", repeat="weekly")
```

#### 2.4.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `schedule_create_event` | title, start_time, end_time, location, category, reminder_minutes | 创建日程事件 |
| `schedule_query` | time_range, category, status | 查询日程（今天/本周/指定日期） |
| `schedule_create_task` | title, priority, due_date, tags, description | 创建任务（待办） |
| `schedule_list_tasks` | status, priority, tags | 查询任务列表 |
| `schedule_complete_task` | task_id | 标记任务完成 |

#### 2.4.4 接入方式

```
schedule_create_event.sh 执行流程：
  stdin ← FR 传入 {
    "title": "产品评审会",
    "start_time": "明天下午3点",
    "category": "meeting"
  }
  -> python3 schedule_engine.py create_event --stdin
    ├── dateparser 解析自然语言时间 -> ISO 8601
    ├── 写入 SQLite events 表
    └── 输出 stdout
  -> FR 接收 {"status": "created", "event_id": 42, "start_time": "2026-07-13T15:00:00"}
```

#### 2.4.5 实现 Checklist

- [ ] 创建 SQLite events / tasks 表 + 索引
- [ ] 实现 dateparser 自然语言时间解析（支持"明天"/"下周一"/"下午3点"/"3小时后"等）
- [ ] 实现 schedule_create_event（含重复日程支持：daily/weekly/monthly）
- [ ] 实现 schedule_query（今日/本周/指定日期范围/按类别过滤）
- [ ] 实现 schedule_create_task（含子任务、优先级、标签）
- [ ] 实现 schedule_list_tasks（按状态/优先级/截止日期排序）
- [ ] 实现 schedule_complete_task
- [ ] 实现到期提醒检查（与 memory_set_reminder 协同）
- [ ] **测试：自然语言时间解析准确率** [目标: >90%]
- [ ] **测试：日程查询延迟** [目标: <500ms]

---

### 2.5 闲聊陪伴 Subagent

#### 2.5.1 功能定位

轻量级直回闲聊，利用路由模型的小参数、低延迟特性，零工具调用，不经过上游 LLM。延迟从 15-40s 降至 1-2s。

#### 2.5.2 核心设计

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

**误判保护（保守策略）**：

```
v3.0 关键变更：宁可假阴性（走上游 LLM），不可假阳性（走 chat_light）

complex 类消息绝对禁止路由到 chat_light：
  - 包含 "为什么" + 专业术语 -> 需要上游 LLM
  - 包含 "怎么做" + 技术动词 -> 需要上游 LLM
  - 包含比较/分析类连接词（"对比" / "区别" / "优缺点"） -> 需要上游 LLM
  - 消息长度 > 200 字 -> 需要上游 LLM
  - 包含任何文件扩展名 -> 需要上游 LLM
  - 包含任何编程/技术关键词（代码/函数/变量/编译/部署等）-> 需要上游 LLM
  - 任何不确定的情况 -> 走上游 LLM（兜底永远安全）
```

**对话风格映射**（mood 参数）：

| mood | 路由模型提示词策略 | 适用场景 |
|------|-----------------|---------|
| casual | 自然日常对话，语气轻松 | 默认/日常寒暄 |
| humor | 优先讲笑话/段子/趣事，风趣幽默 | 用户请求娱乐 |
| comfort | 共情倾听，温暖安慰 | 用户表达负面情绪 |
| curious | 拓展话题，提出有趣问题 | 用户表现出好奇心 |
| auto | 从用户消息中自动判断情感基调 | 默认 |

#### 2.5.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `chat_light` | mood=auto, memory_inject=true | 轻量闲聊直回 |

#### 2.5.4 实现 Checklist

- [ ] 实现 5 条闲聊意图识别规则
- [ ] 实现 complex 消息误判保护（保守策略）
- [ ] 实现 mood 自动检测（基于关键词 + 情感词典）
- [ ] 实现路由模型直回 prompt 构造（含 mood 策略 + 用户画像）
- [ ] **测试：闲聊延迟** [目标: <3s]
- [ ] **测试：complex 消息不误路由到 chat_light**（50 条测试集，0 误判）
- [ ] **测试：连续 10 轮闲聊不走上游 LLM**

---

### 2.6 即时偏好引擎

#### 2.6.1 功能定位

v3.0 核心变更：将 v2.0 的"后台反思引擎"改为"即时偏好引擎"。用户声明偏好时实时写入 memory，不依赖后台 cron 任务。这确保在演示中能即时展示"越用越懂你"的效果。

#### 2.6.2 触发机制

| 触发方式 | 频率 | 处理内容 | 实现 |
|---------|------|---------|------|
| **即时触发** | 用户说"以后都"/"记住了"/"我喜欢"时 | 偏好声明检测 -> 同步写入 memory | 规则匹配 + memory_remember |
| 定时任务 | 每日凌晨 2:00 | 记忆衰减/强化 + 交互统计 | cron + Python 脚本 |
| 手动触发 | 用户主动要求 | "帮我总结一下最近的使用情况" | memory_recall + 统计 |

#### 2.6.3 即时偏好检测（v1）

```python
def detect_and_store_preference(user_message: str) -> dict | None:
    """检测用户消息中的偏好声明，实时写入 memory。

    匹配模式: "以后都" / "我喜欢" / "不要" / "偏好" / "总是" / "记住了"
    例: "以后都用 Markdown 格式" -> {key: "writing_format", value: "markdown"}
    """
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

#### 2.6.4 定时任务（v1，轻量版）

每日凌晨 2:00 执行，仅做：

```python
def run_daily_maintenance():
    # 1. 记忆衰减/强化
    for memory in get_all_memories():
        if memory.access_count > 10:
            memory.importance = min(5, memory.importance + 1)
        if memory.access_count == 0 and memory.days_since_update > 30:
            memory.importance = max(1, memory.importance - 1)

    # 2. 交互统计（写入 reflection_log）
    stats = compute_interaction_stats()
    save_reflection_log(stats)
```

#### 2.6.5 演示效果

```
[演示 - 第 1 轮]
  用户: "帮我写周报，用 Markdown，中文，包含本周完成和下周计划"
  系统: 按详细要求生成（15s）
  同时: 即时偏好引擎检测到 "用 Markdown" + "中文" -> 写入 memory

[演示 - 第 2 轮，同一会话或新会话]
  用户: "写周报"
  系统: memory_recall 自动注入 ->
        {writing_format: "markdown", language: "zh-CN",
         structure: "本周完成 + 下周计划"}
        -> 自动生成符合偏好的周报（12s）
  用户零额外输入 -> 展示 "越用越懂你" 的核心价值
```

#### 2.6.6 实现 Checklist

- [ ] 实现 `detect_and_store_preference()` - 即时偏好检测 + 同步写入
- [ ] 实现 `compute_interaction_stats()` - Subagent 频次/关键词/日均交互数统计
- [ ] 实现记忆衰减/强化逻辑（access_count + 时间规则）
- [ ] 实现即时偏好注入（请求前自动注入）
- [ ] 实现 cron 定时维护任务（轻量版）
- [ ] **测试：跨会话偏好注入** [目标: 第 2 轮自动注入率 >90%]

---

### 2.7 Subagent 协同机制

#### 2.7.1 协同模式

单个用户请求可触发多个 Subagent 协同工作：

```
用户: "把 sample_data 目录导入知识库，然后找一下关于 GPU 算力的笔记"

  FR 调用 rag_ingest("/data/sample_notes")
    -> RAG Subagent 索引 3 篇文档

  FR 调用 rag_search("GPU 算力")
    -> RAG Subagent 语义检索，返回 2 篇相关笔记

  FR 调用 memory_remember("note", "gpu_research", "已整理 GPU 算力笔记")
    -> 记忆 Subagent 记录操作

单一请求 -> 3 个工具调用 -> 2 轮 -> 端到端完成任务
```

#### 2.7.2 FR 多轮工具调用机制

MTClaw 的 `max_tool_rounds=6` 参数决定了单次请求最多可以执行多少轮工具调用。FR 在每轮工具调用后评估 Completion Check：

- `TASK_COMPLETE` -> 停止调用，返回最终结果
- `TASK_INCOMPLETE` -> 继续下一轮工具调用，或转发上游 LLM

#### 2.7.3 关键约束

- 同一请求内多次工具调用共享 session 上下文
- 前序工具的输出自动注入到后续工具的上下文中
- 每个工具调用独立记录到 interaction_log（供偏好引擎使用）

---

## 3. 快：速度优势

### 3.1 分层延迟策略

不是所有请求都需要走过上游大模型。普罗米修斯根据任务类型分三层响应：

| 层级 | Subagent | 典型延迟 [推测] | 技术手段 | 占比预估 [推测] |
|------|----------|---------|---------|---------|
| **L1 即时** | 记忆、闲聊 | < 1-3s | 路由模型直回 / 本地 SQLite | ~25% |
| **L2 快速** | RAG、日程与任务 | 1-5s | 本地向量库 / SQLite | ~35% |
| **L3 标准** | 写作 | 10-40s | 上游 LLM（核心智能依赖） | ~25% |
| **兜底** | 通用推理 | 15-40s | 上游 LLM 全量推理 | ~15% |

**注意**：上述延迟和占比为 [推测] 值，基于 MTClaw 在系统控制领域的实测数据外推。实际数字需在目标硬件上实测验证。

### 3.2 MTClaw 参考数据（MTClaw 团队测试，非 Prometheus 实测）

在 50 个系统控制任务上，每个任务重复 4 次的评测 [推测，MTClaw 团队测试，非 Prometheus 实测]：

| 模式 | Pass@1 | 平均耗时 | 加速比 |
|------|--------|----------|--------|
| Baseline（纯上游 LLM） | 99.0% | 37.97s | 1.00x |
| Permissive | 95.5% | 5.54s | **6.85x** |
| Strict | **100.0%** | 7.61s | **4.99x** |

- Strict 模式：工具召回率 100%，工具准确率 94.8% [推测，MTClaw 团队测试]
- Permissive 模式：工具召回率 100%，工具准确率 97.5% [推测，MTClaw 团队测试]

**重要说明**：上述数据在 7 个系统控制工具的场景下测得。Prometheus 使用 5 个 Subagent / 15 个工具，场景复杂度更高，实际加速比预计会降低。[推测]

### 3.3 闲聊 Subagent 的秒级响应

```
传统路径：用户 "讲个笑话" -> 上游 LLM (doubao/gpt-4o) -> 响应 = 15-30s [推测]
Prometheus：用户 "讲个笑话" -> 路由模型 (qwen3-30b) -> 直回 = 1-3s [推测]

延迟降低 [推测]，对日常寒暄场景体感丝滑
```

### 3.4 Completion Check 快路径

```
TASK_COMPLETE   -> 直接返回（快路径）[目标: 命中率 >70%]
TASK_INCOMPLETE -> 转发上游 LLM 补充（慢路径）

注意：v3.0 将命中率目标从 80% 下调为 70%，更务实。
实际命中率需在目标场景实测。
```

### 3.5 量化对比

| 场景 | ChatGPT 类 [推测] | Prometheus [推测] | 说明 |
|------|-----------|------------|------|
| 文档检索 | 无法检索本地文件 | 1-3s (ChromaDB 混合检索) | 延迟待实测 |
| 偏好记忆 | 每次重新告知 | < 1s (SQLite + 自动注入) | 延迟待实测 |
| 闲聊寒暄 | 15-30s (GPT-4o) | 1-3s (路由模型直回) | 延迟待实测 |
| 日程管理 | 无本地日程 | < 1s (SQLite 本地查询) | 延迟待实测 |

**注意**：以上对比中 Prometheus 的延迟均为 [推测] 值，将在方案验证阶段实测后更新。

---

## 4. 准：准确率优势

### 4.1 Function Router 精准分发

```
路由准确率保证：
  1. temperature = 0.0（确定性 function calling，零随机性）
  2. 5 个 Subagent 描述高度特化（工具描述互不重叠）
  3. 双重意图匹配：触发关键词 + 正则模式
  4. 优先级排序：记忆(P1) > 写作(P2) > 日程(P3) > RAG(P4) > 闲聊(P5) > 兜底(P6)
  5. 防误判保护：complex 消息禁止路由到 chat_light

目标：50 条混合意图的自动分发准确率 > 90% [目标]
注意：v3.0 将目标从 95% 下调为 90%，更务实。
```

**v3.0 关键改进**：工具数从 24 降到 15，回到 LLM function calling 准确率的最佳范围内（研究表明 <15 工具时准确率最高 [推测]）。

### 4.2 记忆注入提升个性化准确率

```
写作 Subagent 收到 "帮我写周报"
  │
  ├── 自动调用 memory_recall("writing weekly_report") ->
  │     { writing_format: "markdown",
  │       language: "zh-CN",
  │       structure: "本周完成 + 下周计划 + 风险与问题" }
  │
  └── 构造 prompt 时自动注入偏好 -> 生成符合用户习惯的周报

无记忆注入：LLM 生成通用格式，用户每次需手动调整
有记忆注入：格式符合用户习惯的概率 > 80% [目标]
```

### 4.3 RAG 混合检索提升召回率

```
稠密检索 (BGE-M3 语义匹配, 1024d)
        +
稀疏检索 (BM25 关键词匹配)
        ↓
RRF 融合排序 (k=60, 互补语义和字面两个维度)
        ↓
Top-5 召回率 > 85% [目标]
```

**注意**：v3.0 将目标从 90% 下调为 85%，更务实。纯向量检索在专业术语、缩写等场景失效；混合检索互补覆盖。

### 4.4 上游 LLM 兜底保证智商

```
未命中任何 Subagent -> 100% 透明转发上游 LLM
  ├── prompt 不做任何改写
  ├── 响应不做任何截断
  └── 原样流式透传

性能增益 = Subagent 命中率 × 各 Subagent 的定制优化
智商兜底 = 100% 的上游 LLM 能力（零衰减）
```

### 4.5 路由 fallback 策略

```
v3.0 新增：路由模型超时/失败时的安全降级

路由模型不可用或超时 (routing_timeout_s=10s)
  │
  └── 直接转发上游 LLM（跳过工具路由）
      -> 确保用户请求不会因为路由模型故障而无响应
```

---

## 5. 稳：可靠性优势

### 5.1 透明兜底

```
用户消息
  │
  ├── 5 个 Subagent 都不命中 -> 100% 转发上游 LLM
  ├── Subagent 命中但执行失败 -> 降级到上游 LLM（错误信息作为上下文注入）
  ├── 路由模型超时/不可用 -> 直接转发上游 LLM
  └── 元数据清洗 -> 仅移除 Hermes 注入的元数据块，不影响语义

最差情况：系统退化为直接使用上游 LLM
```

### 5.2 插件级故障隔离

```
每个 Subagent = 独立 Python 子进程
  ├── stdin/stdout JSON 通信（无共享内存）
  ├── 一个插件崩溃 -> FR 收到非零 exit code -> 降级处理
  ├── 其他插件不受影响（RAG 崩溃不影响日程、写作）
  └── 独立启停
```

### 5.3 四层安全防护

| Subagent | 安全机制 | 防护目标 |
|----------|---------|---------|
| 日程 | SQLite 参数化查询 + 输入校验 | 防止 SQL 注入 |
| RAG | 文件读取权限检查 + 路径校验 | 防止越权访问 |
| 写作 | 上游 LLM 输出过滤 | 防止不当内容 |
| 记忆 | SQLite 参数化查询 | 防止 SQL 注入 |

### 5.4 数据本地化

```
全部数据存储于 ~/.prometheus/data/
  ├── SQLite (用户记忆、交互日志)        ← 不上传
  ├── ChromaDB (文档向量、记忆向量)       ← 不上传
  └── 本地文件系统 (文档/附件/图表)       ← 不上传

零云端上传：隐私数据完全离线
```

### 5.5 上游 LLM 故障处理

```
上游 LLM 调用失败
  │
  ├── 可重试错误 (5xx, 429 Rate Limit, ConnectionError, ReadTimeout)
  │     ├── 第 1 次重试: 等待 1s
  │     ├── 第 2 次重试: 等待 2s
  │     ├── 第 3 次重试: 等待 4s
  │     └── 3 次全部失败 -> 返回友好错误 + 已完成的部分结果
  │
  └── 不可重试错误 (4xx 非 429, Invalid API Key, Model Not Found)
        └── 直接返回错误给用户，不重试
```

### 5.6 端到端超时保护

```
v3.0 新增：单次用户请求总超时 = 120s
  超时触发 -> 返回已完成的部分结果 + "[处理超时，以下结果可能不完整]"
  避免系统进入无响应状态
```

---

## 6. 广：场景覆盖优势

### 6.1 5 个 Subagent × 5+ 类场景矩阵

```
  ┌──────────────┬─────────────────────┬──────────────────────────┐
  │  办公场景      │  写作 + 日程        │  周报/邮件/会议安排/待办管理  │
  │  学习场景      │  RAG                │  笔记检索/文档索引         │
  │  信息检索      │  RAG + 上游兜底     │  本地检索 + 互联网搜索兜底  │
  │  日程场景      │  日程与任务          │  日程创建/待办追踪/提醒     │
  │  社交场景      │  闲聊               │  日常寒暄/情感陪伴         │
  │  通用推理      │  上游 LLM 兜底      │  任何不命中 Subagent 的请求 │
  └──────────────┴─────────────────────┴──────────────────────────┘
```

**v3.0 说明**：相比 v2.0 的 8 个 Subagent，v3.0 砍掉了 WebFetch、WebSearch、DataAnalysis 三个 Subagent。这些场景由上游 LLM 兜底覆盖（上游 LLM 本身具备联网搜索和数据分析能力）。减少 Subagent 数量换取每个 Subagent 的完成度和路由准确率。

### 6.2 跨 Subagent 协同工作流

```
单请求示例: "把 sample_data 目录导入知识库，然后找一下关于 GPU 算力的笔记"

  RAG (ingest) -> RAG (search) -> 记忆 (remember)
  3 个工具调用 -> 2 轮 -> 端到端完成
```

### 6.3 多轮工具循环

```
RAG 典型流程:
  Round 1: rag_ingest("/data/notes")     -> 索引文档
  Round 2: rag_search("GPU 算力")         -> 检索

不是一问一答，而是多步推理执行
```

---

## 7. 产品化完成度

### 7.1 一键安装

```bash
git clone xxx && cd prometheus && ./install/install.sh
# 交互式输入路由模型/上游模型 URL + Key（6 个配置项）
# 自动完成：Python 依赖安装 -> 目录创建 -> DB 初始化 -> cron 设置 -> 服务启动
# 安装时间 < 5 分钟 [目标]
```

### 7.2 预置样本数据

```
demo/sample_data/
├── sample_notes/              # 3 篇个人笔记 (GPU / HICOOL / 周报模板)
├── sample_data.csv            # 12 个月 × 5 品类销售数据（供上游 LLM 分析）
└── sample_weekly_report.md    # 周报范例
```

评委安装后可立即执行演示剧本中全部对话。

### 7.3 路由追踪面板（轻量版）

赛题加分项明确提到"可视化路由追踪：UI 实时展示 Router 决策路径"。v3.0 保留一个轻量实现：

**方案**：单 HTML 文件 + 轮询 `/v1/tool_history` API，零后端依赖。

```
route_tracer.html（~200 行）
  ├── 定时轮询 curl :18790/v1/tool_history?limit=10
  ├── 渲染最近 10 次路由决策：
  │     用户输入 -> 路由目标 Subagent -> 工具调用 -> 延迟分解 -> Completion Check
  ├── 颜色标记：绿(TASK_COMPLETE) / 黄(TASK_INCOMPLETE) / 红(错误)
  └── 浏览器直接打开，无需后端服务

演示时在终端运行:
  python3 -m http.server 8080 -d ~/.prometheus/dashboard/
  -> 浏览器打开 http://localhost:8080/route_tracer.html
  -> 实时展示路由决策链路
```

**API 端点**：

```bash
curl :18790/health              -> {"status":"ok", "tools_loaded":15}
curl :18790/v1/tools            -> 工具列表
curl :18790/v1/tool_history?limit=5  -> 最近 5 次工具调用详情
```

**为什么是轻量版**：一个 HTML 文件 + 轮询 API 足够展示路由决策链路。不做 WebSocket 推送、不做用户认证、不做历史回放--那些是产品化阶段的事。开发量控制在 1 天以内。

### 7.4 路由准确率测试套件

```bash
# v3.0 新增：50 条混合意图测试集
python3 tests/test_routing_accuracy.py
# 输出：路由准确率、误判率、各 Subagent 召回率
```

---

## 8. 生态与商业价值

### 8.1 真实场景价值

**目标用户**：知识工作者（开发者、研究员、产品经理、内容创作者）

| 痛点 | 现有方案 | Prometheus |
|------|---------|------------|
| "那份报告我放哪了" | 手动翻文件夹 | RAG 语义检索，快速定位 |
| "每次写周报都要重新说格式" | 复制粘贴格式要求 | 即时偏好记忆，自动注入 |
| "忘了今天要交代码" | 手动设闹钟 | 提醒功能 |
| "数据隐私担忧" | 数据上传云端 | 全本地存储，零上传 |
| "杀鸡用牛刀" | 闲聊也走完整 LLM 链路 | 路由模型直回，1-3s |

### 8.2 产品化潜力

```
从 demo 到产品的路径清晰：

demo 阶段（当前）:
  5 个 Subagent + 即时偏好 + 一键安装 + 演示剧本
  -> 验证核心价值

产品化阶段:
  ├── 社区贡献 Subagent 插件（plugin.json 标准格式）
  ├── Subagent 市场（prometheus plugin install xxx）
  ├── 多用户支持（当前单用户，产品化后多租户）
  └── 云端同步（可选，用户自选是否同步偏好到云端）

可持续迭代空间:
  ├── 新增 Subagent 不影响现有（独立子进程，零侵入）
  ├── 路由模型可替换（OpenAI-compatible，任意模型）
  └── 嵌入模型可替换（BGE-M3 -> 其他模型）
```

### 8.3 市场与商业模式

```
目标客群:
  1. MTT AIBOOK 用户（赛题指定硬件，预装优势）
  2. 隐私敏感型用户（政府/企业/科研，数据不出设备）
  3. 知识工作者（笔记/文档/周报/数据分析高频场景）

商业模式:
  ├── 开源核心（MIT 协议，社区驱动 Subagent 生态）
  ├── 企业版（多租户 + 审计日志 + 内网部署 + 定制 Subagent）
  └── Subagent 市场（社区贡献 + 付费高级插件）

推广路径:
  ├── HICOOL 比赛 -> 曝光 + 评委背书
  ├── MTT AIBOOK 预装 -> 硬件捆绑分发
  ├── GitHub 开源 -> 开发者社区
  └── 企业定制 -> B2B 销售
```

### 8.4 生态适配价值

```
与 MTClaw 生态协同:
  ├── Prometheus 是 MTClaw 的上层应用（FR 零代码侵入）
  ├── 验证了 MTClaw 在非编程场景的通用性
  └── 为 MTClaw 贡献 5 个垂类 Subagent 示例

与 MTT AIBOOK 生态协同:
  ├── 利用 AIBOOK 本地算力（路由模型 + 嵌入模型）
  ├── 数据全本地，契合 AIBOOK "本地优先" 定位
  └── 可作为 AIBOOK 的旗舰应用展示

与 OpenClaw/Hermes 生态协同:
  ├── OpenAI-compatible 接口，任意 Agent 框架可接入
  ├── Hermes 作为用户交互层，Prometheus 作为智能层
  └── 工具定义标准（functions.jsonl）可复用
```

### 8.5 可复用与可扩展性

```
Subagent 可复用:
  ├── 每个 Subagent 独立目录（plugin.json + functions.jsonl + scripts/ + engine.py）
  ├── 标准 stdin JSON -> stdout JSON 接口
  ├── 可直接移植到其他 MTClaw 项目
  └── 社区可按标准格式贡献新 Subagent

路由策略可复用:
  ├── 路由优先级 + 关键词匹配 + 防误判规则
  ├── 可配置化（config.json 中的 routing 字段）
  └── 适用于任何基于 MTClaw 的项目

偏好引擎可复用:
  ├── 即时偏好检测 + SQLite + ChromaDB 双存储
  ├── 可独立运行，不依赖 Prometheus 其他模块
  └── 适用于任何需要用户个性化记忆的 Agent

扩展到更多行业:
  ├── 金融: 行情查询 Subagent + 投资分析 Subagent
  ├── 教育: 题目讲解 Subagent + 学习计划 Subagent
  ├── 医疗: 症状自查 Subagent + 用药提醒 Subagent
  └── 只需按标准格式开发新 Subagent，无需修改核心
```

### 8.6 示范带动作用

```
作为 MTClaw 优秀案例:
  ├── 展示 MTClaw 在非编程场景的应用潜力
  ├── 提供 5 个可参考的 Subagent 实现模板
  ├── 验证 Function Router 在 15 工具场景下的路由准确率
  └── 为后续参赛者/开发者提供参考

带动生态建设:
  ├── Subagent 标准格式 -> 社区可以贡献更多垂类
  ├── 即时偏好引擎 -> 可移植到其他 Agent 框架
  ├── 路由准确率测试套件 -> 为 MTClaw 生态提供评测标准
  └── 一键安装方案 -> 降低 MTClaw 上手门槛
```

### 8.7 差异化定位

```
ChatGPT / 通用 AI              普罗米修斯
──────────────────────        ──────────────────────
会话级记忆 (用完即忘)     vs   跨会话持久化 (即时偏好学习)
被动问答                 vs   主动推送 + 被动问答
零知识管理               vs   自动偏好提取
通用回答                 vs   个性化 (偏好记忆注入)
云端数据                 vs   全本地隐私
单一模型路由             vs   Function Router 5 Subagent 分治
```

### 8.8 核心价值主张

```
不是"更好的 ChatGPT"
而是"懂你的私人助理"

核心价值：
1. 本地隐私：数据不出设备
2. 个性化记忆：越用越懂你
3. 多场景覆盖：办公/学习/开发/日常
4. 生态可扩展：标准 Subagent 格式，社区驱动
```

---

## 9. 加分项

赛题明确列出三个加分项（不设上限），Prometheus 逐一对应：

### 9.1 Router 自学习：根据用户使用习惯动态优化分发策略

**对应赛题加分项**："Router 自学习：根据用户使用习惯动态优化分发策略"

即时偏好引擎即为 Router 自学习的实现：

```
v3.0 即时偏好引擎 = Router 自学习

学习机制:
  1. 偏好声明检测: 用户说"以后都用 Markdown" -> 实时写入 memory
  2. 行为模式提取: 记录每次工具调用的 interaction_log
  3. 路由策略优化: 根据高频使用模式调整路由提示词

  例: 发现用户说"帮我看看"时 90% 情况是想找文档而非闲聊
  -> 调整路由提示词，提高"帮我看看"在 RAG 的匹配优先级

演示效果:
  [第 1 轮] 用户: "写周报，用 Markdown，中文，包含本周完成和下周计划"
           系统: 按要求生成 + 即时写入偏好
  [第 2 轮] 用户: "写周报"
           系统: 自动注入偏好 -> 生成符合偏好的周报
           用户零额外输入 -> 展示 Router 自学习效果
```

### 9.2 可视化路由追踪：UI 实时展示 Router 决策路径

**对应赛题加分项**："可视化路由追踪：UI 实时展示 Router 决策路径，帮助用户建立信任"

轻量路由追踪面板（§7.3）即为实现：

```
route_tracer.html（~200 行单文件）
  ├── 实时轮询 /v1/tool_history API
  ├── 展示每次请求的路由决策链路:
  │     用户输入 -> 路由目标 Subagent -> 工具调用
  │     -> 各阶段延迟分解 -> Completion Check 结果
  ├── 颜色标记: 绿(TASK_COMPLETE) / 黄(TASK_INCOMPLETE) / 红(错误)
  └── 帮助用户/评委直观理解 Router 的分发逻辑

演示时双屏:
  左屏: Hermes 对话窗口
  右屏: 路由追踪面板实时刷新
  -> 评委可以同时看到对话和路由决策过程
```

### 9.3 开箱即用：MTT AIBOOK 一键安装包

**对应赛题加分项**："开箱即用：提供 MTT AIBOOK 一键安装包，含预置 Subagent 市场"

一键安装 + 预置数据即为实现：

```
git clone xxx && cd prometheus && ./install/install.sh
# 交互式输入路由模型/上游模型 URL + Key
# 自动完成: 依赖安装 -> 目录创建 -> DB 初始化 -> cron 设置 -> 服务启动
# 安装时间 < 5 分钟 [目标]

预置内容:
  ├── 5 个 Subagent（RAG/记忆/写作/Bash/闲聊）
  ├── 7 个写作模板（周报/邮件/技术文档/会议纪要/文章/PPT大纲）
  ├── 3 类样本数据（笔记/CSV/周报范例）
  ├── 路由追踪面板（route_tracer.html）
  └── 路由准确率测试套件（50 条测试集）

评委安装后:
  curl :18790/health -> 确认运行
  ./run_demo.sh -> 自动执行演示剧本
  -> 全程 < 10 分钟从安装到演示
```

### 9.4 路由 fallback 安全网

路由模型超时/不可用时，自动降级到上游 LLM 直通，确保系统永不无响应。

---

## 10. 评分维度对照矩阵

完全对齐 HICOOL 赛题原文的评分维度：

### 快

| 关键指标 | 目标值 | 数据类型 | 技术支撑 | 详细设计 |
|---------|--------|---------|---------|---------|
| Router 决策延迟 | < 1s | [目标] | temperature=0 确定性路由 | §2.1 |
| 首 token 延迟 | < 2s (L1) / < 5s (L2) | [目标] | 分层延迟策略 | §3.1 |
| 端到端响应耗时 | < 3s (L1) / < 10s (L2) / < 40s (L3) | [推测] | L1/L2/L3 三层策略 | §3.1 |
| 加速比 vs openclaw 原生链路 | 4.99x~6.85x | [推测] | MTClaw 团队 50 任务 benchmark（非 Prometheus 实测） | MTClaw 报告 |
| Completion Check 命中率 | > 70% | [目标] | 快路径直接返回 | §2.1 |

### 准

| 关键指标 | 目标值 | 数据类型 | 技术支撑 | 详细设计 |
|---------|--------|---------|---------|---------|
| Router 分发准确率 | > 90% | [目标] | 5 Subagent + 优先级 + 防误判 | §2.1 |
| 各 Subagent 任务完成质量 | 100% 可演示 | [目标] | 每个 Subagent 独立测试 | §2.1-2.5 |
| 通用 Benchmark 智商不变低 | 不退化 | 设计保证 | 100% 透明转发上游 LLM | §4.4 |
| MTClaw 工具准确率 | 94.8%~97.5% | [推测] | MTClaw 团队测试（非 Prometheus 实测） | MTClaw 报告 |
| RAG Top-5 召回率 | > 85% | [目标] | 稠密+稀疏混合 + RRF | §2.1 |
| 写作格式符合率 | > 80% | [目标] | memory_recall 偏好自动注入 | §2.3 |

### 狠

| 关键指标 | 目标值 | 数据类型 | 技术支撑 | 详细设计 |
|---------|--------|---------|---------|---------|
| 场景覆盖广度 | 5 Subagent / 6 类场景 | - | 办公/学习/检索/日程/社交/通用 | §6.1 |
| 产品化完成度 | 可直接安装使用 | [目标] | 一键安装 + 预置数据 + 演示剧本 | §7 |

### 生态和商业价值

| 关键指标 | 对应赛题要求 | 技术支撑 | 详细设计 |
|---------|------------|---------|---------|
| 真实场景价值 | 面向知识工作者真实痛点 | 5 痛点场景全覆盖 | §8.1 |
| 产品化潜力 | 清晰使用流程 + 可持续迭代 | demo->产品路径明确 | §8.2 |
| 市场与商业模式 | 目标客群 + 推广路径 + 商业模式 | 开源核心 + 企业版 + 插件市场 | §8.3 |
| 生态适配价值 | 与 MTClaw/AIBOOK/OpenClaw 协同 | FR 零侵入 + 本地优先 + 标准接口 | §8.4 |
| 可复用与可扩展性 | Subagent 可复用 + 可扩展到更多行业 | 标准格式 + 独立模块 | §8.5 |
| 示范带动作用 | 优秀案例 + 带动生态建设 | 5 个参考模板 + 评测标准 | §8.6 |

### 加分项（不设上限）

| 加分项 | 赛题原文 | 实现方式 | 详细设计 |
|--------|---------|---------|---------|
| Router 自学习 | "根据用户使用习惯动态优化分发策略" | 即时偏好引擎 | §9.1 |
| 可视化路由追踪 | "UI 实时展示 Router 决策路径" | 轻量 route_tracer.html | §9.2 |
| 开箱即用 | "MTT AIBOOK 一键安装包，含预置 Subagent 市场" | 一键安装 + 预置数据 | §9.3 |

---

## 附录：与竞品架构对比

| 维度 | ChatGPT | 通用 Agent 框架 | Prometheus |
|------|---------|----------------|------------|
| 路由策略 | 单一模型 | Prompt 分岔 | **Function Router + 5 Subagent 专职** |
| 记忆 | 会话级 | 手动管理 | **即时偏好学习 + 跨会话持久化** |
| 延迟优化 | 不分层 | 不分层 | **L1/L2/L3 三层策略** |
| 安全 | 通用沙箱 | 无 | **输入校验 + 参数化查询 + 文件权限** |
| 数据隐私 | 云端 | 混合 | **全本地存储** |
| 可观测性 | 无 | 日志 | **tool_history API + 路由追踪面板** |
| 部署 | SaaS | Docker/源码 | **一键安装** |
