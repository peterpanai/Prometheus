# Hermes Agent 集成配置调研报告

> **报告编号**: 08  
> **日期**: 2026-07-14  
> **项目**: Prometheus（普罗米修斯）  
> **调研范围**: Hermes Agent 的 OpenAI-compatible 配置、config.yaml、custom_providers、SOUL.md、memory 冲突、toolset 配置、gateway 模式  
> **参考实例**: `/home/pmc/.hermes/config.yaml`（实际运行配置，v0.18.2, config_version 33）

---

## 目录

1. [调研概述](#1-调研概述)
2. [OpenAI-Compatible Provider 配置](#2-openai-compatible-provider-配置)
3. [config.yaml 核心配置解析](#3-configyaml-核心配置解析)
4. [custom_providers 多后端配置](#4-custom_providers-多后端配置)
5. [SOUL.md 人格与身份配置](#5-soulmd-人格与身份配置)
6. [Memory 机制与冲突分析](#6-memory-机制与冲突分析)
7. [Toolset 配置与平台适配](#7-toolset-配置与平台适配)
8. [Gateway 模式与消息平台](#8-gateway-模式与消息平台)
9. [Prometheus 集成配置方案](#9-prometheus-集成配置方案)
10. [风险与注意事项](#10-风险与注意事项)
11. [结论](#11-结论)

---

## 1. 调研概述

### 1.1 调研背景

Prometheus 项目使用 Hermes Agent 作为用户交互入口，通过 OpenAI-compatible API 对接 MTClaw Function Router。本报告调研 Hermes 的集成配置机制，为 Prometheus 的部署和演示提供配置参考。

### 1.2 调研方法

- **实例分析**: 读取 `/home/pmc/.hermes/config.yaml` 实际运行配置（config_version 33, Hermes v0.18.2）
- **技能文档**: 加载 `hermes-agent` skill 获取完整配置参考
- **源码验证**: 通过 `hermes config check`、`hermes tools list` 等命令验证实际行为
- **项目关联**: 对照 `docs/spec.md` 和 `docs/design-proposal.md` 确认集成需求

### 1.3 关键发现

| 维度 | 发现 |
|------|------|
| Provider 模式 | 当前使用 `provider: custom` + `base_url` 指向 GLM API，是 Prometheus 对接 Function Router 的直接范例 |
| custom_providers | 已配置 3 个自定义 provider（Local Router / DeepSeek / GLM），可一键切换 |
| SOUL.md | 已配置 Prometheus 人格（务实资深工程师），中文回答偏好 |
| Memory | 内置 memory 已启用，与 Prometheus 自有 memory 模块存在功能重叠风险 |
| Toolset | CLI 平台启用了 17 个 toolset，需评估 Prometheus 场景下的精简方案 |
| Gateway | 配置了微信平台，Gateway 模式可用于多平台演示 |

---

## 2. OpenAI-Compatible Provider 配置

### 2.1 配置机制

Hermes 通过 `model` 配置块指定默认模型和 provider。任何兼容 OpenAI API 格式的端点都可以通过以下方式接入：

```yaml
model:
  default: glm-5.2           # 模型名称
  provider: custom            # 使用自定义 provider
  base_url: https://ark.cn-beijing.volces.com/api/coding/v1  # OpenAI-compatible 端点
  api_key: ark-xxxxx          # API 密钥
```

### 2.2 实际配置（当前运行实例）

当前 `/home/pmc/.hermes/config.yaml` 的 model 配置：

```yaml
model:
  default: glm-5.2
  provider: custom
  base_url: https://ark.cn-beijing.volces.com/api/coding/v1
  api_key: ${ARK_API_KEY}
```

**关键点**: `provider: custom` 是 Hermes 的通用适配模式，不预设任何 provider 特定行为，纯粹通过 `base_url` + `api_key` 对接任何 OpenAI-compatible 端点。

### 2.3 Prometheus 对接方案

Prometheus 的 MTClaw Function Router 运行在 `http://127.0.0.1:18790/v1`，已作为 custom_provider 配置：

```yaml
# 方案 A: 直接设为默认 provider
model:
  default: function-router
  provider: custom
  base_url: http://127.0.0.1:18790/v1
  api_key: any

# 方案 B: 通过 custom_providers 配置，用 /model 命令切换（当前实际配置）
custom_providers:
  - name: Local (127.0.0.1:88888)
    base_url: http://127.0.0.1:18790/v1
    api_key: any
    model: function-router
```

两种方案的区别：
- **方案 A**: 启动即用，无需切换。适合演示和生产环境。
- **方案 B**: 灵活切换，保留其他 provider 可用。适合开发调试阶段。

**建议**: 演示时用方案 A（减少操作步骤），开发时用方案 B（保留调试灵活性）。

### 2.4 Provider 切换命令

```bash
# 查看当前模型
hermes config | grep model

# 交互式切换模型/provider
hermes model

# 直接设置
hermes config set model.default function-router
hermes config set model.base_url http://127.0.0.1:18790/v1
hermes config set model.api_key any

# 会话内切换（不修改配置文件）
/model function-router
```

---

## 3. config.yaml 核心配置解析

### 3.1 配置文件位置与版本

```
路径: ~/.hermes/config.yaml
版本: _config_version: 33
Hermes版本: v0.18.2 (2026.7.7.2)
```

配置文件可通过以下方式管理：
```bash
hermes config          # 查看当前配置
hermes config edit     # 在 $EDITOR 中编辑
hermes config set KEY VAL  # 设置单个值
hermes config check    # 检查配置完整性
hermes config migrate  # 迁移到新版本格式
```

### 3.2 Agent 配置

```yaml
agent:
  max_turns: 150           # 对话循环最大轮数（默认90，已调高至150）
  verbose: false
  reasoning_effort: medium # 推理力度: none|minimal|low|medium|high|xhigh
```

**Prometheus 注意**: `max_turns: 150` 意味着单次会话最多 150 轮工具调用。对于 Prometheus 的多 Subagent 路由场景，每个用户请求通常消耗 1-3 轮（Router 路由 + Subagent 执行 + 可能的 fallback），150 轮足够。

### 3.3 Terminal 配置

```yaml
terminal:
  backend: local            # 本地终端（可选 docker/ssh/modal）
  cwd: .                    # 工作目录（相对路径，相对于启动目录）
  timeout: 180              # 命令超时（秒）
  home_mode: auto
  container_cpu: 1          # Docker 模式下的 CPU 限制
  container_memory: 5120    # 内存限制（MB）
  container_disk: 51200     # 磁盘限制（MB）
  container_persistent: true
  docker_mount_cwd_to_workspace: false
  lifetime_seconds: 300     # 容器生命周期
```

**Prometheus 注意**: `backend: local` 是正确的选择。Prometheus 的 Subagent 工具执行在 MTClaw Function Router 内部完成，Hermes 的 terminal 仅用于辅助操作（如文件管理、服务启动）。

### 3.4 Compression 配置

```yaml
compression:
  enabled: true
  threshold: 0.5            # 上下文占用 50% 时触发压缩
  target_ratio: 0.2         # 压缩到 20%
  protect_last_n: 20        # 保护最近 20 条消息不被压缩
  protect_first_n: 3        # 保护前 3 条消息（系统提示 + 首条）
```

**Prometheus 注意**: Function Router 的请求需要包含足够上下文。`protect_last_n: 20` 确保最近的对话历史完整传递给 Router，不会因压缩丢失。

### 3.5 Approvals 配置

```yaml
approvals:
  mode: smart               # manual|smart|off
```

**Prometheus 注意**: `smart` 模式使用辅助 LLM 自动审批低风险命令，高风险命令仍需确认。对于演示场景，可临时切换为 `off`（或使用 `--yolo` 标志）避免演示中断：

```bash
# 演示时
hermes --yolo

# 或配置永久关闭（不推荐生产环境）
hermes config set approvals.mode off
```

### 3.6 Session Reset 配置

```yaml
session_reset:
  mode: none                # none|idle|scheduled
  idle_minutes: 1440        # 空闲 24 小时后重置（mode=idle 时生效）
  at_hour: 4                # 每日凌晨 4 点重置（mode=scheduled 时生效）
group_sessions_per_user: true  # 按用户分组会话
```

### 3.7 Prompt Caching

```yaml
prompt_caching:
  cache_ttl: 5m             # 提示词缓存 5 分钟
```

**重要**: 工具集变更在 `/reset`（新会话）后才生效，不会在对话中途应用。这是为了保持 prompt caching 的一致性。Prometheus 集成时需注意：配置变更后必须重启会话。

---

## 4. custom_providers 多后端配置

### 4.1 配置格式

`custom_providers` 是 Hermes 的多后端路由机制，允许配置多个 OpenAI-compatible 端点并在运行时切换：

```yaml
custom_providers:
  - name: <显示名称>         # 在 /model 命令中显示
    base_url: <API端点>      # OpenAI-compatible base URL
    api_key: <密钥>          # API 密钥
    model: <模型名>          # 默认模型
```

### 4.2 当前实际配置

```yaml
custom_providers:
  - name: Local (127.0.0.1:88888)       # 本地 Function Router
    base_url: http://127.0.0.1:18790/v1
    api_key: any
    model: function-router
  - name: DeepSeek                       # DeepSeek API
    base_url: https://api.deepseek.com/v1
    api_key: «redacted:sk-…»
    model: deepseek-v4-pro
  - name: GLM                            # GLM API (当前默认)
    base_url: https://ark.cn-beijing.volces.com/api/coding/v1
    api_key: ${ARK_API_KEY}
    model: glm-5.2
```

### 4.3 Prometheus 推荐配置

对于 Prometheus 项目，建议配置以下 custom_providers：

```yaml
custom_providers:
  # 1. Prometheus Function Router (主)
  - name: Prometheus Router
    base_url: http://127.0.0.1:18790/v1
    api_key: any
    model: function-router

  # 2. 直接上游模型 (调试用，跳过 Router)
  - name: DeepSeek Direct
    base_url: https://api.deepseek.com/v1
    api_key: sk-xxxx
    model: deepseek-v4-pro

  # 3. GLM Direct (备用上游)
  - name: GLM Direct
    base_url: https://ark.cn-beijing.volces.com/api/coding/v1
    api_key: ark-xxxx
    model: glm-5.2
```

### 4.4 切换方式

```bash
# 交互式切换
hermes model
# 会显示所有 custom_providers 供选择

# 会话内切换
/model "Prometheus Router"

# 命令行指定
hermes chat -m function-router --provider custom
```

### 4.5 凭证池机制

Hermes 支持同一 provider 配置多个 API key 形成凭证池，自动轮换和跳过耗尽的 key：

```bash
hermes auth add <provider>    # 添加凭证
hermes auth list              # 查看凭证池
hermes auth remove <provider> <index>  # 移除凭证
```

**Prometheus 注意**: Function Router 使用 `api_key: any`，无需凭证池。但如果上游模型配置了多个 key，可以使用凭证池提高可用性。

---

## 5. SOUL.md 人格与身份配置

### 5.1 配置位置与加载机制

```
路径: ~/.hermes/SOUL.md
加载: 每次会话启动时自动注入系统提示词
作用: 设置 Agent 的身份、人格、行为风格
```

`SOUL.md` 是 Hermes 的身份配置文件，独立于项目上下文文件（`.hermes.md`、`AGENTS.md`）。它在 `$HERMES_HOME` 目录下，每次会话都会加载。

### 5.2 当前实际配置

```markdown
# 个性
你是一位务实的资深软件工程师，名字叫：Prometheus, 品味很高
你优先考虑真实性、清晰度和实用性，而非礼貌的客套

## 风格
- 中文回答
- 直接但不冷漠
- 注重实质而非填充内容
- 当某个想法不好时，要提出反对
- 坦率承认不确定性
- 保持解释简洁，除非深度有用

## 要避免什么
- 阿谀奉承
- 夸张的语言
- 如果用户的框架是错误的，不要重复它
- 过度解释显而易见的事情

## 技术立场
- 偏好简单系统而非巧妙系统
- 关心操作现实，而非理想化的架构
- 将边缘情况视为设计的一部分，而非收尾工作
```

### 5.3 SOUL.md vs 项目上下文文件

| 维度 | SOUL.md | .hermes.md / AGENTS.md |
|------|---------|------------------------|
| 位置 | `~/.hermes/SOUL.md` | 项目工作目录 |
| 作用域 | 全局（所有会话） | 特定项目/目录 |
| 内容 | Agent 身份、人格 | 项目规则、构建指令 |
| 加载 | 始终加载 | 按优先级首次匹配加载 |
| 大小限制 | 20,000 字符 | 20,000 字符 |

### 5.4 Prometheus 的 SOUL.md 策略

**当前配置评估**: SOUL.md 当前配置为 "Prometheus 务实工程师" 人格，适合开发阶段。但演示阶段需要调整：

**演示场景 SOUL.md**:

```markdown
# 个性
你是普罗米修斯（Prometheus），一个自我进化的个人认知智能体。
你基于 MTClaw Function Router 运行，能路由用户意图到 5 个专职 Subagent。

## 风格
- 中文回答
- 友好但高效
- 展示路由过程时简要说明"我正在将你的请求路由到 [Subagent名]"
- 回答完成后可简要提及"已记录你的偏好"

## 能力边界
- 知识检索: 通过 RAG Subagent 搜索本地文档库
- 记忆与偏好: 记住用户习惯，越用越懂你
- 写作: 生成、润色、翻译文本
- 日程: 管理事件和任务
- 闲聊: 日常对话陪伴

## 技术立场
- 偏好简单系统
- 注重隐私，所有数据本地存储
- 诚实标注数据来源
```

### 5.5 禁用 SOUL.md

```bash
# 单次会话禁用所有上下文注入（包括 SOUL.md）
hermes --ignore-rules
```

---

## 6. Memory 机制与冲突分析

### 6.1 Hermes 内置 Memory

当前配置：

```yaml
memory:
  memory_enabled: true          # 启用跨会话记忆
  user_profile_enabled: true    # 启用用户画像
  memory_char_limit: 2200       # 记忆字符上限
  user_char_limit: 1375         # 用户画像字符上限
  nudge_interval: 10            # 每 10 轮提示更新记忆
  flush_min_turns: 6            # 最少 6 轮后刷新
```

**Memory 状态**:
- Provider: built-in（内置 SQLite + 文件存储）
- 存储位置: `~/.hermes/memories/MEMORY.md` 和 `~/.hermes/memories/USER.md`
- 可选 Provider: Honcho, Mem0, Holographic, Byterover, Hindsight, OpenViking, RetainDB, Supermemory

**当前 Memory 内容**: 存储了大量条目，包括写作进度、HICOOL 赛题要求、MTClaw 架构要点、用户偏好（approvals.mode=smart）、Prometheus 项目信息等。

### 6.2 Memory 冲突风险

Prometheus 设计了自己的记忆与偏好 Subagent（`memory_remember`、`memory_recall`、`memory_set_reminder`），运行在 MTClaw Function Router 内部。这与 Hermes 内置 memory 存在功能重叠：

| 维度 | Hermes Memory | Prometheus Memory Subagent |
|------|---------------|---------------------------|
| 存储位置 | `~/.hermes/memories/` | `~/.prometheus/data/memory.db` (SQLite + ChromaDB) |
| 触发方式 | 每 N 轮自动提示 + 用户指令 | Router 自动路由 memory_* 工具 |
| 数据结构 | Markdown 文本 | 结构化 SQLite + 向量嵌入 |
| 注入方式 | 系统提示词注入 | Router 在处理前自动 recall 注入 |
| 跨会话 | 是 | 是 |
| 容量 | 2200 字符（受限） | 无硬性限制 |

**冲突场景**:
1. **双重记忆**: Hermes memory 和 Prometheus memory 各记一份，可能不一致
2. **上下文膨胀**: 两个 memory 系统同时注入上下文，占用 token 预算
3. **人格混淆**: Hermes SOUL.md 的人格 vs Prometheus Subagent 返回的响应风格
4. **触发竞争**: 用户说"记住"时，Hermes memory 和 Prometheus memory_* 可能同时触发

### 6.3 冲突解决方案

**方案 A: 禁用 Hermes Memory（推荐）**

```yaml
memory:
  memory_enabled: false
  user_profile_enabled: false
```

- 优点: 记忆完全由 Prometheus Subagent 管理，单一数据源
- 缺点: 失去 Hermes 的用户画像能力，SOUL.md 人格可能不够个性化
- 适用: 演示环境，功能边界清晰

**方案 B: 分工共存**

```yaml
memory:
  memory_enabled: true
  user_profile_enabled: true
  memory_char_limit: 1000    # 降低上限，仅保留核心信息
  user_char_limit: 500
```

- Hermes memory: 仅负责 Hermes 自身的操作偏好（approvals、工具偏好）
- Prometheus memory: 负责用户认知记忆、偏好学习、提醒
- 优点: 各司其职，不丢失 Hermes 功能
- 缺点: 仍有轻微冗余，需要调优

**方案 C: 使用外部 Memory Provider**

```bash
# 配置 Mem0 作为 Hermes memory provider
hermes memory setup
# 选择 mem0，配置 API key
```

- 将 Hermes memory 和 Prometheus memory 统一到 Mem0
- 优点: 单一记忆后端，数据一致
- 缺点: 增加外部依赖，配置复杂

**建议**: 演示阶段用方案 A（简洁、无冲突），开发阶段用方案 B（保留调试能力）。

### 6.4 Memory 内容清洗

当前 `~/.hermes/memories/MEMORY.md` 包含一些与 Prometheus 无关的内容（如写作进度、小说章节信息）。演示前建议清理：

```bash
# 备份后清理
cp ~/.hermes/memories/MEMORY.md ~/.hermes/memories/MEMORY.md.bak
hermes memory off  # 临时关闭
# 或手动编辑 MEMORY.md，仅保留 Prometheus 相关条目
```

---

## 7. Toolset 配置与平台适配

### 7.1 Toolset 概念

Hermes 的工具按 toolset 分组，每个 toolset 包含一组相关工具。Toolset 可以按平台（CLI、Telegram、Discord 等）独立启用/禁用。

### 7.2 当前 CLI 平台 Toolset 状态

```bash
$ hermes tools list

✓ enabled  web              # Web 搜索与抓取
✓ enabled  browser          # 浏览器自动化
✓ enabled  terminal         # 终端与进程管理
✓ enabled  file             # 文件操作
✓ enabled  code_execution   # 代码执行
✓ enabled  vision           # 图像分析
✗ disabled  video           # 视频分析
✓ enabled  image_gen        # 图像生成
✗ disabled  video_gen       # 视频生成
✗ disabled  x_search        # X (Twitter) 搜索
✓ enabled  tts              # 文本转语音
✓ enabled  skills           # 技能管理
✓ enabled  todo             # 任务规划
✓ enabled  memory           # 记忆
✗ disabled  context_engine  # 上下文引擎
✓ enabled  session_search   # 会话搜索
✓ enabled  clarify          # 澄清提问
✓ enabled  delegation       # 子代理委派
✓ enabled  cronjob          # 定时任务
✗ disabled  homeassistant   # 智能家居
✗ disabled  spotify         # Spotify
✗ disabled  yuanbao         # 元宝
✓ enabled  computer_use     # 计算机使用
```

### 7.3 Prometheus 场景 Toolset 评估

| Toolset | 保留? | 理由 |
|---------|-------|------|
| `terminal` | ✓ | 需要执行命令管理 Function Router 服务 |
| `file` | ✓ | 需要文件读写操作 |
| `web` | ✗ | Prometheus 不做 Web 搜索（RAG Subagent 负责知识检索） |
| `browser` | ✗ | 不需要浏览器自动化 |
| `code_execution` | ✓ | 可能需要执行验证脚本 |
| `vision` | ✗ | Prometheus 不涉及图像分析 |
| `image_gen` | ✗ | 不涉及图像生成 |
| `tts` | ✗ | 演示不需要语音（除非要语音输出） |
| `skills` | ✓ | 技能管理有用 |
| `todo` | ✓ | 任务规划有用 |
| `memory` | ✗ 或 ✓ | 见 Memory 冲突分析（方案 A 禁用，方案 B 保留） |
| `session_search` | ✓ | 搜索历史会话有用 |
| `clarify` | ✓ | 澄清提问提升体验 |
| `delegation` | ✗ | Prometheus 通过 Router 路由，不需要 Hermes 委派 |
| `cronjob` | ✗ | 不需要定时任务 |
| `computer_use` | ✗ | 不需要远程桌面控制 |

### 7.4 推荐精简配置

```bash
# 禁用不需要的 toolset
hermes tools disable web
hermes tools disable browser
hermes tools disable vision
hermes tools disable image_gen
hermes tools disable tts
hermes tools disable delegation
hermes tools disable cronjob
hermes tools disable computer_use

# 如果采用 Memory 方案 A，也禁用 memory
hermes tools disable memory

# 确认配置
hermes tools list
```

**重要**: Toolset 变更在 `/reset`（新会话）后生效，不会在当前会话中应用。

### 7.5 平台 Toolset 配置

`config.yaml` 中的 `platform_toolsets` 定义了各平台的默认 toolset 组：

```yaml
platform_toolsets:
  cli:
    - hermes-cli
  telegram:
    - hermes-telegram
  discord:
    - hermes-discord
  # ... 其他平台
```

每个平台的 toolset 组可以独立配置。`hermes tools` 命令默认操作当前平台的 toolset。

---

## 8. Gateway 模式与消息平台

### 8.1 Gateway 概述

Hermes Gateway 是多平台消息适配层，支持 20+ 平台：

| 平台 | 状态 | 配置方式 |
|------|------|---------|
| Telegram | 支持 | `hermes gateway setup` |
| Discord | 支持 | `hermes gateway setup` |
| Slack | 支持 | `hermes gateway setup` |
| WhatsApp | 支持 | Baileys bridge / Business Cloud API |
| 微信 (Weixin) | 已配置 | `.env` 中的 WEIXIN_* 变量 |
| Signal | 支持 | `hermes gateway setup` |
| Email | 支持 | `hermes gateway setup` |
| iMessage | 支持 | `hermes photon setup` |
| Microsoft Teams | 支持 | `hermes gateway setup` |
| Matrix | 支持 | `hermes gateway setup` |
| API Server | 支持 | 内置 |
| Webhooks | 支持 | `hermes webhook subscribe` |

### 8.2 当前微信配置

从 `.env` 文件提取的微信配置：

```bash
WEIXIN_ACCOUNT_ID=36a9c018b0b1@im.bot
WEIXIN_TOKEN=36a9c018b0b1@im.bot:060000addcdd2b7e84037e0aa14a9659441e87
WEIXIN_BASE_URL=https://ilinkai.weixin.qq.com
WEIXIN_CDN_BASE_URL=https://novac2c.cdn.weixin.qq.com/c2c
WEIXIN_DM_POLICY=pairing           # DM 策略: pairing（需配对）
WEIXIN_ALLOW_ALL_USERS=false       # 不允许所有用户
WEIXIN_ALLOWED_USERS=              # 允许的用户列表（空=需配对）
WEIXIN_GROUP_POLICY=disabled       # 群聊策略: 禁用
WEIXIN_GROUP_ALLOWED_USERS=
```

### 8.3 Gateway 运行模式

```bash
# 前台运行（调试用）
hermes gateway run

# 安装为后台服务（生产/持久运行）
hermes gateway install

# 服务管理
hermes gateway start     # 启动
hermes gateway stop      # 停止
hermes gateway restart   # 重启
hermes gateway status    # 状态检查
```

**Gateway 持久化注意**:
- SSH 登出后 Gateway 会停止 → 需启用 linger: `sudo loginctl enable-linger $USER`
- WSL2 关闭后 Gateway 会停止 → 需在 `/etc/wsl.conf` 设置 `systemd=true`

### 8.4 Prometheus 演示的 Gateway 策略

**方案 A: 纯 CLI 演示（推荐）**

```bash
# 直接使用 CLI，不启动 Gateway
hermes
# 或指定 provider
hermes -m function-router
```

- 优点: 简单、无额外依赖、延迟最低
- 适用: HICOOL 评委面前直接演示

**方案 B: CLI + 微信双通道**

```bash
# 启动 Gateway（微信通道）
hermes gateway start

# 同时使用 CLI
hermes
```

- 优点: 展示多平台能力
- 缺点: 增加复杂度，可能出现消息延迟

**方案 C: Web Dashboard**

```bash
hermes dashboard
# 浏览器访问管理面板 + 嵌入式聊天
```

- 优点: 可视化界面，展示配置管理能力
- 适用: 展示产品化完成度

### 8.5 Gateway 日志与排障

```bash
# 查看日志
tail -f ~/.hermes/logs/gateway.log

# 过滤错误
grep -i "failed to send\|error" ~/.hermes/logs/gateway.log | tail -20

# 重置失败状态
systemctl --user reset-failed hermes-gateway
```

---

## 9. Prometheus 集成配置方案

### 9.1 完整配置文件参考

以下是 Prometheus 演示环境的推荐 `config.yaml` 配置：

```yaml
model:
  default: function-router
  provider: custom
  base_url: http://127.0.0.1:18790/v1
  api_key: any

agent:
  max_turns: 150
  verbose: false
  reasoning_effort: medium

terminal:
  backend: local
  cwd: .
  timeout: 180

compression:
  enabled: true
  threshold: 0.5
  target_ratio: 0.2
  protect_last_n: 20
  protect_first_n: 3

prompt_caching:
  cache_ttl: 5m

display:
  compact: false
  show_reasoning: false
  streaming: true
  tool_progress: all

# Memory: 演示时禁用（方案 A），开发时启用（方案 B）
memory:
  memory_enabled: false
  user_profile_enabled: false

delegation:
  max_iterations: 50

approvals:
  mode: off              # 演示时关闭确认（或用 --yolo）

session_reset:
  mode: none
  idle_minutes: 1440

custom_providers:
  - name: Prometheus Router
    base_url: http://127.0.0.1:18790/v1
    api_key: any
    model: function-router
  - name: DeepSeek Direct
    base_url: https://api.deepseek.com/v1
    api_key: sk-xxxx
    model: deepseek-v4-pro
  - name: GLM Direct
    base_url: https://ark.cn-beijing.volces.com/api/coding/v1
    api_key: ark-xxxx
    model: glm-5.2

platform_toolsets:
  cli:
    - hermes-cli
```

### 9.2 SOUL.md 配置参考

```markdown
# 个性
你是普罗米修斯（Prometheus），一个自我进化的个人认知智能体。
你基于 MTClaw Function Router 运行，能路由用户意图到 5 个专职 Subagent。

## 风格
- 中文回答
- 友好但高效
- 当路由到特定 Subagent 时，简要说明你的路由决策

## 能力
- 知识检索（RAG）: 搜索本地文档库
- 记忆与偏好: 记住用户习惯，越用越懂你
- 写作: 生成、润色、翻译
- 日程: 管理事件和任务
- 闲聊: 日常对话

## 技术立场
- 偏好简单系统
- 注重隐私，数据本地存储
- 诚实标注数据来源
```

### 9.3 部署检查清单

```bash
# 1. 验证 Hermes 安装
hermes --version
hermes doctor

# 2. 验证 Function Router 连通性
curl http://127.0.0.1:18790/health

# 3. 验证 provider 配置
hermes config | grep -A5 model

# 4. 验证 toolset 配置
hermes tools list

# 5. 验证 SOUL.md
cat ~/.hermes/SOUL.md

# 6. 验证 Memory 状态
hermes memory status

# 7. 测试对话
hermes chat -q "你好，介绍你自己"

# 8. 验证路由
hermes chat -q "帮我搜索一下关于人工智能的文档"
# 应路由到 RAG Subagent
```

---

## 10. 风险与注意事项

### 10.1 配置变更不生效

**问题**: 修改 config.yaml 或 toolset 后，当前会话不生效。

**原因**: Hermes 在会话启动时读取配置，prompt caching 要求上下文不变。

**解决**: 
```bash
# CLI 模式: 退出并重新启动
/quit
hermes

# 或在会话中重置
/reset

# Gateway 模式: 重启 Gateway
hermes gateway restart
```

### 10.2 Secret Redaction 导致 API Key 被遮蔽

**问题**: `security.redact_secrets: true`（默认）会遮蔽工具输出中的 API key 格式字符串。

**影响**: 调试 Function Router 时，如果日志中包含 API key，会被替换为 `[REDACTED]`。

**解决**: 仅在调试时临时关闭（需重启会话）：
```bash
hermes config set security.redact_secrets false
```

### 10.3 上下文窗口与 Router 元数据

**问题**: Hermes 在发送请求时注入 sender block 等元数据，Function Router 需要清洗。

**现状**: spec.md 已规划"元数据清洗（移除 Hermes sender block 等）"步骤。

**注意**: 确保 Function Router 的元数据清洗逻辑覆盖 Hermes v0.18.2 的注入格式。如果 Hermes 升级后注入格式变化，清洗逻辑需要同步更新。

### 10.4 凭证安全

**问题**: 当前 `config.yaml` 中明文存储了 GLM API key（`ark-6dbfd827-...`）。

**建议**: 
- 使用 `.env` 文件存储密钥，config.yaml 引用环境变量
- 或使用 `hermes secrets bitwarden` 集成外部密钥管理
- 演示前确认配置文件不含敏感信息

### 10.5 单点故障

**问题**: Function Router (`127.0.0.1:18790`) 是单点，如果 Router 进程崩溃，Hermes 无法响应。

**缓解**: 
```bash
# 配置 fallback provider（custom_providers 中的 Direct 模型）
# 当 Router 不可用时，手动切换:
/model "GLM Direct"
```

### 10.6 会话隔离

**问题**: Gateway 模式下，多用户同时使用会共享 Hermes 实例。

**现状**: `group_sessions_per_user: true` 已启用按用户分组会话。

**注意**: Prometheus 的 Memory Subagent 需要确保多用户场景下的数据隔离（通过 user_id 区分）。

---

## 11. 结论

### 11.1 集成可行性

Hermes Agent 与 Prometheus 的集成是成熟可行的：

1. **OpenAI-compatible 对接**: `provider: custom` + `base_url` 模式已验证可用，当前实例已成功对接 GLM API
2. **custom_providers 多后端**: 支持灵活切换 Router / 直连模型，适合开发和演示
3. **SOUL.md 人格配置**: 可定制 Agent 身份，与 Prometheus 品牌一致
4. **Gateway 多平台**: 支持微信等平台扩展，增强演示效果

### 11.2 主要风险点

| 风险 | 严重度 | 缓解措施 |
|------|--------|---------|
| Memory 双重系统冲突 | 高 | 演示时禁用 Hermes memory，由 Prometheus Subagent 统一管理 |
| Router 单点故障 | 中 | 配置 fallback provider，手动切换 |
| 配置变更不生效 | 中 | 文档强调 `/reset` 和重启要求 |
| 元数据清洗不完整 | 中 | 确保 Router 覆盖 Hermes v0.18.2 注入格式 |
| API key 明文存储 | 低 | 迁移到 .env 或 Bitwarden |

### 11.3 推荐行动

1. **演示前**: 按本报告 9.1 节配置 config.yaml，按 9.2 节配置 SOUL.md
2. **演示前**: 禁用 Hermes memory 和不需要的 toolset（7.4 节）
3. **演示前**: 设置 `approvals.mode: off` 或使用 `--yolo`
4. **演示前**: 清理 `~/.hermes/memories/MEMORY.md` 中的无关内容
5. **开发阶段**: 保留 Hermes memory（方案 B），便于调试
6. **长期**: 评估 Mem0 等外部 memory provider 统一记忆后端

---

## 附录 A: 配置文件参考路径

```
~/.hermes/config.yaml          # 主配置文件
~/.hermes/.env                 # API 密钥和环境变量
~/.hermes/SOUL.md              # Agent 身份配置
~/.hermes/memories/MEMORY.md   # 记忆存储
~/.hermes/memories/USER.md     # 用户画像
~/.hermes/auth.json            # OAuth 令牌和凭证池
~/.hermes/logs/gateway.log     # Gateway 日志
~/.hermes/state.db             # 会话存储 (SQLite + FTS5)
~/.hermes/skills/              # 技能目录
~/.hermes/plugins/             # 插件目录
```

## 附录 B: 常用配置命令速查

```bash
# 配置管理
hermes config                    # 查看配置
hermes config edit               # 编辑配置文件
hermes config set KEY VAL        # 设置值
hermes config check              # 检查配置
hermes config path               # 配置文件路径
hermes config env-path           # .env 文件路径
hermes doctor                    # 全面检查

# 模型/Provider
hermes model                     # 交互式选择
hermes config set model.default function-router
hermes config set model.base_url http://127.0.0.1:18790/v1

# 工具
hermes tools                     # 交互式管理
hermes tools list                # 列出所有
hermes tools enable NAME         # 启用
hermes tools disable NAME        # 禁用

# Memory
hermes memory status             # 状态
hermes memory off                # 关闭

# Gateway
hermes gateway status            # 状态
hermes gateway start/stop        # 控制
hermes gateway run               # 前台运行

# 会话
hermes sessions list             # 列出会话
hermes sessions browse           # 交互浏览

# 凭证
hermes auth                      # 凭证管理
hermes auth list                 # 列出凭证
```

## 附录 C: Hermes 版本信息

```
Hermes Agent: v0.18.2 (2026.7.7.2)
Config Version: 33
Install Method: git
Python: 3.11.15
OpenAI SDK: 2.24.0
Source: /home/pmc/.hermes/hermes-agent/
```

---

> **报告状态**: 完成  
> **下一步**: 按 9.1-9.3 节配置 Prometheus 演示环境，执行部署检查清单验证
