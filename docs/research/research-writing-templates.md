# 写作 Prompt 模板调研报告

> 普罗米修斯（Prometheus）项目 · 报告 11
>
> 调研日期：2026-07-14 | 版本：v1.0
>
> 关联文档：`docs/spec.md` §3.3 写作润色翻译 Subagent、`docs/design-proposal.md` §2.3.2、`docs/add/add-writing.md`

---

## 目录

1. [调研背景与目标](#1-调研背景与目标)
2. [行业最佳实践综述](#2-行业最佳实践综述)
   - 2.1 [Anthropic Prompt 工程体系](#21-anthropic-prompt-工程体系)
   - 2.2 [OpenAI Prompt 工程体系](#22-openai-prompt-工程体系)
   - 2.3 [两家的共性原则](#23-两家的共性原则)
3. [System Prompt 构造方法论](#3-system-prompt-构造方法论)
   - 3.1 [复杂 Prompt 的十元素结构](#31-复杂-prompt-的十元素结构)
   - 3.2 [System Prompt 分层架构](#32-system-prompt-分层架构)
   - 3.3 [角色设定与任务上下文](#33-角色设定与任务上下文)
4. [用户偏好注入机制](#4-用户偏好注入机制)
   - 4.1 [偏好获取与表示](#41-偏好获取与表示)
   - 4.2 [偏好注入的三个层级](#42-偏好注入的三个层级)
   - 4.3 [动态偏好 vs 静态模板](#43-动态偏好-vs-静态模板)
5. [输出格式控制](#5-输出格式控制)
   - 5.1 [XML 标签法](#51-xml-标签法)
   - 5.2 [JSON 结构化输出](#52-json-结构化输出)
   - 5.3 [Prefill 预填充技术](#53-prefill-预填充技术)
   - 5.4 [Stop Sequence 控制](#54-stop-sequence-控制)
6. [Token 预算管理](#6-token-预算管理)
   - 6.1 [Token 预算分配模型](#61-token-预算分配模型)
   - 6.2 [上下文窗口规划](#62-上下文窗口规划)
   - 6.3 [成本优化策略](#63-成本优化策略)
7. [六类文档 Prompt 模板设计](#7-六类文档-prompt-模板设计)
   - 7.1 [周报 (Weekly Report)](#71-周报-weekly-report)
   - 7.2 [邮件 (Email)](#72-邮件-email)
   - 7.3 [技术文档 (Tech Doc)](#73-技术文档-tech-doc)
   - 7.4 [会议纪要 (Meeting Minutes)](#74-会议纪要-meeting-minutes)
   - 7.5 [文章 (Article)](#75-文章-article)
   - 7.6 [PPT 大纲 (PPT Outline)](#76-ppt-大纲-ppt-outline)
8. [Prompt 模板引擎架构建议](#8-prompt-模板引擎架构建议)
9. [风险与缓解](#9-风险与缓解)
10. [附录：完整 System Prompt 模板示例](#10-附录完整-system-prompt-模板示例)

---

## 1. 调研背景与目标

普罗米修斯项目的写作 Subagent（`writing_engine.py`）需要支持 7 种文档类型的生成（`weekly_report`、`email`、`tech_doc`、`meeting_minutes`、`article`、`essay`、`ppt_outline`），以及润色（`writing_polish`）、翻译（`writing_translate`）和去AI化（`writing_humanize`）四个工具。

本报告聚焦于以下核心问题：

| 问题域 | 关键决策点 |
|--------|-----------|
| **System Prompt 构造** | 如何为 7 种文档类型设计统一且可扩展的 system prompt 架构 |
| **用户偏好注入** | 如何从 memory_engine 获取偏好并动态注入到 prompt 中 |
| **输出格式控制** | 如何确保 LLM 输出严格符合 Markdown 结构、JSON 结构等格式要求 |
| **Token 预算** | 如何在 system prompt + 模板 + 偏好 + 用户输入之间合理分配 token 预算 |

**调研来源：**
- Anthropic Prompt Engineering Interactive Tutorial（9 章 + 附录，GitHub: `anthropics/prompt-eng-interactive-tutorial`）
- OpenAI Cookbook（ChatGPT 模型输入格式化指南）
- OpenAI Chat Completions API 最佳实践文档
- Prometheus `design-proposal.md` §2.3.2 写作引擎设计
- Prometheus `spec.md` §3.3 工具定义与参数枚举

---

## 2. 行业最佳实践综述

### 2.1 Anthropic Prompt 工程体系

Anthropic 的 prompt 工程教程是业界最系统化的指南之一，其核心课程结构如下：

| 章节 | 核心技术 | 与写作模板的关联 |
|------|---------|-----------------|
| Ch1: Basic Prompt Structure | Messages API 的 `system` / `user` / `assistant` 三角色结构 | System prompt 分离于对话消息 |
| Ch2: Being Clear and Direct | 清晰直接的表达，避免歧义 | 模板中使用明确的结构化指令 |
| Ch3: Assigning Roles | 角色提示（Role Prompting） | "你是专业的文档写作助手" |
| Ch4: Separating Data from Instructions | XML 标签分离数据与指令 | 偏好数据用 `<user_preferences>` 标签包裹 |
| Ch5: Formatting Output | XML 标签 + JSON 格式 + Prefill | 输出格式控制的核心技术 |
| Ch6: Precognition | 逐步思考（Chain of Thought） | 复杂文档生成前先列大纲 |
| Ch7: Using Examples | Few-shot Prompting | 提供高质量示例引导输出风格 |
| Ch8: Avoiding Hallucinations | 幻觉规避 | 明确"不知道就说不知道"的指令 |
| Ch9: Complex Prompts | 十元素复杂 prompt 结构 | 写作模板的架构基础 |

**关键发现：** Anthropic 推荐的复杂 prompt 结构（Ch9）包含 **10 个可组合的 prompt 元素**，其顺序有推荐但非强制。这是本报告设计写作模板架构的核心参考。

### 2.2 OpenAI Prompt 工程体系

OpenAI 的最佳实践更偏向 API 参数层面：

| 实践 | 说明 | 适用场景 |
|------|------|---------|
| System message 优先 | `gpt-4` 及以后模型更重视 system message | 写作场景的 system prompt 设计 |
| Temperature 控制 | `temperature=0` 用于确定性输出，`0.7` 用于创意写作 | 周报/技术文档用 0，文章用 0.7 |
| Frequency penalty | 惩罚重复 token，减少冗余 | 长文档生成 |
| Message 交替 | user/assistant 必须交替，以 user 开始 | Few-shot 示例的消息结构 |
| Function calling | 结构化输出替代 prompt 约束 | 可选的 JSON 输出强制方案 |

**关键发现：** OpenAI 强调 system message 在 `gpt-4` 系列模型中权重更高，建议将核心指令放在 system message 中而非 user message 中。这与 Anthropic 的建议一致。

### 2.3 两家的共性原则

综合 Anthropic 和 OpenAI 的实践，以下 7 条原则是两家共同认可的：

1. **System Prompt 与 User Prompt 分离**：角色、规则、格式放在 system；具体任务数据放在 user
2. **使用结构化标记**：XML 标签（Anthropic 偏好）或 Markdown 标题分隔不同 prompt 段落
3. **示例驱动（Few-shot）**：提供 1-3 个高质量示例比冗长的规则描述更有效
4. **明确输出格式**：用具体的格式模板或 Prefill 约束输出，而非模糊的"请按格式输出"
5. **逐步推理引导**：复杂任务要求先思考再输出（CoT / Precognition）
6. **给 LLM 一个"出口"**：不确定时明确说"不知道"，而非编造内容
7. **先复杂后精简**：先用全部元素让 prompt 工作，再逐步删减优化

---

## 3. System Prompt 构造方法论

### 3.1 复杂 Prompt 的十元素结构

Anthropic Ch9 提出的复杂 prompt 结构包含 10 个可组合元素，按推荐顺序排列：

| 序号 | 元素 | 说明 | 写作模板中的对应 |
|------|------|------|-----------------|
| 1 | `user` role | API 调用必须以 user 角色开始 | API 调用层保证 |
| 2 | Task Context | 角色设定与总体目标 | "你是专业文档写作助手" |
| 3 | Tone Context | 语气与风格设定 | formal / casual / technical / academic |
| 4 | Task Description & Rules | 详细任务描述与规则 | 文档结构要求、写作规范 |
| 5 | Examples | Few-shot 示例 | 高质量文档范例 |
| 6 | Input Data | 需要处理的数据 | 用户偏好、历史上下文 |
| 7 | Immediate Task | 当前具体任务 | "请根据以下要点生成本周周报" |
| 8 | Precognition | 逐步思考引导 | "先列出大纲，再生成正文" |
| 9 | Output Formatting | 输出格式要求 | Markdown 结构、XML 标签包裹 |
| 10 | Prefill | 预填充 assistant 回复 | `<document>` 开始标签 |

**关键原则：**
- 并非所有元素都需要——根据文档类型选择性使用
- 元素 2-3（上下文/语气）放在 prompt 前部
- 元素 7-9（当前任务/推理/格式）放在 prompt 后部
- 元素 5（示例）是知识工作中最有效的单一工具

### 3.2 System Prompt 分层架构

基于十元素结构，本报告建议 Prometheus 采用**三层分层架构**：

```
┌─────────────────────────────────────────────────────┐
│  Layer 1: 全局 System Prompt（所有文档类型共享）       │
│  ├── 角色设定：专业文档写作助手                        │
│  ├── 通用写作规范：中文为主、Markdown 输出             │
│  └── 全局规则：不编造、不输出无关内容                  │
├─────────────────────────────────────────────────────┤
│  Layer 2: 文档类型模板（按 doc_type 选择）             │
│  ├── 结构引导：周报三段式 / 邮件三段式 / 技术文档层级   │
│  ├── 写作规范：该类型的特定要求                        │
│  └── Few-shot 示例：1-2 个高质量范例                  │
├─────────────────────────────────────────────────────┤
│  Layer 3: 用户偏好与当前任务（动态注入）               │
│  ├── 用户偏好：format / language / tone / structure   │
│  ├── 当前任务：topic + key_points + style + length    │
│  └── 输出格式控制：XML 标签 / Prefill                 │
└─────────────────────────────────────────────────────┘
```

**分层的好处：**
- Layer 1 全局稳定，可缓存 token，降低重复计算成本
- Layer 2 按需加载，7 种文档类型对应 7 个模板文件
- Layer 3 动态构造，每次调用根据参数和偏好实时生成

### 3.3 角色设定与任务上下文

Anthropic Ch3 的核心建议是：**角色设定应包含具体身份、能力边界和行为约束**。

**推荐的 System Prompt 角色设定模板：**

```
你是由普罗米修斯系统创建的专业文档写作助手。

你的能力：
- 根据用户提供的主题和要点，生成结构清晰、内容准确的各类文档
- 支持 7 种文档类型：周报、邮件、技术文档、会议纪要、文章、短文、PPT 大纲
- 适应用户的个人写作偏好和风格

你的行为约束：
- 只根据用户提供的要点生成内容，不编造未提供的事实或数据
- 如果要点不足以生成完整文档，基于要点合理扩展但保持事实准确
- 始终使用中文输出（除非用户特别指定其他语言）
- 输出格式为 Markdown
- 不输出与文档无关的寒暄、解释或元评论
```

**关键点：**
- 明确能力边界（7 种类型）而非泛泛的"写作助手"
- 行为约束中包含"不编造"这一防幻觉规则（Anthropic Ch8）
- "不输出寒暄"直接来自 Anthropic Ch2 的"Be Clear and Direct"

---

## 4. 用户偏好注入机制

### 4.1 偏好获取与表示

根据 `design-proposal.md` §2.3.2，偏好注入流水线如下：

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

### 4.2 偏好注入的三个层级

偏好应在 prompt 的不同位置注入，形成**三层注入**：

| 层级 | 注入位置 | 偏好类型 | 示例 |
|------|---------|---------|------|
| **L1: System 基础层** | System prompt 前段 | 语言、格式、全局风格 | `preferred_language: zh-CN` |
| **L2: 模板适配层** | System prompt 中段 | 结构偏好、语气偏好 | `structure: 三段式`, `tone: professional` |
| **L3: 任务约束层** | User prompt | 具体参数 | `style: formal`, `length: medium` |

**偏好注入的 XML 标签法（Anthropic Ch4 推荐）：**

```xml
<user_preferences>
  <language>zh-CN</language>
  <format>markdown</format>
  <tone>professional</tone>
  <structure>本周完成 + 下周计划 + 风险与问题</structure>
</user_preferences>
```

使用 XML 标签包裹偏好数据，使 LLM 能清晰区分"指令"和"数据"，这是 Anthropic Ch4（Separating Data from Instructions）的核心建议。

### 4.3 动态偏好 vs 静态模板

| 维度 | 静态模板（templates/*.md） | 动态偏好（memory_recall） |
|------|--------------------------|--------------------------|
| 来源 | 开发者预写的结构引导 | 用户历史交互中学习的偏好 |
| 变化频率 | 低（版本更新时修改） | 高（每次调用可能不同） |
| 注入方式 | Layer 2（文档类型模板） | Layer 3（动态注入） |
| Token 占比 | 200-500 tokens | 50-150 tokens |
| 优先级 | 被动态偏好覆盖 | 最高优先级 |

**冲突处理规则：** 当动态偏好与静态模板冲突时，动态偏好优先。例如：
- 静态模板定义周报结构为"完成 + 计划 + 风险"
- 用户偏好中 `structure: "本周亮点 + 详细进展 + 下周重点"`
- → 使用用户偏好中的结构

在 prompt 中明确声明优先级：

```
如果用户偏好与下方文档模板的结构建议冲突，以用户偏好为准。
```

---

## 5. 输出格式控制

### 5.1 XML 标签法

Anthropic Ch5 的核心建议：**让 LLM 用 XML 标签包裹输出内容**，便于程序提取。

**应用示例：**

```python
# System prompt 中指定
OUTPUT_FORMATTING = "将生成的文档内容放在 <document></document> 标签内。不要输出标签外的任何内容。"

# Prefill（预填充 assistant 回复）
PREFILL = "<document>"
```

**对 Prometheus 的建议：** 写作生成工具的输出用 `<document>` 标签包裹，便于 `writing_engine.py` 提取纯文档内容，剔除 LLM 可能附加的寒暄。

### 5.2 JSON 结构化输出

对于需要元数据的场景（如 `writing_humanize` 需要返回 `changes_summary`），使用 JSON 格式：

```python
# System prompt
"以 JSON 格式输出，包含以下字段：
{
  \"document\": \"生成的文档全文\",
  \"format\": \"markdown\",
  \"word_count\": 估算字数,
  \"sections\": [\"章节1\", \"章节2\"]
}"

# Prefill
PREFILL = "{"
```

**Anthropic 建议：** Prefill 以 `{` 开头可以近乎确定性地强制 JSON 输出。结合 `stop_sequences` 可以进一步控制。

### 5.3 Prefill 预填充技术

Prefill 是 Anthropic 独有的技术（OpenAI 不支持 assistant 消息预填充），在 OpenAI-compatible API 中的兼容性需注意：

| 技术 | Anthropic API | OpenAI API | Prometheus 上游 LLM |
|------|--------------|------------|---------------------|
| Prefill assistant 消息 | ✅ 原生支持 | ❌ 不支持 | ⚠️ 取决于上游模型 |
| XML 标签输出 | ✅ 推荐 | ✅ 可用 | ✅ 可用 |
| JSON Prefill (`{`) | ✅ 推荐 | ⚠️ 部分支持 | ⚠️ 取决于上游模型 |
| Stop sequences | ✅ `stop_sequences` | ✅ `stop` | ✅ 可用 |

**重要约束：** Prometheus 上游 LLM 通过 OpenAI-compatible API 调用（`/v1/chat/completions`），Prefill 技术可能不被支持。因此：

- **主方案：** 使用 XML 标签 + 明确的格式指令 + `stop` 参数
- **备选方案：** 如果上游模型支持 assistant 消息预填充（如 DeepSeek-V4），则启用 Prefill
- **降级方案：** 纯格式指令 + 后处理提取（正则匹配 XML 标签内容）

### 5.4 Stop Sequence 控制

利用 `stop` 参数在 LLM 输出闭合标签后停止生成，节省 token 和时间：

```python
response = httpx.post(
    f"{upstream_url}/v1/chat/completions",
    json={
        "model": upstream_model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt}
        ],
        "stop": ["</document>"],  # 输出闭合标签后停止
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
)
```

---

## 6. Token 预算管理

### 6.1 Token 预算分配模型

假设上游 LLM 上下文窗口为 128K tokens（DeepSeek-V4-Pro / GPT-4o 级别），写作场景的 token 预算分配建议：

| 组成部分 | Token 预算 | 占比 | 说明 |
|---------|-----------|------|------|
| System Prompt (Layer 1) | 300-500 | ~1% | 全局角色 + 规则 |
| 文档模板 (Layer 2) | 200-800 | ~1-2% | 按文档类型，技术文档最长 |
| 用户偏好 (Layer 3a) | 50-150 | <1% | XML 标签包裹的偏好数据 |
| Few-shot 示例 | 200-600 | ~1% | 1-2 个示例 |
| 用户输入 (Layer 3b) | 100-2000 | ~2-5% | topic + key_points |
| **输入总计** | **850-4050** | **~3-8%** | |
| 输出预留 (max_tokens) | 2000-8000 | ~2-10% | 按文档长度 |
| **总计** | **2850-12050** | **~2-12%** | 远低于 128K 上限 |

**关键观察：** 写作场景的 token 使用量远低于模型上下文窗口上限。主要约束不是上下文长度，而是：
1. **输出 token 上限**（`max_tokens`）：长文档需要 4000-8000 tokens
2. **延迟**：输入越长首 token 延迟越高
3. **成本**：输入 + 输出 token 都计费

### 6.2 上下文窗口规划

```
┌─────────────────────────── 128K tokens (模型上下文窗口) ───────────────────────────┐
│                                                                                   │
│  ┌── 输入 (~4K) ──────────────────┐  ┌── 输出预留 (max_tokens) ──┐  ┌── 余量 ──┐ │
│  │                                │  │                           │  │          │ │
│  │ System: 500                    │  │ short:  2,000 tokens      │  │ ~120K    │ │
│  │ Template: 800                  │  │ medium: 4,000 tokens      │  │ (未使用)  │ │
│  │ Preferences: 150               │  │ long:   8,000 tokens      │  │          │ │
│  │ Examples: 600                  │  │                           │  │          │ │
│  │ User Input: 2,000              │  │                           │  │          │ │
│  │                                │  │                           │  │          │ │
│  └────────────────────────────────┘  └───────────────────────────┘  └──────────┘ │
│                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────┘
```

**max_tokens 参数映射（对应 `length` 枚举）：**

| length 参数 | max_tokens | 预期输出字数（中文） | 适用场景 |
|------------|------------|-------------------|---------|
| `short` | 2,000 | 800-1,200 字 | 简短邮件、周报摘要 |
| `medium` | 4,000 | 1,500-2,500 字 | 标准周报、会议纪要 |
| `long` | 8,000 | 3,000-5,000 字 | 技术文档、长文章 |

### 6.3 成本优化策略

| 策略 | 节省比例 | 实现方式 | 风险 |
|------|---------|---------|------|
| **缓存 System Prompt** | 输入 token 减少 30-50% | Layer 1 固定不变，利用 API 的 prompt caching | 需要上游 API 支持 |
| **精简模板** | 输入 token 减少 10-20% | 模板文件保持 200-500 tokens，删除冗余描述 | 可能降低输出质量 |
| **减少 Few-shot** | 输入 token 减少 15-30% | 从 2-3 个示例减为 1 个 | 风格一致性下降 |
| **Stop sequence** | 输出 token 减少 10-30% | `</document>` 后停止，避免 LLM 附加评论 | 低风险 |
| **短文档用小模型** | 成本降低 50-80% | `short` 长度的简单文档路由到更便宜的模型 | 质量波动 |
| **Temperature=0** | 减少重试 | 确定性输出，减少因不满意的重试 | 创意文档可能过于呆板 |

**Temperature 建议表：**

| 文档类型 | Temperature | 理由 |
|---------|-------------|------|
| 周报 | 0.3 | 需要一定的结构灵活性，但内容必须基于事实 |
| 邮件 | 0.4 | 语气需要自然，但格式必须规范 |
| 技术文档 | 0.2 | 准确性第一，减少创造性发挥 |
| 会议纪要 | 0.2 | 忠实记录，不添加主观内容 |
| 文章 | 0.7 | 创意性写作，需要多样性和可读性 |
| 短文 | 0.6 | 适度创意 |
| PPT 大纲 | 0.4 | 结构清晰但内容可灵活 |

---

## 7. 六类文档 Prompt 模板设计

以下为 6 种核心文档类型的 prompt 模板设计（`essay` 短文与 `article` 类似，合并讨论）。每个模板遵循三层架构：Layer 1（全局）+ Layer 2（类型模板）+ Layer 3（动态注入）。

### 7.1 周报 (Weekly Report)

**结构特征：** 三段式（本周完成 + 下周计划 + 风险与问题）

**Layer 2 模板 (`templates/weekly_report.md`)：**

```
## 文档类型：周报

### 结构要求
按以下三段式结构生成：
1. **本周完成**：列出本周完成的主要工作，每项包含任务名称和简述
2. **下周计划**：列出下周计划的工作项
3. **风险与问题**：列出当前遇到的风险和需要协调的问题（如无则写"暂无"）

### 写作规范
- 每项工作用列表项（- ）表示
- 工作描述简明扼要，一句话说明做了什么
- 如有数据指标（如完成率、数量），优先展示
- 语气：专业、客观
- 篇幅控制：medium 约 1500 字，short 约 800 字

### 示例
<example>
## 本周完成
- 完成 API 网关模块开发，包含 3 个接口的实现和单元测试
- 修复用户反馈的 5 个 bug，覆盖登录、支付、通知模块
- 完成数据库迁移方案评审，获得架构组通过

## 下周计划
- 启动 API 网关性能优化，目标 P99 < 200ms
- 协助前端团队联调新接口
- 编写数据库迁移操作手册

## 风险与问题
- 测试环境数据库性能不稳定，需运维团队协助排查
</example>
```

**Layer 3 动态注入：**

```xml
<user_preferences>
  <language>zh-CN</language>
  <tone>professional</tone>
  <structure>{用户偏好中的结构，或默认三段式}</structure>
</user_preferences>

<task>
主题：{topic}
要点：
{key_points 的逐项列表}
风格：{style}
篇幅：{length}
</task>

请根据以上信息生成本周周报。先在思考中列出大纲，再生成完整文档。
将文档内容放在 <document></document> 标签内。
```

### 7.2 邮件 (Email)

**结构特征：** 称呼 + 正文（目的 + 内容 + 行动项）+ 签名

**Layer 2 模板 (`templates/email.md`)：**

```
## 文档类型：邮件

### 结构要求
1. **称呼**：根据收件人关系选择合适称呼（正式/非正式）
2. **正文**：
   - 开头：简明说明邮件目的
   - 主体：详细内容，每点用列表或段落
   - 结尾：明确的行动项或下一步
3. **签名**：标准签名格式

### 写作规范
- 邮件主题（Subject）单独一行，放在正文之前
- 段落之间空行分隔
- 如有多个要点，使用编号列表
- 语气根据 style 参数：formal 使用敬语，casual 使用自然口语
- 避免冗长，一封邮件聚焦一个主题

### 示例
<example>
Subject: 关于 API 网关上线时间的确认

张经理，您好：

关于 API 网关模块的上线事宜，需要与您确认以下事项：

1. 上线时间：建议本周五（X月X日）晚 22:00 进行灰度发布
2. 影响范围：仅影响 v2 接口，v1 接口不受影响
3. 回滚方案：已准备回滚脚本，可在 5 分钟内完成回滚

请在周三前回复确认，以便我们安排运维资源。

谢谢！

XXX
</example>
```

### 7.3 技术文档 (Tech Doc)

**结构特征：** 标题 + 概述 + 架构/设计 + 实现细节 + API/接口 + 注意事项

**Layer 2 模板 (`templates/tech_doc.md`)：**

```
## 文档类型：技术文档

### 结构要求
1. **标题**：H1 标题，简洁明确
2. **概述**：1-2 段说明文档目的和背景
3. **架构设计**：使用文字描述系统架构，如有必要使用 ASCII 图或 Mermaid 语法
4. **核心模块**：按模块分节描述，每节包含职责、接口、关键逻辑
5. **数据结构**：关键数据结构定义（代码块）
6. **API 接口**：接口定义，包含请求/响应格式
7. **注意事项**：性能、安全、兼容性等需要注意的点

### 写作规范
- 使用 Markdown 标题层级（H1 -> H2 -> H3）
- 代码示例使用代码块，标注语言类型
- 技术术语首次出现时给出解释
- 语气：technical，准确、简洁、无冗余
- 保持客观，不使用主观评价词

### 示例
<example>
# API 网关模块技术文档

## 概述

API 网关模块负责统一处理所有外部 API 请求，提供路由转发、鉴权、限流和监控能力。

## 架构设计

```
Client -> [Nginx] -> [API Gateway] -> [Backend Services]
                      |-> Auth Middleware
                      |-> Rate Limiter
                      |-> Request Logger
```

## 核心模块

### 路由引擎

**职责**：根据请求路径和 HTTP 方法将请求转发到对应的后端服务。

**关键接口**：
- `route(request: HttpRequest) -> ServiceEndpoint`
- `match(path: str, method: str) -> RouteRule`

## 注意事项

- 限流默认阈值为 100 QPS，可通过配置文件调整
- 鉴权中间件支持 JWT 和 API Key 两种方式
</example>
```

### 7.4 会议纪要 (Meeting Minutes)

**结构特征：** 会议信息 + 参会人 + 议题 + 决议 + 行动项

**Layer 2 模板 (`templates/meeting_minutes.md`)：**

```
## 文档类型：会议纪要

### 结构要求
1. **会议信息**：会议主题、时间、地点（或会议链接）
2. **参会人员**：列出参会者，标注主持人和记录人
3. **议题与讨论**：按议题分节，每个议题包含讨论要点
4. **决议**：会议达成的决定，编号列出
5. **行动项**：待办事项表格，包含任务、负责人、截止时间

### 写作规范
- 忠实记录讨论内容，不添加主观评价
- 决议用加粗标注
- 行动项使用表格格式
- 语气：objective，简洁
- 如有未决议题，明确标注"待讨论"

### 示例
<example>
# 会议纪要：API 网关上线评审

**时间**：2026-07-14 14:00-15:30
**地点**：会议室 A / 线上会议
**主持人**：张经理
**记录人**：李工程师
**参会人**：张经理、李工程师、王运维、赵前端

## 议题与讨论

### 1. 上线时间确认
- 张经理建议本周五上线，运维团队确认资源可用
- 赵前端反馈前端联调还需 2 天，可能赶不上周五
- **讨论结果**：上线推迟到下周一

## 决议
1. **上线时间定为下周一（7月20日）晚 22:00**
2. 灰度发布，先开放 10% 流量

## 行动项
| 任务 | 负责人 | 截止时间 |
|------|--------|---------|
| 完成前端联调 | 赵前端 | 7月18日 |
| 准备灰度配置 | 王运维 | 7月19日 |
| 编写上线操作手册 | 李工程师 | 7月19日 |
</example>
```

### 7.5 文章 (Article)

**结构特征：** 标题 + 导语 + 正文（多段论述）+ 结论

**Layer 2 模板 (`templates/article.md`)：**

```
## 文档类型：文章

### 结构要求
1. **标题**：吸引读者，点明主题
2. **导语**：1-2 段引入话题，激发阅读兴趣
3. **正文**：2-4 个主要论点，每个论点包含论据和论证
4. **结论**：总结全文，给出观点或展望

### 写作规范
- 段落之间逻辑连贯，使用自然过渡（非机械的"首先/其次/最后"）
- 论点用小标题（H2）分隔
- 适当使用举例、类比增强可读性
- 避免空泛套话和 AI 写作痕迹（如"在当今时代""随着...的发展"）
- 语气根据 style 参数：formal 严谨学术，casual 轻松随笔
- 文章风格可使用较高 temperature（0.7）增强可读性

### 示例
<example>
# 从单体到微服务：一个团队的真实迁移故事

当我们决定拆分那个维护了五年的单体应用时，团队里没有人意识到这条路会有多长。

## 为什么要迁移

系统最初的设计很简单：一个 Rails 应用，一个 PostgreSQL 数据库。但随着业务增长，这个应用变成了一个 30 万行代码的巨石。每次部署都需要 40 分钟，一个小的 bug 修复可能影响到完全不相关的模块。

转折点出现在去年双十一。订单服务的一个内存泄漏导致整个系统宕机两小时。那次事故之后，CTO 说了一句话："我们必须拆了。"

## 第一步：边界识别

我们花了三周时间梳理业务边界。方法很朴素——在白板上画系统调用图，用不同颜色标注业务域。

（后续内容省略...）

## 结论

迁移用了一年，中间踩了无数坑。但回头看，最值得的决定是在迁移开始前花了足够长的时间理解业务边界。技术方案可以迭代，但业务边界的认知错误代价极高。
</example>
```

### 7.6 PPT 大纲 (PPT Outline)

**结构特征：** 逐页大纲，每页包含标题 + 要点 + 备注

**Layer 2 模板 (`templates/ppt_outline.md`)：**

```
## 文档类型：PPT 大纲

### 结构要求
按页生成，每页包含：
1. **页码**：Slide N
2. **标题**：该页主题（简洁，不超过 15 字）
3. **要点**：3-5 个 bullet points
4. **备注**：演讲者备注（该页讲解要点）

### 整体结构建议
- Slide 1：封面（标题 + 副标题 + 演讲者）
- Slide 2：目录/概览
- Slide 3-N：正文（根据主题划分）
- Slide N+1：总结
- Slide N+2：Q&A / 谢谢

### 写作规范
- 每页要点不超过 5 条，每条不超过 20 字
- 标题层级清晰
- 备注详细说明该页的演讲要点
- 语气根据 style 参数

### 示例
<example>
## Slide 1
**标题**：API 网关技术方案
**要点**：
- 演讲者：李工程师
- 日期：2026-07-14
**备注**：开场介绍，说明本次分享的背景和目标

## Slide 2
**标题**：目录
**要点**：
- 背景与问题
- 方案设计
- 关键技术
- 上线计划
**备注**：简要介绍今天的四个部分

## Slide 3
**标题**：背景与问题
**要点**：
- 单体架构部署慢（40分钟）
- 耦合严重，影响范围大
- 双十一宕机事件
**备注**：用双十一事件引出痛点，强调迁移的必要性

## Slide 4
**标题**：方案设计
**要点**：
- 网关层：路由 + 鉴权 + 限流
- 微服务拆分：按业务域
- 渐进式迁移：Strangler Fig 模式
**备注**：重点讲解 Strangler Fig 模式的选择原因
</example>
```

---

## 8. Prompt 模板引擎架构建议

基于以上调研，建议 `writing_engine.py` 的 prompt 构造流程如下：

```python
# writing_engine.py — Prompt 构造核心逻辑

def _build_prompt(
    doc_type: str,
    topic: str,
    key_points: list[str],
    style: str,
    length: str,
    user_preferences: dict,
) -> tuple[str, str, dict]:
    """
    构造 system prompt 和 user prompt。

    Returns:
        (system_prompt, user_prompt, api_kwargs)
    """

    # ── Layer 1: 全局 System Prompt ──
    L1_GLOBAL = """你是由普罗米修斯系统创建的专业文档写作助手。

你的能力：
- 根据用户提供的主题和要点，生成结构清晰、内容准确的各类文档
- 支持 7 种文档类型：周报、邮件、技术文档、会议纪要、文章、短文、PPT 大纲
- 适应用户的个人写作偏好和风格

你的行为约束：
- 只根据用户提供的要点生成内容，不编造未提供的事实或数据
- 如果要点不足以生成完整文档，基于要点合理扩展但保持事实准确
- 始终使用中文输出（除非用户特别指定其他语言）
- 输出格式为 Markdown
- 不输出与文档无关的寒暄、解释或元评论
"""

    # ── Layer 2: 文档类型模板 ──
    template = _load_template(f"templates/{doc_type}.md")

    # ── Layer 3a: 偏好注入 ──
    prefs_xml = _format_preferences(user_preferences)

    # ── 组装 System Prompt ──
    system_prompt = f"""{L1_GLOBAL}

---

## 文档模板

{template}

---

## 用户偏好

{prefs_xml}

如果用户偏好与文档模板的结构建议冲突，以用户偏好为准。
"""

    # ── Layer 3b: User Prompt ──
    key_points_str = "\n".join(f"- {p}" for p in key_points) if key_points else "（用户未提供具体要点，请根据主题合理生成）"

    # ── 根据文档类型选择 temperature ──
    temp_map = {
        "weekly_report": 0.3, "email": 0.4, "tech_doc": 0.2,
        "meeting_minutes": 0.2, "article": 0.7, "essay": 0.6,
        "ppt_outline": 0.4,
    }
    temperature = temp_map.get(doc_type, 0.4)

    # ── 根据篇幅选择 max_tokens ──
    max_tokens_map = {"short": 2000, "medium": 4000, "long": 8000}
    max_tokens = max_tokens_map.get(length, 4000)

    # ── User Prompt 构造 ──
    user_prompt = f"""<task>
主题：{topic}
要点：
{key_points_str}
风格：{style}
篇幅：{length}
</task>

请根据以上信息生成{doc_type}文档。先在思考中列出大纲，再生成完整文档。
将文档内容放在 <document></document> 标签内。
"""

    api_kwargs = {
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stop": ["</document>"],
    }

    return system_prompt, user_prompt, api_kwargs


def _format_preferences(prefs: dict) -> str:
    """将偏好字典格式化为 XML 标签格式。"""
    if not prefs:
        return "<user_preferences>（无特定偏好，使用默认设置）</user_preferences>"

    lines = ["<user_preferences>"]
    field_map = {
        "preferred_language": "language",
        "writing_format": "format",
        "tone": "tone",
        "structure": "structure",
    }
    for key, label in field_map.items():
        val = prefs.get(key)
        if val:
            lines.append(f"  <{label}>{val}</{label}>")
    lines.append("</user_preferences>")
    return "\n".join(lines)


def _load_template(path: str) -> str:
    """从文件加载文档类型模板。"""
    # 实际实现中从 ~/.prometheus/templates/ 或打包路径加载
    ...
```

**架构关键设计决策：**

| 决策点 | 选择 | 理由 |
|--------|------|------|
| System/User 分离 | ✅ 采用 | Anthropic + OpenAI 共同推荐 |
| 三层分层架构 | ✅ 采用 | 全局稳定 + 类型灵活 + 动态注入 |
| XML 标签分离数据 | ✅ 采用 | Anthropic Ch4 核心建议 |
| Few-shot 示例 | ✅ 每类型 1 个 | 平衡 token 成本与效果 |
| Prefill 技术 | ❌ 不采用 | OpenAI-compatible API 兼容性不确定 |
| Stop sequence | ✅ 采用 | 节省输出 token，避免冗余 |
| Temperature 按类型 | ✅ 采用 | 技术文档需低 temperature，文章需高 |
| max_tokens 按篇幅 | ✅ 采用 | short/medium/long 三级映射 |

---

## 9. 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| **上游 LLM 不支持 stop 参数** | 输出包含多余内容 | 低 | 后处理正则提取 `<document>` 内容 |
| **偏好注入导致 prompt 过长** | 超出 token 预算 | 低 | 限制偏好字段数量，XML 标签简洁 |
| **LLM 忽略格式指令** | 输出不符合 Markdown 结构 | 中 | Few-shot 示例 + 明确格式指令双重约束 |
| **Few-shot 示例过时** | 引导效果下降 | 中 | 示例作为模板文件管理，可独立更新 |
| **Temperature 过高导致幻觉** | 事实性文档包含编造内容 | 中 | 技术文档/会议纪要使用低 temperature |
| **Prefill 不兼容** | 无法使用预填充技术 | 已确认 | 设计中不依赖 Prefill，使用 XML 标签替代 |
| **模板与偏好冲突** | 输出结构混乱 | 中 | Prompt 中明确声明"以用户偏好为准" |
| **多语言混用** | 中文文档中出现英文 | 低 | System prompt 强调"始终使用中文" |

---

## 10. 附录：完整 System Prompt 模板示例

以下为"周报"类型的完整 prompt 示例（所有层合并后）：

```
你是由普罗米修斯系统创建的专业文档写作助手。

你的能力：
- 根据用户提供的主题和要点，生成结构清晰、内容准确的各类文档
- 支持 7 种文档类型：周报、邮件、技术文档、会议纪要、文章、短文、PPT 大纲
- 适应用户的个人写作偏好和风格

你的行为约束：
- 只根据用户提供的要点生成内容，不编造未提供的事实或数据
- 如果要点不足以生成完整文档，基于要点合理扩展但保持事实准确
- 始终使用中文输出（除非用户特别指定其他语言）
- 输出格式为 Markdown
- 不输出与文档无关的寒暄、解释或元评论

---

## 文档模板

## 文档类型：周报

### 结构要求
按以下三段式结构生成：
1. **本周完成**：列出本周完成的主要工作，每项包含任务名称和简述
2. **下周计划**：列出下周计划的工作项
3. **风险与问题**：列出当前遇到的风险和需要协调的问题（如无则写"暂无"）

### 写作规范
- 每项工作用列表项（- ）表示
- 工作描述简明扼要，一句话说明做了什么
- 如有数据指标（如完成率、数量），优先展示
- 语气：专业、客观
- 篇幅控制：medium 约 1500 字，short 约 800 字

### 示例
<example>
## 本周完成
- 完成 API 网关模块开发，包含 3 个接口的实现和单元测试
- 修复用户反馈的 5 个 bug，覆盖登录、支付、通知模块
- 完成数据库迁移方案评审，获得架构组通过

## 下周计划
- 启动 API 网关性能优化，目标 P99 < 200ms
- 协助前端团队联调新接口
- 编写数据库迁移操作手册

## 风险与问题
- 测试环境数据库性能不稳定，需运维团队协助排查
</example>

---

## 用户偏好

<user_preferences>
  <language>zh-CN</language>
  <format>markdown</format>
  <tone>professional</tone>
  <structure>本周完成 + 下周计划 + 风险与问题</structure>
</user_preferences>

如果用户偏好与文档模板的结构建议冲突，以用户偏好为准。
```

**对应的 User Prompt：**

```
<task>
主题：本周工作总结
要点：
- 完成 writing_engine.py 的 prompt 构造模块
- 调研 Anthropic/OpenAI prompt 工程最佳实践
- 编写 6 类文档的 prompt 模板
风格：formal
篇幅：medium
</task>

请根据以上信息生成 weekly_report 文档。先在思考中列出大纲，再生成完整文档。
将文档内容放在 <document></document> 标签内。
```

**API 调用参数：**

```json
{
  "model": "deepseek-v4-pro",
  "messages": [
    {"role": "system", "content": "<上述 system_prompt>"},
    {"role": "user", "content": "<上述 user_prompt>"}
  ],
  "temperature": 0.3,
  "max_tokens": 4000,
  "stop": ["</document>"]
}
```

---

## 参考资料

| 来源 | 链接 | 关键内容 |
|------|------|---------|
| Anthropic Prompt Engineering Tutorial | `github.com/anthropics/prompt-eng-interactive-tutorial` | 9 章 + 附录，十元素复杂 prompt 结构 |
| Anthropic Ch1: Basic Prompt Structure | `Anthropic 1P/01_Basic_Prompt_Structure.ipynb` | System/User/Assistant 三角色结构 |
| Anthropic Ch4: Separating Data from Instructions | `Anthropic 1P/04_Separating_Data_and_Instructions.ipynb` | XML 标签分离数据与指令 |
| Anthropic Ch5: Formatting Output | `Anthropic 1P/05_Formatting_Output_and_Speaking_for_Claude.ipynb` | XML/JSON 输出 + Prefill + Stop Sequence |
| Anthropic Ch7: Few-Shot Prompting | `Anthropic 1P/07_Using_Examples_Few-Shot_Prompting.ipynb` | 示例驱动的格式与风格控制 |
| Anthropic Ch9: Complex Prompts | `Anthropic 1P/09_Complex_Prompts_from_Scratch.ipynb` | 十元素结构 + 行业用例 |
| OpenAI Cookbook: ChatGPT Input Formatting | `github.com/openai/openai-cookbook` | System message 权重、Temperature、Frequency penalty |
| Prometheus Design Proposal | `docs/design-proposal.md` §2.3.2 | 偏好注入流水线设计 |
| Prometheus Spec | `docs/spec.md` §3.3 | 工具定义与参数枚举 |
| Prometheus Writing Subagent | `docs/add/add-writing.md` | 模板系统 Checklist、引擎接口 |
