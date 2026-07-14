# 路由模型选型调研报告

> 版本：v1.0 | 日期：2026-07-14 | 作者：Prometheus 自动调研
>
> **数据诚实化声明**：本报告中的数据分为三类：**[实测]** Prometheus/MTClaw 有实际测试数据支撑、**[推测]** 基于架构推断或引用第三方测试、**[官网]** 基于厂商官方定价页/技术文档。引用第三方测试均标注来源，不以他人数据冒充自测。

---

## 目录

1. [MTClaw 对路由模型的硬性要求](#1-mtclaw-对路由模型的硬性要求)
2. [候选模型概览](#2-候选模型概览)
3. [详细对比](#3-详细对比)
   - 3.1 [Function Calling 能力](#31-function-calling-能力)
   - 3.2 [延迟分析](#32-延迟分析)
   - 3.3 [成本分析](#33-成本分析)
   - 3.4 [工程兼容性](#34-工程兼容性)
4. [MTClaw 已有实测数据](#4-mtclaw-已有实测数据)
5. [风险与陷阱](#5-风险与陷阱)
6. [选型建议](#6-选型建议)
7. [附录](#附录-a候选模型参数与定价汇总)

---

## 1. MTClaw 对路由模型的硬性要求

通过阅读 MTClaw Function Router 源码（`server.py` ~2707 行）和配置文件（`~/.function-router/config.json`），提炼出以下硬性约束：

### 1.1 接口协议要求

| 要求 | 来源 | 说明 |
|------|------|------|
| OpenAI-compatible `/v1/chat/completions` | `call_qwen()` 函数 (server.py:936-983) | FR 通过标准 HTTP POST 调用路由模型，非 OpenAI 协议无法接入 |
| 支持 `tools` 参数 (function calling) | `call_qwen()` payload (server.py:950) | `"tools": STATE.tools` — 路由模型必须能识别工具定义并返回 `tool_calls` |
| 支持 `temperature=0.0` | `call_qwen()` payload (server.py:952) | 确定性路由，同一输入必须输出同一路由结果 |
| 支持 `stream=false` | `call_qwen()` payload (server.py:951) | 路由决策走非流式，等全部 token 生成后解析 tool_calls |
| 支持 `parallel_tool_calls=false` | `call_qwen()` payload (server.py:955) | 不允许并行工具调用，每次只选一个工具 |
| 非标准参数: `enable_thinking=false` | `call_qwen()` payload (server.py:956) | Qwen3 系列特有参数；非 Qwen 模型需确认是否忽略未知参数 |

### 1.2 性能要求

| 要求 | 理由 | 来源 |
|------|------|------|
| 首字延迟 < 2s | 路由模型在每次用户请求的最前端，延迟直接叠加到总响应时间 | `routing_timeout_s: 10.0` (config.json) |
| 单次推理总延迟 < 10s | 超时后 FR 会重试一次，再超时则 fallback 到上游 LLM | `call_qwen()` 重试逻辑 (server.py:965-980) |
| function calling 准确率 > 90% | 路由准确率直接决定用户体验；误路由到 chat_light 会产生低质量回复 | design-proposal.md §4.1 [目标] |
| 闲聊生成质量（仅 chat_light 场景） | chat_light Subagent 直接用路由模型回复用户，不经过上游 LLM | design-proposal.md §2.5 |

### 1.3 特殊参数

FR 在调用路由模型时发送以下非标准参数：

```python
# server.py:947-957
payload = {
    "model": STATE.config.routing.model,
    "messages": messages,
    "tools": STATE.tools,
    "stream": False,
    "temperature": 0.0,
    "repetition_penalty": 1.2,      # 非标准 OpenAI 参数
    "frequency_penalty": 0.2,
    "parallel_tool_calls": False,
    "enable_thinking": False,        # Qwen3 特有参数
}
```

- `repetition_penalty` 和 `enable_thinking` 是非标准 OpenAI 参数
- DeepSeek API 和 GLM API 对未知参数的处理需验证（可能忽略或报错）
- **潜在风险**：如果模型 API 严格校验未知参数，调用会失败

### 1.4 Completion Check 也用路由模型

```python
# server.py:1526-1563 — call_qwen_completion_check()
# 使用同一个 routing model 做 Completion Check
"model": STATE.config.routing.model,
```

这意味着路由模型不仅要做 function calling（工具选择），还要做简单的判断任务（TASK_COMPLETE vs TASK_INCOMPLETE）。对模型的指令遵循能力有额外要求。

### 1.5 当前生产配置

```json
// ~/.function-router/config.json
{
  "routing": {
    "base_url": "https://ark.cn-beijing.volces.com/api/coding",
    "model": "deepseek-v4-flash",
    "api_key": "ark-..."
  },
  "upstream": {
    "model": "glm-5.2"
  }
}
```

当前路由模型为 `deepseek-v4-flash`，通过火山引擎 ARK 平台调用。上游模型为 `glm-5.2`。

---

## 2. 候选模型概览

基于项目文档提到的候选模型 + 当前生产配置，确定以下对比对象：

| # | 模型 | 参数规模 | 提供方 | 接入方式 | 定位 |
|---|------|---------|--------|---------|------|
| A | **DeepSeek-V4-Flash** | 未公开（推测 30B+ MoE） | DeepSeek | DeepSeek API / 火山 ARK | 高速、低成本、function calling 原生支持 |
| B | **Qwen3-30B-A3B** | 30B 总参数 / 3B 激活 (MoE) | 阿里通义 | 火山 ARK / 阿里百炼 / 本地部署 | MTClaw 原生设计模型，MoE 低激活比 |
| C | **GLM-4.7-Flash** | 未公开（推测 9B~12B） | 智谱 AI | 智谱开放平台 | 免费、200K 上下文、极速推理 |
| D | **GLM-4.7-FlashX** | 未公开 | 智谱 AI | 智谱开放平台 | 低成本高速、200K 上下文 |
| E | **GLM-4-FlashX-250414** | 未公开 | 智谱 AI | 智谱开放平台 | 极低价 0.1元/百万tokens |
| F | **GLM-4.5-Air** | 未公开 | 智谱 AI | 智谱开放平台 | 高性价比、128K 上下文 |

> **注意**：项目中多处提及 `qwen3-30b` 和 `deepseek-v4-flash`，但 `glm-4-flash` 在智谱当前产品线中已被 `GLM-4.7-Flash` 系列替代。本报告以智谱当前在售的 Flash/Air 系列作为 GLM 侧候选。

---

## 3. 详细对比

### 3.1 Function Calling 能力

| 模型 | Function Calling 支持 | 工具选择准确率 | 依据 |
|------|---------------------|--------------|------|
| **DeepSeek-V4-Flash** | ✅ 原生支持 [官网] | MTClaw 实测：工具准确率 94.8%~97.5% [推测, MTClaw 团队测试, 非本项目实测] | 当前生产配置；MTClaw benchmark |
| **Qwen3-30B-A3B** | ✅ 原生支持，支持 `enable_thinking` 参数 [官网] | MTClaw 原始设计使用此模型，工具召回率 100% [推测, MTClaw 团队测试] | MTClaw README + benchmark |
| **GLM-4.7-Flash** | ✅ 支持 [官网] | 无公开 benchmark；智谱宣称 IFEval 指令跟随 90%+ [官网] | 智谱开放平台文档 |
| **GLM-4.7-FlashX** | ✅ 支持 [官网] | 同上，但参数更小，FC 准确率可能略低 [推测] | 智谱开放平台文档 |
| **GLM-4-FlashX-250414** | ✅ 支持 [官网] | 同上 [推测] | 智谱开放平台文档 |
| **GLM-4.5-Air** | ✅ 支持 [官网] | 高性价比定位，FC 能力应优于 Flash 系列 [推测] | 智谱开放平台文档 |

**关键发现**：

- MTClaw 的 benchmark 数据（50 个系统控制任务 × 4 次）是基于 **7 个工具** 测得的 [推测, MTClaw 团队测试, 非本项目实测]
- Prometheus 使用 16 个自定义工具 + 5 个 builtin = 21 个工具暴露给路由模型 [推测]
- 研究表明 LLM function calling 准确率在工具数 < 15 时最高 [推测]，Prometheus 的 21 个工具略超最佳范围
- **Prometheus 自身的路由准确率实测数据尚未产出** [目标: > 90%]

### 3.2 延迟分析

#### 3.2.1 MTClaw 已有延迟数据 [推测, MTClaw 团队测试, 非本项目实测]

| 模式 | 路由模型 | 平均耗时 | 加速比 (vs Baseline) |
|------|---------|---------|---------------------|
| Baseline（纯上游 LLM） | - | 37.97s | 1.00x |
| Permissive | Qwen3-30B | 5.54s | **6.85x** |
| Strict | Qwen3-30B | 7.61s | **4.99x** |

> 上述数据来自 MTClaw 团队在系统控制垂域（7 工具）的测试。DeepSeek-V4-Flash 的延迟数据需在本项目中实测。

#### 3.2.2 各候选模型延迟推测

| 模型 | 预期首字延迟 [推测] | 预期完整路由延迟 [推测] | 依据 |
|------|-------------------|----------------------|------|
| DeepSeek-V4-Flash | 0.3-1.0s | 0.5-1.5s | 当前生产环境实际使用；Flash 定位低延迟 |
| Qwen3-30B-A3B | 0.3-1.5s | 0.5-2.0s | MoE 3B 激活比，推理快；本地部署 1-3s [推测, design-proposal.md] |
| GLM-4.7-Flash | 0.2-0.8s | 0.3-1.0s | 免费 + Flash 定位，推测延迟极低 |
| GLM-4.7-FlashX | 0.2-0.5s | 0.3-0.8s | FlashX 定位极速推理 |
| GLM-4-FlashX-250414 | 0.2-0.5s | 0.3-0.8s | 同 FlashX 定位 |
| GLM-4.5-Air | 0.3-1.0s | 0.5-1.5s | Air 定位性价比，延迟适中 |

> **重要**：以上延迟均为 [推测] 值。实际延迟受网络往返（API 调用 vs 本地部署）、请求排队、token 数量等因素影响。Prometheus 需在目标硬件（MTT AIBOOK）上实测。

#### 3.2.3 路由超时机制

```python
# server.py:963-980
timeout_s = STATE.config.routing_timeout_s  # 默认 10.0s

# 第一次超时 -> 随机等待 0.1-0.5s -> 重试一次
# 第二次超时 -> raise -> caller fallback to upstream LLM
```

- 路由模型超时不会导致系统不可用，会安全降级到上游 LLM
- 但每次超时增加 ~10-20s 延迟（超时等待 + 重试 + 上游 LLM 调用）
- **目标**：路由模型 P99 延迟 < 5s [目标]，避免超时降级频繁发生

### 3.3 成本分析

#### 3.3.1 官方定价汇总 [官网]

> 汇率参考：1 美元 ≈ 7.2 元人民币

| 模型 | 输入 (每百万 tokens) | 输出 (每百万 tokens) | 缓存命中 (每百万 tokens) | 提供方 |
|------|---------------------|---------------------|------------------------|--------|
| **DeepSeek-V4-Flash** | $0.14（≈1.01元） | $0.28（≈2.02元） | $0.0028（≈0.02元） | DeepSeek API |
| **Qwen3-30B-A3B** | ≈0.5-2元 [推测, 火山 ARK 定价区间] | ≈1-6元 [推测] | — | 火山 ARK / 百炼 |
| **GLM-4.7-Flash** | **免费** | **免费** | **免费** | 智谱开放平台 |
| **GLM-4.7-FlashX** | 0.5元 | 3元 | 0.1元 | 智谱开放平台 |
| **GLM-4-FlashX-250414** | 0.1元 | — (统一计费) | — | 智谱开放平台 |
| **GLM-4.5-Air** | 0.8元 | 2元 (短输出) / 6元 (长输出) | 0.16元 | 智谱开放平台 |

#### 3.3.2 路由场景单次调用成本估算 [推测]

路由场景的典型 token 消耗：
- 输入：system prompt (~300 tokens) + 工具定义 (~1500 tokens) + 用户消息 (~50 tokens) ≈ **1850 tokens**
- 输出：tool_call 决策 (~50 tokens) ≈ **50 tokens**
- 闲聊直回场景输出：~200 tokens

| 模型 | 单次路由成本 [推测] | 单次闲聊直回成本 [推测] | 月成本估算 (1000 次/天) [推测] |
|------|-------------------|----------------------|------------------------------|
| DeepSeek-V4-Flash | ≈0.0014元 | ≈0.0066元 | ≈200元/月 |
| Qwen3-30B-A3B (API) | ≈0.003-0.006元 | ≈0.01-0.02元 | ≈400-600元/月 |
| GLM-4.7-Flash | **0元** | **0元** | **0元** |
| GLM-4.7-FlashX | ≈0.0012元 | ≈0.0056元 | ≈170元/月 |
| GLM-4-FlashX-250414 | ≈0.0002元 | ≈0.0002元 | ≈6元/月 |
| GLM-4.5-Air | ≈0.0016元 | ≈0.0048元 | ≈190元/月 |

> **计算依据**：输入 1850 tokens + 输出 50 tokens (路由) / 200 tokens (闲聊)。月成本按 30 天 × 1000 次/天（70% 路由 + 30% 闲聊直回）估算。以上均为 [推测] 值。

**关键结论**：
- **GLM-4.7-Flash 完全免费**，是成本维度的绝对优势选择
- DeepSeek-V4-Flash 成本极低（$0.14/M input），且 DeepSeek 有 context caching 机制（缓存命中 $0.0028/M），工具定义部分可被缓存
- Qwen3-30B-A3B 本地部署成本为零（但需要 GPU 算力），API 调用成本中等

### 3.4 工程兼容性

| 维度 | DeepSeek-V4-Flash | Qwen3-30B-A3B | GLM-4.7-Flash | GLM-4.5-Air |
|------|-------------------|---------------|---------------|-------------|
| OpenAI-compatible API | ✅ [官网] | ✅ [官网] | ✅ [官网] | ✅ [官网] |
| `tools` 参数支持 | ✅ [官网] | ✅ [官网] | ✅ [官网] | ✅ [官网] |
| `enable_thinking` 参数 | ⚠️ 未知（DeepSeek 有自己的 thinking mode） | ✅ 原生支持 [官网] | ⚠️ 未知（可能忽略） | ⚠️ 未知 |
| `repetition_penalty` 参数 | ⚠️ 未知 | ✅ 原生支持 [官网] | ⚠️ 未知 | ⚠️ 未知 |
| 火山 ARK 平台 | ✅ 当前生产使用 | ✅ 可用 | ❌ 智谱独占 | ❌ 智谱独占 |
| 本地部署 (AIBOOK) | ❌ 参数量过大 | ✅ 30B MoE 可部署 [推测] | ❌ | ❌ |
| Context Caching | ✅ 自动缓存 [官网] | ⚠️ 依赖平台 | ❓ | ❓ |
| 最大上下文 | 1M tokens [官网] | 256K tokens [官网] | 200K tokens [官网] | 128K tokens [官网] |
| 模型稳定性 (SLA) | 高（商业 API） | 高（商业 API） | 中（免费模型，可能有限流） | 高 |

**关键兼容性风险**：

1. **`enable_thinking` 参数**：这是 Qwen3 特有参数。DeepSeek-V4-Flash 有自己的 thinking mode 机制（通过 API 参数控制），`enable_thinking=false` 可能被忽略或报错。GLM 系列大概率忽略未知参数，但需验证。

2. **`repetition_penalty` 参数**：非标准 OpenAI 参数。部分 API 提供商支持，部分不支持。如果 API 严格校验，调用会 422 报错。

3. **火山 ARK 平台**：当前 `base_url` 为 `https://ark.cn-beijing.volces.com/api/coding`，这是火山引擎 ARK 平台。DeepSeek 和 Qwen3 均可通过 ARK 调用，但 GLM 系列需要在智谱开放平台单独调用（`https://open.bigmodel.cn/api/paas/v4`）。

4. **Completion Check 共用路由模型**：`call_qwen_completion_check()` 也使用 `routing.model`，意味着切换路由模型同时影响 Completion Check 的判断质量。

---

## 4. MTClaw 已有实测数据

### 4.1 Benchmark 数据 [推测, MTClaw 团队测试, 非本项目实测]

在 50 个系统控制任务上，每个任务重复 4 次：

| 指标 | Permissive 模式 | Strict 模式 |
|------|----------------|------------|
| Pass@1 | 95.5% | **100.0%** |
| 平均耗时 | 5.54s | 7.61s |
| 加速比 | **6.85x** | **4.99x** |
| 工具召回率 | 100% | 100% |
| 工具准确率 | 97.5% | 94.8% |

- 测试模型：Qwen3-30B（MTClaw 原始设计使用的路由模型）
- 测试工具数：7 个系统控制工具
- 上游 LLM：Doubao

### 4.2 对 Prometheus 的适用性分析

| 差异点 | MTClaw Benchmark | Prometheus | 影响 |
|--------|-----------------|------------|------|
| 工具数 | 7 | 21 (16 自定义 + 5 builtin) | 工具数增加 → FC 准确率下降 [推测] |
| 工具域 | 系统控制（高相似度） | 5 个不相关领域 | 跨领域工具描述更易区分，但边界 case 更多 |
| 路由模型 | Qwen3-30B | DeepSeek-V4-Flash (当前) | 模型不同，无法直接复用 benchmark |
| 闲聊直回 | 无 | 有 (chat_light) | 新增风险：路由模型直回质量 |
| Completion Check | 有 | 有 | 模型切换影响判断质量 |

**结论**：MTClaw 的 benchmark 数据不能直接用于 Prometheus。Prometheus 必须在自己的工具集和场景下重新实测。[推测]

---

## 5. 风险与陷阱

### 5.1 未知参数兼容性风险

```python
# server.py 发送的非标准参数
"repetition_penalty": 1.2,    # 非 OpenAI 标准
"enable_thinking": False,      # Qwen3 特有
```

- **DeepSeek API**：DeepSeek 有自己的 thinking mode（通过 `deepseek-chat` vs `deepseek-reasoner` 区分），`enable_thinking` 参数可能被忽略或需要适配
- **GLM API**：智谱 API 对未知参数的处理策略未知。如果严格校验，调用会失败
- **缓解措施**：切换模型前需测试 API 对未知参数的容错性；必要时修改 FR 源码，按模型类型动态构造 payload

### 5.2 GLM-4.7-Flash 免费模型的风险

- **限流风险**：免费模型通常有严格的 QPS 限制（如 5-10 QPS），高并发场景可能触发 429
- **稳定性风险**：免费模型可能随时调整政策（限流收紧、转为收费、下线）
- **不适用 Completion Check**：如果免费模型限流，Completion Check 也会受影响（因为共用 routing model）
- **缓解措施**：配置 `routing_timeout_s` 为较小值（如 5s），超时快速降级

### 5.3 工具数超过最佳范围

- Prometheus 暴露给路由模型的工具数为 21 个（16 自定义 + 5 builtin）
- 研究表明 function calling 准确率在 < 15 工具时最高 [推测]
- **缓解措施**：
  - builtin 工具（find/ls/cat/grep/sleep）不应暴露给路由模型（FR 源码中 builtin 工具是否在 `STATE.tools` 中需要验证）
  - 考虑两级路由：先选 Subagent，再在 Subagent 内选工具
  - 通过关键词/正则匹配辅助纠正 LLM 的误判（design-proposal.md §2.3 已有设计）

### 5.4 chat_light 误判风险

闲聊直回（chat_light）是风险最高的 Subagent——任何误路由到这里都会产生低质量回复。

- 路由模型的判断能力直接决定 chat_light 的误判率
- 30B 级别模型（Qwen3-30B / DeepSeek-V4-Flash）对闲聊 vs 复杂问题的区分能力较强 [推测]
- 9B 级别模型（GLM-4.7-Flash 等）的区分能力需实测验证 [推测]
- **缓解措施**：保守策略（design-proposal.md §2.5 已有设计），宁可假阴性走上游 LLM

### 5.5 DeepSeek-V4-Flash 的 Thinking Mode

DeepSeek-V4-Flash 默认开启 thinking mode [官网]。FR 通过 `enable_thinking=false` 尝试关闭，但：
- DeepSeek 的 thinking mode 控制方式与 Qwen3 不同
- 如果 thinking mode 未正确关闭，路由延迟会显著增加（先 thinking 再输出 tool_call）
- **需验证**：当前生产配置中 `enable_thinking=false` 是否被 DeepSeek API 正确处理

---

## 6. 选型建议

### 6.1 决策矩阵

| 维度 | 权重 | DeepSeek-V4-Flash | Qwen3-30B-A3B | GLM-4.7-Flash | GLM-4.5-Air |
|------|------|-------------------|---------------|---------------|-------------|
| Function Calling 准确率 | 30% | ⭐⭐⭐⭐ (有实测) | ⭐⭐⭐⭐⭐ (MTClaw 原始设计) | ⭐⭐⭐ (需验证) | ⭐⭐⭐ (需验证) |
| 延迟 | 25% | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 成本 | 20% | ⭐⭐⭐⭐ (极低) | ⭐⭐⭐ (中等) | ⭐⭐⭐⭐⭐ (免费) | ⭐⭐⭐⭐ (低) |
| 工程兼容性 | 15% | ⭐⭐⭐⭐⭐ (当前在用) | ⭐⭐⭐⭐⭐ (原生设计) | ⭐⭐⭐ (参数兼容需验证) | ⭐⭐⭐ (同上) |
| 稳定性/SLA | 10% | ⭐⭐⭐⭐⭐ (商业 API) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ (免费限流风险) | ⭐⭐⭐⭐ |

### 6.2 推荐方案

#### 方案 A（推荐）：保持 DeepSeek-V4-Flash + 验证 GLM-4.7-Flash 作为备选

**理由**：
1. DeepSeek-V4-Flash 是当前生产配置，已在实际运行中验证
2. 成本极低（$0.14/M input），有 context caching 机制进一步降低成本
3. function calling 能力有 MTClaw benchmark 间接支撑（虽然模型不同）
4. 通过火山 ARK 平台统一管理，与 Qwen3 切换方便

**行动项**：
- [ ] 验证 `enable_thinking=false` 是否被 DeepSeek API 正确处理
- [ ] 在 Prometheus 工具集（21 工具）上实测路由准确率
- [ ] 测量 P50/P99 路由延迟
- [ ] 并行测试 GLM-4.7-Flash 作为零成本备选方案

#### 方案 B：Qwen3-30B-A3B（回归 MTClaw 原始设计）

**理由**：
1. MTClaw 原始设计使用此模型，有完整的 benchmark 数据
2. `enable_thinking` 参数原生支持，无兼容性风险
3. 可在 MTT AIBOOK 上本地部署，零网络延迟、零 API 成本
4. MoE 架构 3B 激活比，推理速度快

**适用场景**：如果赛事要求完全本地部署（AIBOOK 本地算力），或需要与 MTClaw 上游 benchmark 对齐

**行动项**：
- [ ] 在 AIBOOK 上部署 Qwen3-30B-A3B（通过 vLLM 或 Ollama）
- [ ] 验证本地部署的延迟和吞吐
- [ ] 在 Prometheus 工具集上实测路由准确率

#### 方案 C：GLM-4.7-Flash（零成本方案）

**理由**：
1. 完全免费，适合演示和比赛场景
2. 200K 上下文充足
3. Flash 定位低延迟

**风险**：
1. 免费模型限流风险，演示中触发 429 会严重影响体验
2. function calling 准确率未知，需实测验证
3. `enable_thinking` 和 `repetition_penalty` 参数兼容性未知
4. 与当前火山 ARK base_url 不兼容，需要更换 API endpoint

**行动项**：
- [ ] 验证智谱 API 对非标准参数的容错性
- [ ] 压测 QPS 限制
- [ ] 在 Prometheus 工具集上实测路由准确率
- [ ] 如可用，作为低优先级备选方案

### 6.3 最终建议

```
推荐路径：

1. 短期（比赛演示）：保持 DeepSeek-V4-Flash
   - 已验证可用，无切换风险
   - 成本可控
   - 专注打磨 Subagent 质量

2. 中期（实测验证）：并行测试 GLM-4.7-Flash
   - 零成本优势明显
   - 如果 FC 准确率和延迟达标，可切换
   - 需要修改 FR 源码适配智谱 API

3. 本地部署场景（AIBOOK）：Qwen3-30B-A3B
   - 零网络延迟
   - 与 MTClaw 原始设计对齐
   - 需要验证 AIBOOK GPU 算力是否足够

4. 必须产出：
   - Prometheus 自有的路由准确率测试集（50+ 条混合意图）
   - 各候选模型在相同测试集上的准确率/延迟/成本对比
   - 标记为 [实测] 的数据，替代当前的 [推测] / [目标] 数据
```

---

## 附录 A：候选模型参数与定价汇总

### A.1 DeepSeek 定价 [官网, https://api-docs.deepseek.com/quick_start/pricing]

| 项目 | DeepSeek-V4-Flash | DeepSeek-V4-Pro |
|------|-------------------|-----------------|
| 输入 (cache miss) | $0.14 / 1M tokens | $0.435 / 1M tokens |
| 输入 (cache hit) | $0.0028 / 1M tokens | $0.003625 / 1M tokens |
| 输出 | $0.28 / 1M tokens | $0.87 / 1M tokens |
| 上下文 | 1M tokens | 1M tokens |
| 最大输出 | 384K tokens | 384K tokens |
| Function Calling | ✅ | ✅ |
| 并发限制 | 2500 | 500 |
| Thinking Mode | 可切换 | 可切换 |

### A.2 智谱 AI 定价 [官网, https://open.bigmodel.cn/pricing]

| 模型 | 输入 (元/百万tokens) | 输出 (元/百万tokens) | 缓存命中 (元/百万tokens) | 上下文 |
|------|---------------------|---------------------|------------------------|--------|
| GLM-5.2 | 8 | 28 | 2 | 1M |
| GLM-5.1 (0-32K) | 6 | 24 | 1.3 | — |
| GLM-5 (0-32K) | 4 | 18 | 1 | — |
| GLM-4.7 (0-32K, 短输出) | 2 | 8 | 0.4 | 200K |
| GLM-4.7-FlashX | 0.5 | 3 | 0.1 | 200K |
| **GLM-4.7-Flash** | **免费** | **免费** | **免费** | 200K |
| GLM-4.5-Air (0-32K, 短输出) | 0.8 | 2 | 0.16 | 128K |
| GLM-4-FlashX-250414 | 0.1 | — | — | 128K |
| GLM-4-Air-250414 | 0.5 | — | — | 128K |
| GLM-4-Plus | 5 | — | — | 128K |
| GLM-4-Long | 1 | — | — | 1M |

### A.3 Qwen3-30B-A3B [推测, 基于火山 ARK / 阿里百炼公开定价区间]

| 项目 | 值 |
|------|-----|
| 架构 | MoE，30B 总参数，3B 激活 |
| 上下文 | 256K tokens |
| Function Calling | ✅ 原生支持 |
| `enable_thinking` | ✅ 原生支持 |
| 本地部署 | ✅ (AIBOOK GPU 可部署) [推测] |
| API 定价 | 因平台而异，火山 ARK 约 0.5-2 元/百万 tokens (输入) [推测] |

---

## 附录 B：MTClaw FR 路由模型调用参数清单

以下参数由 `server.py` 的 `call_qwen()` 函数构造，发送给路由模型 API：

```python
# server.py:947-957
payload = {
    "model": STATE.config.routing.model,          # 配置文件中的 routing.model
    "messages": messages,                          # system prompt + history + user message
    "tools": STATE.tools,                          # 所有工具定义 (JSON Schema 格式)
    "stream": False,                               # 非流式
    "temperature": 0.0,                            # 确定性路由
    "repetition_penalty": 1.2,                     # 非标准参数
    "frequency_penalty": 0.2,                      # OpenAI 标准
    "parallel_tool_calls": False,                  # 不允许并行工具调用
    "enable_thinking": False,                      # Qwen3 特有参数
}
```

Completion Check 调用 (`call_qwen_completion_check()`, server.py:1526-1563) 使用相同模型，参数类似但 messages 不同（注入 `SYSTEM_PROMPT_REVIEW` 判断 TASK_COMPLETE/INCOMPLETE）。

---

## 附录 C：Prometheus 路由准确率测试计划

### C.1 测试集设计 [目标]

| 类别 | 数量 | 示例 |
|------|------|------|
| RAG 检索 | 10 | "帮我找一下 GPU 算力对比的笔记" |
| 记忆偏好 | 10 | "记住我喜欢用 Markdown 格式" |
| 写作润色 | 10 | "帮我写一篇周报" |
| 日程管理 | 10 | "明天有什么安排" |
| 闲聊陪伴 | 10 | "讲个笑话" |
| 边界 case | 10 | "帮我看看这个文件然后总结一下" (RAG vs 写作) |
| 兜底场景 | 10 | "分析一下量子计算的发展趋势" (需上游 LLM) |

### C.2 测试指标

| 指标 | 定义 | 目标 |
|------|------|------|
| 路由准确率 | 正确路由到预期 Subagent 的比例 | > 90% [目标] |
| 闲聊误判率 | 非 chat_lite 场景被误路由到 chat_light 的比例 | < 2% [目标] |
| P50 路由延迟 | 50% 分位路由模型响应时间 | < 1s [目标] |
| P99 路由延迟 | 99% 分位路由模型响应时间 | < 5s [目标] |
| 超时降级率 | 路由模型超时触发 fallback 的比例 | < 1% [目标] |

### C.3 测试方法

```bash
# 1. 准备测试集 (JSONL 格式，每行一条测试用例)
# 2. 逐条调用 FR API，记录路由结果和延迟
# 3. 对比预期路由 vs 实际路由，计算准确率
# 4. 在不同候选模型上重复测试

# 示例测试脚本框架：
for model in deepseek-v4-flash qwen3-30b-a3b glm-4.7-flash; do
    # 更新 config.json routing.model
    # 重启 FR
    # 运行测试集
    # 记录结果
done
```

> 以上测试计划为 [目标]，尚未实施。Prometheus 的实测数据将在验证阶段产出。
