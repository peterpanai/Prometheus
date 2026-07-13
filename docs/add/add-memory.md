# ADD - 记忆与偏好 Subagent

> 版本：v2.0 | 日期：2026-07-12 | 状态：draft | 插件名：`memory`

## 1. 背景

用户需要 AI 记住偏好、身份、习惯和重要信息，跨会话持久化。**即时偏好引擎**在用户声明偏好时实时写入，无需等待后台任务。下次对话自动注入偏好上下文。这是 Prometheus "自我进化" 核心差异化所在。

## 2. 调研

### 2.1 Hermes

- **Memory 插件**：`~/ws/hermes-agent/plugins/memory/` — 提供 `memory` 工具集
- **Memory 工具**：`tools/memory_tool.py` — `memory`、`memory_search`、`memory_dream`（后台反思）
- **Memory 存储**：SQLite 表 `memories(id, content, embedding, created_at, access_count)`
- **会议纪要**：`tools/meeting_transcript_tool.py` — 专门工具
- **提醒系统**：`tools/cron_tool.py` — cronjob 管理

### 2.2 OpenClaw

- **Memory 核心**：`~/ws/openclaw/src/plugin-sdk/memory-core.ts` — 完整 SDK
- **Memory Host**：`~/ws/openclaw/src/memory-host-sdk/` — dream（反思）、events、multimodal
- **Memory 搜索**：`~/ws/openclaw/src/agents/memory-search.ts`
- **Memory embedding**：`~/ws/openclaw/src/plugins/memory-embedding-providers.ts`
- **Memory 存储**：`~/ws/openclaw/src/memory/root-memory-files.ts` + SQLite
- **Cron 系统**：`~/ws/openclaw/src/cron/` — cron 服务、存储、隔离 agent
- **Hooks**：40+ 生命周期钩子，`session_start`/`session_end` 用于记忆注入

### 2.3 Codex

- **Memories 读写**：`~/ws/codex/codex-rs/memories/read/src/lib.rs` / `write/src/lib.rs`
- **Multi-phase memory writing**：phase1.rs / phase2.rs with guard checks
- **Chronicle 功能**：被动屏幕上下文记忆（feature flag：`Chronicle`）
- **Memory Tool**：feature flag `MemoryTool` 控制

### 2.4 结论

三个代码库都有独立的记忆系统，且均区分"在线记忆注入"和"离线反思提取"两个阶段。OpenClaw 的 memory host SDK 设计最为完整（query + dream + events + multimodal），Hermes 的 `memory_dream` 是反思引擎的简洁参考实现。

## 3. 设计决策

### 3.1 双存储模型

```
SQLite (结构化)           ChromaDB (语义化)
├── memories 表           ├── Collection: "memories"
│   ├── category          │   ├── id: "mem_{id}"
│   ├── key               │   ├── embedding: BGE-M3
│   ├── value             │   ├── document: "{key}: {value}"
│   ├── importance        │   └── metadata: {category, importance}
│   └── access_count      │
├── reminders 表          └── 用途：语义检索、相似记忆推荐
├── interaction_log 表
└── reflection_log 表

查询流程：
  memory_recall(context) →
    1. ChromaDB 语义检索 Top K
    2. SQLite 高 importance 记忆补充
    3. 合并去重，按 importance + similarity 排序
```

### 3.2 即时偏好引擎（v2.0 核心变更）

v2.0 将 v1.0 的"后台反思引擎"改为"即时偏好引擎"。用户声明偏好时实时写入 memory，不依赖后台 cron 任务。这确保在演示中能即时展示"越用越懂你"的效果。

| 触发方式 | 频率 | 实现 |
|---------|------|------|
| **即时触发** | 用户说"以后都"/"记住了"/"我喜欢"时 | 规则匹配 + memory_remember 同步写入 |
| 定时维护 | 每日凌晨 2:00 | 记忆衰减/强化 + 交互统计（cron + Python 脚本） |
| 手动触发 | 用户主动 | "帮我总结一下最近" -> memory_recall + 统计 |

### 3.3 反思摘要格式

反思摘要作为下次对话的 system prompt 注入前缀：

```
[近期发现]
- 用户最近 3 次翻译请求均为中译英 → 建议优先展示英文翻译结果
- 用户连续 5 个周五下午撰写周报 → 已设置"每周五 16:00 提醒写周报"
- 高频主题：HICOOL 智能体赛道（出现 8 次）-> 已记录为用户兴趣偏好
```

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "memory",
  "version": "1.0.0",
  "description": "记忆与反思 Subagent — 跨会话记忆、偏好管理、后台反思",
  "enabled": true,
  "priority": 1,
  "requires": {
    "plugins": [],
    "packages": ["chromadb>=0.5", "sentence-transformers>=2.7"]
  },
  "provides": {
    "tools": ["memory_remember", "memory_recall", "memory_set_reminder"],
    "engines": ["memory_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["记住了", "以后都", "提醒我", "别忘了", "我的偏好"],
    "trigger_patterns": ["记住.*", "以后.*", "提醒我.*", "我的.*是.*"],
    "match_priority": "high"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.2，3 个工具：`memory_remember`、`memory_recall`、`memory_set_reminder`。

### 4.3 Python 引擎接口

```python
# memory_engine.py
def remember(category: str, key: str, value: str, importance: int = 3) -> dict
def recall(context: str, top_k: int = 5, category: str = None) -> list[dict]
def set_reminder(content: str, time_str: str, repeat: str = 'once') -> dict
def get_due_reminders() -> list[dict]
def log_interaction(session_id, user_message, subagent, tool_name, tool_input, tool_result, latency_ms) -> None
def get_recent_interactions(limit: int = 100) -> list[dict]
```

## 5. 实现 Checklist

### 数据层

- [ ] MEM-001 创建 SQLite 表 `memories`（id, category, key, value, importance, source_session, created_at, updated_at, access_count）
- [ ] MEM-002 创建 SQLite 表 `reminders`（id, content, trigger_at, repeat_pattern, active, triggered, created_at）
- [ ] MEM-003 创建 SQLite 表 `interaction_log`（id, session_id, user_message, subagent, tool_name, tool_input, tool_result, latency_ms, route_decision, completion_check_result, timestamp）
- [ ] MEM-004 创建 SQLite 表 `reflection_log`（id, summary, reminders_found, preferences_updated, nodes_created, links_created, created_at）
- [ ] MEM-005 创建索引：`idx_memories_category`、`idx_memories_updated`、`idx_reminders_active`、`idx_interaction_session`、`idx_interaction_subagent`
- [ ] MEM-006 初始化 ChromaDB Collection `memories`（1024d）

### 记忆存储与检索

- [ ] MEM-007 实现 `remember()` — SQLite UPSERT + ChromaDB 同步写入
- [ ] MEM-008 实现 `recall()` — 将 context 向量化 → ChromaDB 语义检索 + SQLite 高 importance 补充
- [ ] MEM-009 实现 `set_reminder()` — 自然语言时间解析（dateparser）→ SQLite
- [ ] MEM-010 实现 `get_due_reminders()` — 查询到期提醒
- [ ] MEM-011 实现 `log_interaction()` — 每次工具调用后记录交互日志
- [ ] MEM-012 实现 `get_recent_interactions()` - 偏好引擎加载最近日志

### 即时偏好引擎

- [ ] MEM-013 实现 `preference_engine.py` - `detect_and_store_preference()` 即时偏好检测
- [ ] MEM-014 实现 `run_daily_maintenance()` - 记忆衰减/强化 + 交互统计（每日 cron）
- [ ] MEM-015 实现偏好检测规则匹配（"以后都"/"我喜欢"/"记住了"/"不要"/"总是"）
- [ ] MEM-016 实现偏好同步写入 memory（SQLite + ChromaDB）
- [ ] MEM-017 实现反思摘要格式化（Markdown）
- [ ] MEM-018 实现 `memory_injector.py` - 请求前自动注入记忆上下文到 system prompt

### 定时任务

- [ ] MEM-019 编写 `preference_loop.sh` - 偏好维护入口
- [ ] MEM-020 设置 cron 定时任务（每日凌晨 2:00 记忆衰减/强化 + 交互统计）
- [ ] MEM-021 实现 cron job 注册/注销管理

### Wrapper 脚本

- [ ] MEM-022 编写 `memory_remember.sh`
- [ ] MEM-023 编写 `memory_recall.sh`
- [ ] MEM-024 编写 `memory_set_reminder.sh`

### 测试

- [ ] MEM-025 单元测试：记忆 CRUD 全流程
- [ ] MEM-026 单元测试：语义检索召回率（Top-5 > 90%）
- [ ] MEM-027 单元测试：自然语言时间解析准确率
- [ ] MEM-028 单元测试：即时偏好检测（"以后都"/"记住了"/"我喜欢"等模式）
- [ ] MEM-029 单元测试：记忆衰减/强化逻辑
- [ ] MEM-030 集成测试：跨会话记忆注入
- [ ] MEM-031 集成测试：提醒到期推送

## 6. 参考

- Hermes Memory Plugin: `~/ws/hermes-agent/plugins/memory/`
- Hermes memory_dream: `~/ws/hermes-agent/tools/memory_tool.py`
- OpenClaw Memory Host SDK: `~/ws/openclaw/src/memory-host-sdk/`
- OpenClaw Cron System: `~/ws/openclaw/src/cron/`
- Codex Memories: `~/ws/codex/codex-rs/memories/`
