# ADD - Router 自学习引擎

> 版本：v1.0 | 日期：2026-07-14 | 状态：draft | 模块名：`router_learning`
>
> **对应赛题加分项**："Router 自学习：根据用户使用习惯动态优化分发策略"

## 1. 背景

### 1.1 问题描述

赛题加分项明确要求"Router 自学习：根据用户使用习惯**动态优化分发策略**"。这意味着 Router 不能只是静态地执行预设路由规则，而必须能够：

1. 感知用户的使用习惯（哪些输入被路由到哪里）
2. 识别路由错误（用户修正行为）
3. 动态调整路由策略（让同类输入下次自动路由到正确目标）

### 1.2 v3.0 之前的设计缺陷

v3.0 早期方案中的"即时偏好引擎"只实现了**偏好记忆注入**（用户说"以后都用 Markdown" -> 写入 memory -> 下次生成时注入 prompt），这解决的是"内容生成偏好"问题，**不是路由策略优化**。路由提示词、关键词权重、Subagent 优先级都没有动。

评委对照赛题原文会发现答非所问，这一加分项可能拿不到分。

### 1.3 新设计核心

将 Router 自学习拆解为四个机制：

| 机制 | 作用 | 演示效果 |
|------|------|---------|
| **路由置信度评分** | 路由模型输出 top-1 路由 + 置信度 | 量化路由决策的把握程度 |
| **双层路由** | 低置信度时主动询问用户 | 避免误路由，建立信任 |
| **用户修正反馈** | 记录用户的路由修正行为 | 收集自学习训练数据 |
| **路由策略动态调整** | 根据修正数据调整关键词权重 / 提示词 / 优先级 | 真正的"动态优化分发策略" |

即时偏好引擎（v3.0 早期）降级为**辅助机制**，仍负责偏好记忆注入，但不再是 Router 自学习的核心实现。详见 [add-memory.md](add-memory.md) §3.2。

## 2. 调研

### 2.1 MTClaw Function Router

- **路由模型**：qwen3-30b，temperature=0.0，function calling 模式
- **工具定义加载**：通过 `--functions-file` 加载聚合后的 functions.jsonl
- **路由输出**：top-1 工具调用 + 参数（标准 OpenAI function calling 格式）
- **logprob 可获取性**：OpenAI-compatible 接口支持 `logprobs=true`，可拿到候选 token 的对数概率

> ⚠️ **待验证**：FR 的 `logprobs=true` 返回的是**路由模型（qwen3-30b）对工具名 token 的 logprob**，还是上游 LLM 的 logprob？本引擎依赖前者（路由决策置信度）。
> - 若已暴露路由模型 logprob -> Prometheus 外层读取即可，**无需改 FR 核心**
> - 若未暴露 -> 唯一需要"融入 FR"的改动：让 FR 把路由 logprob 透传到响应（一个很小的上游 PR）

### 2.2 Codex ToolRouter

- `~/ws/codex/codex-rs/tool-router/` - 工具路由分发
- 路由失败时有 fallback 机制（默认工具或询问用户）
- **可参考点**：路由失败的优雅降级

### 2.3 OpenClaw ToolAvailabilitySignal

- `~/ws/openclaw/src/` - 工具可用性信号模型
- 根据工具历史成功率动态调整工具的可用性评分
- **可参考点**：基于历史数据的动态权重调整

### 2.4 结论

**概念区分**：MTClaw FR 提供的是 logprob（原始信号），不是"置信度"。置信度评分（logprob 派生的归一化分数）、双层路由决策、修正反馈与策略自学习均为 Prometheus 的增量，FR 本身不具备。

**分层落点**（详见 §3.6）：
- **FR 层（上游贡献）**：仅暴露路由模型 logprob（通用能力，所有 FR 用户受益）
- **Prometheus 层（包装 FR，不改 FR 核心）**：置信度计算 + 双层路由决策 + 决策/修正记录 + 策略自学习（赛题加分项核心差异化，耦合 Prometheus 的 Subagent 集合，不下沉到 FR）

Codex 的路由失败降级和 OpenClaw 的动态权重调整提供了自学习的实现参考。本设计将二者结合：置信度驱动双层路由 + 历史修正驱动策略调整。

## 3. 设计决策

### 3.1 路由置信度评分

```
路由模型调用 (temperature=0.0, logprobs=true, top_logprobs=5)
  │
  ├── 输出: top-1 工具调用 (如 "rag_search")
  └── 输出: 候选工具的 logprob 分布
       ├── rag_search:        logprob = -0.42  (prob ≈ 0.66)
       ├── memory_recall:     logprob = -1.13  (prob ≈ 0.32)
       ├── chat_light:        logprob = -5.31  (prob ≈ 0.005)
       └── others:            logprob < -8.0

置信度计算:
  confidence = exp(logprob_top1) / sum(exp(logprob_i))
             = 0.66 / (0.66 + 0.32 + 0.005 + ...)
             = 0.671

简化方案 (如果 logprob 不可用):
  confidence = exp(logprob_top1)  # 单一 top-1 概率
```

**置信度阈值**（初始值，可由 §3.4 自学习校准）：

| 阈值 | 默认值 | 含义 |
|------|--------|------|
| `high_threshold` | 0.75 | 高于此值直接自动路由（L1） |
| `low_threshold` | 0.45 | 低于此值触发用户确认（L2） |
| 中间区 | 0.45 ~ 0.75 | 默认走 top-1，但标记为"低置信度"用于学习 |

### 3.2 双层路由（Dual-Layer Routing）

```
用户输入
  │
  ▼
路由模型 (logprobs=true)
  │
  ├── 置信度 ≥ 0.75 (高置信度)
  │     └── L1 自动路由: 直接路由到 top-1 Subagent
  │
  ├── 0.45 ≤ 置信度 < 0.75 (中间区)
  │     └── L1 自动路由 (默认走 top-1) + 标记 low_confidence=true
  │         └── 如果用户后续修正, 记录为高价值学习样本
  │
  └── 置信度 < 0.45 (低置信度)
        └── L2 确认路由: 主动询问用户
              │
              ├── 系统生成澄清问题:
              │     "你是想[查文档]还是[闲聊]? (1/2)"
              │     (基于 top-2 候选 Subagent 生成选项)
              │
              ├── 用户选择 -> 路由到用户指定的 Subagent
              │
              └── 记录修正 (top-1 -> 用户选择)
```

**澄清问题生成规则**：

```
top-2 候选 Subagent 提取
  │
  ├── 基于 Subagent 的 user_friendly_name 字段生成选项
  │     rag_search      -> "查文档"
  │     memory_recall   -> "查记忆"
  │     writing_generate -> "写文档"
  │     schedule_query  -> "查日程"
  │     chat_light      -> "闲聊"
  │
  └── 模板: "你是想[{option_1}]还是[{option_2}]? (1/2)"

特殊处理:
  - 如果 top-2 中包含兜底 (上游 LLM) -> 改为三选一
  - 如果用户连续 3 次不选 -> 默认走 top-1 + 标记为"用户弃权"
```

**误判保护**（沿用 v3.0 闲聊 Subagent 的保守策略）：

```
complex 类消息绝对不触发 L2 确认路由直接走闲聊:
  - 包含文件路径 / 文件扩展名 -> 禁止路由到 chat_light
  - 包含 "为什么" + 专业术语 -> 禁止路由到 chat_light
  - 消息长度 > 200 字 -> 禁止路由到 chat_light
  - 任何不确定 -> 走上游 LLM (兜底永远安全)

这些规则作为路由提示词的硬约束, 优先于置信度判断。
```

### 3.3 用户修正反馈

**修正触发场景**：

| 场景 | 触发方式 | 处理 |
|------|---------|------|
| A. L2 确认后用户选择 | 用户回答澄清问题 | 记录 (top-1 -> 用户选择) |
| B. L1 路由后用户纠正 | 用户说"不对，我要查文档" | 路由模型识别纠正意图 -> 重新路由 -> 记录修正 |
| C. 用户主动澄清 | 用户说"不是闲聊，我是要..." | 检测澄清意图 -> 重新路由 -> 记录修正 |
| D. 用户弃权 | L2 连续 3 次不选 | 不记录修正，但记录"低置信度弃权"事件 |

**修正记录结构**：

```python
# routing_corrections 表
{
    "id": "rc_001",
    "timestamp": "2026-07-14T10:23:45",
    "session_id": "sess_abc",
    "user_input": "帮我看看 GPU 算力对比",
    "input_features": {
        "keywords": ["帮我看看", "GPU", "算力", "对比"],
        "length": 14,
        "has_path": false,
        "has_file_ext": false,
        "has_tech_term": true,
        "message_type": "command"  # command / question / greeting / ...
    },
    "original_route": "chat_light",
    "original_confidence": 0.42,
    "corrected_route": "rag_search",
    "correction_type": "L2_confirm",  # L2_confirm / L1_correct / user_initiated
    "applied_adjustments": []  # 学习调整应用记录
}
```

**纠正意图识别**（场景 B/C）：

```python
def detect_correction(user_message: str, last_route: str) -> bool:
    """检测用户是否在纠正上一轮的路由决策"""
    correction_patterns = [
        r"不是.{1,10}我是要",
        r"不对.{0,5}我要",
        r"我说的是.{1,15}不是",
        r"错了.{0,5}应该",
    ]
    return any(re.search(p, user_message) for p in correction_patterns)
```

### 3.4 路由策略动态调整（核心自学习）

这是"动态优化分发策略"的真正实现。四种调整机制：

#### 3.4.1 关键词权重调整

```
触发条件: 同类修正累积 ≥ 2 次
  (同类 = input_features 相似度 > 0.8)

调整逻辑:
  从修正记录提取 input_features.keywords
    -> 提升 keywords 在 corrected_route Subagent 的触发权重
    -> 降低 keywords 在 original_route Subagent 的触发权重

实现:
  SQLite 表 routing_keyword_weights
    (keyword, subagent, weight, last_updated)
  
  路由提示词动态拼接:
    "关键词权重提示:
     - '帮我看看' + 技术名词 -> 倾向 RAG (weight=1.4)
     - '帮我看看' + 情感词 -> 倾向 chat_light (weight=0.9)
     ..."
  
  路由模型看到这些提示后, 路由决策会向权重高的方向偏移

示例:
  修正 1: "帮我看看 GPU 算力" (chat_light -> rag_search)
  修正 2: "帮我看看 模型对比" (chat_light -> rag_search)
  -> 提取模式: "帮我看看" + 技术名词 -> RAG
  -> 路由提示词加入此规则
  -> 第 3 次 "帮我看看 最新论文" 自动路由到 RAG
```

#### 3.4.2 路由提示词动态增强

```
触发条件: 累积 ≥ 3 次同类修正

调整逻辑:
  将高频修正模式转化为路由示例, 注入路由提示词
  
实现:
  routing_prompt_fragments 表
    (pattern_hash, fragment_text, hit_count, created_at)
  
  路由提示词构造:
    base_prompt = "<基础路由提示词>"
    user_fragments = load_top_fragments(limit=5)  # 按命中次数排序
    full_prompt = base_prompt + "\n\n用户历史修正示例:\n" + "\n".join(user_fragments)

示例:
  路由提示词尾部追加:
    "用户历史修正:
     - '帮我看看' + 技术名词 -> 优先 RAG (用户曾 2 次纠正)
     - '写一下' + 文档类型 -> 优先 writing_generate (用户曾 3 次纠正)
     - 长消息(>200字) + 疑问句 -> 优先上游 LLM (用户曾 2 次纠正)"
```

#### 3.4.3 Subagent 优先级调整

```
触发条件: 统计窗口 (最近 50 次路由) 中某 Subagent 命中率 > 40%

调整逻辑:
  高频 Subagent 优先级 +1
  低频 Subagent (命中率 < 5%) 优先级 -1
  
实现:
  SQLite 表 subagent_priority
    (subagent, base_priority, dynamic_adjustment, last_updated)
  
  effective_priority = base_priority + dynamic_adjustment
  范围限制: [1, 6] (避免极端值)

示例:
  用户最近 50 次路由: RAG 25次 / 写作 12次 / 闲聊 8次 / 日程 3次 / 记忆 2次
  -> RAG 优先级 +1 (从 P4 升到 P3)
  -> 记忆优先级 -1 (从 P1 降到 P2)
  -> 同等置信度下, RAG 优先于原 P3 的 Subagent
```

#### 3.4.4 置信度校准

```
触发条件: 每日凌晨维护 (cron) + 累积 ≥ 10 次修正

调整逻辑:
  分析历史修正数据:
    - 高置信度 (≥0.75) 但被修正的样本 -> 说明阈值过高
    - 低置信度 (<0.45) 但用户弃权的样本 -> 说明阈值合适
  
  动态调整:
    if 高置信度被修正率 > 10%:
        high_threshold += 0.05  (提高门槛, 更谨慎)
    if 低置信度弃权率 > 30%:
        low_threshold -= 0.05   (放宽, 减少打扰)

实现:
  routing_thresholds 表
    (threshold_name, value, last_calibrated, calibration_reason)
```

### 3.5 学习数据存储

```
SQLite 表 (router_learning.db):
  ├── routing_decisions         # 所有路由决策记录
  │   (id, timestamp, session_id, user_input, input_features,
  │    top1_route, top1_confidence, top2_route, top2_confidence,
  │    final_route, routing_layer, correction_type)
  │
  ├── routing_corrections       # 用户修正记录
  │   (id, decision_id, original_route, corrected_route,
  │    correction_type, applied_adjustments)
  │
  ├── routing_keyword_weights   # 关键词权重 (动态)
  │   (keyword, subagent, weight, hit_count, last_updated)
  │
  ├── routing_prompt_fragments  # 提示词片段 (动态)
  │   (pattern_hash, fragment_text, hit_count, created_at, last_used)
  │
  ├── subagent_priority         # 优先级调整 (动态)
  │   (subagent, base_priority, dynamic_adjustment, last_updated)
  │
  └── routing_thresholds        # 置信度阈值 (动态校准)
      (threshold_name, value, last_calibrated, calibration_reason)
```

### 3.6 与 MTClaw FR 的集成（分层落点）

采用**分层架构**：FR 保持通用 Function Router 定位，Prometheus 在外层包装做置信度决策与自学习，不把学习逻辑下沉到 FR 核心。

```
请求处理流程（分两层）:

【FR 层 · MTClaw 核心，通用】
  │
  ├── [FR 配置] 加载 functions.jsonl + 路由提示词（--functions-file）
  ├── [FR 配置] 路由调用启用 logprobs=true
  ├── FR 调用路由模型 (qwen3-30b, temperature=0.0)
  │     └── 输出: top-1 工具调用 + 候选工具 logprob 分布
  ├── 工具调用执行
  └── ⚠️ 待验证: FR 响应是否透传路由模型 logprob？
        ├── 是 -> Prometheus 直接读取，无需改 FR 核心
        └── 否 -> [上游贡献] 让 FR 透传路由 logprob（小 PR，通用能力）

【Prometheus 层 · 包装 FR，差异化】
  │
  ├── 路由前: 构造动态路由提示词（注入 FR）
  │     ├── 基础路由提示词 (静态)
  │     ├── 关键词权重提示 (从 routing_keyword_weights)
  │     └── 用户历史修正示例 (从 routing_prompt_fragments, top 5)
  │
  ├── 路由后: 读 FR logprob -> 置信度计算 (§3.1) + 双层路由决策 (§3.2)
  │     ├── 置信度 ≥ 0.75 -> L1 自动路由
  │     ├── 0.45 ≤ 置信度 < 0.75 -> L1 自动路由 (标记低置信度)
  │     └── 置信度 < 0.45 -> L2 确认路由 (生成澄清问题)
  │
  ├── 路由决策记录到 routing_decisions
  │
  └── 路由后: 修正检测
        ├── 用户纠正意图检测
        ├── 如有修正 -> 记录 routing_corrections
        └── 触发策略调整 (3.4.1 / 3.4.2 / 3.4.3)
```

**为什么不把置信度/学习全塞进 FR**：阈值随用户数据动态校准、修正 schema 耦合 Prometheus 的 Subagent 集合、策略自学习是赛题加分项的核心差异化--下沉会污染通用路由器。FR 只承担"暴露 logprob"这件通用小事。

**比赛策略**：比赛期间 Prometheus 外层包装先跑通 demo（不依赖 upstream merge）；赛后把"FR 暴露路由 logprob"这件通用能力贡献回 MTClaw。

### 3.7 演示剧本（进化展示）

```
[演示 - 第 1 轮] 用户: "帮我看看 GPU 算力对比"
  系统: 路由模型置信度 0.42 (< 0.45)
        -> L2 确认路由: "你是想[查文档]还是[闲聊]? (1/2)"
  用户: "1" (查文档)
  系统: 路由到 RAG -> 检索 -> 返回结果
  记录: 修正 (chat_light -> rag_search), 置信度 0.42

[演示 - 第 2 轮] 用户: "帮我看看 模型对比"
  系统: 路由模型置信度 0.58 (中间区, 走 top-1)
        -> 路由到 chat_light (因为 top-1 仍是 chat_light)
  用户: "不对，我要查文档"
  系统: 识别纠正意图 -> 重新路由到 RAG
  记录: 修正 (chat_light -> rag_search), 置信度 0.58
  触发: 关键词权重调整 ("帮我看看" + 技术名词 -> RAG)

[演示 - 第 5 轮] 用户: "帮我看看 最新论文"
  系统: 路由提示词已注入 "用户历史: '帮我看看' + 技术名词 -> RAG"
        路由模型置信度 0.82 (≥ 0.75)
        -> L1 自动路由到 RAG
  用户零额外输入
  -> 展示"根据用户使用习惯动态优化分发策略"的核心效果
```

### 3.8 隐私与可控性

```
用户控制:
  ├── 查看学习数据: prometheus router stats
  │     -> 显示关键词权重 / 优先级调整 / 阈值校准
  ├── 重置学习: prometheus router reset
  │     -> 清空 routing_corrections / keyword_weights / fragments
  │     -> 保留 routing_decisions (历史记录)
  ├── 关闭自学习: prometheus router learning off
  │     -> 停止策略调整, 仅记录决策
  └── 导出学习数据: prometheus router export
        -> 导出为 JSON, 支持迁移到其他设备

数据本地化:
  所有学习数据存储于 ~/.prometheus/router_learning.db
  不上传云端, 不跨设备同步 (除非用户主动导出)
```

## 4. 模块规格

### 4.1 配置

```json
{
  "router_learning": {
    "enabled": true,
    "confidence_thresholds": {
      "high": 0.75,
      "low": 0.45
    },
    "adjustment_triggers": {
      "keyword_weight_min_samples": 2,
      "prompt_fragment_min_samples": 3,
      "priority_window_size": 50,
      "threshold_calibration_min_samples": 10
    },
    "max_prompt_fragments": 5,
    "priority_range": [1, 6]
  }
}
```

### 4.2 Python 引擎接口

```python
# router_learning_engine.py

def score_confidence(routing_model_output: dict) -> float:
    """从路由模型输出计算置信度"""

def decide_route_layer(confidence: float) -> str:
    """决定路由层级: L1_auto / L1_low_confidence / L2_confirm"""

def generate_clarification(top2_routes: list) -> str:
    """生成澄清问题"""

def detect_correction(user_message: str, last_route: str) -> bool:
    """检测用户纠正意图"""

def record_routing_decision(decision: dict) -> None:
    """记录路由决策"""

def record_correction(decision_id: str, corrected_route: str, correction_type: str) -> None:
    """记录用户修正"""

def adjust_keyword_weights(correction: dict) -> list:
    """调整关键词权重, 返回应用的调整列表"""

def update_prompt_fragments(correction: dict) -> list:
    """更新路由提示词片段"""

def adjust_subagent_priority() -> dict:
    """根据最近路由统计调整 Subagent 优先级"""

def calibrate_thresholds() -> dict:
    """校准置信度阈值 (每日 cron)"""

def build_dynamic_routing_prompt() -> str:
    """构造动态路由提示词 (基础 + 关键词权重 + 历史修正)"""

def get_router_stats() -> dict:
    """获取自学习统计数据 (供 CLI 展示)"""

def reset_learning_data() -> None:
    """重置学习数据 (保留历史决策)"""
```

### 4.3 CLI 命令

```bash
prometheus router stats          # 查看自学习状态
prometheus router reset          # 重置学习数据
prometheus router learning on    # 开启自学习
prometheus router learning off   # 关闭自学习 (仅记录不调整)
prometheus router export <path>  # 导出学习数据
prometheus router calibrate      # 手动触发阈值校准
```

## 5. 实现 Checklist

### 数据层

- [ ] RL-001 创建 SQLite 表 `routing_decisions`
- [ ] RL-002 创建 SQLite 表 `routing_corrections`
- [ ] RL-003 创建 SQLite 表 `routing_keyword_weights`
- [ ] RL-004 创建 SQLite 表 `routing_prompt_fragments`
- [ ] RL-005 创建 SQLite 表 `subagent_priority`
- [ ] RL-006 创建 SQLite 表 `routing_thresholds`
- [ ] RL-007 创建索引（timestamp / session_id / corrected_route）

### 置信度评分

- [ ] RL-008 实现 `score_confidence()` - 从路由模型 logprob 计算置信度
- [ ] RL-009 实现简化方案（logprob 不可用时，用 top-1 单一概率）
- [ ] RL-010 实现置信度阈值配置加载

### 双层路由

- [ ] RL-011 实现 `decide_route_layer()` - 路由层级决策
- [ ] RL-012 实现 `generate_clarification()` - 澄清问题生成
- [ ] RL-013 实现 Subagent user_friendly_name 映射
- [ ] RL-014 实现 L2 确认路由的交互流程（多轮对话）
- [ ] RL-015 实现"用户连续 3 次弃权"的处理

### 用户修正反馈

- [ ] RL-016 实现 `detect_correction()` - 纠正意图识别
- [ ] RL-017 实现 `record_routing_decision()` - 路由决策记录
- [ ] RL-018 实现 `record_correction()` - 修正记录
- [ ] RL-019 实现 input_features 提取（关键词 / 长度 / 路径 / 技术名词检测）

### 路由策略动态调整

- [ ] RL-020 实现 `adjust_keyword_weights()` - 关键词权重调整
- [ ] RL-021 实现 `update_prompt_fragments()` - 提示词片段更新
- [ ] RL-022 实现 `adjust_subagent_priority()` - 优先级调整
- [ ] RL-023 实现 `calibrate_thresholds()` - 阈值校准
- [ ] RL-024 实现 `build_dynamic_routing_prompt()` - 动态提示词构造

### MTClaw FR 集成（分层）

**FR 层（配置 / 上游贡献）**：
- [ ] RL-026 [FR·配置] 启用 logprobs=true + 验证响应是否透传路由模型 logprob（若否，提小 PR 让 FR 透传）

**Prometheus 层（包装 FR，差异化）**：
- [ ] RL-025 路由前构造动态路由提示词注入 FR（关键词权重 + 历史修正示例）
- [ ] RL-027 路由后置信度评估 + 双层路由决策（读 FR logprob）
- [ ] RL-028 路由决策记录到 routing_decisions
- [ ] RL-029 路由后修正检测 + 策略调整触发

### CLI

- [ ] RL-030 实现 `prometheus router stats`
- [ ] RL-031 实现 `prometheus router reset`
- [ ] RL-032 实现 `prometheus router learning on/off`
- [ ] RL-033 实现 `prometheus router export`
- [ ] RL-034 实现 `prometheus router calibrate`

### 测试

- [ ] RL-035 单元测试：置信度计算（logprob 输入 -> 置信度）
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

## 6. 与其他模块的关系

### 6.1 与即时偏好引擎（add-memory.md §3.2）的关系

| 机制 | 职责 | 关系 |
|------|------|------|
| Router 自学习引擎 | 优化**路由分发策略** | 决定"用户输入 -> 哪个 Subagent" |
| 即时偏好引擎 | 优化**内容生成偏好** | 决定"Subagent 生成内容时用什么格式/风格" |

两者独立工作，互不干扰。Router 自学习影响"路由到哪里"，即时偏好影响"到了之后怎么生成"。

### 6.2 与闲聊 Subagent 误判保护的关系

闲聊 Subagent 的 complex 消息禁止规则（[add-chat.md](add-chat.md)）作为**硬约束**，优先于置信度判断。即使置信度 ≥ 0.75，如果输入命中 complex 规则，也不会路由到 chat_light。

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 路由模型 logprob 不可用 | 实现简化方案（top-1 单一概率），并标注精度降低 |
| L2 确认路由打断演示流畅性 | 演示剧本预先准备 1-2 个 L2 场景，展示"建立信任"价值 |
| 自学习过度调整导致路由退化 | 优先级调整范围限制 [1,6]；关键词权重上限 2.0；提供 `router reset` |
| 学习样本不足时策略调整无效 | 设置最小样本数阈值（2/3/10），未达阈值不调整 |
| 动态提示词过长影响路由模型 | 限制 prompt_fragments 数量（top 5）+ 单片段长度（< 100 字符） |

## 8. 参考

- MTClaw Function Router: `https://github.com/MooreThreads/MTClaw`
- Codex ToolRouter: `~/ws/codex/codex-rs/tool-router/`
- OpenClaw ToolAvailabilitySignal: `~/ws/openclaw/src/`
- OpenAI logprobs 文档: `https://platform.openai.com/docs/api-reference/chat`
