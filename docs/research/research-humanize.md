# 去AI化技术调研报告

> 报告编号：R07 | 日期：2026-07-14 | 状态：完成
>
> 主题：AI 写作特征识别、AI 检测器原理、去AI化方案设计、三级强度实现、评估方法、开源工具生态
>
> 关联文档：`spec.md` §3.3 writing_humanize 工具、`add-writing.md` §3.4 去AI化改写机制

---

## 目录

1. [概述与背景](#1-概述与背景)
2. [AI 写作特征分析](#2-ai-写作特征分析)
3. [AI 检测器原理](#3-ai-检测器原理)
4. [去AI化技术方案](#4-去ai化技术方案)
5. [三级强度实现设计](#5-三级强度实现设计)
6. [评估方法与指标](#6-评估方法与指标)
7. [开源工具与生态](#7-开源工具与生态)
8. [Prometheus 集成方案](#8-prometheus-集成方案)
9. [风险与限制](#9-风险与限制)
10. [结论与建议](#10-结论与建议)
11. [参考文献](#11-参考文献)

---

## 1. 概述与背景

### 1.1 问题定义

随着 GPT-4o、DeepSeek-V3、Claude 等大语言模型的普及，AI 生成的文本在语法正确性和信息密度上已接近甚至超越人类水平。但 AI 文本存在可辨识的统计和语言特征——所谓的"AI 味"（AI tells）。这些特征被 AI 检测器（如 GPTZero、Turnitin AI、Originality.ai）利用来判别文本来源，也被人类读者感知为"不自然"。

**去AI化（Humanization）** 是指通过改写、扰动或重写技术，消除或减弱 AI 文本中的可辨识特征，使文本在检测器评估和人类感知上更接近人类写作。本研究为 Prometheus 写作 Subagent 的 `writing_humanize` 工具提供技术调研基础。

### 1.2 应用场景

| 场景 | 需求 | 强度要求 |
|------|------|----------|
| 学术写作辅助 | 去除明显套话，保留学术严谨性 | light |
| 商务文档 | 提升自然度，符合企业风格 | medium |
| 内容创作 | 完全改写，追求个人风格 | heavy |
| 自媒体/博客 | 个性化表达，避免平台限流 | heavy |
| 邮件/周报 | 轻微调整，去除机械感 | light-medium |

### 1.3 研究范围

本报告覆盖以下六个维度：

1. **AI 写作特征**：从词汇、句式、结构、标点、语义五个层面系统归纳
2. **检测器原理**：统计特征法、语言模型法、分类器法、多尺度法
3. **去AI化方案**：规则替换、LLM 改写、统计扰动、混合方案
4. **三级强度**：light / medium / heavy 的差异化设计
5. **评估方法**：检测器通过率、语义保真度、人工评估、自动指标
6. **开源工具**：检测器、改写器、评估框架的生态图谱

---

## 2. AI 写作特征分析

### 2.1 特征分类体系

AI 写作特征可从五个维度系统分类。以下分类综合了 Wikipedia "Signs of AI writing" 指南（由 WikiProject AI Cleanup 维护）、学术研究以及 blader/humanizer 项目的实践经验。

### 2.2 词汇层面特征

#### 2.2.1 AI 高频词（AI Vocabulary Words）

LLM 在生成时倾向于使用一组统计学上高频但语义空泛的词汇。这些词在 2023 年后的文本中出现频率显著上升：

**英文 AI 高频词清单**：

| 类别 | 典型词汇 |
|------|----------|
| 强调词 | crucial, pivotal, vital, significant, key, essential |
| 动作词 | delve, explore, leverage, foster, enhance, showcase, underscore, highlight |
| 抽象名词 | landscape, tapestry, interplay, intricacies, testament, realm |
| 形容词 | vibrant, profound, enduring, rich, dynamic, seamless |
| 连接词 | additionally, moreover, furthermore, consequently |
| 其他 | actually, align with, garner, valuable, compelling |

**中文 AI 高频词清单**：

| 类别 | 典型词汇 |
|------|----------|
| 强调词 | 至关重要、关键、核心、不可或缺 |
| 套话 | 在当今时代、随着...的发展、众所周知 |
| 动作词 | 深入探讨、赋能、助力、推动、促进 |
| 抽象表达 | 生态、矩阵、闭环、抓手、赋能 |
| 连接词 | 首先...其次...最后、一方面...另一方面 |
| 总结词 | 总而言之、综上所述、值得注意的是 |

#### 2.2.2 Copula 回避（系动词回避）

LLM 倾向于用"serves as"、"stands as"、"represents"、"boasts"、"features"、"offers"替代简单的"is/are/has"：

- AI: "The gallery **serves as** the city's exhibition space and **boasts** over 3,000 square feet."
- 人类: "The gallery **is** the city's exhibition space. It **has** 3,000 square feet."

#### 2.2.3 优雅变体（Elegant Variation / Synonym Cycling）

由于 LLM 的重复惩罚机制，模型过度使用同义替换，导致同一概念在一篇文章中出现多个不同的表述：

- AI: "The **protagonist** faces challenges. The **main character** must overcome obstacles. The **central figure** triumphs. The **hero** returns."
- 人类: "The protagonist faces challenges but eventually triumphs and returns home."

### 2.3 句式层面特征

#### 2.3.1 三元组法则（Rule of Three）

LLM 强制将信息组织为三元素组，制造"全面性"的假象：

- AI: "The event features keynote sessions, panel discussions, and networking opportunities."
- 人类: "The event includes talks and panels, with time for informal networking."

#### 2.3.2 否定平行结构（Negative Parallelism）

- "Not only...but also..." / "It's not just about..., it's..." / "Not merely..., but..."

#### 2.3.3 被动语态与无主语句

LLM 频繁隐藏动作执行者：
- AI: "No configuration file needed. The results are preserved automatically."
- 人类: "You don't need a configuration file. The system preserves results automatically."

#### 2.3.4 -ing 短语堆砌

LLM 用现在分词短语添加虚假深度：
- AI: "...resonates with the region's natural beauty, **symbolizing** Texas bluebonnets, **reflecting** the community's deep connection to the land."
- 人类: "The architect said the colors were chosen to reference local bluebonnets and the Gulf coast."

#### 2.3.5 句长均匀性

AI 文本的句子长度分布趋于均匀（方差小），而人类写作交替使用短句和长句，呈现明显的节奏变化。这是统计检测器的核心信号之一。

### 2.4 结构层面特征

#### 2.4.1 机械式总分总

AI 文本普遍采用"概述→分点→总结"的三段式结构，段落间过渡高度模板化。

#### 2.4.2 套路化"挑战与展望"段落

- "Despite its... faces several challenges... Despite these challenges... continues to thrive..."

#### 2.4.3 碎片化标题（Fragmented Headers）

标题后紧跟一句话复述标题，再进入正文——LLM 的"热身"习惯。

#### 2.4.4 内联标题列表（Inline-Header Vertical Lists）

```
- **用户体验：** 用户体验已通过新界面显著改善。
- **性能：** 性能通过优化算法得到提升。
- **安全：** 安全通过端到端加密得到加强。
```

#### 2.4.5 虚假范围（False Ranges）

"from X to Y"结构中，X 和 Y 不在同一有意义的量表上：
- AI: "from the singularity of the Big Bang to the grand cosmic web"

### 2.5 标点与格式特征

| 特征 | AI 倾向 | 人类倾向 |
|------|---------|----------|
| 破折号（em dash —） | 过度使用 | 适度/偶尔使用 |
| 粗体 | 机械地强调术语 | 谨慎使用 |
| 标题大小写 | Title Case（每个词首字母大写） | Sentence case（仅首词大写） |
| Emoji | 装饰性使用（🚀💡✅） | 极少在正式文本中使用 |
| 引号 | 弯引号（""） | 直引号（""）或依编辑器设置 |
| 分号 | 频繁使用 | 较少使用 |
| 连字符对 | data-driven, cross-functional（一律连字符） | 仅作定语时连字符，作表语时去掉 |

### 2.6 语义与语用特征

#### 2.6.1 过度强调意义（Inflated Symbolism）

LLM 将任意细节提升为"重要时刻"或"深层象征"：
- "marking a pivotal moment in the evolution of..."
- "stands as a testament to..."
- "underscores the significance of..."

#### 2.6.2 推广性语言（Promotional Language）

- "nestled in the heart of", "breathtaking", "vibrant", "stunning", "must-visit"

#### 2.6.3 模糊归因（Vague Attributions）

- "Experts argue...", "Industry reports suggest...", "Observers have cited..."

#### 2.6.4 谄媚语气（Sycophantic Tone）

- "Great question!", "You're absolutely right!", "That's an excellent point!"

#### 2.6.5 通用积极结尾（Generic Positive Conclusions）

- "The future looks bright...", "Exciting times lie ahead..."

#### 2.6.6 知识截止声明与推测填充

- "While specific details are limited...", "it is believed that...", "likely grew up in..."

#### 2.6.7 格言化（Aphorism Formulas）

- "X is the Y of Z", "X becomes a trap", "X is not a tool but a mirror"

#### 2.6.8 信号标注（Signposting）

LLM 宣布即将做什么，而非直接做：
- "Let's dive in...", "Here's what you need to know...", "Without further ado..."

### 2.7 中英文特征差异

| 维度 | 英文 AI 特征 | 中文 AI 特征 |
|------|-------------|-------------|
| 高频词 | delve, crucial, tapestry | 赋能、助力、深入探讨 |
| 句式 | -ing 堆砌、被动语态 | "不仅...而且..."、"既...又..." |
| 结构 | Rule of Three | "首先...其次...最后..." |
| 标点 | em dash 过度 | 破折号、分号过度 |
| 套话 | "nestled in" | "在当今...背景下" |
| 结尾 | "future looks bright" | "综上所述...意义重大" |

### 2.8 特征置信度矩阵

并非所有特征都是可靠的 AI 指标。单个特征出现不构成证据，**特征聚类**（clusters of tells）才是可靠信号：

| 特征 | 单独出现可靠性 | 聚类后可靠性 |
|------|---------------|-------------|
| 破折号 | 低（人类也用） | 中高 |
| 弯引号 | 极低（编辑器自动转换） | 低 |
| 完美语法 | 极低 | 低 |
| "Additionally" 单独出现 | 极低 | 中 |
| Rule of Three + 破折号 + "vibrant tapestry" | — | 高 |
| 推广语言 + 模糊归因 + 通用结尾 | — | 高 |

**核心原则**：单个 tell 无意义；多个 tell 聚集才是 AI 写作的"自白"。

---

## 3. AI 检测器原理

### 3.1 检测器分类

AI 文本检测器可分为四大技术路线：

```
                    AI 文本检测器
                         │
          ┌──────────────┼──────────────┐
          │              │              │
    统计特征法      语言模型法       分类器法
    (Statistical)  (LM-based)    (Classifier)
          │              │              │
   ┌──────┴──────┐  ┌────┴────┐   ┌────┴────┐
   │  困惑度     │  │ Log-    │   │ 微调    │
   │  Burstiness │  │ Rank    │   │ BERT/   │
   │  N-gram     │  │ Perplexity│  │ RoBERTa│
   └─────────────┘  └─────────┘   └─────────┘
                                  ┌─────────┐
                                  │ 多尺度  │
                                  │ PU 学习 │
                                  └─────────┘
```

### 3.2 统计特征法

#### 3.2.1 困惑度（Perplexity）

**原理**：使用参考语言模型计算文本的困惑度。AI 生成的文本对参考模型来说"更可预测"（低困惑度），因为 AI 模型同样在最大化概率。

```
PPL(text) = exp(-1/N * Σ log P(token_i | context))
```

- AI 文本：低 PPL（可预测性高）
- 人类文本：高 PPL（可预测性低，更"意外"）

**GPTZero 的核心指标之一**即为困惑度。

#### 3.2.2 突发性（Burstiness）

**原理**：衡量文本中困惑度的方差。人类写作的句子困惑度波动大（有时平淡，有时意外），AI 写作的困惑度趋于均匀。

```
Burstiness = Var(PPL(sentence_1), PPL(sentence_2), ..., PPL(sentence_n))
```

- AI 文本：低 Burstiness（均匀）
- 人类文本：高 Burstiness（波动大）

**这是 GPTZero 最核心的判别指标。** Burstiness 比单独的 PPL 更有效，因为即使 AI 文本的平均困惑度被人为调高，其句间方差仍然偏小。

#### 3.2.3 N-gram 分析

统计 n-gram 频率分布，AI 文本的 n-gram 分布更集中（多样性低），人类文本更分散。

### 3.3 语言模型法

#### 3.3.1 Log-Likelihood / Log-Rank

使用参考语言模型计算每个 token 的对数似然和对数排名：

- **Log-Likelihood**：AI 文本的 token 对数似然更高（模型更"自信"）
- **Log-Rank**：AI 文本的 token 在模型预测分布中排名更靠前

**DetectGPT**（Mitchell et al., 2023）利用扰动后的对数似然变化来检测：对原文做微小扰动（如用 T5 mask-fill），如果扰动后似然下降，则原文可能是 AI 生成（AI 文本处于概率局部最大值）。

#### 3.3.2 DNA-GPT / Binoculars

- **DNA-GPT**：比较生成模型和检测模型的似然差异
- **Binoculars**（Hans et al., 2024）：使用两个语言模型的交叉困惑度比值，无需微调，zero-shot 检测

### 3.4 分类器法

#### 3.4.1 微调预训练模型

最常见的做法：在 HC3（Human ChatGPT Comparison Corpus）等数据集上微调 BERT/RoBERTa：

```
训练数据：
  - 正例（AI 生成）：ChatGPT/GPT-4/DeepSeek 生成文本
  - 负例（人类撰写）：人类回答/文章/论文

模型：RoBERTa-base → 二分类头
```

**OpenAI 的 AI 分类器**（已下线）即采用此方法，但因假阳性率过高而停止服务。

#### 3.4.2 多尺度 PU 学习（ICLR'24 Spotlight）

**YuchuanTian/AIGC_text_detector** 提出了多尺度正-无标签（Positive-Unlabeled）学习：

**核心创新**：
1. **PU 学习框架**：不依赖干净的负样本，将所有人类文本视为"无标签"数据，仅用 AI 文本作为正例
2. **多尺度特征**：结合句子级和全文级特征
3. **数据增强**：句子删除增强，提升鲁棒性

**性能**（HC3-English）：

| 变体 | Full-Text 准确率 | Sentence-Level 准确率 |
|------|-----------------|----------------------|
| seed0 | 98.68% | 82.84% |
| seed1 | 98.56% | 87.06% |
| seed2 | 97.97% | 86.02% |
| **平均** | **98.40 ± 0.31%** | **85.31 ± 1.80%** |

**v3 版本**（2025年6月更新）已针对 DeepSeek-V3、GPT-4、推理模型等最新 LLM 进行适配。

### 3.5 商业检测器对比

| 检测器 | 技术路线 | 特点 | 准确率声称 |
|--------|---------|------|-----------|
| **GPTZero** | PPL + Burstiness | 教育领域主流，免费可用 | ~99% (自称) |
| **Turnitin AI** | 专有模型 | 学术界广泛使用 | ~98% (自称) |
| **Originality.ai** | 多模型集成 | 内容创作领域 | ~99% (自称) |
| **Copyleaks** | 专有模型 | 企业级，支持多语言 | ~99% (自称) |
| **Winston AI** | 专有模型 | 教育+企业 | ~99% (自称) |
| **Sapling AI** | 统计特征 | 轻量级，API 友好 | ~97% (自称) |
| **OpenAI Classifier** | 微调 RoBERTa | **已下线**（假阳性高） | 曾声称 26% 假阳性 |

### 3.6 检测器的局限性

1. **假阳性问题**：非英语母语者的写作、高度结构化的技术文档容易被误判为 AI 生成
2. **对抗脆弱性**：简单的改写、翻译、或风格扰动即可降低检测准确率
3. **模型迭代滞后**：检测器训练数据滞后于新模型发布，对最新 LLM 效果下降
4. **短文本困难**：<100 词的文本检测准确率显著下降
5. **领域偏移**：在特定领域（如诗歌、代码注释）训练的检测器在其他领域效果差

---

## 4. 去AI化技术方案

### 4.1 方案分类

```
                  去AI化技术方案
                       │
        ┌──────────────┼──────────────┐
        │              │              │
    规则替换法      LLM 改写法      统计扰动法
    (Rule-based)   (LLM Rewrite)  (Statistical)
        │              │              │
   ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
   │ 词典替换 │   │ Prompt  │   │ 同义词  │
   │ 句式模板 │   │ 引导改写│   │ 插入删除│
   │ 标点修正 │   │ 风格迁移│   │ 困惑度  │
   └─────────┘   └─────────┘   └─────────┘
                       │
                  ┌────┴────┐
                  │ 混合方案 │  ← 推荐方案
                  └─────────┘
```

### 4.2 规则替换法

#### 4.2.1 原理

基于预定义规则和词典，对 AI 特征词进行确定性替换。

#### 4.2.2 实现示例

```python
# 词典替换规则示例
AI_WORD_REPLACEMENTS = {
    # 英文
    "delve into": "examine",
    "crucial": "important",
    "pivotal": "key",
    "vibrant": "active",
    "tapestry": "mix",
    "underscore": "show",
    "showcase": "display",
    "leverage": "use",
    "foster": "encourage",
    "enhance": "improve",
    "intricate": "complex",
    "testament": "proof",
    # 中文
    "至关重要": "很重要",
    "赋能": "支持",
    "助力": "帮助",
    "深入探讨": "讨论",
    "在当今时代": "现在",
    "随着...的发展": "",  # 删除
    "综上所述": "总之",
}

# 句式替换规则
SENTENCE_PATTERNS = {
    r"不仅.{1,20}而且": lambda m: rewrite_parallel(m),
    r"首先.{1,50}其次.{1,50}最后": lambda m: rewrite_enumeration(m),
    r"尽管.{1,30}但.{1,30}": lambda m: simplify_concession(m),
}

# 标点修正
PUNCTUATION_FIXES = {
    "—": ",",      # em dash → comma
    "–": "-",      # en dash → hyphen
    """: "\"",    # curly → straight
    """: "\"",
    "；": "。",    # 分号过度使用 → 句号
}
```

#### 4.2.3 优缺点

| 优点 | 缺点 |
|------|------|
| 速度快（O(n)） | 覆盖面有限 |
| 确定性高 | 可能产生不自然替换 |
| 无需 LLM 调用 | 无法处理深层语义特征 |
| 可控性强 | 规则维护成本高 |

### 4.3 LLM 改写法

#### 4.3.1 原理

通过精心设计的 Prompt 引导 LLM 重写文本，去除 AI 特征。

#### 4.3.2 Prompt 工程策略

**策略一：负向指令（Negative Instructions）**

```
请改写以下文本，使其更自然。避免以下 AI 写作特征：
1. 不要使用 "delve", "crucial", "tapestry", "underscore" 等词
2. 不要使用 em dash（—）
3. 不要强制使用三元组（Rule of Three）
4. 不要用 "serves as" 替代 "is"
5. 不要添加虚假意义（"marking a pivotal moment"）
6. 不要用推广性语言（"vibrant", "breathtaking"）
7. 不要用模糊归因（"experts argue"）
8. 句子长度要变化，不要均匀
9. 不要用 "Let's dive in" 等信号标注
10. 不要用通用积极结尾
```

**策略二：正向指令（Positive Instructions）**

```
请改写以下文本，使其像真人写的：
1. 用简单的词替代华丽词（is 而非 serves as）
2. 句子长短交替，制造节奏感
3. 加入具体细节和实际数字
4. 可以有个人观点和不确定性
5. 像在跟同事说话一样自然
6. 保留原文的核心信息，但用你自己的方式表达
```

**策略三：风格迁移（Style Transfer）**

```
以下是 [用户名] 的写作样本：
[用户历史写作样本]

请用 [用户名] 的写作风格改写以下文本：
[待改写文本]

注意匹配：
- 句子长度模式
- 词汇选择
- 段落开头方式
- 标点习惯
- 过渡方式
```

**策略四：Draft-Audit-Revise 循环（blader/humanizer 方法）**

```
步骤1：写出改写草稿
步骤2：自问"这段文字还有什么 AI 痕迹？"列出剩余 tells
步骤3：根据剩余 tells 修订成终稿
步骤4：扫描终稿中的 em dash（—）和 en dash（–），确保为零
```

#### 4.3.3 优缺点

| 优点 | 缺点 |
|------|------|
| 覆盖面广 | 速度慢（需 LLM 调用） |
| 可处理深层语义 | 可能引入新的 AI 痕迹（LLM 改写 LLM） |
| 支持风格迁移 | 成本高 |
| 效果上限高 | 语义保真度风险 |

#### 4.3.4 "LLM 改写 LLM"的悖论

使用 LLM 去AI化的核心矛盾：改写模型本身可能引入新的 AI 特征。缓解策略：

1. **使用不同模型族改写**：用 Claude 改写 GPT 生成的文本（不同模型的 tell 模式不同）
2. **显式负向约束**：在 Prompt 中列出具体禁用模式
3. **多轮迭代**：Draft → Audit → Revise 循环
4. **混合规则后处理**：LLM 改写后用规则替换残留特征词

### 4.4 统计扰动法

#### 4.4.1 原理

通过对文本进行统计层面的微调，改变其困惑度和突发性分布，使其在检测器眼中"更像人类"。

#### 4.4.2 具体技术

**同义词替换（Synonym Substitution）**

```python
# 基于 WordNet / 同义词词林 的随机替换
def perturb_synonyms(text, replacement_rate=0.1):
    tokens = tokenize(text)
    for i, token in enumerate(tokens):
        if random() < replacement_rate:
            synonyms = get_synonyms(token)
            if synonyms:
                tokens[i] = choice(synonyms)  # 随机选择，非最优
    return detokenize(tokens)
```

关键：**随机选择同义词而非选择最高频同义词**，因为"选择最高频"本身是 AI 行为。

**句子结构扰动**

```python
def perturb_sentence_structure(sentence):
    strategies = [
        split_long_sentence,      # 长句拆短句
        merge_short_sentences,    # 短句合并
        reorder_clauses,          # 从句重排
        add_minor_errors,         # 添加轻微"不完美"
        vary_punctuation,         # 标点变化
    ]
    return choice(strategies)(sentence)
```

**困惑度注入（Perplexity Injection）**

在特定位置插入低概率（高困惑度）词汇或表达，人为提升文本的整体困惑度和突发性。

#### 4.4.3 优缺点

| 优点 | 缺点 |
|------|------|
| 直接针对检测器弱点 | 可能损害语义 |
| 速度快 | 效果有限（仅降低检测分数） |
| 无需 LLM | 可能引入语法错误 |
| 可量化控制 | 不改善人类感知 |

### 4.5 混合方案（推荐）

将三种方法组合为流水线，取长补短：

```
输入文本
    │
    ▼
┌─────────────────┐
│ 1. 规则预清洗    │  ← 词典替换、标点修正、套话删除
│ (Rule Pre-pass)  │     速度快，确定性高
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 2. LLM 改写     │  ← Prompt 引导改写 + 风格迁移
│ (LLM Rewrite)   │     处理深层语义特征
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 3. 规则后清洗    │  ← 扫描残留 AI 特征词、em dash
│ (Rule Post-pass)│     确保零残留
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 4. 统计校准      │  ← 句长方差检查、困惑度检查
│ (Stat Check)    │     可选：检测器自评
└────────┬────────┘
         │
         ▼
输出 humanized 文本 + changes_summary
```

---

## 5. 三级强度实现设计

### 5.1 设计原则

Prometheus 的 `writing_humanize` 工具支持三级强度：`light`、`medium`、`heavy`。各级别的差异化设计遵循以下原则：

| 原则 | 说明 |
|------|------|
| **信息保真递减** | 强度越高，表达方式改变越大，但核心信息保留 |
| **处理深度递增** | light 仅表面替换，heavy 深层重写 |
| **速度递减** | light 最快（规则为主），heavy 最慢（LLM 多轮） |
| **风险递增** | heavy 可能改变语气和细节程度 |

### 5.2 Light 级别（轻度去AI化）

**目标**：去除最明显的 AI 套话和标点特征，保留原文风格和结构。

**适用场景**：学术写作、技术文档、正式邮件——仅需"去味"，不需要改变写作风格。

**处理流程**：

```
输入文本
    │
    ├── 1. 标点修正（em dash → comma/period，弯引号 → 直引号）
    ├── 2. 高频词替换（delve → examine, 至关重要 → 很重要）
    ├── 3. 套话删除（"在当今时代" → 删除, "Let's dive in" → 删除）
    ├── 4. 推广词降级（"breathtaking" → "impressive", "vibrant" → "active"）
    └── 5. 通用结尾替换（"The future looks bright" → 具体陈述）
```

**技术实现**：纯规则替换，无需 LLM 调用。

```python
def humanize_light(text: str) -> dict:
    changes = []
    
    # 标点修正
    text, n = replace_punctuation(text)
    if n: changes.append(f"修正标点 {n} 处")
    
    # 高频词替换
    text, n = replace_ai_vocabulary(text)
    if n: changes.append(f"替换 AI 高频词 {n} 处")
    
    # 套话删除
    text, n = remove_clichés(text)
    if n: changes.append(f"删除套话 {n} 处")
    
    # 推广词降级
    text, n = downgrade_promotional(text)
    if n: changes.append(f"降级推广词 {n} 处")
    
    return {"humanized": text, "changes_summary": "; ".join(changes)}
```

**预期效果**：
- 检测器分数降低 10-20%
- 人类感知改善轻微
- 语义保真度 >98%
- 处理速度 <100ms（1000词）

### 5.3 Medium 级别（中度去AI化）

**目标**：重写句式结构，提升自然度，打破均匀节奏。

**适用场景**：商务文档、周报、博客初稿——需要明显改善但保留信息结构。

**处理流程**：

```
输入文本
    │
    ├── 1. [规则] Light 级别的全部处理
    ├── 2. [LLM]  句式重写 Prompt：
    │         - 打破 Rule of Three
    │         - 拆解 -ing 堆砌
    │         - 简化否定平行结构
    │         - 被动语态转主动
    │         - Copula 回避修正（serves as → is）
    ├── 3. [LLM]  句长变化注入：
    │         - 长句拆短句
    │         - 短句适当合并
    │         - 制造节奏变化
    ├── 4. [规则] 后处理扫描残留特征
    └── 5. [统计] 句长方差检查（目标：σ > 阈值）
```

**LLM Prompt 模板**：

```markdown
你是一个文本编辑专家。请改写以下文本，使其更自然。

具体要求：
1. 保留所有核心信息和事实
2. 打破"三元组"结构（A, B, and C → 自由表达）
3. 用简单动词替代华丽动词（is/are/has 而非 serves as/boasts）
4. 将 -ing 短语堆砌改为独立句子
5. 被动语态改为主动语态
6. 句子长度要变化：交替使用短句（<10词）和长句（>20词）
7. 不要使用以下词汇：{AI_HIGH_FREQ_WORDS}
8. 不要使用 em dash（—）
9. 不要添加原文没有的信息
10. 保持原文的段落数和大致结构

原文：
{text}
```

**预期效果**：
- 检测器分数降低 30-50%
- 人类感知明显改善
- 语义保真度 >92%
- 处理速度 2-5s/1000词（含 LLM 调用）

### 5.4 Heavy 级别（深度去AI化）

**目标**：全面改写，完全改变表达方式，追求个人风格和"人味"。

**适用场景**：自媒体内容、个人博客、创意写作——需要完全消除 AI 痕迹并注入个人风格。

**处理流程**：

```
输入文本
    │
    ├── 1. [规则] Light 级别的全部处理
    ├── 2. [LLM]  第一轮改写（Draft）：
    │         - 完全重写表达方式
    │         - 注入用户风格（如有写作样本）
    │         - 添加具体细节和个人观点
    │         - 允许不完美和不确定性
    ├── 3. [LLM]  自审（Audit）：
    │         "这段文字还有什么 AI 痕迹？列出剩余 tells"
    ├── 4. [LLM]  修订（Revise）：
    │         根据自审结果修订成终稿
    ├── 5. [规则] 后处理扫描：
    │         - em dash 零容忍检查
    │         - AI 高频词残留检查
    │         - 推广语言检查
    ├── 6. [统计] 检测器自评（可选）：
    │         - 困惑度检查
    │         - 突发性检查
    │         - 句长分布检查
    └── 7. [LLM]  最终润色（如果自评不通过）
```

**LLM Prompt 模板（Draft）**：

```markdown
你是一个专业写手。请完全改写以下文本，使其像真人写的。

核心要求：
1. 保留核心信息，但完全改变表达方式
2. 像在跟同事或朋友说话一样自然
3. 可以有个人观点、不确定性和真实感受
4. 用具体的细节替代抽象概括
5. 句子长短自由变化，不要均匀
6. 可以有轻微的"不完美"——偶尔的口语化、半成型的想法
7. 绝对不要使用以下模式：
   - em dash（—）
   - "delve", "crucial", "tapestry", "vibrant" 等词
   - Rule of Three（三元组）
   - "serves as" 替代 "is"
   - 推广性语言（"breathtaking", "nestled"）
   - 模糊归因（"experts argue"）
   - 通用积极结尾
   - 信号标注（"Let's dive in"）
8. 如果提供了写作样本，请匹配该风格

{user_writing_sample_if_available}

原文：
{text}
```

**LLM Prompt 模板（Audit）**：

```markdown
请审查以下改写文本，列出所有残留的 AI 写作痕迹。

检查清单：
- [ ] 是否有 em dash（—）或 en dash（–）？
- [ ] 是否有 AI 高频词？
- [ ] 是否有 Rule of Three？
- [ ] 是否有推广性语言？
- [ ] 是否有模糊归因？
- [ ] 句子长度是否均匀？
- [ ] 是否有通用积极结尾？
- [ ] 是否有信号标注？
- [ ] 是否有 -ing 短语堆砌？
- [ ] 是否有否定平行结构？

改写文本：
{draft}
```

**预期效果**：
- 检测器分数降低 60-80%
- 人类感知显著改善
- 语义保真度 >85%
- 处理速度 5-15s/1000词（含多轮 LLM 调用）

### 5.5 三级对比

| 维度 | Light | Medium | Heavy |
|------|-------|--------|-------|
| 处理方法 | 纯规则 | 规则 + LLM 单轮 | 规则 + LLM 多轮 + 自审 |
| 信息保真 | >98% | >92% | >85% |
| 检测器降幅 | 10-20% | 30-50% | 60-80% |
| 人类感知改善 | 轻微 | 明显 | 显著 |
| 处理速度 | <100ms | 2-5s | 5-15s |
| LLM 调用次数 | 0 | 1 | 2-3 |
| 风格迁移 | 否 | 部分 | 是 |
| 句式重写 | 否 | 是 | 完全 |
| 适用场景 | 学术/技术 | 商务/周报 | 创作/博客 |

### 5.6 强度选择建议

```python
def recommend_intensity(context: dict) -> str:
    """根据上下文自动推荐强度"""
    doc_type = context.get("doc_type", "")
    formality = context.get("formality", "medium")
    
    if doc_type in ["tech_doc", "academic", "meeting_minutes"]:
        return "light"
    elif doc_type in ["weekly_report", "email", "business_doc"]:
        return "medium"
    elif doc_type in ["blog", "article", "creative"]:
        return "heavy"
    elif formality == "formal":
        return "light"
    elif formality == "casual":
        return "heavy"
    else:
        return "medium"
```

---

## 6. 评估方法与指标

### 6.1 评估维度

去AI化效果需要从三个维度综合评估：

```
                    评估体系
                       │
        ┌──────────────┼──────────────┐
        │              │              │
    检测器通过率    语义保真度     人类感知质量
    (Detection     (Semantic      (Human
     Evasion)       Fidelity)      Perception)
        │              │              │
   ┌────┴────┐   ┌────┴────┐   ┌────┴────┐
   │GPTZero  │   │BLEU     │   │人工评估  │
   │Turnitin │   │ROUGE    │   │A/B测试   │
   │Original │   │BERTScore│   │图灵测试  │
   └─────────┘   │语义相似度│   └─────────┘
                 └─────────┘
```

### 6.2 检测器通过率评估

#### 6.2.1 评估流程

```python
def evaluate_detection_evasion(original, humanized, detectors):
    """
    对比原文和去AI化文本在多个检测器上的分数
    """
    results = {}
    for detector_name, detector_api in detectors.items():
        original_score = detector_api(original)
        humanized_score = detector_api(humanized)
        results[detector_name] = {
            "original_ai_probability": original_score,
            "humanized_ai_probability": humanized_score,
            "reduction": original_score - humanized_score,
            "reduction_pct": (original_score - humanized_score) / original_score * 100,
            "pass": humanized_score < 0.3,  # 通过阈值
        }
    return results
```

#### 6.2.2 推荐检测器组合

| 检测器 | 用途 | API 可用性 |
|--------|------|-----------|
| GPTZero | 主力评估（教育场景） | 有 API |
| Originality.ai | 内容创作场景 | 有 API |
| Sapling AI | 轻量级快速检查 | 有 API（免费） |
| AIGC detector (开源) | 本地离线评估 | HuggingFace API |

#### 6.2.3 评估指标

- **AI 概率降幅**：`ΔP = P_AI(original) - P_AI(humanized)`
- **通过率**：`pass_rate = count(P_AI < threshold) / total`
- **跨检测器鲁棒性**：在多个检测器上同时通过的比率

### 6.3 语义保真度评估

#### 6.3.1 自动指标

| 指标 | 衡量内容 | 目标值 |
|------|---------|--------|
| **BLEU** | n-gram 重叠 | >0.3（去AI化必然降低） |
| **ROUGE-L** | 最长公共子序列 | >0.4 |
| **BERTScore** | 语义嵌入相似度 | >0.85 |
| **语义相似度（Sentence-BERT）** | 句向量余弦相似度 | >0.80 |
| **事实一致性** | 关键实体/数字保留率 | >0.95 |

```python
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity

def evaluate_semantic_fidelity(original, humanized):
    model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')
    emb_orig = model.encode([original])
    emb_human = model.encode([humanized])
    similarity = cosine_similarity(emb_orig, emb_human)[0][0]
    return {
        "semantic_similarity": float(similarity),
        "fidelity_grade": "A" if similarity > 0.90 else "B" if similarity > 0.80 else "C",
    }
```

#### 6.3.2 关键信息保留检查

```python
def check_key_info_preservation(original, humanized):
    """检查关键信息（数字、专有名词、日期）是否保留"""
    # 提取原文中的数字和专有名词
    numbers_orig = extract_numbers(original)
    numbers_human = extract_numbers(humanized)
    entities_orig = extract_entities(original)
    entities_human = extract_entities(humanized)
    
    number_retention = len(numbers_orig & numbers_human) / len(numbers_orig) if numbers_orig else 1.0
    entity_retention = len(entities_orig & entities_human) / len(entities_orig) if entities_orig else 1.0
    
    return {
        "number_retention": number_retention,
        "entity_retention": entity_retention,
        "overall_retention": (number_retention + entity_retention) / 2,
    }
```

### 6.4 人类感知质量评估

#### 6.4.1 人工评估量表

| 维度 | 评分（1-5） | 说明 |
|------|------------|------|
| 自然度 | 1=明显AI, 5=完全人类 | 文本读起来是否像真人写的 |
| 流畅度 | 1=生硬, 5=流畅 | 句子衔接和节奏是否自然 |
| 信息完整 | 1=大量丢失, 5=完全保留 | 核心信息是否保留 |
| 风格一致 | 1=风格混乱, 5=风格统一 | 是否符合目标风格 |
| AI 痕迹 | 1=痕迹明显, 5=无痕迹 | AI 写作特征的残留程度 |

#### 6.4.2 图灵测试式评估

```python
def turing_test_evaluation(humanized_texts, human_texts, evaluators):
    """
    让评估者判断文本是 AI 还是人类写的
    """
    results = []
    for evaluator in evaluators:
        mixed = shuffle(humanized_texts + human_texts)
        for text, actual_source in mixed:
            judgment = evaluator.judge(text)  # "AI" or "Human"
            results.append({
                "text": text,
                "actual": actual_source,
                "judgment": judgment,
                "correct": judgment == actual_source,
            })
    
    accuracy = sum(r["correct"] for r in results) / len(results)
    return {
        "evaluator_accuracy": accuracy,
        "humanized_misclassified_as_human": sum(
            1 for r in results 
            if r["actual"] == "humanized" and r["judgment"] == "Human"
        ) / sum(1 for r in results if r["actual"] == "humanized"),
    }
```

#### 6.4.3 A/B 对比测试

向评估者展示原文和去AI化版本（随机顺序），让评估者选择"哪个更自然"。

### 6.5 综合评估框架

```python
def comprehensive_evaluation(original, humanized, intensity, detectors=None):
    """综合评估去AI化效果"""
    return {
        "intensity": intensity,
        "detection_evasion": evaluate_detection_evasion(
            original, humanized, detectors or DEFAULT_DETECTORS
        ),
        "semantic_fidelity": evaluate_semantic_fidelity(original, humanized),
        "key_info_preservation": check_key_info_preservation(original, humanized),
        "statistical_metrics": {
            "sentence_length_variance": calc_sentence_length_variance(humanized),
            "type_token_ratio": calc_ttr(humanized),
            "avg_sentence_length": calc_avg_sentence_length(humanized),
        },
        "overall_score": None,  # 加权综合分
    }
```

### 6.6 评估基线建议

| 指标 | Light 基线 | Medium 基线 | Heavy 基线 |
|------|-----------|------------|-----------|
| AI 概率降幅 | ≥10% | ≥30% | ≥60% |
| 通过率（P<0.3） | ≥40% | ≥70% | ≥90% |
| BERTScore | ≥0.92 | ≥0.85 | ≥0.78 |
| 关键信息保留 | ≥98% | ≥95% | ≥90% |
| 句长方差提升 | ≥10% | ≥30% | ≥50% |
| 人类感知评分 | ≥3.0/5 | ≥3.5/5 | ≥4.0/5 |

---

## 7. 开源工具与生态

### 7.1 工具生态图谱

```
开源生态
    │
    ├── AI 检测器
    │   ├── YuchuanTian/AIGC_text_detector (ICLR'24, 多尺度PU学习)
    │   ├── Hello-SimpleAI/chatgpt-comparison-detection (HC3数据集)
    │   ├── Hans-binoculars (零样本检测)
    │   └── DetectGPT (扰动法)
    │
    ├── 去AI化工具
    │   ├── blader/humanizer (⭐29k, Claude Code Skill)
    │   ├── lynote-ai/humanize-text (⭐1.5k, Dify/n8n集成)
    │   ├── DadaNanjesha/AI-Text-Humanizer-App (⭐400, Streamlit)
    │   └── anasu1/text-humanizer (⭐400, 轻量级)
    │
    ├── 评估框架
    │   ├── HC3 数据集 (Human ChatGPT Comparison Corpus)
    │   ├── M4 数据集 (Multi-generator, Multi-domain, Multi-lingual)
    │   └── DeepfakeTextDetect (综合检测基准)
    │
    └── 辅助工具
        ├── NLTK / spaCy (NLP处理)
        ├── WordNet / 同义词词林 (同义词替换)
        ├── Sentence-Transformers (语义相似度)
        └── HuggingFace Transformers (模型推理)
```

### 7.2 重点工具详析

#### 7.2.1 blader/humanizer

| 属性 | 值 |
|------|-----|
| GitHub | github.com/blader/humanizer |
| Stars | ~29,100 |
| 许可证 | MIT |
| 形式 | 纯 Markdown Skill（SKILL.md） |
| 兼容 | Claude Code, 任意支持 Skill 的 Agent |
| 版本 | v2.8.2 |

**核心价值**：这是一份基于 Wikipedia "Signs of AI writing" 的系统性 AI 写作特征指南，定义了 33 种 AI 写作模式，每种配有 Before/After 示例。它不是代码库，而是一份 Prompt/Skill 文档，可直接注入任何 LLM 的系统提示词。

**33 种模式分类**：
- 内容模式（6种）：意义膨胀、媒体强调、-ing分析、推广语言、模糊归因、套路挑战段
- 语言语法模式（7种）：AI高频词、Copula回避、否定平行、三元组、优雅变体、虚假范围、被动语态
- 风格模式（6种）：em dash、粗体过度、内联标题列表、标题大小写、Emoji、弯引号
- 交流模式（3种）：协作痕迹、知识截止声明、谄媚语气
- 填充与对冲（4种）：填充短语、过度对冲、通用结尾、连字符对过度
- 其他（7种）：权威套路、信号标注、碎片标题、Diff锚定、制造高潮、格言公式、对话式开头

**集成方案**：将 SKILL.md 内容作为 Prometheus `writing_humanize` 工具的 system prompt 一部分。

#### 7.2.2 YuchuanTian/AIGC_text_detector

| 属性 | 值 |
|------|-----|
| GitHub | github.com/YuchuanTian/AIGC_text_detector |
| Stars | ~448 |
| 论文 | ICLR'24 Spotlight |
| 许可证 | 研究用途 |
| 模型 | RoBERTa-based, 多尺度PU学习 |
| 语言 | 英文 + 中文 |
| 版本 | v3（2025-06 更新，适配 DeepSeek-V3/GPT-4） |

**集成方案**：作为 Prometheus 去AI化后的自评检测器，部署在本地（MTT AIBOOK GPU 可运行 RoBERTa-base）。

#### 7.2.3 DadaNanjesha/AI-Text-Humanizer-App

| 属性 | 值 |
|------|-----|
| GitHub | github.com/DadaNanjesha/AI-Text-Humanizer-App |
| Stars | ~404 |
| 许可证 | MIT |
| 技术栈 | Python + Streamlit + spaCy + NLTK |
| 功能 | 缩写展开、学术过渡词、被动语态转换、同义词替换 |

**参考价值**：规则替换法的具体实现参考，缩写展开和同义词替换模块可复用。

#### 7.2.4 lynote-ai/humanize-text

| 属性 | 值 |
|------|-----|
| GitHub | github.com/lynote-ai/humanize-text |
| Stars | ~1,470 |
| 集成 | Dify, n8n |
| 功能 | LLM 驱动的去AI化，支持多检测器绕过 |

### 7.3 数据集

| 数据集 | 描述 | 规模 | 语言 |
|--------|------|------|------|
| **HC3** | Human ChatGPT Comparison Corpus | ~24K 对话 | 中/英 |
| **M4** | Multi-generator, Multi-domain, Multi-lingual | ~144K | 多语言 |
| **DeepfakeTextDetect** | 综合检测基准 | ~2.8M | 多语言 |
| **MAGE** | Mixed AI-Human Generated Text | 多规模 | 英文 |
| **CHEAT** | ChatGPT Academic Text | ~35K | 英文 |

### 7.4 商业 API 对比

| 服务 | API | 价格 | 特点 |
|------|-----|------|------|
| GPTZero API | 有 | $0.01-0.05/1000词 | 教育场景主流 |
| Originality.ai API | 有 | $0.01/100词 | 内容创作场景 |
| Copyleaks API | 有 | 企业定价 | 多语言 |
| Sapling AI | 有 | 免费/付费 | 轻量级 |
| Winston AI | 有 | 企业定价 | 教育+企业 |

---

## 8. Prometheus 集成方案

### 8.1 架构集成

基于 `add-writing.md` §3.4 的设计，去AI化功能作为 `writing` Subagent 的 `writing_humanize` 工具实现：

```
用户请求 "去AI化" 
    │
    ▼
Function Router 路由 → writing Subagent
    │
    ▼
writing_humanize(text, intensity, preserve_formatting)
    │
    ├── intensity="light"  → 规则替换流水线（本地，无LLM）
    ├── intensity="medium" → 规则 + LLM单轮改写
    └── intensity="heavy"  → 规则 + LLM多轮（Draft-Audit-Revise）
    │
    ▼
返回 {humanized, changes_summary}
```

### 8.2 AI 特征词典设计

```python
# ai_patterns.py — AI 写作特征词典

# 英文 AI 高频词 → 替换词
EN_AI_VOCABULARY = {
    "delve into": "examine",
    "delve": "examine",
    "crucial": "important",
    "pivotal": "key",
    "vibrant": "active",
    "tapestry": "mix",
    "underscore": "show",
    "showcase": "display",
    "leverage": "use",
    "foster": "encourage",
    "enhance": "improve",
    "intricate": "complex",
    "testament": "proof",
    "garner": "get",
    "seamless": "smooth",
    "compelling": "strong",
    "landscape": "field",
    "interplay": "interaction",
    "realm": "area",
    "enduring": "lasting",
    "profound": "deep",
    # ... 完整词典见附录
}

# 中文 AI 高频词 → 替换词
ZH_AI_VOCABULARY = {
    "至关重要": "很重要",
    "赋能": "支持",
    "助力": "帮助",
    "深入探讨": "讨论",
    "在当今时代": "现在",
    "综上所述": "总之",
    "值得注意的是": "",
    "众所周知": "",
    "随着...的发展": "",  # 正则匹配
    "不可或缺": "必需",
    # ... 完整词典见附录
}

# 推广性语言
PROMOTIONAL_WORDS = {
    "en": ["breathtaking", "stunning", "nestled", "must-visit", "renowned", 
           "boasts", "rich heritage", "natural beauty"],
    "zh": ["令人叹为观止", "美不胜收", "坐落", "闻名遐迩"],
}

# 信号标注短语
SIGNPOSTING_PHRASES = {
    "en": ["Let's dive in", "Let's explore", "Let's break this down",
           "Here's what you need to know", "Without further ado",
           "Now let's look at"],
    "zh": ["让我们深入探讨", "让我们来看看", "接下来我们将"],
}

# 标点修正规则
PUNCTUATION_RULES = {
    "—": ",",    # em dash → comma (主要替换)
    "–": "-",    # en dash → hyphen
    """: "\"", # curly left → straight
    """: "\"", # curly right → straight
    "''": "\"",
    "``": "\"",
}
```

### 8.3 规则引擎实现

```python
# humanize_engine.py

import re
from typing import Tuple

class HumanizeEngine:
    def __init__(self, lang="auto"):
        self.lang = lang
        self.en_vocab = EN_AI_VOCABULARY
        self.zh_vocab = ZH_AI_VOCABULARY
        self.promotional = PROMOTIONAL_WORDS
        self.signposting = SIGNPOSTING_PHRASES
        self.punct_rules = PUNCTUATION_RULES
    
    def detect_language(self, text: str) -> str:
        chinese_chars = len(re.findall(r'[\u4e00-\u9fff]', text))
        return "zh" if chinese_chars > len(text) * 0.3 else "en"
    
    def fix_punctuation(self, text: str) -> Tuple[str, int]:
        """修正标点符号"""
        count = 0
        for old, new in self.punct_rules.items():
            n = text.count(old)
            if n:
                text = text.replace(old, new)
                count += n
        return text, count
    
    def replace_ai_vocabulary(self, text: str, lang: str) -> Tuple[str, int]:
        """替换 AI 高频词"""
        vocab = self.zh_vocab if lang == "zh" else self.en_vocab
        count = 0
        for ai_word, replacement in vocab.items():
            if ai_word in text:
                n = text.count(ai_word)
                text = text.replace(ai_word, replacement)
                count += n
        # 清理多余空格
        text = re.sub(r'  +', ' ', text)
        return text, count
    
    def remove_signposting(self, text: str, lang: str) -> Tuple[str, int]:
        """删除信号标注短语"""
        phrases = self.signposting.get(lang, [])
        count = 0
        for phrase in phrases:
            if phrase in text:
                n = text.count(phrase)
                text = text.replace(phrase, "")
                count += n
        # 清理句首多余空格和标点
        text = re.sub(r'^\s*[,，。]\s*', '', text, flags=re.MULTILINE)
        return text, count
    
    def downgrade_promotional(self, text: str, lang: str) -> Tuple[str, int]:
        """降级推广性语言"""
        words = self.promotional.get(lang, [])
        # 实现降级逻辑
        count = 0
        for word in words:
            if word in text.lower():
                # 替换为更中性的表达
                # ... 具体替换逻辑
                count += 1
        return text, count
    
    def check_em_dash_zero(self, text: str) -> bool:
        """检查 em dash 零容忍"""
        return "—" not in text and "–" not in text
    
    def calculate_burstiness(self, text: str) -> float:
        """计算句长方差（突发性代理指标）"""
        sentences = re.split(r'[。.!?！？]', text)
        lengths = [len(s.split()) for s in sentences if s.strip()]
        if len(lengths) < 2:
            return 0.0
        mean = sum(lengths) / len(lengths)
        variance = sum((l - mean) ** 2 for l in lengths) / len(lengths)
        return variance ** 0.5
    
    def humanize_light(self, text: str) -> dict:
        """Light 级别去AI化"""
        lang = self.detect_language(text) if self.lang == "auto" else self.lang
        changes = []
        
        text, n = self.fix_punctuation(text)
        if n: changes.append(f"修正标点 {n} 处")
        
        text, n = self.replace_ai_vocabulary(text, lang)
        if n: changes.append(f"替换AI高频词 {n} 处")
        
        text, n = self.remove_signposting(text, lang)
        if n: changes.append(f"删除信号标注 {n} 处")
        
        text, n = self.downgrade_promotional(text, lang)
        if n: changes.append(f"降级推广语言 {n} 处")
        
        return {
            "humanized": text,
            "changes_summary": "; ".join(changes) if changes else "无明显AI特征需修改",
            "stats": {
                "em_dash_check": self.check_em_dash_zero(text),
                "burstiness": self.calculate_burstiness(text),
            }
        }
```

### 8.4 LLM 改写 Prompt 模板

```python
# prompt_templates.py

LIGHT_RULE_DESCRIPTION = """
已执行规则预清洗（标点修正、高频词替换、套话删除）。
"""

MEDIUM_SYSTEM_PROMPT = """你是一个专业文本编辑。请改写文本使其更自然。

严格要求：
1. 保留所有核心信息和事实
2. 用简单动词替代华丽动词（is/are/has 而非 serves as/boasts）
3. 打破"三元组"结构（A, B, and C → 自由表达）
4. 将 -ing 短语堆砌改为独立句子
5. 被动语态改为主动语态
6. 句子长度交替变化（短句 <10词，长句 >20词）
7. 禁用词汇：delve, crucial, pivotal, vibrant, tapestry, underscore, showcase, leverage, foster, enhance, intricate, testament, landscape, interplay, seamless, compelling
8. 禁用 em dash（—）和 en dash（–）
9. 不添加原文没有的信息
10. 保持段落数和大致结构
"""

HEAVY_SYSTEM_PROMPT = """你是一个专业写手。请完全改写文本使其像真人写的。

核心要求：
1. 保留核心信息，但完全改变表达方式
2. 像在跟同事说话一样自然
3. 可以有个人观点和不确定性
4. 用具体细节替代抽象概括
5. 句子长短自由变化
6. 允许轻微"不完美"——口语化、半成型的想法
7. 绝对禁止：
   - em dash（—）和 en dash（–）
   - AI高频词：delve, crucial, tapestry, vibrant, underscore, showcase, foster, enhance, landscape, testament, intricate, seamless, compelling
   - Rule of Three（三元组）
   - "serves as" 替代 "is"
   - 推广语言：breathtaking, nestled, stunning, vibrant, renowned
   - 模糊归因：experts argue, industry reports
   - 通用结尾：future looks bright, exciting times
   - 信号标注：Let's dive in, here's what you need
   - -ing 短语堆砌
   - 否定平行：not only...but also, not just...it's
   - 格言公式：X is the Y of Z
8. {style_instruction}
"""

AUDIT_PROMPT = """请审查以下改写文本，列出所有残留的AI写作痕迹。

检查清单：
1. 是否有 em dash（—）或 en dash（–）？
2. 是否有 AI 高频词？
3. 是否有 Rule of Three？
4. 是否有推广性语言？
5. 是否有模糊归因？
6. 句子长度是否均匀？
7. 是否有通用积极结尾？
8. 是否有信号标注？
9. 是否有 -ing 短语堆砌？
10. 是否有否定平行结构？

只列出发现的问题，如果没有问题请回答"无残留AI痕迹"。

改写文本：
{text}
"""
```

### 8.5 完整工具实现架构

```python
# writing_engine.py — humanize 函数

def humanize(text: str, intensity: str = "medium", 
             preserve_formatting: bool = True,
             upstream_url: str = None, upstream_model: str = None, 
             upstream_key: str = None) -> dict:
    """
    去AI化改写主函数
    
    Args:
        text: 待改写文本
        intensity: light / medium / heavy
        preserve_formatting: 是否保留 Markdown 格式
        upstream_url: 上游 LLM API 地址
        upstream_model: 上游模型名
        upstream_key: API 密钥
    
    Returns:
        {humanized, changes_summary, stats}
    """
    engine = HumanizeEngine()
    
    # Step 1: 规则预清洗（所有级别共用）
    result = engine.humanize_light(text)
    preprocessed = result["humanized"]
    changes = [result["changes_summary"]]
    
    if intensity == "light":
        return _format_result(preprocessed, changes, engine)
    
    # Step 2: LLM 改写（medium / heavy）
    if intensity == "medium":
        prompt = MEDIUM_SYSTEM_PROMPT
        rewritten = call_upstream_llm(
            upstream_url, upstream_model, upstream_key,
            system=prompt, user=preprocessed
        )
        changes.append("LLM句式重写完成")
        
    elif intensity == "heavy":
        # Draft
        style_instr = get_user_style_instruction()  # 从记忆中获取用户风格
        prompt = HEAVY_SYSTEM_PROMPT.format(style_instruction=style_instr)
        draft = call_upstream_llm(
            upstream_url, upstream_model, upstream_key,
            system=prompt, user=preprocessed
        )
        changes.append("LLM第一轮改写完成")
        
        # Audit
        audit_result = call_upstream_llm(
            upstream_url, upstream_model, upstream_key,
            system=AUDIT_PROMPT.format(text=draft),
            user="请执行审查。"
        )
        
        # Revise
        if "无残留AI痕迹" not in audit_result:
            revise_prompt = f"""根据以下审查意见修订文本：

审查意见：
{audit_result}

待修订文本：
{draft}

请修订所有指出的问题，输出终稿。"""
            rewritten = call_upstream_llm(
                upstream_url, upstream_model, upstream_key,
                system="你是文本修订专家。",
                user=revise_prompt
            )
            changes.append(f"LLM自审修订完成（发现 {audit_result.count(chr(10))} 个问题）")
        else:
            rewritten = draft
            changes.append("LLM自审通过，无残留痕迹")
    
    # Step 3: 规则后清洗
    post_result = engine.humanize_light(rewritten)
    final_text = post_result["humanized"]
    if "无明显AI特征需修改" not in post_result["changes_summary"]:
        changes.append(f"规则后清洗：{post_result['changes_summary']}")
    
    # Step 4: 质量检查
    stats = {
        "em_dash_zero": engine.check_em_dash_zero(final_text),
        "burstiness": engine.calculate_burstiness(final_text),
        "original_burstiness": engine.calculate_burstiness(text),
        "burstiness_improved": engine.calculate_burstiness(final_text) > engine.calculate_burstiness(text),
    }
    
    return {
        "humanized": final_text,
        "changes_summary": " | ".join(changes),
        "stats": stats,
    }


def _format_result(text, changes, engine):
    return {
        "humanized": text,
        "changes_summary": " | ".join(changes),
        "stats": {
            "em_dash_zero": engine.check_em_dash_zero(text),
            "burstiness": engine.calculate_burstiness(text),
        }
    }
```

### 8.6 用户偏好集成

利用 Prometheus 的记忆系统，去AI化可以融入用户个人风格：

```python
def get_user_style_instruction() -> str:
    """从记忆中获取用户写作风格偏好"""
    # 调用 memory_engine.recall(context="writing_style")
    # 返回类似：
    # "用户偏好短句、口语化风格，常用'其实'作为过渡词，
    #  很少使用分号，段落较短。"
    memory = memory_recall(context="writing_style_preferences")
    if memory:
        return f"请匹配以下用户写作风格：\n{memory}"
    return "使用自然、多变的写作风格。"
```

---

## 9. 风险与限制

### 9.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| **LLM 改写引入新 AI 痕迹** | 去AI化后仍有检测风险 | 多轮 Audit-Revise + 规则后清洗 |
| **语义丢失** | 信息失真 | BERTScore 检查 + 关键信息保留检查 |
| **过度改写** | 原文风格完全丧失 | 强度分级 + preserve_formatting 参数 |
| **检测器军备竞赛** | 检测器更新后效果下降 | 持续更新词典 + 跟踪检测器原理 |
| **短文本效果差** | <100词文本去AI化困难 | 文本长度检查 + 提示用户 |

### 9.2 伦理风险

| 风险 | 说明 | 立场 |
|------|------|------|
| **学术诚信** | 学生用于绕过 Turnitin | 工具定位为"辅助写作改善"，非"作弊工具" |
| **信息操纵** | 用于生成虚假内容 | 不改变事实，仅改变表达 |
| **透明度** | 隐藏 AI 参与 | 建议在适当场景声明 AI 辅助 |

### 9.3 已知限制

1. **无法保证 100% 通过检测器**：检测器不断进化，任何去AI化方案都无法保证完全通过
2. **中文效果可能弱于英文**：开源工具和词典以英文为主，中文 AI 特征研究相对不足
3. **领域特异性**：在高度结构化的文本（法律、医学）中，去AI化可能损害专业性
4. **Heavy 级别的不可预测性**：完全改写可能产生意料之外的结果

---

## 10. 结论与建议

### 10.1 核心结论

1. **AI 写作特征是可系统化的**：Wikipedia "Signs of AI writing" 和 blader/humanizer 已定义了 33+ 种可辨识模式，覆盖词汇、句式、结构、标点、语义五个层面。

2. **混合方案最优**：纯规则法覆盖面有限，纯 LLM 法有"以 AI 改 AI"的悖论，统计扰动法效果有限。三级混合流水线（规则预清洗 → LLM 改写 → 规则后清洗 → 统计校准）是最佳实践。

3. **三级强度设计合理**：Light（纯规则）满足学术/技术场景，Medium（规则+单轮LLM）满足商务场景，Heavy（规则+多轮LLM+自审）满足创作场景。

4. **blader/humanizer 是最有价值的参考**：29k Stars 的纯 Markdown Skill，其 33 种 AI 模式定义可直接注入 Prometheus 的 system prompt，作为 LLM 改写的指导框架。

5. **评估需要多维度**：单一检测器通过率不足以衡量效果，需结合语义保真度（BERTScore）、关键信息保留率、句长分布和人类感知评估。

### 10.2 实施建议

| 优先级 | 建议 | 工作量 |
|--------|------|--------|
| P0 | 实现 Light 级别（纯规则引擎 + 词典） | 2-3 天 |
| P0 | 集成 blader/humanizer SKILL.md 作为 system prompt | 0.5 天 |
| P1 | 实现 Medium 级别（规则 + LLM 单轮改写） | 2 天 |
| P1 | 集成 AIGC_text_detector 本地自评 | 3 天 |
| P2 | 实现 Heavy 级别（Draft-Audit-Revise 循环） | 3 天 |
| P2 | 用户风格迁移（记忆系统集成） | 2 天 |
| P3 | 检测器 API 集成（GPTZero/Sapling） | 2 天 |
| P3 | 综合评估仪表板 | 3 天 |

### 10.3 技术路线图

```
Phase 1 (MVP): Light 级别规则引擎 + 基础词典
    ↓
Phase 2: Medium 级别 LLM 改写 + blader/humanizer Prompt 集成
    ↓
Phase 3: Heavy 级别 Draft-Audit-Revise + 用户风格迁移
    ↓
Phase 4: 本地检测器自评 + 检测器 API 集成 + 评估仪表板
```

---

## 11. 参考文献

### 11.1 学术论文

1. **Tian et al. (2023)**. "Multiscale Positive-Unlabeled Detection of AI-Generated Texts." ICLR'24 Spotlight. arXiv:2305.18149
2. **Mitchell et al. (2023)**. "DetectGPT: Zero-Shot Machine-Generated Text Detection using Probability Curvature." ICML'23
3. **Hans et al. (2024)**. "Spotting LLMs With Binoculars: Zero-Shot Detection of Machine-Generated Text." ICML'24
4. **Guo et al. (2023)**. "How Close is ChatGPT to Human Experts? Comparison Corpus, Evaluation, and Detection." HC3 Dataset. arXiv:2301.07597
5. **Wang et al. (2023)**. "M4: Multi-generator, Multi-domain, and Multi-lingual Black-Box Machine-Generated Text Detection."

### 11.2 开源项目

6. **blader/humanizer** — AI 写作特征去除 Skill (⭐29k). github.com/blader/humanizer
7. **YuchuanTian/AIGC_text_detector** — 多尺度 PU 学习 AI 检测器 (ICLR'24). github.com/YuchuanTian/AIGC_text_detector
8. **DadaNanjesha/AI-Text-Humanizer-App** — Streamlit 去AI化应用. github.com/DadaNanjesha/AI-Text-Humanizer-App
9. **lynote-ai/humanize-text** — 开源去AI化工具 (Dify/n8n). github.com/lynote-ai/humanize-text
10. **anasu1/text-humanizer** — 轻量级去AI化. github.com/anasu1/text-humanizer

### 11.3 在线资源

11. **Wikipedia: Signs of AI writing** — AI 写作特征系统性指南. en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing
12. **GPTZero** — AI 文本检测器. gptzero.me
13. **Originality.ai** — AI 内容检测. originality.ai
14. **HuggingFace AIGC Detector Demo** — 在线 AI 检测演示. huggingface.co/spaces/yuchuantian/AIGC_text_detector

### 11.4 内部文档

15. Prometheus 技术规格说明书 — `docs/spec.md` §3.3
16. 写作 Subagent 设计文档 — `docs/add/add-writing.md` §3.4
17. MTClaw 深度调研报告 — `docs/MTClaw-深度调研报告.md`

---

> **报告结束** | 报告编号 R07 | 去AI化技术调研 | 2026-07-14
