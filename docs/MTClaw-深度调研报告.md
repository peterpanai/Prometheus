# MTClaw (OpenClaw Function Router) 深度调研报告

> 调研日期：2026-07-11 | 版本：v1.0.0 | 作者：自动调研生成

---

## 一、项目概述

MTClaw（原名 OpenClaw Function Router）是 **MooreThreads（摩尔线程）** 开源的 OpenAI-compatible **模型 Provider / Provider Proxy**。它在一个统一 Provider 接口背后组合了路由子代理（Routing Subagent）、工具执行器、完成检查（Completion Check）子代理和上游 LLM，通过自定义工具实现垂类领域加速，同时保留上游大模型的通用能力。

- **仓库地址**：https://github.com/MooreThreads/MTClaw
- **许可证**：MIT
- **语言**：Python 3.10+（核心服务），TypeScript（OpenClaw 插件）
- **核心依赖**：FastAPI + uvicorn + httpx（极简依赖栈）
- **核心代码量**：~4,700 行（server 2707 行 + builtin_tools 379 行 + 2 个 TS 插件 300 行 + 测试 ~1,400 行）

### 架构概览

```
OpenAI-compatible Clients (OpenClaw, Hermes, OpenCode, 任意Agent/IDE)
         │
         ▼
  Function Router Provider  (FastAPI, port 18790)
         │
         ├── Routing Subagent (本地路由模型)
         │     ├── 命中工具 → 工具执行 (Builtin / 用户自定义 Wrapper)
         │     │                → Completion Check (TASK_COMPLETE? → 直接回复 : 上游LLM)
         │     └── 未命中   → 上游 LLM
         │
         └── 上游 LLM → 最终回复
```

核心思想：用小参数路由模型做"快速分诊"，只在需要通用推理时才调用大模型，从而实现 4.99x~6.85x 的延迟加速。

---

## 二、当前项目状态

### 2.1 代码仓库状态

| 指标 | 状态 |
|------|------|
| 当前分支 | `main` |
| 总提交数 | 18 commits |
| 首次提交 | 2026-03（约4个月前） |
| 核心文件 | `function_router/server.py` (2707行) |
| 插件系统 | 2 个 TypeScript 插件（session-bridge、fr-tools） |
| 测试覆盖 | 3 个测试文件，覆盖路由、工具执行、配置加载 |
| CI/CD | 未见 CI 配置文件 |
| 版本 | v1.0.0（已发布到 ClawHub 插件市场） |

### 2.2 开发活跃度

- 最近活跃，主要贡献者来自 MooreThreads 团队
- PR 合并节奏健康（#1~#6）
- 存在未合并的功能分支 `feature/media-lifecycle`（媒体播放状态机）
- README 中标注了一个明确的 TODO：「开源可视化自动评测平台」

### 2.3 发布渠道

- GitHub 仓库
- ClawHub 插件市场（session-bridge plugin）
- pip 可安装（`pip install .`）

### 2.4 Agent 调用机制

MTClaw 本身不直接面向用户，而是作为一个 OpenAI-compatible **Provider Proxy** 被其他 Agent/客户端调用。整体架构层次如下：

```
用户 → Agent框架 (OpenClaw / Claude Code / ChatGPT / 任意客户端)
         │
         │  base_url = http://127.0.0.1:18790/v1
         │  model = function-router
         ▼
      MTClaw Function Router
         │
         ├── 路由模型（本地小模型，判断是否命中工具）
         ├── 工具执行（本地 shell 脚本 / builtin tools）
         └── 上游 LLM（兜底推理，生成最终回复）
```

**核心要点**：MTClaw 对上层 Agent 是完全透明的——Agent 只知道自己调了一个 `base_url`，不知道背后有路由模型、工具执行、上游代理这一整套机制。这种"零侵入接入"是其最核心的设计理念。

#### 2.4.1 以 OpenClaw 为例的完整配置

要使 OpenClaw 通过 MTClaw 工作，需要修改 `~/.openclaw/openclaw.json`：

```json
{
  "models": {
    "providers": {
      "function_router": {
        "baseUrl": "http://127.0.0.1:18790/v1",
        "apiKey": "any",
        "api": "openai-completions",
        "models": [{ "id": "function-router", "name": "Function Router" }]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "function_router/function-router"
      }
    }
  },
  "plugins": {
    "allow": ["session-bridge", "fr-tools"],
    "entries": {
      "session-bridge": { "enabled": true },
      "fr-tools": { "enabled": true }
    }
  }
}
```

配置包含三个关键步骤：

| 步骤 | 作用 | 说明 |
|------|------|------|
| **注册 Provider** | 声明 `function_router` 为可用模型供应商 | `baseUrl` 指向本地 18790 端口，协议为 `openai-completions` |
| **设为主模型** | `primary: "function_router/function-router"` | OpenClaw 收到用户请求后，默认走此 provider |
| **加载插件** | session-bridge + fr-tools | 注入 session header + 注册 FR 工具到 OpenClaw |

#### 2.4.2 插件的作用

**session-bridge 插件**：
- 每次请求时自动把 OpenClaw 的 session ID 注入 HTTP header（`x-openclaw-session-id` / `x-openclaw-session-key`）
- 使 MTClaw 能按 session 隔离路由模型上下文
- 支持 `wrapStreamFn`（HTTP stream 路径）和 `resolveTransportTurnState`（WebSocket / Responses API 路径）两种传输方式

**fr-tools 插件**：
- 启动时从 MTClaw 的 `openclaw-tools.json` 中读取所有工具定义
- 将每个工具注册为 OpenClaw 可执行工具
- 运行时通过 `POST /v1/execute_tool` 调用 MTClaw 执行

#### 2.4.3 完整请求链路（工具命中场景）

```
用户 "把音量调到50%"
    │
    ▼
OpenClaw Gateway
    │  primary model = function_router/function-router
    │  session-bridge 注入 x-openclaw-session-id
    ▼
MTClaw (POST /v1/chat/completions)
    │
    ├── 路由模型判断 → 命中 system_control 工具
    │
    ├── delegate_tools_to_openclaw 开启？
    │   ├── 是 → 返回 assistant.tool_calls, finish_reason=tool_calls
    │   │         │
    │   │         ▼
    │   │    OpenClaw fr-tools 插件执行
    │   │         │
    │   │         ▼
    │   │    POST /v1/execute_tool → MTClaw 执行脚本 → 返回结果
    │   │         │
    │   │         ▼
    │   │    OpenClaw 保存 tool_call + tool_result 到 session
    │   │         │
    │   │         ▼
    │   │    再次调用 MTClaw（continuation，末尾携带 role=tool）
    │   │         │
    │   │         ▼
    │   │    MTClaw 检测到 delegated continuation → 恢复
    │   │
    │   └── 否 → MTClaw 内部直接执行脚本
    │
    ├── Completion Check（permissive/strict）
    │   ├── TASK_COMPLETE → MTClaw 直接回复用户
    │   └── TASK_INCOMPLETE → 转发给上游 LLM
    │
    ▼
最终回复返回给 OpenClaw → 呈现给用户
```

#### 2.4.4 其他客户端的接入方式

对于非 OpenClaw 的客户端（如 ChatGPT 桌面端、Claude Code、自定义应用），接入更简单——只需配置一个 OpenAI-compatible endpoint：

```python
# Python SDK 示例
from openai import OpenAI

client = OpenAI(
    base_url="http://127.0.0.1:18790/v1",
    api_key="any"
)

response = client.chat.completions.create(
    model="function-router",
    messages=[{"role": "user", "content": "把音量调到50%"}]
)
```

无需任何插件。但在这种模式下：
- Session 隔离依赖客户端在 body 中传递 `sessionKey`/`sessionId` 等字段
- 工具委托必须关闭（`delegate_tools_to_openclaw: false`），因为这些客户端无法执行 `assistant.tool_calls`

---

## 三、已完成功能清单

### 3.1 核心路由能力

| 功能 | 状态 | 说明 |
|------|------|------|
| OpenAI-compatible API | 完成 | `/v1/chat/completions`、`/v1/models`、`/v1/tools` |
| 路由模型选择 | 完成 | 任一支持 tool calling 的 OpenAI-compatible 模型 |
| 多轮工具循环 | 完成 | 可配置最大轮数（默认6轮） |
| 上游 LLM 透明代理 | 完成 | 流式/非流式 SSE 透传 |
| Completion Check | 完成 | permissive / strict / always_true 三种模式 |
| Session 上下文管理 | 完成 | 路由模型侧按 session 维护对话上下文 |
| 上下文保持/清除策略 | 完成 | `fr_context_history` + `fr_context_preserve` 可配置 |
| 心跳消息绕过 | 完成 | HEARTBEAT、Conversation summary 等消息直接透传 |
| 消息连续性检测 | 完成 | 最后一条非 user 消息时跳过路由 |

### 3.2 工具系统

| 功能 | 状态 | 说明 |
|------|------|------|
| Builtin Shell Tools | 完成 | find、ls、cat、grep、sleep（Python 实现） |
| 用户自定义工具 | 完成 | JSONL 函数定义 + Shell Wrapper 脚本 |
| Wrapper 脚本接口规范 | 完成 | stdin JSON → stdout JSON，exit code 约定 |
| 工具目录安全校验 | 完成 | 路径遍历防护 |
| 函数名合法性校验 | 完成 | `^[a-zA-Z0-9_]+$` |
| 工具执行超时 | 完成 | `tool_exec_timeout_s` 可配置 |
| FR_TOOLS_BASE_DIR 环境变量 | 完成 | 暴露给 wrapper 脚本的工具根目录 |
| 用户工具覆盖 builtin | 完成 | 同名时用户定义优先 |

### 3.3 工具委托（Tool Delegation）

| 功能 | 状态 | 说明 |
|------|------|------|
| 委托到 OpenClaw | 完成 | 返回 `assistant.tool_calls` 而非内部执行 |
| 委托后恢复 | 完成 | 检测 OpenClaw tool result continuation 后恢复 |
| 精确委托控制 | 完成 | 可按工具名列表选择性委托 |
| 完全禁用委托 | 完成 | 兼容非 tool-capable 客户端 |
| fr-tools 插件 | 完成 | 自动注册 Function Router 工具到 OpenClaw |

### 3.4 Session Bridge（会话桥接）

| 功能 | 状态 | 说明 |
|------|------|------|
| Session Key 注入 | 完成 | 通过 HTTP Header `x-openclaw-session-key` |
| Session ID fallback | 完成 | `x-openclaw-session-id` |
| Body 字段提取 | 完成 | sessionKey/sessionId/conversationId/chatId 等 |
| Session Bridge Plugin | 完成 | OpenClaw >= 2026.3.24，支持 WebSocket/Responses API |
| ClawHub 一键安装 | 完成 | `openclaw plugins install clawhub:openclaw-session-bridge-plugin` |

### 3.5 配置系统

| 配置项 | 状态 | 说明 |
|--------|------|------|
| 路由模型配置 | 完成 | base_url + model + api_key |
| 上游模型配置 | 完成 | base_url + model + api_key |
| 环境变量替换 | 完成 | `${ENV_VAR}` 递归替换 |
| 旧版 qwen 配置兼容 | 完成 | 自动迁移到 routing 键 |
| `fr_completion_check` | 完成 | enabled + mode + always_true |
| `fr_context_history` | 完成 | enabled |
| `fr_context_preserve` | 完成 | enabled |
| `delegate_tools_to_openclaw` | 完成 | bool 或 {enabled, tools} |
| `routing_timeout_s` | 完成 | 超时自动重试一次 |
| `debug_logging` | 完成 | transcript 格式 |

### 3.6 运维与可观测性

| 功能 | 状态 | 说明 |
|------|------|------|
| Health Check | 完成 | `/health`（含 tools_loaded 信息）|
| Readiness Check | 完成 | `/ready`（检查路由模型可达性）|
| Tool History API | 完成 | `/v1/tool_history`（按时间范围查询，内存环形缓冲）|
| Debug 日志 | 完成 | transcript 格式，10MB 自动轮转 |
| 请求日志 | 完成 | 结构化 JSON 日志，含 route/function/latency 等 |
| 文件日志轮转 | 完成 | RotatingFileHandler（5个备份）|
| 日志文件自动恢复 | 完成 | 日志被删除后自动创建新文件 |
| 全服务重启脚本 | 完成 | 反向依赖停止 + 健康检查等待 |
| 安装/卸载脚本 | 完成 | 交互式配置 + 自动检测已有配置 |

### 3.7 示例工具（系统控制垂域）

| 工具 | 功能 |
|------|------|
| `system_control` | 音量与亮度控制（状态/设置/增减/静音） |
| `display_control` | 显示器与外观（主题/显示器管理/分辨率/刷新率） |
| `system_settings` | 定位服务与共享设置 |
| `wifi_bluetooth_control` | WiFi 与蓝牙控制 |
| `wallpaper_control` | 壁纸管理与切换 |
| `power_control` | 电源与屏幕控制（含定时关机） |
| `vlc_control` | VLC 媒体播放器控制 |

### 3.8 Skill 生态系统

| 功能 | 状态 | 说明 |
|------|------|------|
| skill-to-fc | 完成 | 将 script-backed skill 转换为 Function Router 工具配置 |
| 跨客户端支持 | 完成 | Claude Code / Codex / OpenClaw / OpenCode |

---

## 四、完成度评估

### 4.1 整体完成度：~80%

| 模块 | 完成度 | 说明 |
|------|--------|------|
| 核心路由引擎 | 95% | 功能完备，边缘 case 处理到位 |
| 工具系统 | 90% | Builtin + 自定义 shell 完善，缺少 Python/Node 原生插件 |
| OpenClaw 集成 | 95% | 插件体系完备，ClawHub 发布 |
| 配置系统 | 90% | 完整，有向下兼容 |
| 运维可观测性 | 70% | 日志/健康检查完备，缺少 Metrics/Prometheus |
| 测试覆盖 | 60% | 核心逻辑有测试，缺少集成/E2E 测试 |
| 文档 | 85% | 中英文 README + 多篇专项文档 + benchmark 数据 |
| 评测体系 | 30% | 有 benchmark 数据，但可视化平台是 TODO |
| 生产化特性 | 40% | 缺少认证、多节点、持久化等 |

### 4.2 Benchmark 数据支撑

在 50 个系统控制任务上，每个任务重复 4 次的评测：

| 模式 | Pass@1 | 平均耗时 | 加速比 |
|------|--------|----------|--------|
| Baseline（纯 Doubao） | 99.0% | 37.97s | 1.00x |
| Permissive | 95.5% | 5.54s | **6.85x** |
| Strict | **100.0%** | 7.61s | **4.99x** |

- Strict 模式：工具召回率 100%，工具准确率 94.8%
- Permissive 模式：工具召回率 100%，工具准确率 97.5%

---

## 五、优势分析

### 5.1 架构设计

1. **两阶段路由 + 执行模型**：用小参数路由模型（如 Qwen3-30B-A3B）做"快分诊"，只把需要通用推理的请求转发大模型。这在系统控制领域取得了 4.99x~6.85x 加速，且 strict 模式下 Pass@1 达到 100%。

2. **OpenAI-compatible 零侵入设计**：任何能配置 `base_url` 的客户端都能无缝接入，不需要 SDK 修改。这是比起 LangChain/LlamaIndex 等框架级方案的明显优势。

3. **工具委托机制**：将工具执行委托回 OpenClaw，使 OpenClaw 拥有完整的 session 工具调用历史，避免了 Function Router 内部执行工具导致的"幽灵工具调用"问题——上游模型看不到工具调用/结果导致幻觉。

### 5.2 工程实践

1. **依赖极简化**：仅需 FastAPI + uvicorn + httpx，无重型框架依赖。`requirements.txt` 仅 3 个包。

2. **Wrapper 脚本约定简单而强大**：stdin JSON → stdout JSON，exit code 0/非0。可以用任何语言编写（shell/curl/systemctl/Python/Go/Rust/Node），不需要额外包装。

3. **Session 管理的多层优先级**：header → body 字段 → metadata fallback → "default"，对各类客户端兼容性好。

4. **元数据清洗**：路由前自动剥离 OpenClaw 注入的 `<relevant-memories>`、sender blocks、时间戳前缀等元数据，保证路由模型看到纯净的用户意图。

5. **Debug 日志设计出色**：transcript 格式按 session 分组展示，路由侧和上游侧分别记录，排查问题直观高效。

### 5.3 社区与生态

1. **ClawHub 插件市场发布**：session-bridge 插件支持一行命令安装。
2. **skill-to-fc 生态工具**：支持将已有 skill 自动转换为 Function Router 工具配置。
3. **文档齐全**：中英文 README + config/add-tools/skill-to-fc/tool-delegation/session-header-patch 多篇专项文档。

---

## 六、缺点与风险

### 6.1 架构层面

1. **路由模型单点故障**：路由模型不可达时虽然会 fallback 到上游，但增加了一次失败 + 重试的延迟。路由模型的可用性直接决定了加速效果。

2. **Session 上下文纯内存存储**：`_QWEN_SAVED_CONTEXTS` 和 `_QWEN_PENDING_UPSTREAM_TURNS` 是进程内 dict，重启即丢失。虽然有 `fr_context_preserve` 模式但不解决重启问题。（Feature 分支上的 media-lifecycle 状态机声称可通过 OpenClaw session history 恢复，但还未合入 main。）

3. **仅支持 Shell Wrapper**：自定义工具只能通过 shell 脚本执行。不支持原生的 Python/Node/Go 工具插件机制。虽然 shell 可以调用任何语言，但缺少类型安全、import 管理等便利。

4. **流式代理的局限**：短路径（工具执行 + completion check 通过）下可以返回流式（当前实现为一次性返回），但工具执行过程中不支持流式反馈。

### 6.2 工程层面

1. **系统提示词硬编码为中文**：`SYSTEM_PROMPT` 要求"必须用中文回复"，国际化不友好。

2. **缺少 Metrics/可观测性端点**：没有 Prometheus `/metrics` 端点，依赖日志做可观测性，不利于生产环境监控告警。

3. **无认证/鉴权**：Function Router 自身没有内置的 API key 验证，依赖网络隔离保安全。

4. **单进程部署**：没有多 worker 支持（uvicorn 的 workers 未配置），高并发下存在性能瓶颈。

5. **缺少 CI/CD**：仓库中没有 GitHub Actions 或其他 CI 配置。

6. **测试覆盖不足**：核心路由逻辑有 mock 测试，但缺少：
   - 集成测试（真实 HTTP 请求端到端）
   - 性能回归测试
   - 路由模型准确率回归测试
   - 多 session 并发测试

### 6.3 生态绑定

1. **OpenClaw 强耦合**：session-bridge、fr-tools、工具委托等功能深度依赖 OpenClaw 生态。虽然可以作为独立 OpenAI-compatible provider 工作，但 session 隔离、工具委托等高级特性需要 OpenClaw 支持。

2. **未提供 Docker 镜像**：部署依赖手动 pip install + shell 脚本，没有容器化方案。

---

## 七、下一步开发建议（按优先级排列）

### P0 — 必须做（生产就绪）

| 序号 | 内容 | 说明 |
|------|------|------|
| 1 | **Metrics 端点** | Prometheus `/metrics` 端点，暴露路由命中率、工具执行延迟、上游延迟、错误率等 |
| 2 | **API Key 鉴权** | 在 Function Router 自身加上 API key 验证 |
| 3 | **Docker 化部署** | 提供 Dockerfile 和 docker-compose.yml |
| 4 | **CI/CD Pipeline** | GitHub Actions：lint + test + build |

### P1 — 应该做（体验与稳定性）

| 序号 | 内容 | 说明 |
|------|------|------|
| 5 | **Session 持久化** | 将会话上下文和工具历史持久化到 SQLite/文件，重启不丢失 |
| 6 | **多 Worker 支持** | 配置 uvicorn workers，或者引入 Redis 做 session 共享 |
| 7 | **国际化 System Prompt** | 根据用户语言自适应系统提示词语言 |
| 8 | **合入 media-lifecycle 分支** | 将媒体播放状态机合并到主分支 |
| 9 | **可视化评测平台** | 这是 README 中明确标注的 TODO |
| 10 | **路由模型配置热加载** | 修改 functions.jsonl 或 config 后无需重启 |

### P2 — 可以做（生态与扩展）

| 序号 | 内容 | 说明 |
|------|------|------|
| 11 | **原生 Python 工具插件** | 支持直接注册 Python 函数作为工具，无需 shell 包装 |
| 12 | **路由规则引擎** | 除 LLM 路由外支持简单的规则匹配（正则/关键词），进一步降低延迟 |
| 13 | **多上游模型路由** | 根据不同请求类型路由到不同上游模型 |
| 14 | **工具执行沙箱** | 增加 Docker/syscall 沙箱以安全执行不可信脚本 |
| 15 | **WebSocket 原生支持** | 支持 OpenAI Responses API 的 WebSocket 模式 |

---

## 八、Prometheus 二开建议

基于以上调研，Prometheus 项目在 MTClaw 基础上进行二次开发时，建议重点考虑以下方向：

### 8.1 优先保留和复用的能力

- **核心路由引擎**（`run_tool_loop` + `call_qwen` + `execute_tool`）：设计优秀，直接复用
- **工具系统接口规范**：stdin JSON → stdout JSON 的 wrapper 约定通用性好
- **Completion Check 机制**：permissive/strict 双模式设计合理
- **Session 管理**：多层优先级提取 session key，兼容性好
- **元数据清洗**：`_strip_openclaw_metadata` 函数可复用

### 8.2 需要改造的方向

- **去掉 OpenClaw 耦合**：session-bridge/fr-tools 插件设计改为通用协议
- **替换中文硬编码**：系统提示词支持配置化/多语言
- **增强可观测性**：添加 Prometheus metrics、结构化日志
- **持久化**：session 上下文、工具历史从内存移到持久化存储
- **多工具类型**：除 shell wrapper 外增加原生 Python 函数注册

### 8.3 可以新增的能力

- 工具编排（多工具组合执行）
- 条件路由（基于用户/角色/时间的不同路由策略）
- 工具执行结果缓存
- Rate limiting / Quota 管理

---

## 附录 A：文件清单

```
MTClaw/
├── function_router/
│   ├── __init__.py          # 包入口，暴露 __version__ 和 main
│   ├── server.py            # 核心服务（2707行）：路由、工具执行、代理
│   ├── builtin_tools.py     # Builtin 工具实现（379行）：find/ls/cat/grep/sleep
│   └── function-builtin.jsonl  # Builtin 工具的 JSON Schema 定义
├── plugins/
│   ├── session-bridge/      # OpenClaw Session 桥接插件（TypeScript）
│   │   ├── index.ts         # 核心逻辑（96行）
│   │   ├── dist/index.js    # 编译产物
│   │   └── package.json
│   └── fr-tools/            # OpenClaw 工具注册插件（TypeScript）
│       ├── index.ts         # 核心逻辑（203行）
│       ├── dist/index.js    # 编译产物
│       └── package.json
├── examples/
│   ├── config.example.json  # 配置模板
│   ├── functions.example.jsonl  # 7 个示例工具定义
│   └── scripts/*.sh        # 7 个示例 wrapper 脚本
├── scripts/
│   ├── install.sh           # 交互式安装脚本（415行）
│   ├── restart.sh           # 快速重启
│   ├── uninstall.sh         # 卸载脚本
│   └── patch-openclaw-session-header.sh  # 旧版 session patch
├── skills/
│   └── skill-to-fc/         # Skill 到 Function Router 转换工具
├── tests/
│   ├── test_routing.py      # 路由测试（868行）
│   ├── test_tools.py        # 工具测试（239行）
│   ├── test_config.py       # 配置测试（264行）
│   └── conftest.py
├── docs/
│   ├── config.md            # 配置参考
│   ├── adding-tools.md      # 工具开发指南
│   ├── skill-to-fc.md       # skill-to-fc 使用指南
│   ├── openclaw-tool-delegation.md  # 工具委托说明
│   ├── openclaw-session-header-patch.md  # 旧版 patch 说明
│   └── benchmarks/          # Benchmark 数据和报告
├── pyproject.toml
├── requirements.txt
├── restart_all.sh           # 全服务重启（含健康检查流）
├── README.md / README.en.md / README.zh-CN.md
└── LICENSE (MIT)
```

## 附录 B：API 端点总览

| Method | Path | 说明 |
|--------|------|------|
| GET | `/health` | 健康检查，返回工具加载数量 |
| GET | `/ready` | 就绪检查，验证路由模型可达性 |
| GET | `/v1/models` | OpenAI-compatible 模型列表 |
| GET | `/v1/tools` | 已加载的工具定义列表 |
| GET | `/v1/tool_history` | 工具执行历史（支持 since/limit） |
| POST | `/v1/chat/completions` | 核心：聊天补全（支持流式/非流式） |
| POST | `/v1/execute_tool` | 执行单个工具（供 OpenClaw 委托调用） |

## 附录 C：配置键一览

| 配置键 | 类型 | 默认值 | 作用 |
|--------|------|--------|------|
| `listen_host` | string | - | 绑定地址 |
| `listen_port` | int | 18790 | 监听端口 |
| `routing.base_url` | string | - | 路由模型地址 |
| `routing.model` | string | - | 路由模型名 |
| `routing.api_key` | string | - | 路由模型 API key |
| `upstream.base_url` | string | - | 上游模型地址 |
| `upstream.model` | string | - | 上游模型名 |
| `upstream.api_key` | string | - | 上游模型 API key |
| `functions_file` | string | - | 函数定义 JSONL 路径 |
| `scripts_dir` | string | - | 工具脚本目录 |
| `max_tool_rounds` | int | 6 | 最大工具调用轮数 |
| `tool_exec_timeout_s` | int | 30 | 单次工具执行超时 |
| `routing_timeout_s` | float | 10.0 | 路由模型 HTTP 超时 |
| `tools_base_dir` | string | - | 工具根目录（FR_TOOLS_BASE_DIR） |
| `fr_completion_check.enabled` | bool | true | 是否进行完成检查 |
| `fr_completion_check.mode` | string | permissive | permissive / strict |
| `fr_completion_check.always_true` | bool | false | FR-only 测试模式 |
| `fr_context_history.enabled` | bool | true | 是否保留路由模型上下文 |
| `fr_context_preserve.enabled` | bool | false | 永不自动清除上下文 |
| `delegate_tools_to_openclaw` | bool/obj | {enabled:true} | 工具委托配置 |
| `debug_logging.enabled` | bool | false | 是否开启 debug 日志 |
