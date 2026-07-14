# 路由准确率测试方法调研报告

> **报告编号**：报告9  
> **主题**：路由准确率测试方法  
> **项目**：普罗米修斯（Prometheus）— 基于 MTClaw Function Router 的自我进化型个人认知智能体  
> **版本**：v1.0 | **日期**：2026-07-14  
> **调研范围**：LLM function calling 评测方法、50 条测试集设计、评测指标体系、A/B 测试方法、pytest 集成、可视化方案

---

## 目录

1. [调研背景与目标](#1-调研背景与目标)
2. [LLM Function Calling 评测方法综述](#2-llm-function-calling-评测方法综述)
3. [50 条测试集设计](#3-50-条测试集设计)
4. [评测指标体系](#4-评测指标体系)
5. [A/B 测试方法](#5-ab-测试方法)
6. [pytest 集成方案](#6-pytest-集成方案)
7. [可视化方案](#7-可视化方案)
8. [与 Prometheus 现有设计的衔接](#8-与-prometheus-现有设计的衔接)
9. [实施计划与 Checklist](#9-实施计划与-checklist)
10. [风险与缓解](#10-风险与缓解)
11. [参考来源](#11-参考来源)

---

## 1. 调研背景与目标

### 1.1 项目背景

Prometheus 通过 MTClaw Function Router 将用户意图精准分发到 5 个 Subagent（RAG 知识库 / 记忆与偏好 / 写作润色翻译 / 日程与任务 / 闲聊陪伴），路由准确率是项目核心指标之一：

- **初始路由准确率目标**：> 90% [目标]（50 条混合意图自动分发）
- **自学习后路由准确率目标**：> 95% [目标]
- **双层路由误判率目标**：< 8% [目标]

### 1.2 调研目标

本报告调研业界 LLM function calling 路由准确率评测的成熟方法，为 Prometheus 设计一套完整的、可执行的测试方案，覆盖：

| 维度 | 具体内容 |
|------|---------|
| 评测方法 | LLM function calling 评测的业界实践（τ-bench / BFCL / ToolBench 等） |
| 测试集设计 | 50 条混合意图测试集的结构、标注、覆盖度 |
| 评测指标 | 准确率、精确率、召回率、F1、误判率、置信度分布 |
| A/B 测试 | 路由策略变更前后的对比测试方法 |
| pytest 集成 | 自动化测试框架与 CI 集成 |
| 可视化 | 路由准确率仪表盘与报告生成 |

### 1.3 数据诚实化声明

本报告中的数据分为三类：**[实测]** 有实际测试数据支撑、**[目标]** 设计目标尚未实测、**[推测]** 基于架构推断或引用第三方测试。当前 Prometheus 尚未进入实现阶段，所有性能目标均为 [目标] 值。

---

## 2. LLM Function Calling 评测方法综述

### 2.1 业界主流评测框架

#### 2.1.1 Berkeley Function Calling Leaderboard (BFCL)

**来源**：UC Berkeley, Shishir Patil 等, 2024

BFCL 是目前业界最权威的 LLM function calling 评测排行榜，覆盖 2000+ 测试用例。

| 维度 | 内容 |
|------|------|
| 评测范围 | 工具选择准确率、参数提取准确率、多工具调用、复杂推理 |
| 测试集规模 | 2000+ 用例，涵盖简单/复杂/多步场景 |
| 评测方法 | 将 LLM 的 function call 输出与人工标注的 ground truth 精确匹配 |
| 关键指标 | Overall Accuracy、AST (Abstract Syntax Tree) Accuracy、Exec (Execution) Accuracy |
| 工具数影响 | 实验数据显示工具数 < 15 时准确率最高，> 25 时显著下降 |

**BFCL 的评测分类**：

```
1. Simple Function Call      — 单工具调用，参数提取
2.Multiple Function Call      — 多个可用工具中选择正确的一个
3. Parallel Function Call     — 同一请求中并行调用多个工具
4. Parallel Function Call     — 并行调用 + 参数冲突
5. Function Relevance        — 判断是否需要调用工具（no-tool 场景）
6. Function Dependency       — 工具间存在依赖关系的链式调用
```

**对 Prometheus 的借鉴**：
- Prometheus 的路由场景对应 BFCL 的 Category 2（Multiple Function Call）：从 5 个 Subagent 的 16 个工具中选择正确的工具
- BFCL 的 AST Accuracy 方法可用于验证路由模型的参数提取准确性
- BFCL 的工具数 vs 准确率曲线验证了 Prometheus 将工具数从 24 降到 16 的决策

#### 2.1.2 τ-bench (Tau-Bench)

**来源**：Sierra Research, 2024

τ-bench 专注于多轮对话中的工具调用评测，模拟真实用户场景。

| 维度 | 内容 |
|------|------|
| 评测场景 | 航空客服、零售客服等领域，模拟用户与 Agent 的多轮对话 |
| 评测方法 | 任务完成率（Task Completion Rate）+ 工具调用正确率 |
| 关键创新 | 引入数据库状态校验——不仅检查工具调用是否正确，还检查工具调用后数据库状态是否符合预期 |
| 多轮特性 | 单次任务平均需要 3-7 轮工具调用才能完成 |

**对 Prometheus 的借鉴**：
- τ-bench 的数据库状态校验理念可应用于 Prometheus 的日程/记忆 Subagent：不仅检查路由是否正确，还检查工具执行后 SQLite 状态是否符合预期
- 多轮工具调用场景对应 Prometheus 的 Subagent 协同（§2.7 of design-proposal.md）

#### 2.1.3 ToolBench / ToolLLM

**来源**：清华大学, Qin Yujia 等, 2023

ToolBench 构建了大规模工具调用数据集，包含 16000+ 真实 API。

| 维度 | 内容 |
|------|------|
| 规模 | 16000+ API，46000+ 工具调用指令 |
| 评测方法 | Pass Rate（任务完成率）+ Win Rate（人工偏好对比） |
| 关键发现 | 工具描述质量对路由准确率影响极大；描述模糊是误判的首要原因 |

**对 Prometheus 的借鉴**：
- 工具描述质量是路由准确率的基础——Prometheus 的 functions.jsonl 中每个工具描述需要经过审查，确保互不重叠
- ToolBench 的工具描述最佳实践：每个工具描述 < 200 字符，包含触发条件示例

#### 2.1.4 MTClaw Function Router 自有测试

**来源**：MTClaw 团队测试数据 [推测，非 Prometheus 实测]

MTClaw 团队在 50 个系统控制任务上进行了路由准确率评测：

| 模式 | Pass@1 | 平均耗时 | 加速比 | 工具准确率 | 工具召回率 |
|------|--------|---------|--------|-----------|-----------|
| Baseline（纯上游 LLM） | 99.0% | 37.97s | 1.00x | — | — |
| Permissive | 95.5% | 5.54s | 6.85x | 97.5% | 100% |
| Strict | 100.0% | 7.61s | 4.99x | 94.8% | 100% |

**注意**：上述数据在 7 个系统控制工具的场景下测得。Prometheus 使用 16 个工具，场景复杂度更高，实际准确率预计会低于 MTClaw 的系统控制垂域 [推测]。

### 2.2 评测方法分类总结

综合业界实践，LLM function calling 评测方法可分为以下几类：

| 方法 | 评测粒度 | 优点 | 缺点 | 适用场景 |
|------|---------|------|------|---------|
| **精确匹配** (Exact Match) | 工具名 + 参数 | 简单直接，可自动化 | 无法处理语义等价的参数变体 | Prometheus 路由测试主力方法 |
| **AST 匹配** (AST Match) | 抽象语法树比对 | 容忍参数顺序差异、类型等价 | 实现复杂度中等 | 参数提取准确性验证 |
| **执行结果校验** (Exec Match) | 工具执行后状态 | 验证端到端正确性 | 需要可执行的工具环境 | 日程/记忆 Subagent 集成测试 |
| **人工评估** (Human Eval) | 主观质量评分 | 可评估模糊场景 | 成本高、不可重复 | 边界 case 与争议样本 |
| **LLM-as-Judge** | LLM 评判路由合理性 | 可扩展、成本低 | 评判模型本身有偏差 | 大规模路由质量抽样 |

### 2.3 Prometheus 评测方法选型

基于上述调研，Prometheus 路由准确率测试采用**分层评测**策略：

```
第一层：精确匹配（主力方法）
  └── 50 条测试集 × 预期工具名精确匹配 → 路由准确率

第二层：AST 匹配（参数验证）
  └── 对路由命中的工具，验证参数提取准确性

第三层：执行结果校验（端到端）
  └── 对日程/记忆等本地工具，验证工具执行后状态

第四层：LLM-as-Judge（质量抽样）
  └── 对模糊边界 case，用上游 LLM 评判路由合理性
```

---

## 3. 50 条测试集设计

### 3.1 设计原则

基于 BFCL 和 ToolBench 的测试集设计经验，Prometheus 的 50 条测试集遵循以下原则：

| 原则 | 说明 | 来源 |
|------|------|------|
| **覆盖均衡** | 每个 Subagent 至少 8 条测试用例，兜底场景至少 5 条 | BFCL 均衡覆盖原则 |
| **难度分层** | 简单(50%) / 中等(35%) / 困难(15%) 三级难度 | BFCL 难度分级 |
| **边界覆盖** | 包含歧义输入、多意图输入、复杂消息防误判 | ToolBench 边界 case |
| **中英文混合** | 覆盖中文为主、英文为辅的混合场景 | Prometheus 目标用户特征 |
| **可复现** | 每条用例标注预期工具名 + 预期参数 + 预期路由层级 | τ-bench 可复现设计 |
| **标注规范** | 每条用例包含输入、预期输出、难度、类别、备注 | BFCL 标注格式 |

### 3.2 测试集结构

每条测试用例的 JSON 结构：

```json
{
  "id": "TC-001",
  "category": "rag",
  "difficulty": "easy",
  "input": "帮我找一下关于 GPU 算力的笔记",
  "expected_tool": "rag_search",
  "expected_params": {
    "query": "GPU 算力"
  },
  "expected_route_layer": "L1_auto",
  "expected_confidence_range": [0.75, 1.0],
  "tags": ["keyword_match", "chinese"],
  "description": "RAG 检索 — 明确关键词触发"
}
```

**字段说明**：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | string | 是 | 测试用例 ID，格式 TC-NNN |
| `category` | string | 是 | Subagent 类别：rag/memory/writing/schedule/chat/fallback |
| `difficulty` | string | 是 | easy / medium / hard |
| `input` | string | 是 | 用户输入文本 |
| `expected_tool` | string | 是 | 预期命中的工具名（functions.jsonl 中的 name） |
| `expected_params` | object | 否 | 预期参数（用于 AST 匹配验证） |
| `expected_route_layer` | string | 否 | 预期路由层级：L1_auto / L1_low_confidence / L2_confirm |
| `expected_confidence_range` | [float, float] | 否 | 预期置信度范围（用于置信度评估验证） |
| `tags` | string[] | 否 | 标签：keyword_match / ambiguity / multi_intent / edge_case 等 |
| `description` | string | 是 | 用例描述 |

### 3.3 测试用例分布

#### 3.3.1 按 Subagent 分布

| Subagent | 用例数 | 占比 | 难度分布 (E/M/H) | 说明 |
|----------|--------|------|-------------------|------|
| RAG 知识库 | 10 | 20% | 5/3/2 | 检索 + 摄入 + 状态查询 |
| 记忆与偏好 | 8 | 16% | 4/3/1 | 记忆存储 + 检索 + 提醒 |
| 写作润色翻译 | 9 | 18% | 5/3/1 | 生成 + 润色 + 翻译 + 去AI化 |
| 日程与任务 | 10 | 20% | 5/3/2 | 日程创建/查询 + 任务创建/查询/完成 |
| 闲聊陪伴 | 8 | 16% | 4/2/2 | 寒暄 + 情感 + 娱乐 + 误判保护 |
| 兜底（上游 LLM） | 5 | 10% | 2/2/1 | 通用推理 + 复杂问题 |
| **合计** | **50** | **100%** | **25/16/9** | |

#### 3.3.2 按难度分布

| 难度 | 用例数 | 占比 | 定义 |
|------|--------|------|------|
| Easy | 25 | 50% | 明确关键词触发，单一意图，无歧义 |
| Medium | 16 | 32% | 需要语义理解，或有轻微歧义 |
| Hard | 9 | 18% | 高歧义、多意图混合、边界 case、误判陷阱 |

#### 3.3.3 按标签分布

| 标签 | 用例数 | 说明 |
|------|--------|------|
| `keyword_match` | 18 | 明确关键词触发路由 |
| `semantic_match` | 15 | 需要语义理解才能正确路由 |
| `ambiguity` | 7 | 输入存在歧义，需要优先级仲裁 |
| `multi_intent` | 4 | 单输入包含多个意图（协同场景） |
| `edge_case` | 6 | 边界 case：超长消息、纯英文、空输入等 |
| `misroute_trap` | 5 | 误判陷阱：看起来像闲聊但实际需要上游 LLM |

### 3.4 测试用例示例

#### 3.4.1 RAG 知识库（10 条示例）

```jsonl
{"id":"TC-001","category":"rag","difficulty":"easy","input":"帮我找一下关于 GPU 算力的笔记","expected_tool":"rag_search","expected_params":{"query":"GPU 算力"},"tags":["keyword_match"],"description":"RAG检索—明确关键词"}
{"id":"TC-002","category":"rag","difficulty":"easy","input":"搜索一下我之前的周报模板","expected_tool":"rag_search","tags":["keyword_match"],"description":"RAG检索—搜索关键词"}
{"id":"TC-003","category":"rag","difficulty":"easy","input":"我之前写的 HICOOL 提案在哪","expected_tool":"rag_search","tags":["semantic_match"],"description":"RAG检索—语义匹配'在哪'"}
{"id":"TC-004","category":"rag","difficulty":"medium","input":"帮我看看 GPU 算力对比","expected_tool":"rag_search","tags":["ambiguity","misroute_trap"],"description":"RAG检索—'帮我看看'可能误判闲聊，但技术名词应路由RAG"}
{"id":"TC-005","category":"rag","difficulty":"medium","input":"把 /data/notes 目录导入知识库","expected_tool":"rag_ingest","expected_params":{"path":"/data/notes"},"tags":["keyword_match"],"description":"RAG摄入—明确路径"}
{"id":"TC-006","category":"rag","difficulty":"easy","input":"知识库里有多少文档了","expected_tool":"rag_status","tags":["semantic_match"],"description":"RAG状态—语义匹配"}
{"id":"TC-007","category":"rag","difficulty":"medium","input":"帮我看看 最新论文","expected_tool":"rag_search","tags":["ambiguity","misroute_trap"],"description":"RAG检索—Router自学习演示case"}
{"id":"TC-008","category":"rag","difficulty":"hard","input":"之前那个关于 CUDA 编程优化的文档，能再找一下吗","expected_tool":"rag_search","tags":["semantic_match","edge_case"],"description":"RAG检索—长句+口语化+技术术语"}
{"id":"TC-009","category":"rag","difficulty":"hard","input":"索引这个目录下的所有 markdown 文件","expected_tool":"rag_ingest","tags":["semantic_match"],"description":"RAG摄入—'索引'同义词"}
{"id":"TC-010","category":"rag","difficulty":"medium","input":"find my notes about GPU benchmark","expected_tool":"rag_search","tags":["semantic_match","edge_case"],"description":"RAG检索—纯英文输入"}
```

#### 3.4.2 闲聊陪伴 + 误判保护（8 条示例）

```jsonl
{"id":"TC-034","category":"chat","difficulty":"easy","input":"你好","expected_tool":"chat_light","tags":["keyword_match"],"description":"闲聊—寒暄"}
{"id":"TC-035","category":"chat","difficulty":"easy","input":"讲个笑话","expected_tool":"chat_light","tags":["keyword_match"],"description":"闲聊—娱乐"}
{"id":"TC-036","category":"chat","difficulty":"easy","input":"今天好累啊","expected_tool":"chat_light","tags":["semantic_match"],"description":"闲聊—情感"}
{"id":"TC-037","category":"chat","difficulty":"medium","input":"嗨，最近怎么样","expected_tool":"chat_light","tags":["semantic_match"],"description":"闲聊—寒暄变体"}
{"id":"TC-038","category":"chat","difficulty":"hard","input":"为什么天空是蓝色的","expected_tool":null,"expected_route_layer":"L1_auto","tags":["misroute_trap"],"description":"误判保护—'为什么'+知识问答，应走兜底而非闲聊"}
{"id":"TC-039","category":"chat","difficulty":"hard","input":"给我讲讲量子计算的基本原理","expected_tool":null,"tags":["misroute_trap"],"description":"误判保护—看起来像闲聊但需要深度推理"}
{"id":"TC-040","category":"chat","difficulty":"hard","input":"对比一下 React 和 Vue 的优缺点","expected_tool":null,"tags":["misroute_trap"],"description":"误判保护—包含'对比''优缺点'，禁止路由闲聊"}
{"id":"TC-041","category":"chat","difficulty":"medium","input":"你叫什么名字","expected_tool":"chat_light","tags":["semantic_match"],"description":"闲聊—简单问答"}
```

#### 3.4.3 兜底场景（5 条示例）

```jsonl
{"id":"TC-046","category":"fallback","difficulty":"easy","input":"1+1等于几","expected_tool":null,"tags":["semantic_match"],"description":"兜底—通用推理"}
{"id":"TC-047","category":"fallback","difficulty":"medium","input":"帮我分析一下这个 CSV 数据的趋势","expected_tool":null,"tags":["semantic_match"],"description":"兜底—数据分析（无专用Subagent）"}
{"id":"TC-048","category":"fallback","difficulty":"hard","input":"请详细解释 Transformer 架构中的自注意力机制，包括数学推导","expected_tool":null,"tags":["misroute_trap","edge_case"],"description":"兜底—长消息+技术深度，禁止路由闲聊"}
{"id":"TC-049","category":"fallback","difficulty":"medium","input":"今天北京天气怎么样","expected_tool":null,"tags":["semantic_match"],"description":"兜底—无天气Subagent"}
{"id":"TC-050","category":"fallback","difficulty":"hard","input":"写一个 Python 脚本，读取 CSV 文件并生成柱状图，要求支持命令行参数","expected_tool":null,"tags":["edge_case"],"description":"兜底—编程任务（>200字，含技术关键词）"}
```

### 3.5 测试集管理与维护

#### 3.5.1 文件组织

```
tests/
├── routing_accuracy/
│   ├── __init__.py
│   ├── conftest.py              # pytest fixtures
│   ├── test_routing_accuracy.py # 主测试文件
│   ├── test_dataset.jsonl       # 50 条测试集（JSONL 格式）
│   ├── test_cases_expanded.jsonl # 扩展测试集（>100 条，后续迭代）
│   ├── evaluators/
│   │   ├── exact_match.py       # 精确匹配评测器
│   │   ├── ast_match.py         # AST 匹配评测器
│   │   ├── exec_match.py        # 执行结果校验评测器
│   │   └── llm_judge.py         # LLM-as-Judge 评测器
│   ├── reports/
│   │   ├── latest/              # 最新报告
│   │   └── history/             # 历史报告归档
│   └── visualizations/
│       ├── confusion_matrix.py  # 混淆矩阵生成
│       └── dashboard.py         # 仪表盘生成
```

#### 3.5.2 测试集版本管理

- 测试集以 JSONL 文件形式纳入 Git 版本控制
- 每次修改测试集需提交 PR 并说明变更原因
- 标记 `version` 字段，支持版本间对比
- 扩展测试集（>100 条）作为后续迭代计划，初期聚焦 50 条核心集

---

## 4. 评测指标体系

### 4.1 指标总览

Prometheus 路由准确率评测指标体系分为四层：

```
第一层：核心指标（必测）
  ├── 路由准确率 (Routing Accuracy)
  ├── 路由误判率 (Misroute Rate)
  └── 各 Subagent 召回率 (Per-Subagent Recall)

第二层：置信度指标（与双层路由相关）
  ├── 置信度分布 (Confidence Distribution)
  ├── L1 高置信度误判率 (L1 High-Confidence Misroute Rate)
  ├── L2 确认路由触发率 (L2 Trigger Rate)
  └── 置信度-准确率校准曲线 (Confidence-Accuracy Calibration)

第三层：参数提取指标
  ├── 参数准确率 (Parameter Accuracy)
  └── 参数完整率 (Parameter Completeness)

第四层：系统指标
  ├── 路由延迟 (Routing Latency)
  └── 路由稳定性 (Routing Stability — 重复测试方差)
```

### 4.2 核心指标定义

#### 4.2.1 路由准确率 (Routing Accuracy)

```
Routing Accuracy = (正确路由的用例数 / 总用例数) × 100%

判定标准:
  - expected_tool != null: 路由模型输出的 tool_name == expected_tool → 正确
  - expected_tool == null (兜底场景): 路由模型未命中任何工具 → 正确

目标: > 90% [目标]（初始）；> 95% [目标]（自学习后）
```

#### 4.2.2 路由误判率 (Misroute Rate)

```
Misroute Rate = (误路由的用例数 / 总用例数) × 100%

误路由定义:
  - 路由到了错误的 Subagent（非 expected_tool 也非兜底）
  - 注意：兜底场景路由到了具体 Subagent 也算误路由

目标: < 10% [目标]（初始）；< 5% [目标]（自学习后）
```

#### 4.2.3 各 Subagent 召回率 (Per-Subagent Recall)

```
Recall(subagent) = (该 Subagent 正确路由的用例数 / 该 Subagent 的总用例数) × 100%

示例:
  RAG Recall = (RAG 正确路由数 / RAG 总用例数) × 100%
  Chat Recall = (Chat 正确路由数 / Chat 总用例数) × 100%

目标: 每个 Subagent Recall > 85% [目标]
```

#### 4.2.4 各 Subagent 精确率 (Per-Subagent Precision)

```
Precision(subagent) = (该 Subagent 正确路由的用例数 / 路由到该 Subagent 的总用例数) × 100%

意义: 精确率低说明该 Subagent 被"过度路由"——不该路由到它的请求被路由过来了

目标: 每个 Subagent Precision > 85% [目标]
```

### 4.3 置信度指标

#### 4.3.1 置信度分布

统计 50 条测试用例的置信度分布：

```
置信度区间      用例数    占比
[0.90, 1.00]    ??        ??%     ← 高置信度，应全部正确
[0.75, 0.90)    ??        ??%     ← 高置信度
[0.45, 0.75)    ??        ??%     ← 中间区（低置信度标记）
[0.00, 0.45)    ??        ??%     ← 低置信度，应触发 L2
```

#### 4.3.2 L1/L2 路由层级统计

```
路由层级              用例数    占比    准确率
L1_auto (≥0.75)       ??        ??%     ??%     ← 高置信度自动路由
L1_low_conf (0.45~0.75) ??      ??%     ??%     ← 低置信度自动路由
L2_confirm (<0.45)    ??        ??%     ??%     ← 确认路由（用户选择后）
```

#### 4.3.3 置信度-准确率校准

理想情况下，置信度越高，准确率应越高。校准曲线用于评估置信度评分的质量：

```
理想校准:
  置信度 0.9 的用例 → 准确率应 ≈ 90%
  置信度 0.7 的用例 → 准确率应 ≈ 70%

校准误差 (ECE - Expected Calibration Error):
  ECE = Σ |accuracy(bin) - avg_confidence(bin)| × weight(bin)

目标: ECE < 0.10 [目标]
```

### 4.4 混淆矩阵

混淆矩阵是路由准确率分析的核心可视化工具：

```
              预测路由
              RAG  Mem  Wrt  Sch  Chat  Fallback
实际 RAG      [✓]  [ ]  [ ]  [ ]  [ ]   [ ]
实际 Mem      [ ]  [✓]  [ ]  [ ]  [ ]   [ ]
实际 Wrt      [ ]  [ ]  [✓]  [ ]  [ ]   [ ]
实际 Sch      [ ]  [ ]  [ ]  [✓]  [ ]   [ ]
实际 Chat     [ ]  [ ]  [ ]  [ ]  [✓]   [ ]
实际 Fallback [ ]  [ ]  [ ]  [ ]  [ ]   [✓]

对角线 = 正确路由
非对角线 = 误路由（可用于分析误路由模式）
```

**典型误路由模式分析**：

| 误路由方向 | 可能原因 | 缓解措施 |
|------------|---------|---------|
| Chat → Fallback | 闲聊误判保护过严 | 调整 complex 消息规则 |
| RAG → Chat | "帮我看看"被误判为闲聊 | 关键词权重调整（自学习） |
| Writing → Fallback | 写作意图表述模糊 | 优化 writing 工具描述 |
| Schedule → Memory | "提醒"被误判为记忆 | 优先级调整 |

### 4.5 参数提取指标

对于路由命中正确工具的用例，进一步验证参数提取质量：

```
Parameter Accuracy = (参数完全匹配的用例数 / 路由命中正确的用例数) × 100%

参数匹配规则:
  - 必填参数: 值必须匹配（允许语义等价，如"明天下午3点" == "2026-07-15T15:00"）
  - 选填参数: 不检查（路由模型可不填选填参数）
  - 类型检查: 参数类型必须正确（string/int/boolean）

目标: Parameter Accuracy > 85% [目标]
```

### 4.6 系统指标

| 指标 | 定义 | 目标 |
|------|------|------|
| 路由延迟 (P50) | 50% 的路由决策延迟 | < 500ms [目标] |
| 路由延迟 (P95) | 95% 的路由决策延迟 | < 1000ms [目标] |
| 路由延迟 (P99) | 99% 的路由决策延迟 | < 2000ms [目标] |
| 路由稳定性 | 同一输入重复 10 次的准确率方差 | 0（temperature=0 应完全确定性） |

---

## 5. A/B 测试方法

### 5.1 A/B 测试场景

A/B 测试用于评估路由策略变更的效果，主要场景包括：

| 场景 | A 组（对照组） | B 组（实验组） | 评估目标 |
|------|---------------|---------------|---------|
| 工具描述优化 | 原始工具描述 | 优化后的描述 | 描述优化对准确率的影响 |
| 关键词权重调整 | 无权重提示 | 自学习生成的权重提示 | 关键词权重对准确率的影响 |
| 提示词片段注入 | 基础提示词 | 基础 + 历史修正片段 | 提示词增强对准确率的影响 |
| 置信度阈值调整 | high=0.75/low=0.45 | high=0.80/low=0.40 | 阈值调整对 L2 触发率的影响 |
| Subagent 优先级调整 | 基础优先级 | 动态调整后优先级 | 优先级对歧义场景的影响 |
| 工具数量变更 | 16 工具 | 增减工具后的 N 工具 | 工具数对路由准确率的影响 |

### 5.2 A/B 测试流程

```
┌─────────────────────────────────────────────────────┐
│                  A/B 测试流程                         │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. 定义假设                                         │
│     "优化 writing 工具描述后，写作类路由准确率提升"    │
│                                                     │
│  2. 准备测试集                                       │
│     使用同一份 50 条测试集（确保可比性）                │
│                                                     │
│  3. 运行 A 组（对照组）                               │
│     python3 tests/routing_accuracy/run_ab_test.py    │
│       --variant control                              │
│       --config configs/routing_control.json          │
│       --repeat 3  # 重复 3 次取平均                   │
│                                                     │
│  4. 运行 B 组（实验组）                               │
│     python3 tests/routing_accuracy/run_ab_test.py    │
│       --variant experiment                           │
│       --config configs/routing_experiment.json       │
│       --repeat 3                                     │
│                                                     │
│  5. 统计分析                                         │
│     - 逐用例对比 A vs B 的路由结果                    │
│     - 计算准确率差异 + 统计显著性                      │
│     - 生成对比报告                                    │
│                                                     │
│  6. 决策                                             │
│     显著提升 → 合入 B 组策略                           │
│     无显著差异 → 保留 A 组，记录实验结果                │
│     显著下降 → 回滚，分析原因                          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 5.3 统计显著性检验

50 条测试集样本量较小，需选择合适的统计检验方法：

| 样本特征 | 推荐方法 | 说明 |
|---------|---------|------|
| 配对二值数据（A/B 逐用例对比） | **McNemar 检验** | 最适合 A/B 测试同一样本集的前后对比 |
| 独立二值数据 | Fisher 精确检验 | 适用于小样本（n<1000）的准确率比较 |
| 连续数据（延迟对比） | Wilcoxon 符号秩检验 | 非参数检验，不假设正态分布 |

**McNemar 检验示例**：

```
                    B 组正确    B 组错误
A 组正确             n_11        n_12
A 组错误             n_21        n_22

McNemar 统计量 = (|n_12 - n_21| - 1)² / (n_12 + n_21)

p < 0.05 → 差异显著
p ≥ 0.05 → 差异不显著（可能需要更大样本量）
```

**实现**：

```python
from statsmodels.stats.contingency_tables import mcnemar

def run_mcnemar_test(results_a: list[bool], results_b: list[bool]) -> dict:
    """
    对 A/B 两组路由结果（布尔列表）执行 McNemar 检验。
    
    返回: {
        "statistic": float,
        "p_value": float,
        "significant": bool,  # p < 0.05
        "interpretation": str
    }
    """
    # 构建列联表
    n_11 = sum(1 for a, b in zip(results_a, results_b) if a and b)      # A对 B对
    n_12 = sum(1 for a, b in zip(results_a, results_b) if a and not b)   # A对 B错
    n_21 = sum(1 for a, b in zip(results_a, results_b) if not a and b)   # A错 B对
    n_22 = sum(1 for a, b in zip(results_a, results_b) if not a and not b) # A错 B错
    
    table = [[n_11, n_12], [n_21, n_22]]
    result = mcnemar(table, exact=True)  # 小样本用精确检验
    
    return {
        "statistic": result.statistic,
        "p_value": result.pvalue,
        "significant": result.pvalue < 0.05,
        "n_11": n_11, "n_12": n_12, "n_21": n_21, "n_22": n_22,
        "interpretation": (
            f"B 组改善了 {n_21} 个 case，劣化了 {n_12} 个 case。"
            f"{'差异显著' if result.pvalue < 0.05 else '差异不显著'}（p={result.pvalue:.4f}）"
        )
    }
```

### 5.4 A/B 测试报告格式

```json
{
  "test_id": "AB-001",
  "timestamp": "2026-07-14T15:30:00",
  "hypothesis": "优化 writing 工具描述后，写作类路由准确率提升",
  "dataset": "tests/routing_accuracy/test_dataset.jsonl",
  "repeat_count": 3,
  "results": {
    "control": {
      "overall_accuracy": 0.88,
      "per_category": {"rag": 0.90, "writing": 0.78, "schedule": 0.90, ...},
      "avg_confidence": 0.72
    },
    "experiment": {
      "overall_accuracy": 0.92,
      "per_category": {"rag": 0.90, "writing": 0.89, "schedule": 0.90, ...},
      "avg_confidence": 0.76
    },
    "delta": {
      "overall_accuracy": +0.04,
      "writing_accuracy": +0.11
    },
    "statistical_test": {
      "method": "McNemar",
      "p_value": 0.031,
      "significant": true,
      "improved_cases": 4,
      "degraded_cases": 1
    }
  },
  "decision": "adopt_experiment",
  "notes": "写作类准确率显著提升（+11%），整体准确率提升 4%"
}
```

### 5.5 自学习效果 A/B 测试

Prometheus Router 自学习引擎的 A/B 测试是特殊场景——需要验证"学习后"比"学习前"更好：

```
自学习 A/B 测试设计:

阶段 1（基线）: 
  对 50 条测试集运行路由 → 记录准确率 A_baseline

阶段 2（注入学习数据）:
  向 routing_corrections 表注入模拟修正数据（如 10 条同类修正）
  → 触发关键词权重调整 + 提示词片段注入

阶段 3（学习后）:
  对同一份 50 条测试集运行路由 → 记录准确率 B_learned

对比: B_learned vs A_baseline
  关注指标:
    - 整体准确率变化
    - 被修正类别的准确率变化（如 "帮我看看" + 技术名词 → RAG）
    - 非修正类别的准确率变化（确认没有退化）
```

---

## 6. pytest 集成方案

### 6.1 测试框架架构

```
tests/routing_accuracy/
├── conftest.py                      # 全局 fixtures
├── test_routing_accuracy.py         # 主测试：50 条路由准确率
├── test_confidence_scoring.py       # 置信度计算单元测试
├── test_route_layer_decision.py     # 双层路由决策单元测试
├── test_ab_comparison.py            # A/B 测试对比
├── test_correction_detection.py     # 修正意图识别测试
├── run_routing_suite.py             # 独立运行入口（CI 友好）
└── evaluators/
    ├── __init__.py
    ├── exact_match.py
    ├── ast_match.py
    ├── exec_match.py
    └── llm_judge.py
```

### 6.2 conftest.py — 全局 Fixtures

```python
# tests/routing_accuracy/conftest.py

import json
import pytest
import os
from pathlib import Path

TEST_DIR = Path(__file__).parent


@pytest.fixture(scope="session")
def test_dataset():
    """加载 50 条测试集"""
    dataset_path = TEST_DIR / "test_dataset.jsonl"
    cases = []
    with open(dataset_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                cases.append(json.loads(line))
    assert len(cases) == 50, f"测试集应为 50 条，实际 {len(cases)} 条"
    return cases


@pytest.fixture(scope="session")
def fr_client():
    """
    MTClaw Function Router 客户端。
    通过 OpenAI-compatible API 调用 FR 的路由接口。
    """
    import httpx
    
    fr_url = os.getenv("FR_URL", "http://localhost:18790")
    fr_api_key = os.getenv("FR_API_KEY", "test-key")
    
    client = httpx.Client(
        base_url=fr_url,
        headers={"Authorization": f"Bearer {fr_api_key}"},
        timeout=30.0,
    )
    
    # 健康检查
    resp = client.get("/health")
    assert resp.status_code == 200, f"FR 不可用: {resp}"
    
    yield client
    client.close()


@pytest.fixture(scope="session")
def functions_jsonl():
    """加载工具定义"""
    functions_path = TEST_DIR.parent.parent / "subagents" / "functions.jsonl"
    tools = []
    with open(functions_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                tools.append(json.loads(line))
    return tools
```

### 6.3 test_routing_accuracy.py — 主测试文件

```python
# tests/routing_accuracy/test_routing_accuracy.py

import pytest
import json
from evaluators.exact_match import exact_match_eval
from evaluators.ast_match import ast_match_eval


def route_message(fr_client, user_input: str, functions: list) -> dict:
    """
    通过 FR 的 OpenAI-compatible API 路由用户消息。
    
    返回: {
        "tool_name": str | None,
        "tool_args": dict,
        "logprobs": dict | None,  # 路由模型 logprob
        "latency_ms": float,
        "raw_response": dict
    }
    """
    import time
    
    start = time.monotonic()
    resp = fr_client.post("/v1/chat/completions", json={
        "model": "qwen3-30b",
        "messages": [{"role": "user", "content": user_input}],
        "tools": [{"type": "function", "function": f} for f in functions],
        "tool_choice": "auto",
        "temperature": 0.0,
        "logprobs": True,
        "top_logprobs": 5,
    })
    elapsed_ms = (time.monotonic() - start) * 1000
    
    data = resp.json()
    
    # 解析路由结果
    tool_name = None
    tool_args = {}
    if data.get("choices"):
        choice = data["choices"][0]
        if choice.get("message", {}).get("tool_calls"):
            call = choice["message"]["tool_calls"][0]
            tool_name = call["function"]["name"]
            tool_args = json.loads(call["function"]["arguments"])
    
    return {
        "tool_name": tool_name,
        "tool_args": tool_args,
        "logprobs": data.get("choices", [{}])[0].get("logprobs"),
        "latency_ms": elapsed_ms,
        "raw_response": data,
    }


# ============================================================
# 参数化测试：50 条用例 × 精确匹配
# ============================================================

def test_routing_accuracy_overall(fr_client, test_dataset, functions_jsonl):
    """整体路由准确率测试"""
    correct = 0
    results = []
    
    for case in test_dataset:
        route_result = route_message(fr_client, case["input"], functions_jsonl)
        is_correct = exact_match_eval(route_result["tool_name"], case["expected_tool"])
        results.append({
            "id": case["id"],
            "input": case["input"],
            "expected": case["expected_tool"],
            "actual": route_result["tool_name"],
            "correct": is_correct,
            "latency_ms": route_result["latency_ms"],
        })
        if is_correct:
            correct += 1
    
    accuracy = correct / len(test_dataset)
    
    # 输出详细结果
    print(f"\n{'='*60}")
    print(f"路由准确率测试结果")
    print(f"{'='*60}")
    print(f"总用例数: {len(test_dataset)}")
    print(f"正确路由: {correct}")
    print(f"路由准确率: {accuracy:.2%}")
    print(f"{'='*60}")
    
    # 打印错误用例
    errors = [r for r in results if not r["correct"]]
    if errors:
        print(f"\n错误用例 ({len(errors)} 条):")
        for e in errors:
            print(f"  [{e['id']}] 输入: {e['input']}")
            print(f"         预期: {e['expected']}, 实际: {e['actual']}")
    
    # 断言：准确率 > 90%
    assert accuracy >= 0.90, f"路由准确率 {accuracy:.2%} 低于目标 90%"


# ============================================================
# 参数化测试：逐用例验证
# ============================================================

@pytest.mark.parametrize("case", [c for c in []], indirect=True)  # 运行时动态填充
def test_single_case(fr_client, case, functions_jsonl):
    """单条用例测试（可用于 pytest 参数化展示）"""
    route_result = route_message(fr_client, case["input"], functions_jsonl)
    assert exact_match_eval(route_result["tool_name"], case["expected_tool"]), (
        f"[{case['id']}] 输入: {case['input']}\n"
        f"预期: {case['expected_tool']}, 实际: {route_result['tool_name']}"
    )


# ============================================================
# 各 Subagent 召回率
# ============================================================

def test_per_subagent_recall(fr_client, test_dataset, functions_jsonl):
    """各 Subagent 召回率测试"""
    categories = {}
    for case in test_dataset:
        cat = case["category"]
        if cat not in categories:
            categories[cat] = {"total": 0, "correct": 0}
        categories[cat]["total"] += 1
        
        route_result = route_message(fr_client, case["input"], functions_jsonl)
        if exact_match_eval(route_result["tool_name"], case["expected_tool"]):
            categories[cat]["correct"] += 1
    
    print(f"\n{'='*60}")
    print(f"各 Subagent 召回率")
    print(f"{'='*60}")
    print(f"{'Subagent':<15} {'正确':>6} {'总数':>6} {'召回率':>10}")
    print(f"{'-'*40}")
    
    for cat, stats in sorted(categories.items()):
        recall = stats["correct"] / stats["total"]
        print(f"{cat:<15} {stats['correct']:>6} {stats['total']:>6} {recall:>10.2%}")
        
        # 每个 Subagent 召回率 > 85%
        assert recall >= 0.85, f"{cat} 召回率 {recall:.2%} 低于目标 85%"
    
    print(f"{'='*60}")


# ============================================================
# 误判保护测试
# ============================================================

def test_misroute_protection(fr_client, test_dataset, functions_jsonl):
    """误判保护：complex 消息不应路由到 chat_light"""
    trap_cases = [c for c in test_dataset if "misroute_trap" in c.get("tags", [])]
    
    violations = []
    for case in trap_cases:
        route_result = route_message(fr_client, case["input"], functions_jsonl)
        if route_result["tool_name"] == "chat_light":
            violations.append({
                "id": case["id"],
                "input": case["input"],
                "reason": "complex 消息被误路由到 chat_light"
            })
    
    assert len(violations) == 0, (
        f"误判保护违反: {len(violations)} 条 complex 消息被路由到 chat_light\n"
        + "\n".join(f"  [{v['id']}] {v['input']}" for v in violations)
    )


# ============================================================
# 路由确定性测试
# ============================================================

def test_routing_determinism(fr_client, test_dataset, functions_jsonl):
    """路由确定性：同一输入多次路由结果应一致（temperature=0）"""
    import random
    
    # 随机选 10 条用例
    sample = random.sample(test_dataset, min(10, len(test_dataset)))
    repeat = 5
    
    for case in sample:
        results = set()
        for _ in range(repeat):
            route_result = route_message(fr_client, case["input"], functions_jsonl)
            results.add(route_result["tool_name"])
        
        assert len(results) == 1, (
            f"[{case['id']}] 输入: {case['input']}\n"
            f"重复 {repeat} 次路由结果不一致: {results}"
        )
```

### 6.4 评测器实现

#### 6.4.1 精确匹配评测器

```python
# tests/routing_accuracy/evaluators/exact_match.py

def exact_match_eval(actual_tool: str | None, expected_tool: str | None) -> bool:
    """
    精确匹配评测。
    
    判定规则:
      - expected_tool is None (兜底场景): actual_tool is None → 正确
      - expected_tool is not None: actual_tool == expected_tool → 正确
      - 其他情况 → 错误
    
    注意: 工具名匹配是精确的，不接受子串匹配。
    """
    if expected_tool is None:
        return actual_tool is None
    return actual_tool == expected_tool
```

#### 6.4.2 AST 匹配评测器

```python
# tests/routing_accuracy/evaluators/ast_match.py

import ast
import json

def ast_match_eval(actual_args: dict, expected_args: dict) -> bool:
    """
    AST 匹配评测：验证工具参数提取准确性。
    
    判定规则:
      - 所有 expected_args 中的 key 必须在 actual_args 中存在
      - 值匹配（支持语义等价，如 "明天下午3点" == "2026-07-15T15:00"）
      - actual_args 中的额外 key 不算错误（路由模型可填选填参数）
    """
    if not expected_args:
        return True  # 无预期参数，不检查
    
    for key, expected_value in expected_args.items():
        if key not in actual_args:
            return False
        if not _value_match(actual_args[key], expected_value):
            return False
    
    return True


def _value_match(actual, expected) -> bool:
    """值匹配（支持类型等价）"""
    if isinstance(expected, str) and isinstance(actual, str):
        return actual.lower().strip() == expected.lower().strip()
    if isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
        return actual == expected
    if isinstance(expected, bool) and isinstance(actual, bool):
        return actual == expected
    return str(actual) == str(expected)
```

#### 6.4.3 执行结果校验评测器

```python
# tests/routing_accuracy/evaluators/exec_match.py

import sqlite3
import json

def exec_match_eval(tool_name: str, tool_args: dict, 
                     db_path: str, expected_db_state: dict) -> bool:
    """
    执行结果校验：工具执行后验证 SQLite 状态。
    
    适用 Subagent: 记忆（memories 表）、日程（events/tasks 表）
    
    示例:
      tool_name = "memory_remember"
      expected_db_state = {
        "table": "memories",
        "where": {"key": "writing_format"},
        "expected_value": {"value": "markdown"}
      }
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    table = expected_db_state["table"]
    where_clause = " AND ".join(f"{k} = ?" for k in expected_db_state["where"])
    where_values = list(expected_db_state["where"].values())
    
    cursor.execute(f"SELECT * FROM {table} WHERE {where_clause}", where_values)
    row = cursor.fetchone()
    
    if not row:
        return False
    
    for key, val in expected_db_state["expected_value"].items():
        if row[key] != val:
            return False
    
    conn.close()
    return True
```

### 6.5 CI 集成

#### 6.5.1 GitHub Actions 集成

```yaml
# .github/workflows/routing-accuracy.yml

name: Routing Accuracy Tests

on:
  push:
    paths:
      - 'subagents/**'
      - 'tests/routing_accuracy/**'
      - '.github/workflows/routing-accuracy.yml'
  pull_request:
    paths:
      - 'subagents/**'
      - 'tests/routing_accuracy/**'

jobs:
  routing-accuracy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install pytest httpx statsmodels matplotlib seaborn jinja2
      
      - name: Start MTClaw Function Router
        run: |
          # 启动 FR 服务
          cd function_router && python -m mtclaw_fr --port 18790 &
          sleep 5
          # 健康检查
          curl -s http://localhost:18790/health | jq .status
      
      - name: Run routing accuracy tests
        env:
          FR_URL: http://localhost:18790
          FR_API_KEY: ${{ secrets.FR_API_KEY }}
        run: |
          pytest tests/routing_accuracy/ -v \
            --tb=short \
            --html=reports/routing_accuracy_report.html \
            --self-contained-html
      
      - name: Generate accuracy report
        run: |
          python tests/routing_accuracy/run_routing_suite.py \
            --output-dir reports/
      
      - name: Upload reports
        uses: actions/upload-artifact@v4
        with:
          name: routing-accuracy-reports
          path: reports/
```

#### 6.5.2 pytest 命令行用法

```bash
# 运行全部路由准确率测试
pytest tests/routing_accuracy/ -v

# 只运行主准确率测试
pytest tests/routing_accuracy/test_routing_accuracy.py -v

# 只运行误判保护测试
pytest tests/routing_accuracy/test_routing_accuracy.py::test_misroute_protection -v

# 跳过需要 FR 服务的测试（离线模式）
pytest tests/routing_accuracy/ -v -m "not requires_fr"

# 生成 HTML 报告
pytest tests/routing_accuracy/ -v --html=reports/report.html --self-contained-html

# 运行 A/B 测试
python tests/routing_accuracy/run_ab_test.py \
  --control-config configs/routing_v1.json \
  --experiment-config configs/routing_v2.json \
  --output reports/ab_test_report.json

# 独立运行路由测试套件（CI 友好）
python tests/routing_accuracy/run_routing_suite.py \
  --output-dir reports/ \
  --format json,html,markdown
```

### 6.6 测试标记 (Markers)

```python
# pytest.ini
[pytest]
markers =
    requires_fr: 需要运行中的 MTClaw Function Router 服务
    requires_llm: 需要可用的上游 LLM API
    slow: 运行时间较长的测试
    smoke: 冒烟测试（快速验证核心功能）
    ab_test: A/B 测试
    unit: 单元测试（不需要外部服务）
    integration: 集成测试（需要外部服务）
```

---

## 7. 可视化方案

### 7.1 可视化组件总览

```
路由准确率可视化
├── 7.2 混淆矩阵热力图 (Confusion Matrix Heatmap)
├── 7.3 准确率仪表盘 (Accuracy Dashboard)
├── 7.4 置信度分布图 (Confidence Distribution)
├── 7.5 路由决策时间线 (Routing Decision Timeline)
├── 7.6 A/B 测试对比图 (A/B Comparison Chart)
└── 7.7 HTML 报告生成 (HTML Report Generation)
```

### 7.2 混淆矩阵热力图

```python
# tests/routing_accuracy/visualizations/confusion_matrix.py

import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from pathlib import Path


def generate_confusion_matrix(results: list[dict], output_path: str):
    """
    生成路由混淆矩阵热力图。
    
    results: [{"expected": "rag_search", "actual": "rag_search", ...}, ...]
    output_path: 图片保存路径
    """
    # 收集所有工具名
    tools = sorted(set(
        [r["expected"] for r in results] + 
        [r["actual"] for r in results]
    ))
    # 将 None 替换为 "fallback"
    tools = [t if t else "fallback" for t in tools]
    
    # 构建混淆矩阵
    n = len(tools)
    matrix = np.zeros((n, n), dtype=int)
    tool_idx = {t: i for i, t in enumerate(tools)}
    
    for r in results:
        expected = r["expected"] if r["expected"] else "fallback"
        actual = r["actual"] if r["actual"] else "fallback"
        matrix[tool_idx[expected]][tool_idx[actual]] += 1
    
    # 绘制热力图
    fig, ax = plt.subplots(figsize=(10, 8))
    sns.heatmap(
        matrix,
        annot=True,
        fmt="d",
        cmap="YlOrRd",
        xticklabels=tools,
        yticklabels=tools,
        ax=ax,
    )
    ax.set_xlabel("Actual Route", fontsize=12)
    ax.set_ylabel("Expected Route", fontsize=12)
    ax.set_title("Routing Confusion Matrix", fontsize=14)
    plt.tight_layout()
    plt.savefig(output_path, dpi=150)
    plt.close()
```

### 7.3 准确率仪表盘

```python
# tests/routing_accuracy/visualizations/dashboard.py

import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import json
from pathlib import Path


def generate_dashboard(results: dict, output_path: str):
    """
    生成路由准确率仪表盘（单页综合视图）。
    
    results: {
        "overall_accuracy": float,
        "per_category": {"rag": float, "memory": float, ...},
        "per_difficulty": {"easy": float, "medium": float, "hard": float},
        "confidence_distribution": {"[0.9,1.0]": int, ...},
        "latency": {"p50": float, "p95": float, "p99": float},
        "errors": [{"id": str, "input": str, "expected": str, "actual": str}, ...]
    }
    """
    fig = plt.figure(figsize=(16, 10))
    gs = gridspec.GridSpec(2, 3, hspace=0.35, wspace=0.3)
    
    # 1. 整体准确率（大数字）
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.text(0.5, 0.5, f"{results['overall_accuracy']:.1%}",
             fontsize=48, ha="center", va="center", fontweight="bold",
             color="green" if results["overall_accuracy"] >= 0.90 else "red")
    ax1.set_title("Overall Routing Accuracy", fontsize=14)
    ax1.axis("off")
    
    # 2. 各 Subagent 准确率（柱状图）
    ax2 = fig.add_subplot(gs[0, 1:])
    cats = list(results["per_category"].keys())
    accs = list(results["per_category"].values())
    colors = ["green" if a >= 0.85 else "orange" if a >= 0.70 else "red" for a in accs]
    ax2.barh(cats, accs, color=colors)
    ax2.set_xlim(0, 1)
    ax2.axvline(0.85, color="gray", linestyle="--", label="Target 85%")
    ax2.set_xlabel("Accuracy")
    ax2.set_title("Per-Subagent Accuracy", fontsize=14)
    ax2.legend()
    
    # 3. 难度分布准确率
    ax3 = fig.add_subplot(gs[1, 0])
    diffs = list(results["per_difficulty"].keys())
    diff_accs = list(results["per_difficulty"].values())
    ax3.bar(diffs, diff_accs, color=["green", "orange", "red"])
    ax3.set_ylim(0, 1)
    ax3.set_title("Accuracy by Difficulty", fontsize=14)
    
    # 4. 置信度分布
    ax4 = fig.add_subplot(gs[1, 1])
    conf_bins = list(results["confidence_distribution"].keys())
    conf_counts = list(results["confidence_distribution"].values())
    ax4.bar(conf_bins, conf_counts, color="steelblue")
    ax4.set_title("Confidence Distribution", fontsize=14)
    ax4.tick_params(axis="x", rotation=45)
    
    # 5. 延迟分布
    ax5 = fig.add_subplot(gs[1, 2])
    latency = results["latency"]
    ax5.bar(["P50", "P95", "P99"], 
            [latency["p50"], latency["p95"], latency["p99"]],
            color="steelblue")
    ax5.axhline(1000, color="red", linestyle="--", label="1s target")
    ax5.set_ylabel("Latency (ms)")
    ax5.set_title("Routing Latency", fontsize=14)
    ax5.legend()
    
    fig.suptitle("Prometheus Routing Accuracy Dashboard", fontsize=16, y=1.02)
    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    plt.close()
```

### 7.4 HTML 报告生成

```python
# tests/routing_accuracy/report_generator.py

import json
from datetime import datetime
from pathlib import Path
from jinja2 import Template


HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>Prometheus 路由准确率测试报告</title>
    <style>
        body { font-family: -apple-system, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 40px; border-radius: 8px; }
        h1 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .metric-card { display: inline-block; width: 200px; margin: 10px; padding: 20px; 
                       border-radius: 8px; text-align: center; color: white; }
        .metric-green { background: #4CAF50; }
        .metric-red { background: #f44336; }
        .metric-orange { background: #FF9800; }
        .metric-value { font-size: 36px; font-weight: bold; }
        .metric-label { font-size: 14px; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin: 15px 0; }
        th { background: #4CAF50; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .error-row { background: #ffebee; }
        .pass { color: #4CAF50; font-weight: bold; }
        .fail { color: #f44336; font-weight: bold; }
        .chart { margin: 20px 0; }
        .chart img { max-width: 100%; border-radius: 4px; }
    </style>
</head>
<body>
<div class="container">
    <h1>Prometheus 路由准确率测试报告</h1>
    <p>生成时间: {{ timestamp }}</p>
    
    <h2>核心指标</h2>
    <div>
        <div class="metric-card {{ 'metric-green' if overall_accuracy >= 0.90 else 'metric-red' }}">
            <div class="metric-value">{{ '%.1f' % (overall_accuracy * 100) }}%</div>
            <div class="metric-label">路由准确率</div>
        </div>
        <div class="metric-card {{ 'metric-green' if misroute_rate <= 0.10 else 'metric-red' }}">
            <div class="metric-value">{{ '%.1f' % (misroute_rate * 100) }}%</div>
            <div class="metric-label">误判率</div>
        </div>
        <div class="metric-card metric-orange">
            <div class="metric-value">{{ total_cases }}</div>
            <div class="metric-label">测试用例数</div>
        </div>
        <div class="metric-card metric-orange">
            <div class="metric-value">{{ '%.0f' % avg_latency }}ms</div>
            <div class="metric-label">平均路由延迟</div>
        </div>
    </div>
    
    <h2>各 Subagent 召回率</h2>
    <table>
        <tr><th>Subagent</th><th>正确</th><th>总数</th><th>召回率</th><th>状态</th></tr>
        {% for cat, stats in per_category.items() %}
        <tr>
            <td>{{ cat }}</td>
            <td>{{ stats.correct }}</td>
            <td>{{ stats.total }}</td>
            <td>{{ '%.1f' % (stats.recall * 100) }}%</td>
            <td class="{{ 'pass' if stats.recall >= 0.85 else 'fail' }}">
                {{ '✓ PASS' if stats.recall >= 0.85 else '✗ FAIL' }}
            </td>
        </tr>
        {% endfor %}
    </table>
    
    <h2>错误用例详情</h2>
    {% if errors %}
    <table>
        <tr><th>ID</th><th>难度</th><th>输入</th><th>预期路由</th><th>实际路由</th><th>描述</th></tr>
        {% for e in errors %}
        <tr class="error-row">
            <td>{{ e.id }}</td>
            <td>{{ e.difficulty }}</td>
            <td>{{ e.input }}</td>
            <td>{{ e.expected or 'fallback' }}</td>
            <td>{{ e.actual or 'fallback' }}</td>
            <td>{{ e.description }}</td>
        </tr>
        {% endfor %}
    </table>
    {% else %}
    <p class="pass">无错误用例 🎉</p>
    {% endif %}
    
    <h2>混淆矩阵</h2>
    <div class="chart">
        <img src="confusion_matrix.png" alt="Confusion Matrix">
    </div>
    
    <h2>仪表盘</h2>
    <div class="chart">
        <img src="dashboard.png" alt="Dashboard">
    </div>
    
    <h2>置信度分布</h2>
    <table>
        <tr><th>置信度区间</th><th>用例数</th><th>占比</th><th>准确率</th></tr>
        {% for bin, stats in confidence_bins.items() %}
        <tr>
            <td>{{ bin }}</td>
            <td>{{ stats.count }}</td>
            <td>{{ '%.1f' % (stats.percentage * 100) }}%</td>
            <td>{{ '%.1f' % (stats.accuracy * 100) }}%</td>
        </tr>
        {% endfor %}
    </table>
</div>
</body>
</html>
"""


def generate_html_report(results: dict, output_dir: str):
    """生成 HTML 测试报告"""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    template = Template(HTML_TEMPLATE)
    html = template.render(
        timestamp=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        **results,
    )
    
    report_path = output_dir / "routing_accuracy_report.html"
    report_path.write_text(html, encoding="utf-8")
    return report_path
```

### 7.5 路由追踪面板集成

Prometheus 现有的 `route_tracer.html`（§7.3 of design-proposal.md）可以与测试报告集成：

```
双屏演示方案:
  左屏: route_tracer.html（实时路由决策追踪）
  右屏: routing_accuracy_report.html（测试报告 + 混淆矩阵 + 仪表盘）

演示流程:
  1. 运行测试套件 → 生成 HTML 报告
  2. 打开报告 → 展示准确率指标 + 混淆矩阵 + 各 Subagent 召回率
  3. 切换到 route_tracer.html → 实时展示路由决策链路
  4. 评委可直观看到：测试覆盖度 + 实际路由表现
```

### 7.6 Markdown 报告（CI 友好）

```markdown
# Prometheus 路由准确率测试报告

**测试时间**: 2026-07-14 15:30:00  
**测试集版本**: v1.0 (50 条)  
**路由模型**: qwen3-30b (temperature=0.0)

## 核心指标

| 指标 | 结果 | 目标 | 状态 |
|------|------|------|------|
| 路由准确率 | 91.0% | > 90% | ✅ PASS |
| 误判率 | 8.0% | < 10% | ✅ PASS |
| 平均路由延迟 | 320ms | < 500ms | ✅ PASS |

## 各 Subagent 召回率

| Subagent | 正确 | 总数 | 召回率 | 状态 |
|----------|------|------|--------|------|
| rag | 9 | 10 | 90.0% | ✅ |
| memory | 7 | 8 | 87.5% | ✅ |
| writing | 8 | 9 | 88.9% | ✅ |
| schedule | 9 | 10 | 90.0% | ✅ |
| chat | 7 | 8 | 87.5% | ✅ |
| fallback | 5 | 5 | 100.0% | ✅ |

## 错误用例

| ID | 输入 | 预期 | 实际 | 难度 |
|----|------|------|------|------|
| TC-004 | 帮我看看 GPU 算力对比 | rag_search | chat_light | medium |
| TC-038 | 为什么天空是蓝色的 | fallback | chat_light | hard |
| ... | ... | ... | ... | ... |
```

---

## 8. 与 Prometheus 现有设计的衔接

### 8.1 与 design-proposal.md 的对应

| 设计文档章节 | 本报告对应章节 |
|-------------|--------------|
| §4.1 Function Router 精准分发（>90% 目标） | §4.2 路由准确率定义 + §3 测试集设计 |
| §4.6 双层路由降低误判（<8% 目标） | §4.3 置信度指标 + §4.2.2 误判率 |
| §4.7 Router 自学习持续优化 | §5.5 自学习效果 A/B 测试 |
| §7.4 路由准确率测试套件 | §6 pytest 集成方案 |
| §7.3 路由追踪面板 | §7 可视化方案 |
| §2.5 闲聊误判保护 | §3.4.2 误判保护测试用例 |
| §2.6 Router 自学习引擎（RL-035~RL-046） | §6.3 测试文件覆盖 RL 测试项 |

### 8.2 与 CHECKLIST.md 的对应

本报告覆盖以下 CHECKLIST 项：

| CHECKLIST 项 | 本报告覆盖 | 说明 |
|-------------|-----------|------|
| SYS-006 路由准确率测试套件（50 条混合意图） | §3 + §6 | 50 条测试集 + pytest 框架 |
| RL-035 单元测试：置信度计算 | §6.2 conftest + test_confidence_scoring | 置信度计算单元测试 |
| RL-036 单元测试：路由层级决策 | §6.3 test_route_layer_decision | 3 个阈值区间测试 |
| RL-037 单元测试：澄清问题生成 | §6.3 | top-2 候选生成测试 |
| RL-038 单元测试：纠正意图识别 | §6.3 test_correction_detection | 4 种模式测试 |
| RL-039 单元测试：input_features 提取 | §6.3 | 关键词/长度/路径/技术名词检测 |
| RL-040~RL-045 集成测试 | §6.3 | L2 路由/关键词权重/提示词片段/优先级/阈值 |
| RL-046 演示验证：5 轮进化剧本 | §5.5 自学习 A/B 测试 | 学习前后准确率对比 |
| CHT-012 单元测试：complex 消息误判保护 | §6.3 test_misroute_protection | 误判保护专项测试 |
| CHT-010 单元测试：5 类意图识别准确率 | §3.4.2 + §6.3 | 闲聊用例覆盖 5 类意图 |

### 8.3 与 Router 自学习引擎的衔接

路由准确率测试套件是 Router 自学习引擎的验证基础设施：

```
自学习闭环:
  1. 路由准确率测试（基线）→ 记录 baseline accuracy
  2. 注入修正数据 → 触发策略调整（关键词权重 / 提示词片段 / 优先级）
  3. 路由准确率测试（学习后）→ 记录 learned accuracy
  4. A/B 对比（McNemar 检验）→ 验证学习效果
  5. 若显著提升 → 保留学习策略
  6. 若无显著差异或退化 → 回滚策略 + 分析原因

验证指标:
  - 同类输入第 2 次路由准确率 > 75% [目标]
  - 同类输入第 5 次路由准确率 > 90% [目标]
  - 路由准确率随使用量持续提升
```

---

## 9. 实施计划与 Checklist

### 9.1 实施阶段

| 阶段 | 内容 | 依赖 | 预估工时 |
|------|------|------|---------|
| Phase 1 | 测试集设计 + JSONL 编写 | 无 | 1-2 天 |
| Phase 2 | pytest 框架搭建 + conftest | Phase 1 | 1 天 |
| Phase 3 | 评测器实现（exact/ast/exec） | Phase 2 | 1 天 |
| Phase 4 | 主测试文件 + 参数化测试 | Phase 2, 3 | 1 天 |
| Phase 5 | A/B 测试框架 | Phase 4 | 0.5 天 |
| Phase 6 | 可视化（混淆矩阵 + 仪表盘） | Phase 4 | 1 天 |
| Phase 7 | HTML 报告生成 | Phase 6 | 0.5 天 |
| Phase 8 | CI 集成 | Phase 4, 6 | 0.5 天 |
| **合计** | | | **~7 天** |

### 9.2 详细 Checklist

#### 测试集

- [ ] RA-001 设计 50 条测试用例的 JSONL schema
- [ ] RA-002 编写 RAG 测试用例（10 条）
- [ ] RA-003 编写记忆与偏好测试用例（8 条）
- [ ] RA-004 编写写作润色翻译测试用例（9 条）
- [ ] RA-005 编写日程与任务测试用例（10 条）
- [ ] RA-006 编写闲聊陪伴测试用例（8 条）
- [ ] RA-007 编写兜底场景测试用例（5 条）
- [ ] RA-008 审查测试用例覆盖度（每 Subagent ≥ 8 条，难度分层）
- [ ] RA-009 审查误判陷阱用例（≥ 5 条 misroute_trap）

#### pytest 框架

- [ ] RA-010 创建 tests/routing_accuracy/ 目录结构
- [ ] RA-011 编写 conftest.py（fixtures: test_dataset, fr_client, functions_jsonl）
- [ ] RA-012 实现 route_message() 辅助函数
- [ ] RA-013 配置 pytest.ini markers

#### 评测器

- [ ] RA-014 实现 exact_match.py（精确匹配）
- [ ] RA-015 实现 ast_match.py（AST 匹配）
- [ ] RA-016 实现 exec_match.py（执行结果校验）
- [ ] RA-017 实现 llm_judge.py（LLM-as-Judge，可选）

#### 主测试

- [ ] RA-018 实现 test_routing_accuracy_overall（整体准确率）
- [ ] RA-019 实现 test_per_subagent_recall（各 Subagent 召回率）
- [ ] RA-020 实现 test_per_subagent_precision（各 Subagent 精确率）
- [ ] RA-021 实现 test_misroute_protection（误判保护）
- [ ] RA-022 实现 test_routing_determinism（路由确定性）
- [ ] RA-023 实现 test_confidence_scoring（置信度计算）
- [ ] RA-024 实现 test_route_layer_decision（双层路由决策）
- [ ] RA-025 实现 test_correction_detection（修正意图识别）

#### A/B 测试

- [ ] RA-026 实现 run_ab_test.py（A/B 测试运行器）
- [ ] RA-027 实现 McNemar 检验
- [ ] RA-028 实现自学习效果 A/B 测试流程

#### 可视化

- [ ] RA-029 实现混淆矩阵热力图生成
- [ ] RA-030 实现准确率仪表盘生成
- [ ] RA-031 实现置信度分布图生成
- [ ] RA-032 实现 HTML 报告生成
- [ ] RA-033 实现 Markdown 报告生成

#### CI 集成

- [ ] RA-034 编写 GitHub Actions workflow
- [ ] RA-035 实现 run_routing_suite.py 独立运行入口
- [ ] RA-036 配置报告上传 artifact

---

## 10. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| FR logprob 不可用 | 置信度指标无法计算 | 使用简化方案（top-1 单一概率），标注精度降低 |
| 50 条测试集样本量小 | A/B 测试统计显著性不足 | 重复测试取平均 + 使用 McNemar 精确检验 + 扩展到 100+ 条 |
| 路由模型版本变更导致结果不可复现 | 历史对比失效 | 记录路由模型版本号 + 使用固定模型版本 |
| 测试集过拟合（为通过测试而设计用例） | 准确率虚高 | 引入 LLM-as-Judge 生成额外测试用例 + 定期人工审查 |
| FR 服务不稳定影响 CI | CI 频繁失败 | 增加 retry 机制 + 标记 requires_fr 的测试可跳过 |
| 中英文混合输入的路由偏差 | 部分用例路由不稳定 | 测试集覆盖中英文混合 + 标注语言标签 |
| 自学习策略调整导致退化 | 准确率下降 | A/B 测试 + 自动回滚机制（准确率下降 > 3% 时回滚） |

---

## 11. 参考来源

### 11.1 学术论文与评测框架

| 来源 | 说明 | 关键贡献 |
|------|------|---------|
| **BFCL** (Berkeley Function Calling Leaderboard) | UC Berkeley, 2024 | LLM function calling 评测标准、工具数 vs 准确率曲线 |
| **τ-bench** (Tau-Bench) | Sierra Research, 2024 | 多轮工具调用评测、数据库状态校验方法 |
| **ToolBench / ToolLLM** | 清华大学, 2023 | 大规模工具调用数据集、工具描述质量影响研究 |
| **OpenAI Function Calling Guide** | OpenAI, 2023 | function calling 最佳实践、logprobs 使用方法 |
| **AgentBench** | 清华大学, 2023 | Agent 多场景评测框架 |

### 11.2 项目内部文档

| 文档 | 章节 | 关联内容 |
|------|------|---------|
| `docs/design-proposal.md` | §4 准：准确率优势 | 路由准确率目标 > 90% |
| `docs/design-proposal.md` | §7.4 路由准确率测试套件 | 50 条测试集需求 |
| `docs/design-proposal.md` | §2.6 Router 自学习引擎 | 置信度评分 + 双层路由 |
| `docs/add/add-router-learning.md` | §3 路由置信度评分 + §5 测试 Checklist | RL-035~RL-046 测试项 |
| `docs/spec.md` | §7 路由策略 | 优先级排序 + 防误判规则 |
| `docs/speed-accuracy-impact.md` | §2 准：精准分发 | 路由准确率设计决策分析 |
| `docs/CHECKLIST.md` | §6 Router 自学习引擎 | RL-035~RL-046 |
| `docs/CHECKLIST.md` | §7 系统集成 | SYS-006 路由准确率测试套件 |

### 11.3 工具与库

| 工具 | 用途 | 版本 |
|------|------|------|
| pytest | 测试框架 | >= 8.0 |
| httpx | FR API 调用 | >= 0.27 |
| statsmodels | 统计检验（McNemar） | >= 0.14 |
| matplotlib | 可视化 | >= 3.8 |
| seaborn | 热力图 | >= 0.13 |
| jinja2 | HTML 报告模板 | >= 3.1 |
| pytest-html | HTML 测试报告 | >= 4.1 |

---

> **本报告结论**：Prometheus 路由准确率测试方案采用"精确匹配为主 + AST/执行/LLM-Judge 为辅"的分层评测策略，50 条测试集覆盖 5 个 Subagent + 兜底场景、三级难度、6 类标签。通过 pytest 集成实现自动化测试与 CI 流水线衔接，通过 McNemar 检验实现 A/B 测试统计显著性验证，通过混淆矩阵 + 仪表盘 + HTML 报告实现可视化。该方案可直接支撑 design-proposal.md §4.1 的 > 90% 路由准确率目标和 §4.7 的自学习持续优化目标的验证。
