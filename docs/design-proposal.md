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
   - 2.4 [Bash 命令行 Subagent](#24-bash-命令行-subagent)
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
| Subagent 从 8 个缩减到 5 个 | 砍掉 WebFetch/WebSearch/DataAnalysis（上游 LLM 兜底覆盖） | 工具数从 24 降到 15，路由准确率提升 |
| 砍掉插件系统 | 比赛不需要，直接写死配置 | 省 1 周开发时间 |
| 砍掉知识图谱 | 小数据量上无实际价值 | 省 3-5 天 |
| 砍掉路由追踪 Web UI | 用 /v1/tool_history API 替代 | 省 3-5 天 |
| 砍掉模型 fallback 链 | 比赛环境不会挂 | 省 2 天 |
| 砍掉上下文压缩器 | MTClaw 已有 fr_context_history | 省 2-3 天 |
| 砍掉多搜索后端 fallback | DuckDuckGo 够用 | 省 2 天 |
| 反思引擎改为即时偏好提取 | 演示中能即时展示"进化"效果 | 演示可跑通 |
| 所有性能数字标注来源 | 诚实化，区分"实测"和"目标" | 应对评委追问 |
| 工具数控制在 15 个以内 | LLM function calling 在 <15 工具时准确率最高 | 路由更准 |

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
                    ├─ bash_*        -> Bash 命令行   (subprocess 沙箱，<1-30s)
                    ├─ chat_light    -> 闲聊陪伴       (路由模型直回，1-2s)
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
| **[实测]** | 有实际测试数据支撑 | 高 |
| **[目标]** | 设计目标值，尚未实测 | 中 |
| **[推测]** | 基于架构推断的估计值 | 低 |

评委追问时，我们将明确区分这三类数据。

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

#### 2.3.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `writing_generate` | doc_type, topic, key_points, style, length | 生成各类文档 |
| `writing_polish` | text, goal, target_language | 润色已有文本 |
| `writing_translate` | text, source_lang, target_lang, keep_formatting | 翻译文本 |

#### 2.3.4 实现 Checklist

- [ ] 创建 7 个文档模板
- [ ] 实现 writing_engine.py（generate / polish / translate）
- [ ] 实现偏好注入（import memory_engine.recall）
- [ ] 实现上游 LLM 调用（httpx -> OpenAI-compatible API）
- [ ] 实现错误降级（上游不可用时返回友好错误）
- [ ] **测试：格式符合偏好概率** [目标: >80%]

---

### 2.4 Bash 命令行 Subagent

#### 2.4.1 功能定位

安全执行本地 Bash 命令，用于文件管理、系统操作、脚本运行等

#### 2.4.2 核心设计

**安全模型--四层防护**：

```
用户命令
  │
  ├── 第 1 层: 白名单校验
  │     允许的命令: find, grep, cat, ls, wc, head, tail, awk, sed, sort,
  │                  uniq, curl, wget, git, python3, node, npm, pip,
  │                  df, du, ps, top, free, echo, date, env, mkdir, touch, cp, mv
  │     不在白名单中 -> 拒绝，提示 "命令未授权"
  │
  ├── 第 2 层: 黑名单正则匹配
  │     rm\s+(-rf?\s+)?/       -> rm -rf / (绝对禁止)
  │     dd\s+if=               -> dd 磁盘操作
  │     mkfs\.                 -> 格式化文件系统
  │     shutdown / reboot      -> 关机/重启
  │     >\s*/dev/              -> 写入设备文件
  │     :\(\)\s*\{\s*:\|:&\s*\}\s*;:  -> fork bomb
  │     chmod\s+777\s+/        -> 危险权限
  │     匹配任一黑名单 -> 拒绝，告警日志记录
  │
  ├── 第 3 层: 参数消毒
  │     检测命令注入模式: ; rm / `cmd` $(cmd) | 管道到危险命令
  │
  └── 第 4 层: 写入确认
       命令涉及文件变更（rm / mv / cp / chmod / chown / mkdir / touch）
       -> 返回确认请求，需用户二次确认后执行
```

#### 2.4.3 工具定义

| 工具 | 参数 | 功能 |
|------|------|------|
| `bash_exec` | command, workdir, timeout=30 | 执行命令并返回结果 |
| `bash_spawn` | command, workdir, label | 后台启动进程 |
| `bash_status` | label | 查询后台进程状态 |

#### 2.4.4 实现 Checklist

- [ ] 实现命令白名单校验器
- [ ] 实现黑名单正则匹配器（含 7 类危险模式）
- [ ] 实现参数消毒（防命令注入）
- [ ] 实现写入操作确认机制
- [ ] 实现 bash_exec（subprocess.run + timeout + 输出截断）
- [ ] 实现 bash_spawn（subprocess.Popen + SQLite 记录）
- [ ] 实现 bash_status / kill_process
- [ ] 安全测试：rm -rf / / dd / shutdown / fork bomb 全部拒绝

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
| **L2 快速** | RAG、Bash | 1-10s | 本地向量库 / subprocess | ~35% |
| **L3 标准** | 写作 | 10-40s | 上游 LLM（核心智能依赖） | ~25% |
| **兜底** | 通用推理 | 15-40s | 上游 LLM 全量推理 | ~15% |

**注意**：上述延迟和占比为 [推测] 值，基于 MTClaw 在系统控制领域的实测数据外推。实际数字需在目标硬件上实测验证。

### 3.2 MTClaw 实测数据（唯一有实测支撑的数据）

在 50 个系统控制任务上，每个任务重复 4 次的评测 [实测]：

| 模式 | Pass@1 | 平均耗时 | 加速比 |
|------|--------|----------|--------|
| Baseline（纯上游 LLM） | 99.0% | 37.97s | 1.00x |
| Permissive | 95.5% | 5.54s | **6.85x** |
| Strict | **100.0%** | 7.61s | **4.99x** |

- Strict 模式：工具召回率 100%，工具准确率 94.8% [实测]
- Permissive 模式：工具召回率 100%，工具准确率 97.5% [实测]

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
| Shell 命令 | 无法执行 | < 2s (subprocess 沙箱) | 延迟待实测 |

**注意**：以上对比中 Prometheus 的延迟均为 [推测] 值，将在方案验证阶段实测后更新。

---

## 4. 准：准确率优势

### 4.1 Function Router 精准分发

```
路由准确率保证：
  1. temperature = 0.0（确定性 function calling，零随机性）
  2. 5 个 Subagent 描述高度特化（工具描述互不重叠）
  3. 双重意图匹配：触发关键词 + 正则模式
  4. 优先级排序：记忆(P1) > 写作(P2) > RAG(P3) > Bash(P4) > 闲聊(P5) > 兜底(P6)
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
  ├── 其他插件不受影响（RAG 崩溃不影响 Shell、写作）
  └── 独立启停
```

### 5.3 四层安全防护

| Subagent | 安全机制 | 防护目标 |
|----------|---------|---------|
| Shell | 白名单 + 黑名单 + 命令注入检测 + 写入确认 | 防止系统破坏 |
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
  │  办公场景      │  写作 + Bash        │  周报/邮件/文件批量管理     │
  │  学习场景      │  RAG                │  笔记检索/文档索引         │
  │  信息检索      │  RAG + 上游兜底     │  本地检索 + 互联网搜索兜底  │
  │  日程场景      │  记忆               │  提醒设置/习惯追踪         │
  │  社交场景      │  闲聊               │  日常寒暄/情感陪伴         │
  │  开发场景      │  Bash               │  命令执行/脚本运行         │
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

### 7.3 健康检查与可观测性

```bash
curl :18790/health  -> {"status":"ok", "tools_loaded":15, "uptime":"2h"}
curl :18790/v1/tools | jq '.tools | length'  -> 15
curl :18790/v1/tool_history?limit=5  -> 最近 5 次工具调用详情
```

**v3.0 变更**：砍掉了路由追踪 Web UI，用 `/v1/tool_history` API 替代。演示时可在终端 `curl` 展示路由决策链路。

### 7.4 路由准确率测试套件

```bash
# v3.0 新增：50 条混合意图测试集
python3 tests/test_routing_accuracy.py
# 输出：路由准确率、误判率、各 Subagent 召回率
```

---

## 8. 商业价值

### 8.1 目标用户：知识工作者

| 痛点 | 现有方案 | Prometheus |
|------|---------|------------|
| "那份报告我放哪了" | 手动翻文件夹 | RAG 语义检索，快速定位 |
| "每次写周报都要重新说格式" | 复制粘贴格式要求 | 记忆自动注入偏好 |
| "忘了今天要交代码" | 手动设闹钟 | 主动提醒 |
| "数据隐私担忧" | 数据上传云端 | 全本地存储，零上传 |

### 8.2 差异化定位

```
ChatGPT / 通用 AI              普罗米修斯
──────────────────────        ──────────────────────
会话级记忆 (用完即忘)     vs   跨会话持久化 (即时偏好学习)
被动问答                 vs   主动推送 + 被动问答
零知识管理               vs   自动偏好提取
通用回答                 vs   个性化 (偏好记忆注入)
云端数据                 vs   全本地隐私
```

### 8.3 价值主张

```
不是"更好的 ChatGPT"
而是"懂你的私人助理"

核心价值：
1. 本地隐私：数据不出设备
2. 个性化记忆：越用越懂你
3. 多场景覆盖：办公/学习/开发/日常
```

---

## 9. 加分项

### 9.1 路由准确率实测数据

50 条混合意图测试集，覆盖 5 个 Subagent + 通用兜底场景。测试结果将作为方案验证阶段的第一个交付物。

### 9.2 即时偏好学习演示

```
[Day 1]  用户: "写周报，用 Markdown，中文，包含本周完成和下周计划"
         系统: 按详细要求生成（15s）
         同时: 即时偏好引擎检测到偏好 -> 写入 memory

[Day 2]  用户: "写周报"
         系统: 自动注入偏好 -> 自动生成 Markdown 中文三段式周报（12s）
         用户零额外输入 -> 展示 "越用越懂你" 的核心价值
```

### 9.3 路由 fallback 安全网

路由模型超时/不可用时，自动降级到上游 LLM 直通，确保系统永不无响应。

---

## 10. 评分维度对照矩阵

| 维度 | 关键指标 | 目标值 | 数据类型 | 技术支撑 | 详细设计 |
|------|---------|--------|---------|---------|---------|
| **快** | 闲聊延迟 | < 3s | [目标] | 路由模型直回 | §2.5 |
| | RAG 检索延迟 | < 3s | [目标] | ChromaDB + BGE-M3 本地检索 | §2.1 |
| | 记忆查询延迟 | < 1s | [目标] | SQLite + ChromaDB 双存储 | §2.2 |
| | 路由决策延迟 | < 1s | [目标] | temperature=0 确定性路由 | §2.1 |
| | Completion Check 命中率 | > 70% | [目标] | 快路径直接返回 | §2.1 |
| | MTClaw 加速比 | 4.99x~6.85x | [实测] | 50 任务 benchmark | MTClaw 报告 |
| **准** | 路由分发准确率 | > 90% | [目标] | 5 Subagent + 优先级 + 防误判 | §2.1 |
| | RAG Top-5 召回率 | > 85% | [目标] | 稠密+稀疏混合 + RRF | §2.1 |
| | 写作格式符合率 | > 80% | [目标] | memory_recall 偏好自动注入 | §2.3 |
| | 偏好召回准确率 | > 85% | [目标] | 语义 + 结构化双检索 | §2.2 |
| | MTClaw 工具准确率 | 94.8%~97.5% | [实测] | strict/permissive 模式 | MTClaw 报告 |
| | 通用智商 | 不退化 | 设计保证 | 100% 透明转发上游 LLM | §2.1 |
| **稳** | 透明兜底 | 100% | 设计保证 | 未命中 -> 上游 LLM 原样透传 | §5.1 |
| | 故障隔离 | 插件级 | 设计保证 | 独立子进程 | §5.2 |
| | 路由 fallback | 有 | 设计保证 | 路由超时 -> 上游直通 | §4.5 |
| | 安全防护 | 4 层 | 设计保证 | 白名单+黑名单 / AST审计 / SSRF / 限速 | §5.3 |
| | 数据隐私 | 全本地 | 设计保证 | SQLite + ChromaDB 零上传 | §5.4 |
| | 端到端超时 | 120s | 设计保证 | 超时返回部分结果 | §5.6 |
| **广** | Subagent 数量 | 5 个 | - | RAG/记忆/写作/Bash/闲聊 | §2.1-2.5 |
| | 覆盖场景 | 5+ 类 | - | 办公/学习/检索/日程/社交/开发/通用 | §6.1 |
| | 多轮工具循环 | 2+ | - | RAG ingest+search | §2.7 |
| | 跨 Subagent 协同 | 3 串联 | - | RAG->RAG->记忆 | §2.7 |
| | 通用兜底 | 100% | 设计保证 | 任何不命中的请求走上游 LLM | §4.4 |
| **产品化** | 安装时间 | < 5 min | [目标] | 一键安装 + 交互式配置 | §7.1 |
| | 预置数据 | 3 类 | - | 笔记/CSV/周报 | §7.2 |
| | 健康检查 | 1 endpoint | - | /health + /v1/tools | §7.3 |
| | 路由测试套件 | 50 条 | - | test_routing_accuracy.py | §7.4 |
| **商业** | 目标用户 | 知识工作者 | - | 办公/学习/开发 全链路 | §8.1 |
| | 差异化 | 本地隐私+个性化 | - | 即时偏好 + 跨会话记忆 | §8.2 |
| | 核心价值 | 懂你的私人助理 | - | 不是更好的 ChatGPT | §8.3 |
| **加分** | 路由准确率实测 | 50 条测试集 | - | 真实数据，非编造 | §9.1 |
| | 即时偏好演示 | 可演示 | - | 演示中即时可见 | §9.2 |
| | 路由 fallback | 安全网 | - | 路由故障永不无响应 | §9.3 |

---

## 附录：与竞品架构对比

| 维度 | ChatGPT | 通用 Agent 框架 | Prometheus |
|------|---------|----------------|------------|
| 路由策略 | 单一模型 | Prompt 分岔 | **Function Router + 5 Subagent 专职** |
| 记忆 | 会话级 | 手动管理 | **即时偏好学习 + 跨会话持久化** |
| 延迟优化 | 不分层 | 不分层 | **L1/L2/L3 三层策略** |
| 安全 | 通用沙箱 | 无 | **4 层针对性防护** |
| 数据隐私 | 云端 | 混合 | **全本地存储** |
| 可观测性 | 无 | 日志 | **tool_history API + 交互日志** |
| 部署 | SaaS | Docker/源码 | **一键安装** |
