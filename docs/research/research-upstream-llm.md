# 上游 LLM 选型调研报告

> 普罗米修斯（Prometheus）项目 · 报告 6
>
> 调研日期：2026-07-14 | 版本：v1.0
>
> 关联文档：`docs/spec.md` §1.3 技术栈、§6.3 配置示例；`docs/MTClaw-深度调研报告.md`

---

## 目录

1. [上游 LLM 的角色定位](#1-上游-llm-的角色定位)
2. [选型评估维度](#2-选型评估维度)
3. [候选模型概览](#3-候选模型概览)
4. [候选模型详细分析](#4-候选模型详细分析)
   - 4.1 [DeepSeek-V4-Pro](#41-deepseek-v4-pro)
   - 4.2 [Doubao（豆包大模型）](#42-doubao豆包大模型)
   - 4.3 [GPT-4o](#43-gpt-4o)
   - 4.4 [Claude（Claude 4 / Sonnet 4）](#44-claudeclaude-4--sonnet-4)
5. [核心维度对比](#5-核心维度对比)
   - 5.1 [中文质量](#51-中文质量)
   - 5.2 [价格](#52-价格)
   - 5.3 [流式支持](#53-流式支持)
   - 5.4 [Function Calling 与工具调用](#54-function-calling-与工具调用)
   - 5.5 [延迟与吞吐](#55-延迟与吞吐)
   - 5.6 [API 兼容性与集成成本](#56-api-兼容性与集成成本)
6. [综合评分矩阵](#6-综合评分矩阵)
7. [推荐方案](#7-推荐方案)
8. [风险与缓解](#8-风险与缓解)
9. [附录：配置示例](#9-附录配置示例)

---

## 1. 上游 LLM 的角色定位

在普罗米修斯架构中，上游 LLM 承担以下职责：

```
用户请求
  │
  ▼
MTClaw Function Router (:18790)
  │
  ├── 路由模型判断 (qwen3-30b-a3b, 本地)
  │     │
  │     ├── 命中工具 -> 工具执行 -> Completion Check
  │     │     ├── TASK_COMPLETE   -> 直接返回（快路径，不走上游 LLM）
  │     │     └── TASK_INCOMPLETE -> 转发上游 LLM（慢路径）
  │     │
  │     └── 未命中任何工具 -> 转发上游 LLM（通用推理兜底）
  │
  └── 路由模型超时/故障 -> 直接转发上游 LLM（安全降级）
```

**上游 LLM 在系统中的具体使用场景：**

| 场景 | 触发条件 | 调用方 | 典型延迟 [推测] |
|------|---------|--------|----------------|
| 写作生成（周报/邮件/技术文档/会议纪要等） | 命中 `writing_generate` 工具，Completion Check 判定 TASK_INCOMPLETE | writing_engine.py -> httpx POST 上游 LLM | 10-40s |
| 文本润色 | 命中 `writing_polish`，工具需 LLM 二次加工 | writing_engine.py -> 上游 LLM | 5-15s |
| 翻译 | 命中 `writing_translate`，需 LLM 翻译 | writing_engine.py -> 上游 LLM | 5-15s |
| 去AI化改写 | 命中 `writing_humanize`，需 LLM 改写 | writing_engine.py -> 上游 LLM | 5-15s |
| 通用推理兜底 | 路由模型未命中任何工具 | MTClaw FR 透明代理 -> 上游 LLM | 15-40s |
| Completion Check 判定不完整 | 工具执行结果需上游 LLM 补充 | MTClaw FR 透明代理 -> 上游 LLM | 10-30s |

**关键约束：**

- **OpenAI-compatible API**：MTClaw FR 的 `upstream` 配置要求 `base_url + model + api_key`，必须兼容 OpenAI Chat Completions API 格式（`/v1/chat/completions`）
- **流式透传**：MTClaw FR 支持 SSE 流式透传，上游 LLM 必须支持 `stream=true`
- **中文为主**：系统提示词为中文硬编码，用户群体以中文知识工作者为主
- **成本敏感**：个人认知智能体产品，单用户年推理成本需控制在合理范围

---

## 2. 选型评估维度

| 维度 | 权重 | 说明 |
|------|------|------|
| **中文质量** | ★★★★★ | 目标用户为中文知识工作者，写作/润色/翻译的中文输出质量是核心竞争力 |
| **价格** | ★★★★☆ | 云上知识库模式下单用户年推理成本 ~¥40 [推测]，模型定价直接影响毛利率 |
| **流式支持** | ★★★★☆ | MTClaw FR SSE 透传 + Hermes 流式渲染，必须支持 SSE 流式输出 |
| **Function Calling** | ★★★☆☆ | 上游 LLM 本身不直接做工具路由（路由由路由模型完成），但需支持基础 function calling 格式以兼容 MTClaw 协议 |
| **API 兼容性** | ★★★★☆ | 必须 OpenAI-compatible，零代码改动接入 MTClaw |
| **延迟** | ★★★☆☆ | 上游 LLM 调用场景本身允许 10-40s 延迟，但首 token 延迟影响用户体验 |
| **合规与可用性** | ★★★☆☆ | 国内可用性、备案合规、数据安全 |
| **上下文窗口** | ★★☆☆☆ | 写作/翻译场景偶尔需要长上下文，但不是核心瓶颈 |

---

## 3. 候选模型概览

基于项目 spec.md §1.3 技术栈标注（"上游模型：Cloud API (DeepSeek / GPT-4o)"）和 design-proposal.md 中的上下文，本报告调研以下 4 个候选：

| 候选模型 | 提供方 | 参数规模 | 上下文窗口 | 定价区间 | 国内可用性 |
|---------|--------|---------|-----------|---------|-----------|
| **DeepSeek-V4-Pro** | 深度求索 | MoE（总参数 ~671B，激活 ~37B）[推测] | 128K | 低价 | ✅ 原生可用 |
| **Doubao（豆包）** | 字节跳动 | 未公开（推测 100B+ 级） | 128K-256K | 低价 | ✅ 原生可用 |
| **GPT-4o** | OpenAI | 多模态（未公开参数） | 128K | 中高 | ❌ 需代理/中转 |
| **Claude（Sonnet 4）** | Anthropic | 未公开 | 200K | 中高 | ❌ 需代理/中转 |

> **说明**：spec.md §6.3 配置示例中 upstream.model 已标注为 `deepseek-v4-pro`，本报告将验证此选型的合理性，并对比替代方案。

---

## 4. 候选模型详细分析

### 4.1 DeepSeek-V4-Pro

**背景**：深度求索（DeepSeek）系列模型，以极高性价比和开源策略著称。DeepSeek-V3 已在 2024 年底发布，V4-Pro 为后续迭代版本 [推测]。

**技术特征：**

| 属性 | 详情 |
|------|------|
| 架构 | MoE（Mixture of Experts），总参数 ~671B，每次推理激活 ~37B [推测] |
| 上下文窗口 | 128K tokens |
| 训练数据 | 多语言，中文数据占比高 |
| 开源 | 模型权重开源（MIT 协议），可自部署 |
| API | OpenAI-compatible |

**中文质量评估：**

- DeepSeek 系列在中文理解、生成、翻译方面表现优秀，与国内一线模型（Qwen、GLM）同属第一梯队 [推测]
- 中文写作自然度高，套话倾向低于部分国产模型
- 中文古文/专业领域（法律、医学）理解能力较强

**价格（API 调用）：**

| 计费项 | DeepSeek-V4-Pro [推测] | 对比 GPT-4o |
|--------|----------------------|------------|
| 输入（per 1M tokens） | ~¥2-4（缓存命中更低） | ~¥17.5（$2.5） |
| 输出（per 1M tokens） | ~¥8-16 | ~¥70（$10） |
| 缓存命中输入 | ~¥0.5-1 | ~¥8.75（$1.25） |

> DeepSeek 定价通常为 GPT-4o 的 1/5~1/8，是其最大竞争优势。

**流式支持：**

- ✅ 完整支持 SSE 流式输出（`stream=true`）
- 首 token 延迟 ~1-3s [推测]
- MTClaw FR 可直接 SSE 透传，零适配

**优势：**

1. **极高性价比**：价格为 GPT-4o 的 1/5~1/8，对云上知识库订阅模式（Cloud Pro ¥29/月）的毛利空间至关重要
2. **中文原生优势**：中文训练数据充足，中文写作/翻译质量优秀
3. **OpenAI-compatible**：零适配接入 MTClaw FR
4. **开源可自部署**：未来可在 MTT AIBOOK 或私有云上自部署，进一步降低成本
5. **国内合规**：深度求索已完成大模型备案，国内可用无障碍
6. **MTClaw 已验证**：MTClaw Benchmark 中 Baseline 使用 Doubao，但 DeepSeek 系列在多个 benchmark 中表现优于或持平 Doubao

**劣势：**

1. **品牌认知度**：在国际市场知名度低于 GPT-4o / Claude，评委可能对质量存疑
2. **多模态缺失**：纯文本模型，不支持图像输入（如需 OCR 场景需额外方案）
3. **稳定性**：高峰期偶有限流，需做好重试机制

### 4.2 Doubao（豆包大模型）

**背景**：字节跳动旗下豆包大模型，通过火山引擎提供 API 服务。MTClaw 团队的 Benchmark 数据即使用 Doubao 作为 Baseline 上游模型。

**技术特征：**

| 属性 | 详情 |
|------|------|
| 架构 | 未公开（推测为大规模 MoE 或 Dense） |
| 上下文窗口 | 128K-256K |
| 训练数据 | 中文数据丰富（字节生态数据优势） |
| 开源 | ❌ 闭源，仅 API |
| API | OpenAI-compatible（火山引擎适配） |

**中文质量评估：**

- 字节跳动在中文 NLP 领域积累深厚，豆包模型中文生成质量在国内第一梯队 [推测]
- 适合社交媒体、短视频文案等场景化写作
- 在 MTClaw 系统控制垂域 Benchmark 中，Doubao Baseline Pass@1 达 99.0%，说明其 instruction following 能力强

**价格：**

| 计费项 | Doubao [推测] | 说明 |
|--------|-------------|------|
| 输入（per 1M tokens） | ~¥0.8-5 | 火山引擎有阶梯定价 |
| 输出（per 1M tokens） | ~¥2-15 | 与 DeepSeek 同属低价梯队 |

> 字节跳动 2024 年起大幅降价，Doubao 定价与 DeepSeek 处于同一竞争区间。

**流式支持：**

- ✅ 支持 SSE 流式输出
- 火山引擎 API 网络延迟低（国内 CDN 优势）
- 首 token 延迟 ~0.5-2s [推测]

**优势：**

1. **MTClaw 原生验证**：MTClaw 团队已使用 Doubao 作为 Baseline 测试，Pass@1=99.0%，兼容性已验证
2. **中文场景化能力强**：字节生态数据优势，在社交/内容场景的中文生成有特色
3. **国内网络低延迟**：火山引擎国内节点，网络延迟优于海外模型
4. **价格低廉**：与 DeepSeek 同属低价梯队
5. **国内合规**：已完成大模型备案

**劣势：**

1. **闭源**：无法自部署，长期依赖字节 API
2. **API 适配层**：火山引擎 API 虽兼容 OpenAI 格式，但部分高级参数（如 logprobs）支持可能不完整
3. **品牌绑定**：使用字节系模型可能被视为生态绑定
4. **通用推理能力**：在复杂逻辑推理、代码生成等场景可能略弱于 DeepSeek [推测]

### 4.3 GPT-4o

**背景**：OpenAI 旗舰多模态模型，2024 年 5 月发布，支持文本、图像、音频输入输出。

**技术特征：**

| 属性 | 详情 |
|------|------|
| 架构 | 多模态（未公开参数规模） |
| 上下文窗口 | 128K tokens |
| 多模态 | ✅ 文本 + 图像 + 音频 |
| 开源 | ❌ 闭源 |
| API | OpenAI 原生 API |

**中文质量评估：**

- GPT-4o 中文能力优秀，但中文写作的自然度和文化适配略逊于国产模型 [推测]
- 英文场景表现顶级，中英混合场景表现良好
- 翻译质量高，尤其中英互译

**价格：**

| 计费项 | GPT-4o | 说明 |
|--------|--------|------|
| 输入（per 1M tokens） | $2.5（~¥17.5） | 标准定价 |
| 输出（per 1M tokens） | $10（~¥70） | 标准定价 |
| 缓存命中输入 | $1.25（~¥8.75） | |

> GPT-4o 定价约为 DeepSeek 的 5-8 倍。

**流式支持：**

- ✅ 原生支持 SSE 流式输出
- 首 token 延迟 ~0.5-2s [推测]
- 流式质量稳定

**优势：**

1. **综合能力最强**：在多数 benchmark（MMLU、HumanEval、GSM8K 等）中表现顶级
2. **多模态**：支持图像输入，未来可扩展 OCR、图表理解等场景
3. **生态最成熟**：OpenAI SDK / 兼容库最丰富，社区支持最好
4. **品牌效应**：国际知名度最高，对外展示有加分效果
5. **Function Calling 标杆**：OpenAI 是 function calling 协议的制定者，兼容性最佳

**劣势：**

1. **国内不可直接访问**：需代理或中转 API，增加延迟和运维复杂度
2. **价格高**：为 DeepSeek 的 5-8 倍，严重影响云上订阅模式毛利
3. **中文自然度**：中文写作略带"翻译腔"，不如国产模型自然 [推测]
4. **合规风险**：国内使用 OpenAI API 存在合规不确定性
5. **数据安全**：数据出境需额外评估

### 4.4 Claude（Claude 4 / Sonnet 4）

**背景**：Anthropic 旗下 Claude 系列模型，以长文本理解和安全性著称。Claude Sonnet 4 为 2025 年发布的高性价比版本 [推测]。

**技术特征：**

| 属性 | 详情 |
|------|------|
| 架构 | 未公开 |
| 上下文窗口 | 200K tokens（业界最大之一） |
| 多模态 | ✅ 文本 + 图像 |
| 开源 | ❌ 闭源 |
| API | Anthropic 原生 API（非 OpenAI 格式，需适配层） |

**中文质量评估：**

- Claude 系列中文写作质量优秀，风格偏正式、严谨 [推测]
- 长文本理解能力突出（200K 上下文窗口），适合长文档处理
- 中文创意写作能力略弱于国产模型，但逻辑性和结构性强

**价格：**

| 计费项 | Claude Sonnet 4 [推测] | 说明 |
|--------|----------------------|------|
| 输入（per 1M tokens） | $3（~¥21） | |
| 输出（per 1M tokens） | $15（~¥105） | |
| 缓存命中输入 | $0.3（~¥2.1） | Prompt Caching 优势明显 |

> Claude 定价与 GPT-4o 接近，但 Prompt Caching 可显著降低重复请求成本。

**流式支持：**

- ✅ 支持 SSE 流式输出
- Anthropic API 使用自有 SSE 格式，需适配层转换为 OpenAI 格式 [推测]

**优势：**

1. **长文本处理**：200K 上下文窗口，适合长文档写作、润色场景
2. **写作风格**：输出风格严谨、结构清晰，适合技术文档和学术写作
3. **安全性**：Anthropic 的 Constitutional AI 方法使模型输出更安全可控
4. **Prompt Caching**：可显著降低重复系统提示词的成本
5. **去AI化改写**：Claude 的写作风格更接近人类，去AI化效果可能更好 [推测]

**劣势：**

1. **API 格式不兼容**：Anthropic API 非 OpenAI 格式，需额外适配层或中转服务，增加集成成本
2. **国内不可直接访问**：需代理或中转，合规风险与 GPT-4o 类似
3. **价格高**：与 GPT-4o 同价位，云上订阅模式毛利压力大
4. **中文文化适配**：中文表达偏"正式翻译"风格，不如国产模型地道
5. **Function Calling**：支持 Tool Use 但格式与 OpenAI 有差异，需适配

---

## 5. 核心维度对比

### 5.1 中文质量

| 维度 | DeepSeek-V4-Pro | Doubao | GPT-4o | Claude Sonnet 4 |
|------|-----------------|--------|--------|-----------------|
| 中文写作自然度 | ★★★★★ | ★★★★☆ | ★★★★☆ | ★★★★☆ |
| 中文翻译质量 | ★★★★★ | ★★★★☆ | ★★★★★ | ★★★★☆ |
| 中文古文/专业领域 | ★★★★☆ | ★★★★☆ | ★★★★☆ | ★★★☆☆ |
| 去AI化改写 | ★★★★☆ | ★★★★☆ | ★★★☆☆ | ★★★★★ |
| 中文文化理解 | ★★★★★ | ★★★★★ | ★★★☆☆ | ★★★☆☆ |
| **综合** | **★★★★★** | **★★★★☆** | **★★★★☆** | **★★★★☆** |

**结论**：DeepSeek-V4-Pro 在中文质量上综合最优，国产模型在中文文化理解和写作自然度上有天然优势。Claude 在去AI化改写场景有独特优势（写作风格更接近人类），但整体中文文化适配不如国产模型。

### 5.2 价格

以下按 Prometheus 典型使用场景估算**单用户月成本**：

```
假设（Cloud Pro 用户日均使用量 [推测]）:
  - 写作生成：3 次/天，平均输出 800 tokens/次 = 2,400 output tokens/天
  - 翻译：1 次/天，平均输出 500 tokens/次 = 500 output tokens/天
  - 润色：1 次/天，平均输出 600 tokens/次 = 600 output tokens/天
  - 通用兜底：5 次/天，平均输出 400 tokens/次 = 2,000 output tokens/天
  - 总输出：~5,500 tokens/天 = ~165K output tokens/月
  - 总输入（含 system prompt + 上下文）：~165K input tokens/月（含缓存命中）
  - 缓存命中率：~50%（system prompt + 偏好注入可缓存）
```

| 模型 | 月输入成本 | 月输出成本 | **月总成本** | **年总成本** | Cloud Pro 年毛利（¥199） |
|------|-----------|-----------|------------|------------|----------------------|
| **DeepSeek-V4-Pro** | ¥0.3-0.7 | ¥1.3-2.6 | **~¥2-3** | **~¥24-36** | **~¥163-175** |
| **Doubao** | ¥0.1-0.8 | ¥0.3-2.5 | **~¥1-3** | **~¥12-36** | **~¥163-187** |
| **GPT-4o** | ¥1.5-2.9 | ¥11.6 | **~¥13-15** | **~¥156-180** | **~¥19-43** |
| **Claude Sonnet 4** | ¥1.8-3.2 | ¥17.3 | **~¥19-21** | **~¥228-252** | **负毛利** |

**结论**：

- DeepSeek-V4-Pro 和 Doubao 的推理成本极低，Cloud Pro 订阅模式可保持 ~80%+ 毛利率
- GPT-4o 成本可控但毛利空间大幅压缩（~10-22% 毛利），依赖规模化摊薄
- Claude Sonnet 4 在当前定价下无法实现 Cloud Pro 正毛利（除非大幅提价或使用 Prompt Caching 优化）

### 5.3 流式支持

| 维度 | DeepSeek-V4-Pro | Doubao | GPT-4o | Claude Sonnet 4 |
|------|-----------------|--------|--------|-----------------|
| SSE 流式输出 | ✅ | ✅ | ✅ | ✅（需适配） |
| OpenAI SSE 格式 | ✅ 原生 | ✅ 适配 | ✅ 原生 | ❌ 需转换 |
| 首 token 延迟 | 1-3s [推测] | 0.5-2s [推测] | 0.5-2s [推测] | 1-3s [推测] |
| MTClaw FR SSE 透传 | ✅ 零适配 | ✅ 零适配 | ✅ 零适配 | ⚠️ 需适配层 |
| 流式稳定性 | 良好 [推测] | 良好 | 优秀 | 优秀 |

**结论**：DeepSeek-V4-Pro、Doubao、GPT-4o 均原生支持 OpenAI SSE 格式，可零适配接入 MTClaw FR。Claude 需额外适配层将 Anthropic SSE 转换为 OpenAI 格式，增加集成成本和故障点。

### 5.4 Function Calling 与工具调用

> **注意**：在 Prometheus 架构中，上游 LLM 本身不直接做工具路由决策（路由由路由模型 qwen3-30b 完成）。但 MTClaw FR 的 `delegate_tools_to_openclaw` 和 Completion Check 机制可能涉及上游 LLM 的 function calling 能力。

| 维度 | DeepSeek-V4-Pro | Doubao | GPT-4o | Claude Sonnet 4 |
|------|-----------------|--------|--------|-----------------|
| Function Calling | ✅ | ✅ | ✅（标杆） | ✅（Tool Use） |
| OpenAI 格式兼容 | ✅ | ✅ | ✅ 原生 | ⚠️ 需适配 |
| 工具调用准确率 | 高 [推测] | 高（MTClaw 验证） | 最高 | 高 |
| JSON Mode | ✅ | ✅ | ✅ | ✅ |

**结论**：GPT-4o 是 function calling 的标杆，但 Prometheus 场景下上游 LLM 不承担路由决策，function calling 能力非关键瓶颈。DeepSeek 和 Doubao 均满足需求。

### 5.5 延迟与吞吐

| 维度 | DeepSeek-V4-Pro | Doubao | GPT-4o | Claude Sonnet 4 |
|------|-----------------|--------|--------|-----------------|
| 首 token 延迟 | 1-3s [推测] | 0.5-2s [推测] | 0.5-2s [推测] | 1-3s [推测] |
| 生成速度（tokens/s） | 30-60 [推测] | 40-80 [推测] | 50-100 [推测] | 40-80 [推测] |
| 国内网络延迟 | 低 | 最低 | 高（需代理） | 高（需代理） |
| 高峰期稳定性 | 中 [推测] | 高 | 高 | 高 |
| 端到端延迟（写作场景） | 10-30s [推测] | 8-25s [推测] | 8-20s [推测] | 10-30s [推测] |

**结论**：Doubao 在国内网络延迟方面有天然优势（火山引擎国内节点）。GPT-4o 生成速度最快但国内访问需代理。DeepSeek 延迟可接受。所有模型均满足 Prometheus 写作场景 10-40s 的延迟预算。

### 5.6 API 兼容性与集成成本

| 维度 | DeepSeek-V4-Pro | Doubao | GPT-4o | Claude Sonnet 4 |
|------|-----------------|--------|--------|-----------------|
| OpenAI-compatible | ✅ 原生 | ✅ 适配 | ✅ 原生 | ❌ 需适配层 |
| MTClaw FR `upstream` 配置 | 直接填入 | 直接填入 | 直接填入 | 需中转服务 |
| 配置复杂度 | 最低 | 低 | 中（需代理） | 高（需适配层） |
| SDK 可用性 | OpenAI SDK 直接用 | OpenAI SDK 直接用 | OpenAI SDK 原生 | 需 Anthropic SDK 或中转 |

**MTClaw FR 配置示例（任一 OpenAI-compatible 模型）：**

```json
{
  "upstream": {
    "base_url": "https://api.deepseek.com/v1",
    "model": "deepseek-v4-pro",
    "api_key": "${UPSTREAM_API_KEY}"
  }
}
```

> Claude 需通过第三方中转服务（如 OpenRouter）或自建适配层，增加了一层故障点和延迟。

---

## 6. 综合评分矩阵

> 评分采用 10 分制，权重按 §2 评估维度分配。

| 维度 | 权重 | DeepSeek-V4-Pro | Doubao | GPT-4o | Claude Sonnet 4 |
|------|------|:-:|:-:|:-:|:-:|
| 中文质量 | 25% | **9.5** | 8.5 | 8.0 | 8.0 |
| 价格 | 20% | **9.5** | **9.5** | 5.0 | 3.5 |
| 流式支持 | 15% | **9.5** | 9.0 | **9.5** | 6.0 |
| API 兼容性 | 15% | **10** | 9.0 | **10** | 5.0 |
| 延迟 | 10% | 8.0 | **9.0** | 7.0 | 7.0 |
| 综合推理能力 | 10% | 8.5 | 8.0 | **9.5** | 9.0 |
| 合规与可用性 | 5% | **10** | **10** | 5.0 | 5.0 |
| **加权总分** | 100% | **9.35** | **8.83** | **7.73** | **6.25** |

---

## 7. 推荐方案

### 7.1 首选：DeepSeek-V4-Pro

**推荐理由：**

1. **中文质量最优**：中文写作、翻译、润色全场景第一梯队，目标用户为中文知识工作者，中文质量是核心竞争力
2. **性价比最高**：价格为 GPT-4o 的 1/5~1/8，Cloud Pro 订阅模式可保持 80%+ 毛利率
3. **零适配集成**：OpenAI-compatible API，直接填入 MTClaw FR `upstream` 配置
4. **国内合规可用**：已完成大模型备案，无需代理
5. **开源可自部署**：未来可在 MTT AIBOOK 或私有云部署，进一步降低成本，符合"本地优先"产品理念
6. **spec.md 已预设**：spec.md §6.3 配置示例中已标注 `deepseek-v4-pro`，与现有设计一致

**推荐配置：**

```json
{
  "upstream": {
    "base_url": "https://api.deepseek.com/v1",
    "model": "deepseek-v4-pro",
    "api_key": "${DEEPSEEK_API_KEY}"
  }
}
```

### 7.2 备选：Doubao（豆包）

**备选理由：**

1. **MTClaw 原生验证**：MTClaw 团队 Benchmark 已使用 Doubao 作为 Baseline，Pass@1=99.0%，兼容性有实测保障
2. **国内网络延迟最低**：火山引擎国内 CDN 节点，首 token 延迟最优
3. **价格同属低价梯队**：与 DeepSeek 价格竞争激烈
4. **中文场景化能力强**：字节生态数据优势

**切换条件：**
- DeepSeek API 稳定性不达标（高峰期限流严重）
- 需要更低的网络延迟（演示场景）
- MTClaw 团队建议使用 Doubao 以保持一致性

### 7.3 不推荐作为主选

| 模型 | 不推荐原因 |
|------|-----------|
| **GPT-4o** | 价格为 DeepSeek 的 5-8 倍，严重压缩毛利；国内不可直接访问，合规风险；中文自然度不如国产模型 |
| **Claude Sonnet 4** | API 格式不兼容，需适配层；价格最高，Cloud Pro 无法正毛利；国内不可直接访问 |

### 7.4 多模型策略建议（未来演进）

spec.md §7 路由策略和 MTClaw 调研报告 P2 建议第 13 项提到"多上游模型路由"。建议未来支持按场景路由到不同上游模型：

| 场景 | 推荐模型 | 原因 |
|------|---------|------|
| 中文写作/周报/邮件 | DeepSeek-V4-Pro | 中文质量最优 + 成本低 |
| 翻译（中英互译） | DeepSeek-V4-Pro / GPT-4o | 两者翻译质量均优 |
| 去AI化改写 | Claude Sonnet 4 | 写作风格最接近人类 |
| 通用推理兜底 | DeepSeek-V4-Pro | 综合性价比最高 |
| 长文档处理（>128K） | Claude Sonnet 4 | 200K 上下文窗口 |
| 图像理解（未来） | GPT-4o | 多模态能力 |

> 此多模型策略为 v2.0+ 演进方向，MVP 阶段使用 DeepSeek-V4-Pro 单一模型即可。

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| DeepSeek API 高峰期限流 | 写作/通用推理请求失败 | 1. MTClaw FR 已有路由 fallback 机制；2. 实现 retry + exponential backoff；3. 备选 Doubao 作为 fallback |
| DeepSeek 模型版本迭代 | API 行为变化 | 1. 锁定模型版本（如 `deepseek-v4-pro-0714`）；2. 版本升级前做回归测试 |
| DeepSeek API 停服 | 上游 LLM 不可用 | 1. 配置 Doubao 作为 backup upstream；2. MTClaw FR 配置支持动态切换 upstream |
| 中文质量不达预期 | 用户满意度下降 | 1. 写作 Subagent 使用模板 + 偏好注入约束输出质量；2. 建立中文质量评测集定期回归 |
| 评委对非 GPT-4o 模型质量存疑 | 比赛评分受影响 | 1. 演示中展示中文写作质量对比；2. 准备 benchmark 数据证明 DeepSeek 中文能力；3. 强调"性价比 + 本地优先"设计理念 |
| 成本超预期 | 云上模式毛利下降 | 1. 监控单用户 token 消耗；2. 设置 Cloud Pro 日调用上限（10,000 条/天）；3. 启用 prompt caching |

---

## 9. 附录：配置示例

### 9.1 首选配置（DeepSeek-V4-Pro）

```json
{
  "upstream": {
    "base_url": "https://api.deepseek.com/v1",
    "model": "deepseek-v4-pro",
    "api_key": "${DEEPSEEK_API_KEY}"
  }
}
```

### 9.2 备选配置（Doubao via 火山引擎）

```json
{
  "upstream": {
    "base_url": "https://ark.cn-beijing.volces.com/api/v3",
    "model": "doubao-pro-256k",
    "api_key": "${VOLCENGINE_API_KEY}"
  }
}
```

### 9.3 国际场景配置（GPT-4o，需代理）

```json
{
  "upstream": {
    "base_url": "https://api.openai.com/v1",
    "model": "gpt-4o",
    "api_key": "${OPENAI_API_KEY}"
  }
}
```

### 9.4 写作引擎调用上游 LLM 示例（writing_engine.py）

```python
import httpx

async def call_upstream_llm(
    system_prompt: str,
    user_prompt: str,
    temperature: float = 0.7,
    max_tokens: int = 4096,
    stream: bool = True
) -> str:
    """调用上游 LLM（DeepSeek-V4-Pro）生成文本。

    通过 MTClaw FR 的 upstream 配置透明代理，
    也可直接调用上游 API（写作 Subagent 场景）。
    """
    async with httpx.AsyncClient(timeout=120.0) as client:
        response = await client.post(
            f"{UPSTREAM_BASE_URL}/chat/completions",
            headers={
                "Authorization": f"Bearer {UPSTREAM_API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": UPSTREAM_MODEL,  # "deepseek-v4-pro"
                "messages": [
                    {"role": "system", "content": system_prompt},
                    {"role": "user", "content": user_prompt}
                ],
                "temperature": temperature,
                "max_tokens": max_tokens,
                "stream": stream
            }
        )
        result = response.json()
        return result["choices"][0]["message"]["content"]
```

### 9.5 延迟预算参考

基于 spec.md §10.1 演示剧本和 §12 评估维度：

| 路径 | 组件 | 延迟预算 [推测] | 上游 LLM 占比 |
|------|------|----------------|--------------|
| 闲聊（chat_light） | 路由模型直回 | 1-3s | 0%（不走上游） |
| RAG 检索 | 本地 ChromaDB | 1-3s | 0%（不走上游） |
| 记忆查询 | 本地 SQLite | <1s | 0%（不走上游） |
| 日程管理 | 本地 SQLite | <1s | 0%（不走上游） |
| 写作生成 | 上游 LLM | 10-40s | ~90% |
| 通用兜底 | 上游 LLM | 15-40s | ~95% |

> 上游 LLM 仅在写作和通用兜底场景使用，占总体请求的 ~30% [推测]。其余 ~70% 请求通过本地工具 + 路由模型直回完成，不消耗上游 LLM 成本。

---

## 总结

本报告对 DeepSeek-V4-Pro、Doubao、GPT-4o、Claude Sonnet 4 四个候选上游 LLM 进行了全面对比。综合中文质量、价格、流式支持、API 兼容性、延迟和合规性六大维度：

- **首选 DeepSeek-V4-Pro**：中文质量最优、性价比最高（GPT-4o 的 1/5~1/8）、OpenAI-compatible 零适配、国内合规可用、开源可自部署
- **备选 Doubao**：MTClaw 原生验证、国内网络延迟最低、价格同属低价梯队
- **GPT-4o / Claude** 不推荐作为主选：价格高、国内不可直接访问、合规风险、中文自然度不如国产模型

推荐 MVP 阶段使用 DeepSeek-V4-Pro 单一模型，未来演进为多模型按场景路由策略。
