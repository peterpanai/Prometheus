# Prometheus 实现 Checklist

> 最后更新：2026-07-13
> 统一进度追踪文件。所有 Subagent 的实现任务汇总在此。
> 详细设计见 `docs/add/` 下各 ADD 文档。

---

## 总览

| Subagent | 任务数 | 已完成 | 进行中 | 未开始 | 完成率 |
|----------|--------|--------|--------|--------|--------|
| RAG 知识库 | 25 | 0 | 0 | 25 | 0% |
| 记忆与偏好 | 31 | 0 | 0 | 31 | 0% |
| 写作润色翻译 | 25 | 0 | 0 | 25 | 0% |
| 日程与任务 | 33 | 0 | 0 | 33 | 0% |
| 闲聊陪伴 | 15 | 0 | 0 | 15 | 0% |
| 即时偏好引擎 | 6 | 0 | 0 | 6 | 0% |
| 系统集成 | 12 | 0 | 0 | 12 | 0% |
| **合计** | **147** | **0** | **0** | **147** | **0%** |

---

## 1. RAG 知识库 Subagent

详细设计：`docs/add/add-rag.md`

### 数据层

- [ ] RAG-001 初始化 ChromaDB Collection `documents`（1024d, cosine）
- [ ] RAG-002 初始化 ChromaDB Collection `documents_bm25`（稀疏向量）
- [ ] RAG-003 创建 SQLite 表 `documents`（id, path, file_type, title, chunk_count, ingested_at, size_bytes）

### 文档摄入

- [ ] RAG-004 实现 `.md` 分段器（按 ## 标题 + 空行）
- [ ] RAG-005 实现 `.pdf` 分段器（pdfplumber 提取文本 -> 段落分段）
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

### Wrapper 脚本

- [ ] RAG-017 编写 `rag_search.sh`
- [ ] RAG-018 编写 `rag_ingest.sh`
- [ ] RAG-019 编写 `rag_status.sh`

### 测试

- [ ] RAG-020 单元测试：分段器（每种格式 3 个样本文件）
- [ ] RAG-021 单元测试：嵌入生成一致性
- [ ] RAG-022 单元测试：检索召回率（Top-5 > 85%）
- [ ] RAG-023 集成测试：ingest -> search 端到端
- [ ] RAG-024 集成测试：source_filter 过滤正确性
- [ ] RAG-025 集成测试：重复摄入去重

---

## 2. 记忆与偏好 Subagent

详细设计：`docs/add/add-memory.md`

### 数据层

- [ ] MEM-001 创建 SQLite 表 `memories`
- [ ] MEM-002 创建 SQLite 表 `reminders`
- [ ] MEM-003 创建 SQLite 表 `interaction_log`
- [ ] MEM-004 创建 SQLite 表 `reflection_log`
- [ ] MEM-005 创建索引
- [ ] MEM-006 初始化 ChromaDB Collection `memories`（1024d）

### 记忆存储与检索

- [ ] MEM-007 实现 `remember()` - SQLite UPSERT + ChromaDB 同步写入
- [ ] MEM-008 实现 `recall()` - 语义检索 + 高 importance 补充
- [ ] MEM-009 实现 `set_reminder()` - dateparser 自然语言时间解析
- [ ] MEM-010 实现 `get_due_reminders()` - 查询到期提醒
- [ ] MEM-011 实现 `log_interaction()` - 交互日志记录
- [ ] MEM-012 实现 `get_recent_interactions()` - 加载最近日志

### 即时偏好引擎

- [ ] MEM-013 实现 `preference_engine.py` - `detect_and_store_preference()`
- [ ] MEM-014 实现 `run_daily_maintenance()` - 记忆衰减/强化 + 交互统计
- [ ] MEM-015 实现偏好检测规则匹配（"以后都"/"我喜欢"/"记住了"/"不要"/"总是"）
- [ ] MEM-016 实现偏好同步写入 memory（SQLite + ChromaDB）
- [ ] MEM-017 实现反思摘要格式化（Markdown）
- [ ] MEM-018 实现 `memory_injector.py` - 请求前自动注入记忆上下文

### 定时任务

- [ ] MEM-019 编写 `preference_loop.sh`
- [ ] MEM-020 设置 cron 定时任务（每日凌晨 2:00）
- [ ] MEM-021 实现 cron job 注册/注销管理

### Wrapper 脚本

- [ ] MEM-022 编写 `memory_remember.sh`
- [ ] MEM-023 编写 `memory_recall.sh`
- [ ] MEM-024 编写 `memory_set_reminder.sh`

### 测试

- [ ] MEM-025 单元测试：记忆 CRUD 全流程
- [ ] MEM-026 单元测试：语义检索召回率（Top-5 > 90%）
- [ ] MEM-027 单元测试：自然语言时间解析准确率
- [ ] MEM-028 单元测试：即时偏好检测
- [ ] MEM-029 单元测试：记忆衰减/强化逻辑
- [ ] MEM-030 集成测试：跨会话记忆注入
- [ ] MEM-031 集成测试：提醒到期推送

---

## 3. 写作润色翻译 Subagent

详细设计：`docs/add/add-writing.md`

### 模板系统

- [ ] WRT-001 创建 `templates/` 目录
- [ ] WRT-002 编写 `weekly_report.md` 模板
- [ ] WRT-003 编写 `email_formal.md` 模板
- [ ] WRT-004 编写 `tech_doc.md` 模板
- [ ] WRT-005 编写 `meeting_minutes.md` 模板
- [ ] WRT-006 编写 `article.md` 模板
- [ ] WRT-007 编写 `ppt_outline.md` 模板

### 核心引擎

- [ ] WRT-008 实现 `writing_engine.py` - `generate()` 主函数
- [ ] WRT-009 实现偏好注入：调用 `memory_engine.recall()`
- [ ] WRT-010 实现模板加载与渲染
- [ ] WRT-011 实现 prompt 构造（system + user）
- [ ] WRT-012 实现上游 LLM 调用（httpx -> OpenAI-compatible API）
- [ ] WRT-013 实现 `polish()` - 润色 prompt + 偏好注入
- [ ] WRT-014 实现 `translate()` - 翻译 prompt + 格式保持
- [ ] WRT-015 实现 `changes_summary` 生成
- [ ] WRT-016 实现 `humanize()` - AI痕迹识别 + 三级强度改写

### Wrapper 脚本

- [ ] WRT-017 编写 `writing_generate.sh`
- [ ] WRT-018 编写 `writing_polish.sh`
- [ ] WRT-019 编写 `writing_translate.sh`
- [ ] WRT-020 编写 `writing_humanize.sh`

### 测试

- [ ] WRT-021 单元测试：模板渲染正确性
- [ ] WRT-022 单元测试：prompt 构造（偏好注入验证）
- [ ] WRT-023 集成测试：generate -> 格式符合偏好
- [ ] WRT-024 集成测试：translate -> 格式保持
- [ ] WRT-025 集成测试：polish -> goal 匹配
- [ ] WRT-026 集成测试：humanize -> 去AI化效果（三级强度对比）
- [ ] WRT-027 集成测试：上游 LLM 不可用时的降级处理

---

## 4. 日程与任务 Subagent

详细设计：`docs/add/add-schedule.md`

### 数据层

- [ ] SCH-001 创建 SQLite 表 `events`
- [ ] SCH-002 创建 SQLite 表 `tasks`
- [ ] SCH-003 创建索引
- [ ] SCH-004 实现 `tasks.parent_task_id` 外键约束与子任务查询

### 时间解析

- [ ] SCH-005 封装 `parse_time()` - dateparser 自然语言解析
- [ ] SCH-006 实现时间范围快捷映射：today/tomorrow/this_week/next_week/all
- [ ] SCH-007 实现时间格式标准化（ISO 8601，时区 Asia/Shanghai）
- [ ] SCH-008 处理时间解析失败（错误提示 + 原始输入回显）

### 日程 CRUD

- [ ] SCH-009 实现 `create_event()` - 解析时间 -> 写入 events -> 同步记忆
- [ ] SCH-010 实现 `query_events()` - 多条件过滤
- [ ] SCH-011 实现 `get_due_events()` - 检查到期事件
- [ ] SCH-012 实现事件状态更新
- [ ] SCH-013 实现到期提醒触发（联动 memory_engine）

### 任务 CRUD

- [ ] SCH-014 实现 `create_task()` - 解析 due_date -> 写入 tasks -> 同步记忆
- [ ] SCH-015 实现 `list_tasks()` - 多条件过滤
- [ ] SCH-016 实现 `complete_task()` - 更新状态
- [ ] SCH-017 实现子任务关联查询
- [ ] SCH-018 实现任务状态流转

### Wrapper 脚本

- [ ] SCH-019 编写 `schedule_create_event.sh`
- [ ] SCH-020 编写 `schedule_query.sh`
- [ ] SCH-021 编写 `schedule_create_task.sh`
- [ ] SCH-022 编写 `schedule_list_tasks.sh`
- [ ] SCH-023 编写 `schedule_complete_task.sh`

### 测试

- [ ] SCH-024 单元测试：时间解析（中文自然语言）
- [ ] SCH-025 单元测试：时间范围映射
- [ ] SCH-026 单元测试：事件 CRUD 全流程
- [ ] SCH-027 单元测试：任务 CRUD 全流程
- [ ] SCH-028 单元测试：子任务关联查询
- [ ] SCH-029 单元测试：tags 过滤逻辑
- [ ] SCH-030 集成测试：create_event -> query_events 端到端
- [ ] SCH-031 集成测试：create_task -> list_tasks -> complete_task 端到端
- [ ] SCH-032 集成测试：到期提醒联动
- [ ] SCH-033 集成测试：与记忆 Subagent 协同

---

## 5. 闲聊陪伴 Subagent

详细设计：`docs/add/add-chat.md`

### 意图识别

- [ ] CHT-001 实现闲聊意图判断规则引擎（5 条规则）
- [ ] CHT-002 实现消息分类器：greeting/emotion/entertainment/simple_qa/complex
- [ ] CHT-003 实现 mood 自动检测
- [ ] CHT-004 实现误判保护：complex 类消息禁止路由到 chat_light

### 响应生成

- [ ] CHT-005 实现路由模型直回 prompt 构造（含 mood 策略）
- [ ] CHT-006 实现记忆注入上下文拼接
- [ ] CHT-007 实现 Completion Check permissive 模式配置
- [ ] CHT-008 实现响应后处理（表情符号适当化、长度控制）

### Wrapper 脚本

- [ ] CHT-009 编写 `chat_light.sh`

### 测试

- [ ] CHT-010 单元测试：5 类意图识别准确率
- [ ] CHT-011 单元测试：mood 自动检测
- [ ] CHT-012 单元测试：complex 消息误判保护
- [ ] CHT-013 集成测试：闲聊延迟 < 3s
- [ ] CHT-014 集成测试：记忆注入
- [ ] CHT-015 集成测试：连续 10 轮闲聊不走上游 LLM

---

## 6. 即时偏好引擎（跨 Subagent）

详细设计：`docs/add/add-memory.md` §3.2

- [ ] PREF-001 实现 `detect_and_store_preference()` - 即时偏好检测 + 同步写入
- [ ] PREF-002 实现 `compute_interaction_stats()` - Subagent 频次/关键词统计
- [ ] PREF-003 实现记忆衰减/强化逻辑（access_count + 时间规则）
- [ ] PREF-004 实现即时偏好注入（请求前自动注入）
- [ ] PREF-005 实现 cron 定时维护任务（轻量版）
- [ ] PREF-006 测试：跨会话偏好注入 [目标: 第 2 轮自动注入率 >90%]

---

## 7. 系统集成

- [ ] SYS-001 合入 MTClaw 仓库 subagents/ 目录结构
- [ ] SYS-002 扩展 MTClaw install.sh（支持 Prometheus Subagent 安装）
- [ ] SYS-003 聚合 functions.jsonl（5 Subagent 工具定义合并）
- [ ] SYS-004 配置路由模型 + 上游模型
- [ ] SYS-005 端到端验证：单轮对话 5 种领域路由
- [ ] SYS-006 路由准确率测试套件（50 条混合意图）
- [ ] SYS-007 路由追踪面板 route_tracer.html
- [ ] SYS-008 演示剧本排练（10 轮连续对话 + 进化演示）
- [ ] SYS-009 样本数据准备（笔记/CSV/周报范例）
- [ ] SYS-010 写作模板创建（7 个）
- [ ] SYS-011 一键安装流程验证
- [ ] SYS-012 演示录屏备份
