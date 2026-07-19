# Prometheus 实现 Checklist

> 最后更新：2026-07-19
> 统一进度追踪文件。所有 Subagent 的实现任务汇总在此。
> 详细设计见 `docs/add/` 下各 ADD 文档。

---

## 总览

| Subagent / 模块 | 任务数 | 已完成 | 进行中 | 未开始 | 完成率 |
|----------------|--------|--------|--------|--------|--------|
| RAG 知识库 | 24 | 0 | 0 | 24 | 0% |
| 记忆与偏好 | 31 | 0 | 0 | 31 | 0% |
| 写作润色翻译 | 27 | 0 | 0 | 27 | 0% |
| 日程与任务 | 33 | 0 | 0 | 33 | 0% |
| 闲聊陪伴 | 15 | 0 | 0 | 15 | 0% |
| Router 自学习引擎 | 46 | 0 | 0 | 46 | 0% |
| 即时偏好引擎（辅助） | 6 | 0 | 0 | 6 | 0% |
| Skills 三级加载 | 40 | 0 | 0 | 40 | 0% |
| 系统集成 | 11 | 0 | 0 | 11 | 0% |
| **合计** | **233** | **0** | **0** | **233** | **0%** |

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

## 6. Router 自学习引擎（跨 Subagent，赛题加分项核心）

详细设计：`docs/add/add-router-learning.md`

### 数据层

- [ ] RL-001 创建 SQLite 表 `routing_decisions`（id, timestamp, session_id, user_input, input_features, top1_route, top1_confidence, top2_route, top2_confidence, final_route, routing_layer, correction_type）
- [ ] RL-002 创建 SQLite 表 `routing_corrections`（id, decision_id, original_route, corrected_route, correction_type, applied_adjustments）
- [ ] RL-003 创建 SQLite 表 `routing_keyword_weights`（keyword, subagent, weight, hit_count, last_updated）
- [ ] RL-004 创建 SQLite 表 `routing_prompt_fragments`（pattern_hash, fragment_text, hit_count, created_at, last_used）
- [ ] RL-005 创建 SQLite 表 `subagent_priority`（subagent, base_priority, dynamic_adjustment, last_updated）
- [ ] RL-006 创建 SQLite 表 `routing_thresholds`（threshold_name, value, last_calibrated, calibration_reason）
- [ ] RL-007 创建索引（timestamp / session_id / corrected_route）

### 置信度评分

- [ ] RL-008 实现 `score_confidence()` - 从路由模型 logprob 计算置信度
- [ ] RL-009 实现简化方案（logprob 不可用时，用 top-1 单一概率）
- [ ] RL-010 实现置信度阈值配置加载（high=0.75, low=0.45）

### 双层路由

- [ ] RL-011 实现 `decide_route_layer()` - 路由层级决策（L1_auto / L1_low_confidence / L2_confirm）
- [ ] RL-012 实现 `generate_clarification()` - 澄清问题生成（基于 top-2 候选）
- [ ] RL-013 实现 Subagent user_friendly_name 映射（rag_search -> "查文档" 等）
- [ ] RL-014 实现 L2 确认路由的交互流程（多轮对话）
- [ ] RL-015 实现"用户连续 3 次弃权"的处理（默认走 top-1 + 标记）

### 用户修正反馈

- [ ] RL-016 实现 `detect_correction()` - 纠正意图识别（4 种模式："不是...我是要" / "不对...我要" / "我说的是...不是" / "错了...应该"）
- [ ] RL-017 实现 `record_routing_decision()` - 路由决策记录
- [ ] RL-018 实现 `record_correction()` - 修正记录
- [ ] RL-019 实现 input_features 提取（关键词 / 长度 / 路径 / 技术名词检测）

### 路由策略动态调整

- [ ] RL-020 实现 `adjust_keyword_weights()` - 关键词权重调整（同类修正 ≥ 2 次触发）
- [ ] RL-021 实现 `update_prompt_fragments()` - 提示词片段更新（累积 ≥ 3 次触发）
- [ ] RL-022 实现 `adjust_subagent_priority()` - 优先级调整（50 次窗口统计）
- [ ] RL-023 实现 `calibrate_thresholds()` - 阈值校准（每日 cron + ≥ 10 次修正）
- [ ] RL-024 实现 `build_dynamic_routing_prompt()` - 动态提示词构造（基础 + 权重 + 片段 top 5）

### MTClaw FR 集成（分层）

> 分层落点：FR 仅暴露 logprob（通用），Prometheus 外层做置信度决策与自学习（差异化）。详见 `add-router-learning.md` §3.6。

**FR 层（配置 / 上游贡献）**：
- [ ] RL-026 [FR·配置] 路由调用启用 logprobs=true + 验证响应是否透传路由模型 logprob（若否，提小 PR 让 FR 透传，通用能力）

**Prometheus 层（包装 FR，差异化）**：
- [ ] RL-025 路由前构造动态路由提示词注入 FR（关键词权重 + 历史修正示例 top5）
- [ ] RL-027 路由后置信度评估 + 双层路由决策（读 FR logprob，§3.1/§3.2）
- [ ] RL-028 路由决策记录到 routing_decisions
- [ ] RL-029 路由后修正检测 + 策略调整触发（§3.4）

### CLI

- [ ] RL-030 实现 `prometheus router stats` - 查看自学习状态
- [ ] RL-031 实现 `prometheus router reset` - 重置学习数据
- [ ] RL-032 实现 `prometheus router learning on/off` - 开关自学习
- [ ] RL-033 实现 `prometheus router export <path>` - 导出学习数据
- [ ] RL-034 实现 `prometheus router calibrate` - 手动触发阈值校准

### 测试

- [ ] RL-035 单元测试：置信度计算（logprob 输入 -> 置信度，误差 < 0.02）
- [ ] RL-036 单元测试：路由层级决策（3 个阈值区间）
- [ ] RL-037 单元测试：澄清问题生成（top-2 候选）
- [ ] RL-038 单元测试：纠正意图识别（4 种模式）
- [ ] RL-039 单元测试：input_features 提取
- [ ] RL-040 集成测试：L2 确认路由端到端
- [ ] RL-041 集成测试：修正触发关键词权重调整
- [ ] RL-042 集成测试：修正触发提示词片段更新
- [ ] RL-043 集成测试：优先级统计调整
- [ ] RL-044 集成测试：阈值校准（高置信度被修正率驱动）
- [ ] RL-045 集成测试：动态提示词构造（基础 + 权重 + 片段）
- [ ] RL-046 演示验证：5 轮进化剧本（误判 -> 修正 -> 自动正确路由）

---

## 6.5 即时偏好引擎（辅助机制）

详细设计：`docs/add/add-memory.md` §3.2

- [ ] PREF-001 实现 `detect_and_store_preference()` - 即时偏好检测 + 同步写入（"以后都"/"我喜欢"/"记住了"/"不要"/"总是"）
- [ ] PREF-002 实现 `compute_interaction_stats()` - Subagent 频次/关键词统计
- [ ] PREF-003 实现记忆衰减/强化逻辑（access_count + 时间规则）
- [ ] PREF-004 实现即时偏好注入（请求前自动注入到 Subagent 的内容生成 prompt）
- [ ] PREF-005 实现 cron 定时维护任务（轻量版，每日凌晨 2:00）
- [ ] PREF-006 测试：跨会话偏好注入 [目标: 第 2 轮自动注入率 >90%]

---

## 7. 系统集成

- [ ] SYS-001 合入 MTClaw 仓库 subagents/ 目录结构
- [ ] SYS-002 扩展 MTClaw install.sh（支持 Prometheus Subagent 安装 + 预置系统级技能拷到 `~/.function-router/skills`，详见 §8 SKL-030）
- [ ] SYS-003 聚合 functions.jsonl（安装时静态聚合 5 个官方 Subagent 工具定义；技能 builtin 注册见 §8 SKL-021）
- [ ] SYS-004 配置路由模型 + 上游模型（路由模型启用 logprobs=true）
- [ ] SYS-005 端到端验证：单轮对话 5 种领域路由
- [ ] SYS-006 路由准确率测试套件（50 条混合意图）
- [ ] SYS-007 演示剧本排练（10 轮连续对话 + 5 轮进化演示 + 技能三级覆盖演示）
- [ ] SYS-008 样本数据准备（笔记/CSV/周报范例）
- [ ] SYS-009 写作模板创建（7 个）
- [ ] SYS-010 一键安装流程验证
- [ ] SYS-011 演示录屏备份

---

## 8. Skills 三级加载（赛题扩展性创新点）

详细设计：`docs/add/add-skills.md`

### 数据层

- [ ] SKL-001 定义 `SKILL.md` frontmatter schema（JSON Schema）
- [ ] SKL-002 定义 `SkillRecord` 数据结构（skill + tier + source_path + overridden_by）
- [ ] SKL-003 创建 `~/.prometheus/skills/.skills_index.json` 索引快照格式
- [ ] SKL-004 创建 `config.skills` 配置 schema（tier_dirs / disabled / limits）

### 加载与优先级

- [ ] SKL-005 实现 `parse_skill_md()` - frontmatter 解析（YAML）
- [ ] SKL-006 实现 `validate_skill_manifest()` - name/description 校验
- [ ] SKL-007 实现三级目录扫描（system -> user -> project）
- [ ] SKL-008 实现后写覆盖优先级（Map by name，project > user > system）
- [ ] SKL-009 实现覆盖链标注（`list_overrides()`）
- [ ] SKL-010 实现路径解析（环境变量覆盖 + 项目级相对 cwd）
- [ ] SKL-011 实现禁用过滤（config.skills.disabled）

### 发现与调用

- [ ] SKL-012 实现 `get_skill_index()` - Tier-1 索引构建
- [ ] SKL-013 实现按 Subagent 过滤（applies_to 三态语义）
- [ ] SKL-014 实现 `<available_skills>` 提示词片段渲染
- [ ] SKL-015 实现 `load_skill()` - Tier-2 正文加载
- [ ] SKL-016 实现 `load_skill(file_path=)` - Tier-3 引用文件加载
- [ ] SKL-017 实现索引快照写入/读取（加速重启）

### FR 集成（分层）

> 分层落点：FR 暴露 `skill_load`/`skills_list` 通用 builtin（可上游贡献），普罗米修斯外层做三级优先级与注入（差异化）。详见 `add-skills.md` §3.7。

**FR 层（通用能力）**：
- [ ] SKL-018 [FR·配置] FR 暴露 `skill_load` / `skills_list` builtin 工具（若 MTClaw 无，提小 PR 补充）

**普罗米修斯层（差异化）**：
- [ ] SKL-019 FR 启动时调用 `load_all_skills()` 扫描三级目录
- [ ] SKL-020 将 Tier-1 索引注入路由提示词 `<available_skills>`
- [ ] SKL-021 注册 `skill_load`/`skills_list` 到 functions.jsonl
- [ ] SKL-022 实现 `POST /v1/reload` 触发技能重载

### CLI

- [ ] SKL-023 实现 `prometheus skills list`（含 --tier / --category 过滤）
- [ ] SKL-024 实现 `prometheus skills info <name>`（含覆盖链展示）
- [ ] SKL-025 实现 `prometheus skills paths`
- [ ] SKL-026 实现 `prometheus skills create <name>`（骨架生成）
- [ ] SKL-027 实现 `prometheus skills reload`
- [ ] SKL-028 实现 `prometheus skills enable/disable`
- [ ] SKL-029 实现 `prometheus skills doctor`（诊断冲突/非法/孤儿）

### 预置与演示

- [ ] SKL-030 预置 5 个系统级技能（weekly-report-zh / meeting-minutes-zh / note-tagging / task-eisenhower / polish-academic）
- [ ] SKL-031 准备演示用用户级覆盖技能（weekly-report-zh 含签名档）
- [ ] SKL-032 准备演示用项目级覆盖技能（weekly-report-zh 含里程碑章节）
- [ ] SKL-033 演示剧本：三级覆盖 + 项目上下文自适应

### 测试

- [ ] SKL-034 单元测试：SKILL.md 解析（合法/非法 frontmatter）
- [ ] SKL-035 单元测试：三级优先级覆盖（同名 project>user>system）
- [ ] SKL-036 单元测试：按 Subagent 过滤（applies_to 三态）
- [ ] SKL-037 单元测试：路径解析（环境变量 + cwd 相对）
- [ ] SKL-038 集成测试：skill_load 端到端（路由 -> 加载 -> 注入 -> 生成）
- [ ] SKL-039 集成测试：FR 热重载（新增技能后立即可用）
- [ ] SKL-040 集成测试：项目切换后技能集变化（项目级回退用户级）
