# ADD - 日程与任务 Subagent

> 版本：v1.0 | 日期：2026-07-13 | 状态：draft | 插件名：`schedule`

## 1. 背景

用户需要本地日程管理与任务追踪：创建日程事件、查询日程、管理待办任务、完成提醒。数据完全存储在本地，不出设备。对应赛题推荐方向"日程与任务--串联本地日历、待办、提醒"。

v3.0 新增此 Subagent，替换原 Bash 命令行 Subagent。日程与任务是个人助手的核心场景之一，通过自然语言时间解析和与记忆 Subagent 的协同，实现"对话即管理"的日程体验。

## 2. 调研

### 2.1 Hermes

- **提醒系统**：`~/ws/hermes-agent/tools/cron_tool.py` - cronjob 管理，支持定时触发提醒，但无日程事件/待办任务的数据模型
- **Memory 插件**：`~/ws/hermes-agent/plugins/memory/` - `memory_set_reminder` 可设置简单提醒，提醒存于 SQLite `reminders` 表
- **记忆存储**：SQLite 表 `memories` / `reminders`（id, content, trigger_at, repeat_pattern, active, triggered, created_at）
- **文件操作**：`tools/file_tools.py` - 可读写日程文件，但无结构化查询能力

### 2.2 OpenClaw

- **Cron 系统**：`~/ws/openclaw/src/cron/` - 完整的 cron 服务、存储、隔离 agent 执行
- **Cron 存储**：`~/ws/openclaw/src/cron/storage.ts` - cron job 持久化
- **Cron 服务**：`~/ws/openclaw/src/cron/service.ts` - cron 调度与触发
- **Events 系统**：`~/ws/openclaw/src/memory-host-sdk/` - events 接口可用于事件驱动提醒
- **Hooks**：`session_start` / `session_end` 等生命周期钩子，可用于日程上下文注入
- **无专门日程/任务模型**：OpenClaw 的 cron 系统面向任务调度，非个人日程管理

### 2.3 Codex

- **Memories 读写**：`~/ws/codex/codex-rs/memories/read/src/lib.rs` / `write/src/lib.rs` - 记忆存储，可记录用户日程偏好
- **Multi-phase memory**：phase1.rs / phase2.rs with guard checks
- **无专门日程工具**：Codex 无内置的日历/待办管理能力
- **Chronicle 功能**：被动屏幕上下文记忆，可辅助日程上下文捕获（feature flag：`Chronicle`）

### 2.4 结论

三个代码库均无专门的个人日程/任务管理 Subagent。Hermes 的 `cron_tool.py` 提供了定时提醒的基础设施，OpenClaw 的 cron 系统提供了成熟的调度服务参考，但二者均面向"系统任务调度"而非"个人日程管理"。Prometheus 需要自建结构化的日程与任务数据模型，结合自然语言时间解析（dateparser）和记忆 Subagent 协同，实现赛题要求的"串联本地日历、待办、提醒"。

## 3. 设计决策

### 3.1 数据模型

采用双表模型：`events`（日程事件）+ `tasks`（待办任务），分离日历场景与任务场景。

```sql
-- 日程事件表
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    start_time TEXT NOT NULL,       -- ISO 8601
    end_time TEXT,                   -- ISO 8601, 可空（全天事件）
    location TEXT,
    category TEXT DEFAULT 'general', -- work/personal/health/social/other
    reminder_minutes INTEGER DEFAULT 15,
    status TEXT DEFAULT 'pending',   -- pending/confirmed/cancelled/completed
    created_at TEXT DEFAULT (datetime('now')),
    source TEXT DEFAULT 'manual'     -- manual/memory_import/voice
);

-- 待办任务表
CREATE TABLE tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    description TEXT,
    priority INTEGER DEFAULT 3,       -- 1(最高) ~ 5(最低)
    status TEXT DEFAULT 'pending',    -- pending/in_progress/completed/cancelled
    due_date TEXT,                     -- ISO 8601, 可空
    tags TEXT,                         -- JSON array string
    parent_task_id INTEGER,           -- 子任务关联，可空
    created_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    FOREIGN KEY (parent_task_id) REFERENCES tasks(id)
);
```

### 3.2 自然语言时间解析

使用 `dateparser` 库解析中文自然语言时间表达：

```python
import dateparser

# 支持的时间表达示例：
# "明天下午3点" -> 2026-07-14T15:00:00
# "下周一上午10点" -> 2026-07-20T10:00:00
# "3天后" -> 2026-07-16T当前时间
# "2026年7月15日" -> 2026-07-15T00:00:00

settings = {
    'PREFER_DATES_FROM': 'future',
    'TIMEZONE': 'Asia/Shanghai',
    'RETURN_AS_TIMEZONE_AWARE': True,
    'LANGUAGE': 'zh',
}
parsed = dateparser.parse(time_str, settings=settings)
```

时间范围快捷映射：

| 快捷词 | 计算逻辑 |
|--------|---------|
| `today` | start=today 00:00, end=today 23:59 |
| `tomorrow` | start=tomorrow 00:00, end=tomorrow 23:59 |
| `this_week` | start=本周一 00:00, end=本周日 23:59 |
| `next_week` | start=下周一 00:00, end=下周日 23:59 |
| `all` | 无时间过滤 |

### 3.3 与记忆 Subagent 协同

```
日程与任务 Subagent <-> 记忆 Subagent 协同链路：

1. 日程创建时：
   schedule_create_event() ->
     memory_engine.remember(category='schedule_preference',
                            key=f'event_{event_id}',
                            value=f'{title} at {start_time}',
                            importance=2)

2. 提醒到期时：
   get_due_events() ->  # 检查 reminder_minutes 到期的事件
     memory_engine.set_reminder(content=f'日程提醒: {event.title}',
                                time_str=event.start_time)

3. 反思引擎发现重复日程模式：
   reflection_engine.extract_reminder_candidates() ->
     自动建议创建周期性事件（如"每周五 16:00 写周报"）

4. 日程上下文注入：
   memory_recall(context='schedule') ->
     返回用户日程偏好（如"用户偏好上午处理重要任务"）
     -> schedule_create_event 时自动建议时间段
```

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "schedule",
  "version": "1.0.0",
  "description": "日程与任务 Subagent - 本地日程管理、待办任务追踪、提醒",
  "enabled": true,
  "priority": 4,
  "requires": {
    "plugins": ["memory"],
    "packages": ["dateparser>=1.2"]
  },
  "provides": {
    "tools": [
      "schedule_create_event",
      "schedule_query",
      "schedule_create_task",
      "schedule_list_tasks",
      "schedule_complete_task"
    ],
    "engines": ["schedule_engine.py"]
  },
  "routing": {
    "trigger_keywords": [
      "日程", "提醒", "待办", "任务",
      "明天有什么", "这周安排", "加个日程",
      "创建任务", "完成任务", "待办事项"
    ],
    "trigger_patterns": [
      "帮我(加|创建|安排).*日程",
      "(明天|后天|下周|今天).*什么(安排|日程)",
      "提醒我.*",
      "(创建|添加).*任务",
      "完成.*任务",
      "(列出|查看).*待办"
    ],
    "match_priority": "high"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.x，5 个工具：

#### schedule_create_event

创建日程事件。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| title | string | 是 | 事件标题 |
| start_time | string | 是 | 开始时间（自然语言或 ISO 8601） |
| end_time | string | 否 | 结束时间（自然语言或 ISO 8601） |
| location | string | 否 | 地点 |
| category | string | 否 | 分类：work/personal/health/social/other，默认 general |
| reminder_minutes | integer | 否 | 提前提醒分钟数，默认 15 |

#### schedule_query

查询日程事件。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| time_range | string | 否 | 时间范围：today/tomorrow/this_week/next_week/all，默认 today |
| category | string | 否 | 按分类过滤 |
| status | string | 否 | 按状态过滤：pending/confirmed/cancelled/completed |

#### schedule_create_task

创建待办任务。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| title | string | 是 | 任务标题 |
| priority | integer | 否 | 优先级 1-5（1 最高），默认 3 |
| due_date | string | 否 | 截止日期（自然语言或 ISO 8601） |
| tags | array | 否 | 标签列表 |
| description | string | 否 | 任务描述 |

#### schedule_list_tasks

列出待办任务。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| status | string | 否 | 按状态过滤：pending/in_progress/completed/cancelled |
| priority | integer | 否 | 按优先级过滤 |
| tags | array | 否 | 按标签过滤（匹配任一） |

#### schedule_complete_task

完成任务。

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| task_id | integer | 是 | 任务 ID |

### 4.3 Python 引擎接口

```python
# schedule_engine.py

# ---- 日程事件 ----
def create_event(
    title: str,
    start_time: str,
    end_time: str = None,
    location: str = None,
    category: str = "general",
    reminder_minutes: int = 15,
) -> dict
    """创建日程事件，返回 {id, title, start_time, end_time, ...}"""

def query_events(
    time_range: str = "today",
    category: str = None,
    status: str = None,
) -> list[dict]
    """查询日程事件，返回事件列表"""

def get_due_events() -> list[dict]
    """获取需要提醒的到期事件（基于 reminder_minutes）"""

# ---- 待办任务 ----
def create_task(
    title: str,
    priority: int = 3,
    due_date: str = None,
    tags: list[str] = None,
    description: str = None,
) -> dict
    """创建待办任务，返回 {id, title, priority, due_date, ...}"""

def list_tasks(
    status: str = None,
    priority: int = None,
    tags: list[str] = None,
) -> list[dict]
    """列出待办任务，返回任务列表"""

def complete_task(task_id: int) -> dict
    """标记任务完成，返回 {id, status, completed_at}"""
```

## 5. 实现 Checklist

### 数据层

- [ ] SCH-001 创建 SQLite 表 `events`（id, title, description, start_time, end_time, location, category, reminder_minutes, status, created_at, source）
- [ ] SCH-002 创建 SQLite 表 `tasks`（id, title, description, priority, status, due_date, tags, parent_task_id, created_at, completed_at）
- [ ] SCH-003 创建索引：`idx_events_start_time`、`idx_events_category`、`idx_events_status`、`idx_tasks_status`、`idx_tasks_priority`、`idx_tasks_due_date`
- [ ] SCH-004 实现 `tasks.parent_task_id` 外键约束与级联查询（子任务列表）

### 时间解析

- [ ] SCH-005 封装 `parse_time()` 函数 - dateparser 自然语言解析（中文优先，fallback 英文）
- [ ] SCH-006 实现时间范围快捷映射：today/tomorrow/this_week/next_week/all -> (start, end) 元组
- [ ] SCH-007 实现时间格式标准化：输入 -> ISO 8601 输出，统一时区 Asia/Shanghai
- [ ] SCH-008 处理模糊时间解析失败（返回错误提示 + 原始输入回显）

### 日程 CRUD

- [ ] SCH-009 实现 `create_event()` - 解析时间 -> 写入 events 表 -> 同步记忆
- [ ] SCH-010 实现 `query_events()` - 时间范围 + category + status 多条件过滤
- [ ] SCH-011 实现 `get_due_events()` - 检查 `reminder_minutes` 到期事件
- [ ] SCH-012 实现事件状态更新（pending -> confirmed -> completed / cancelled）
- [ ] SCH-013 实现到期提醒触发：调用 `memory_engine.set_reminder()`

### 任务 CRUD

- [ ] SCH-014 实现 `create_task()` - 解析 due_date -> 写入 tasks 表 -> 同步记忆
- [ ] SCH-015 实现 `list_tasks()` - status + priority + tags 多条件过滤
- [ ] SCH-016 实现 `complete_task()` - 更新 status=completed + completed_at
- [ ] SCH-017 实现子任务关联查询（parent_task_id 递归查询子任务树）
- [ ] SCH-018 实现任务状态流转：pending -> in_progress -> completed / cancelled

### Wrapper 脚本

- [ ] SCH-019 编写 `schedule_create_event.sh`（stdin JSON -> Python -> stdout JSON）
- [ ] SCH-020 编写 `schedule_query.sh`
- [ ] SCH-021 编写 `schedule_create_task.sh`
- [ ] SCH-022 编写 `schedule_list_tasks.sh`
- [ ] SCH-023 编写 `schedule_complete_task.sh`

### 测试

- [ ] SCH-024 单元测试：时间解析 - 中文自然语言（"明天下午3点"、"下周一上午10点"、"3天后"）
- [ ] SCH-025 单元测试：时间范围映射（today/tomorrow/this_week/next_week 边界正确性）
- [ ] SCH-026 单元测试：事件 CRUD 全流程
- [ ] SCH-027 单元测试：任务 CRUD 全流程
- [ ] SCH-028 单元测试：子任务关联查询
- [ ] SCH-029 单元测试：tags 过滤逻辑（多标签匹配）
- [ ] SCH-030 集成测试：create_event -> query_events 端到端
- [ ] SCH-031 集成测试：create_task -> list_tasks -> complete_task 端到端
- [ ] SCH-032 集成测试：到期提醒 -> memory_engine.set_reminder 联动
- [ ] SCH-033 集成测试：与记忆 Subagent 协同（日程偏好注入）

## 6. 参考

- Hermes Cron Tool: `~/ws/hermes-agent/tools/cron_tool.py`
- Hermes Memory Plugin: `~/ws/hermes-agent/plugins/memory/`
- OpenClaw Cron System: `~/ws/openclaw/src/cron/`
- OpenClaw Memory Host SDK: `~/ws/openclaw/src/memory-host-sdk/`
- Codex Memories: `~/ws/codex/codex-rs/memories/`
- dateparser: https://dateparser.readthedocs.io/
