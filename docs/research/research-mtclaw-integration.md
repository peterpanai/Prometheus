# MTClaw 源码集成方案调研报告

> 调研日期：2026-07-14 | 版本：v1.0 | 基于 MTClaw v1.0.0 源码分析
>
> 参考源码：`/home/pmc/ws/MTClaw`（main 分支，18 commits）
> 参考文档：`/home/pmc/ws/Prometheus/docs/MTClaw-深度调研报告.md`

---

## 一、调研目标

本报告针对 Prometheus 项目「源码合入 MTClaw 仓库」的集成方案进行深度调研，重点回答以下四个问题：

1. **server.py 的扩展点**：哪些函数/机制可以被 Prometheus 利用，需要修改哪些，需要新增哪些
2. **install.sh 如何扩展**：现有安装脚本的结构与扩展方式，如何支持 Prometheus 的 5 个 Subagent
3. **subagents/ 目录结构设计**：每个 Subagent 的文件组织方式与 MTClaw 现有目录的融合关系
4. **functions.jsonl 聚合方式**：多个 Subagent 的工具定义如何聚合为单个 functions.jsonl 供路由模型加载

---

## 二、server.py 扩展点分析

### 2.1 server.py 整体结构

`server.py` 共 2707 行，是 MTClaw 的核心服务文件，包含以下主要模块：

| 行号范围 | 模块 | 说明 |
|----------|------|------|
| 1-103 | 常量与系统提示词 | `SYSTEM_PROMPT`（硬编码中文）、`SYSTEM_PROMPT_REVIEW`、配置路径 |
| 106-189 | 数据类与全局状态 | `ModelConfig`、`AppConfig`、`AppStateData`、`STATE`、`TOOL_HISTORY` |
| 191-378 | Session 上下文管理 | `_QWEN_SAVED_CONTEXTS`、`derive_session_key`、pending upstream turns |
| 381-540 | 配置加载与校验 | `substitute_env_vars`、`load_config`、环境变量替换 |
| 543-582 | 工具加载 | `load_tools` — 加载 JSONL + 合并 builtin |
| 585-893 | 元数据清洗 | `_strip_openclaw_metadata`、多正则清洗链 |
| 894-984 | 路由模型调用 | `call_qwen`、`warmup_qwen`、`qwen_health_check` |
| 1026-1111 | 工具执行 | `execute_tool` — builtin 优先，否则 shell wrapper |
| 1267-1485 | 工具循环引擎 | `run_tool_loop` — 核心路由循环 |
| 1487-1611 | 完成检查 | `call_qwen_completion_check` — permissive/strict 模式 |
| 1629-1914 | 响应构建与上游代理 | `_build_completion_response`、`proxy_upstream` |
| 1917-2029 | 日志与历史 | `log_request`、`_record_tool_history` |
| 2032-2707 | FastAPI 应用 | 路由定义、startup/shutdown、`main()` |

### 2.2 可直接复用的扩展点（无需修改）

#### 2.2.1 工具加载机制 — `load_tools()` (L543-582)

```python
def load_tools(functions_path: Path) -> list[dict[str, Any]]:
    # 逐行解析 JSONL -> {"type": "function", "function": {...}}
    # 然后合并 builtin tools（同名用户工具优先）
    ...
```

**复用方式**：Prometheus 只需提供一个聚合后的 `functions.jsonl` 文件，`load_tools` 自动处理加载和 builtin 合并。无需修改此函数。

**关键细节**：
- 用户工具定义在 functions.jsonl 中，每行一个 JSON 对象
- builtin 工具定义在 `function-builtin.jsonl` 中（find/ls/cat/grep/sleep）
- 合并时用户工具同名覆盖 builtin（L576-580: `if builtin_name in seen_names: continue`）
- 返回格式为 OpenAI tools 标准：`[{"type": "function", "function": {...}}]`

#### 2.2.2 工具执行机制 — `execute_tool()` (L1031-1111)

```python
async def execute_tool(function_name: str, arguments_json: str) -> dict[str, Any]:
    # 1. 验证函数名 (^[a-zA-Z0-9_]+$)
    # 2. 如果是 builtin -> execute_builtin_tool()
    # 3. 否则 -> bash {scripts_dir}/{function_name}.sh
    #    - stdin: arguments_json
    #    - stdout: JSON 响应
    #    - 超时: tool_exec_timeout_s
    #    - 环境变量: FR_TOOLS_BASE_DIR
```

**复用方式**：Prometheus 的每个 Subagent 工具编写为 `{tool_name}.sh` wrapper 脚本放在 `scripts_dir` 中。脚本接收 stdin JSON，输出 stdout JSON。

**关键约束**：
- 函数名只能包含 `[a-zA-Z0-9_]`（L1026-1028）
- 脚本路径必须在 `scripts_dir` 内（L1048-1051，防路径遍历）
- 脚本名必须为 `{function_name}.sh`
- 环境变量 `FR_TOOLS_BASE_DIR` 可用于脚本内定位其他资源

#### 2.2.3 Session 管理 — `derive_session_key()` (L333-378)

多层 session key 提取：HTTP header (`x-openclaw-session-key` / `x-openclaw-session-id`) -> body 字段 (sessionKey/sessionId/conversationId/chatId) -> metadata/extra_body 嵌套 -> "default"

**复用方式**：Prometheus 使用 Hermes 作为前端客户端，Hermes 通过 HTTP 调用 FR。需要确保 Hermes 请求中携带 session 标识。如果 Hermes 不自动注入 session header，可以在 body 中传递 `sessionKey` 字段。

#### 2.2.4 元数据清洗 — `_strip_openclaw_metadata()` (L873-889)

清洗链移除：`<relevant-memories>`、`<ingest-reply-assist>`、sender blocks、conversation info、timestamp 前缀、transcript-style 包装器。

**复用方式**：Prometheus 使用 Hermes 而非 OpenClaw，但 Hermes 也可能注入类似元数据。可以扩展此函数添加 Hermes 特有的清洗规则。当前函数已是模块化设计，添加新正则即可。

#### 2.2.5 上游代理 — `proxy_upstream()` (L1788-1914)

透明转发到上游 LLM，支持流式 SSE 透传、pending turns 注入、tool context 注入。

**复用方式**：直接复用。Prometheus 的上游模型配置（DeepSeek/GPT-4o）通过 config.json 指定即可。

#### 2.2.6 API 端点

| 端点 | 方法 | 复用状态 |
|------|------|---------|
| `/v1/chat/completions` | POST | 直接复用 |
| `/v1/models` | GET | 直接复用 |
| `/v1/tools` | GET | 直接复用 |
| `/v1/tool_history` | GET | 直接复用（Prometheus 路由追踪面板使用） |
| `/v1/execute_tool` | POST | 直接复用 |
| `/health` | GET | 直接复用 |
| `/ready` | GET | 直接复用 |

### 2.3 需要修改的扩展点

#### 2.3.1 系统提示词 — `SYSTEM_PROMPT` (L57-78)

**现状**：
```python
SYSTEM_PROMPT = (
    "You are a system and filesystem assistant. Use only the provided tools to handle "
    "user requests about system settings, wallpaper, volume, brightness, file search, "
    "directory listing, file reading, text search, and short waits. "
    "If a request does not match any available tool, reply briefly that you cannot handle it. "
    "You must always reply in Chinese. "
    ...
)
```

**问题**：
- 硬编码为「system and filesystem assistant」，与 Prometheus 的 5 个 Subagent 领域不匹配
- 硬编码「must always reply in Chinese」
- 工具描述列举的是 MTClaw 的系统控制工具，不是 Prometheus 的 RAG/记忆/写作/日程/闲聊

**修改方案**：改为从配置文件加载

```python
# 修改前 (L57-78):
SYSTEM_PROMPT = "You are a system and filesystem assistant..."

# 修改后:
SYSTEM_PROMPT: str = ""  # 启动时从配置加载

def _load_system_prompt(config: AppConfig) -> str:
    """Load system prompt from config file or use default."""
    prompt_file = config.root_dir / "system_prompt.txt"
    if prompt_file.exists():
        return prompt_file.read_text(encoding="utf-8").strip()
    # 回退到默认提示词
    return _DEFAULT_SYSTEM_PROMPT
```

**配置示例** (`~/.prometheus/config/system_prompt.txt`)：
```
You are Prometheus, a personal cognitive assistant. Use the provided tools to handle
user requests about knowledge search, memory and preferences, writing assistance,
schedule management, and casual conversation. If a request does not match any available
tool, reply briefly that you cannot handle it. Reply in the same language as the user.
```

**影响范围**：`call_qwen()` (L936-983)、`run_tool_loop()` (L1311-1312)、`warmup_qwen()` (L999)

#### 2.3.2 完成检查提示词 — `COMPLETION_CHECK_PROMPT_*` (L1502-1514)

**现状**：permissive 和 strict 模式的提示词均硬编码为中文。

**修改方案**：同样改为配置加载，或根据用户语言自适应。

#### 2.3.3 心跳消息绕过逻辑 — `chat_completions()` (L2243-2246)

**现状**：
```python
if ("HEARTBEAT" in user_text) or \
    ("Conversation summary" in user_text) or \
    ("A new session was started" in user_text):
```

硬编码了 OpenClaw 特有的心跳消息关键词。Prometheus 使用 Hermes，心跳消息格式不同。

**修改方案**：将关键词列表改为配置项，或通过正则模式匹配。

```python
# 配置项新增:
"bypass_keywords": ["HEARTBEAT", "Conversation summary", "A new session was started"]
```

#### 2.3.4 工具委托配置 — `delegate_tools_to_openclaw`

**现状**：默认 `{"enabled": True}`，设计依赖 OpenClaw 执行工具。

**Prometheus 需求**：使用 Hermes 而非 OpenClaw，工具委托应禁用。工具由 FR 内部直接执行。

**修改方式**：无需修改代码，配置中设为 `false` 即可：
```json
"delegate_tools_to_openclaw": false
```

#### 2.3.5 `openclaw-tools.json` 快照生成 — `startup_event()` (L2044-2050)

**现状**：启动时自动生成 `openclaw-tools.json` 供 fr-tools 插件读取。

**Prometheus 需求**：不使用 fr-tools 插件，此快照无意义。可以保留（不影响功能），或通过配置跳过。

### 2.4 需要新增的扩展点

#### 2.4.1 请求前置 Hook — 即时偏好注入

**需求**：在路由模型调用前，检测用户消息中的偏好声明并注入记忆上下文。

**方案**：在 `chat_completions()` 函数中，`extract_user_text()` 之后、`run_tool_loop()` 之前，插入一个可配置的前置处理步骤。

```python
# 在 chat_completions() 中新增（约 L2351 之前）:
async def _pre_route_hook(
    user_text: str,
    session_key: str,
    messages: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Prometheus 请求前置处理：偏好检测 + 记忆注入。"""
    # 1. 即时偏好检测
    # 2. memory_recall 注入
    # 返回可能修改后的 messages
    return messages
```

**实现方式**：
- **方案 A（侵入式）**：直接在 server.py 中添加 hook 调用点
- **方案 B（非侵入式，推荐）**：通过 wrapper 脚本实现——在路由模型看到用户消息前，先调用一个 `pre_route.sh` 脚本修改 user message 内容

方案 B 的优势是不修改 server.py 核心逻辑，通过工具系统自身实现。例如在 `chat_light` 工具中实现记忆注入逻辑。

#### 2.4.2 交互日志记录 — `interaction_log` 表

**需求**：Prometheus 需要记录每次交互到 SQLite `interaction_log` 表供偏好引擎使用。

**方案**：扩展现有的 `_record_tool_history()` (L1941-2029) 或新增一个后置 hook。

现有 `TOOL_HISTORY` 是内存环形缓冲（`deque(maxlen=200)`），不持久化。Prometheus 需要持久化到 SQLite。

**推荐方案**：在 wrapper 脚本中自行记录。每次工具执行时，wrapper 脚本除了返回工具结果外，同时写入 SQLite interaction_log。这样不需要修改 server.py。

#### 2.4.3 路由置信度 — logprob 透传

**需求**：Router 自学习引擎需要路由模型的 logprob 来计算置信度。

**现状**：`call_qwen()` (L936-983) 的 payload 中没有 `"logprobs": true`。

**修改方案**：在 `call_qwen()` 的 payload 中添加 `logprobs` 支持：

```python
# call_qwen() payload 新增 (约 L956):
payload = {
    "model": STATE.config.routing.model,
    "messages": messages,
    "tools": STATE.tools,
    "stream": False,
    "temperature": 0.0,
    "repetition_penalty": 1.2,
    "frequency_penalty": 0.2,
    "parallel_tool_calls": False,
    "enable_thinking": False,
    # Prometheus 新增：路由置信度评估
    "logprobs": STATE.config.logprobs_enabled if hasattr(STATE.config, 'logprobs_enabled') else False,
    "top_logprobs": 5 if (hasattr(STATE.config, 'logprobs_enabled') and STATE.config.logprobs_enabled) else None,
}
```

**影响范围**：仅 `call_qwen()` 函数，`ToolLoopResult` 需新增字段存储 logprob 数据。

### 2.5 server.py 修改清单汇总

| 编号 | 修改点 | 行号 | 侵入程度 | 必要性 |
|------|--------|------|---------|--------|
| S-01 | `SYSTEM_PROMPT` 配置化 | L57-78 | 低 | 必须 |
| S-02 | `COMPLETION_CHECK_PROMPT` 配置化 | L1502-1514 | 低 | 建议 |
| S-03 | 心跳关键词配置化 | L2243-2246 | 低 | 建议 |
| S-04 | logprobs 透传 | L947-957 | 中 | Router 自学习需要 |
| S-05 | 前置 Hook 机制 | L2351 附近 | 中 | 偏好注入需要 |
| S-06 | AppConfig 新增字段 | L137-160 | 低 | 支持 S-01~S-05 配置 |

**总侵入评估**：核心路由引擎（`run_tool_loop`、`execute_tool`、`proxy_upstream`）完全不需要修改。修改集中在配置加载和系统提示词层面，侵入度低。

---

## 三、install.sh 扩展分析

### 3.1 现有 install.sh 结构分析

`scripts/install.sh` 共 415 行，结构如下：

| 行号范围 | 功能 | 说明 |
|----------|------|------|
| 1-11 | 变量定义 | `REPO_ROOT`、`TARGET_DIR=~/.function-router`、路径常量 |
| 12-83 | 交互式 prompt 函数 | `prompt_default`、`prompt_required`、`prompt_yes_no`（双语） |
| 85-166 | OpenClaw 配置检测 | 自动检测已有 OpenClaw primary model 作为上游默认值 |
| 168-268 | 交互式输入 | 路由模型/上游模型/端口/工具目录/OpenClaw 配置路径 |
| 270-274 | 文件复制 | 复制 config.example.json、functions.example.jsonl、scripts/*.sh |
| 276-294 | 插件安装 | 复制 session-bridge 和 fr-tools 插件到 OpenClaw extensions |
| 296-322 | 配置生成 | 用 Python 内联脚本生成 config.json（注入用户输入的值） |
| 324-342 | 工具快照生成 | 调用 `load_tools()` 生成 `openclaw-tools.json` |
| 344-389 | OpenClaw 配置修改 | 注册 provider、设置 primary model、启用插件 |
| 391-415 | 安装结果输出 | 打印各路径信息 |

### 3.2 关键扩展点

#### 3.2.1 文件复制段 (L270-274)

```bash
mkdir -p "$TARGET_DIR" "$SCRIPTS_DIR" "$LOGS_DIR"
cp "$REPO_ROOT/examples/config.example.json" "$CONFIG_PATH"
cp "$REPO_ROOT/examples/functions.example.jsonl" "$FUNCTIONS_PATH"
cp "$REPO_ROOT/examples/scripts/"*.sh "$SCRIPTS_DIR/"
chmod 755 "$SCRIPTS_DIR/"*.sh
```

**扩展方式**：在现有复制逻辑之后，添加 Prometheus 专用的文件复制段：

```bash
# === Prometheus 扩展 ===
PROMETHEUS_DIR="${HOME}/.prometheus"
PROMETHEUS_DATA_DIR="${PROMETHEUS_DIR}/data"
PROMETHEUS_CONFIG_DIR="${PROMETHEUS_DIR}/config"
PROMETHEUS_SCRIPTS_DIR="${PROMETHEUS_DIR}/scripts"
PROMETHEUS_TEMPLATES_DIR="${PROMETHEUS_DIR}/templates"

mkdir -p "$PROMETHEUS_DATA_DIR" "$PROMETHEUS_CONFIG_DIR" \
         "$PROMETHEUS_SCRIPTS_DIR" "$PROMETHEUS_TEMPLATES_DIR"

# 复制聚合后的 functions.jsonl
cp "$REPO_ROOT/subagents/functions.jsonl" "$FUNCTIONS_PATH"

# 复制所有 Subagent wrapper 脚本
cp "$REPO_ROOT/subagents/"*/scripts/*.sh "$SCRIPTS_DIR/"
chmod 755 "$SCRIPTS_DIR/"*.sh

# 复制 Python 引擎模块
cp "$REPO_ROOT/subagents/"*/engine.py "$PROMETHEUS_DIR/python_tools/"

# 复制写作模板
cp "$REPO_ROOT/templates/"*.md "$PROMETHEUS_TEMPLATES_DIR/"

# 复制系统提示词
cp "$REPO_ROOT/config/system_prompt.txt" "$PROMETHEUS_CONFIG_DIR/"

# 初始化 SQLite 数据库
python3 "$REPO_ROOT/subagents/init_db.py" --data-dir "$PROMETHEUS_DATA_DIR"

# 初始化 ChromaDB（空库）
python3 -c "import chromadb; chromadb.PersistentClient(path='$PROMETHEUS_DATA_DIR/chroma')"
```

#### 3.2.2 配置生成段 (L296-322)

现有脚本使用内联 Python 修改 config.json。Prometheus 需要额外注入配置项：

```bash
# 在现有配置生成 Python 脚本之后追加:
python3 -c '
import json, os
from pathlib import Path

path = Path(os.environ["CONFIG_PATH"])
data = json.loads(path.read_text(encoding="utf-8"))

# Prometheus 专用配置
data["prometheus"] = {
    "data_dir": os.environ["PROMETHEUS_DATA_DIR"],
    "preference_cron": "0 2 * * *",
    "max_memories_per_user": 1000,
    "embedding_model": "BAAI/bge-m3",
    "embedding_device": "cpu",
}

# 禁用 OpenClaw 工具委托（Prometheus 使用 Hermes）
data["delegate_tools_to_openclaw"] = {"enabled": False}

# 系统提示词路径
data["system_prompt_file"] = os.environ["PROMETHEUS_CONFIG_DIR"] + "/system_prompt.txt"

path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
'
```

#### 3.2.3 OpenClaw 配置修改段 (L344-389)

Prometheus 使用 Hermes 而非 OpenClaw，因此整个 OpenClaw 配置修改段可以跳过或替换为 Hermes 配置说明：

```bash
# === Prometheus 扩展：跳过 OpenClaw 配置，输出 Hermes 配置说明 ===
if [ "$INSTALL_TARGET" = "prometheus" ]; then
    echo "Hermes 配置说明："
    echo "在 Hermes 的模型配置中添加："
    echo "  base_url: http://127.0.0.1:${LISTEN_PORT}/v1"
    echo "  api_key: any"
    echo "  model: function-router"
else
    # 原有 OpenClaw 配置逻辑
    ...
fi
```

### 3.3 install.sh 扩展方案

**推荐方案**：保持 `scripts/install.sh` 作为 MTClaw 核心安装脚本不变，新增 `scripts/install-prometheus.sh` 作为 Prometheus 扩展安装脚本。

```bash
#!/bin/bash
# scripts/install-prometheus.sh
# Prometheus Subagent 扩展安装（在 MTClaw install.sh 之后执行）

set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
FR_DIR="${HOME}/.function-router"
PROMETHEUS_DIR="${HOME}/.prometheus"

# 1. 验证 MTClaw 已安装
if [ ! -f "$FR_DIR/config.json" ]; then
    echo "Error: MTClaw not installed. Run ./scripts/install.sh first." >&2
    exit 1
fi

# 2. 创建 Prometheus 目录结构
mkdir -p "${PROMETHEUS_DIR}/data" \
         "${PROMETHEUS_DIR}/config" \
         "${PROMETHEUS_DIR}/scripts" \
         "${PROMETHEUS_DIR}/python_tools" \
         "${PROMETHEUS_DIR}/templates"

# 3. 安装 Python 依赖
pip install -r "$REPO_ROOT/subagents/requirements.txt"

# 4. 聚合 functions.jsonl
python3 "$REPO_ROOT/subagents/aggregate_functions.py" \
    --output "$FR_DIR/functions.jsonl" \
    --subagents-dir "$REPO_ROOT/subagents"

# 5. 复制 wrapper 脚本到 FR scripts 目录
cp "$REPO_ROOT/subagents/"*/scripts/*.sh "$FR_DIR/scripts/"
chmod 755 "$FR_DIR/scripts/"*.sh

# 6. 复制 Python 引擎模块
cp "$REPO_ROOT/subagents/"*/engine.py "$PROMETHEUS_DIR/python_tools/"

# 7. 复制写作模板
cp "$REPO_ROOT/templates/"*.md "$PROMETHEUS_DIR/templates/"

# 8. 复制系统提示词
cp "$REPO_ROOT/config/system_prompt.txt" "$PROMETHEUS_DIR/config/"

# 9. 初始化 SQLite 数据库
python3 "$REPO_ROOT/subagents/init_db.py" \
    --data-dir "$PROMETHEUS_DIR/data"

# 10. 更新 FR 配置（注入 prometheus 配置段）
python3 "$REPO_ROOT/subagents/update_config.py" \
    --config "$FR_DIR/config.json" \
    --prometheus-dir "$PROMETHEUS_DIR"

# 11. 重启 FR
"$REPO_ROOT/scripts/restart.sh"

echo "Prometheus 安装完成。"
```

### 3.4 install.sh 修改清单汇总

| 编号 | 修改点 | 方式 | 侵入程度 |
|------|--------|------|---------|
| I-01 | 新增 `install-prometheus.sh` | 新文件 | 零侵入 |
| I-02 | `install.sh` 增加 `--target` 参数 | 可选修改 | 低 |
| I-03 | `restart.sh` 无需修改 | 直接复用 | 无 |
| I-04 | `uninstall.sh` 增加 Prometheus 清理 | 扩展 | 低 |

---

## 四、subagents/ 目录结构设计

### 4.1 设计原则

1. **与 MTClaw 现有目录平行**：subagents/ 作为 MTClaw 仓库的新增顶级目录
2. **每个 Subagent 自包含**：工具定义、脚本、引擎代码放在一起
3. **聚合机制自动化**：通过脚本自动聚合所有 Subagent 的 functions.jsonl
4. **不侵入 function_router/ 目录**：核心代码保持不变

### 4.2 目录结构

```
MTClaw/
├── function_router/               # MTClaw 核心（已有，不修改）
│   ├── __init__.py
│   ├── server.py
│   ├── builtin_tools.py
│   └── function-builtin.jsonl
│
├── subagents/                     # Prometheus 新增顶级目录
│   ├── README.md                  # Subagent 开发指南
│   ├── requirements.txt           # Prometheus 额外依赖
│   ├── aggregate_functions.py     # functions.jsonl 聚合脚本
│   ├── init_db.py                 # SQLite 数据库初始化
│   ├── update_config.py           # FR 配置更新脚本
│   │
│   ├── rag/                       # RAG 知识库 Subagent
│   │   ├── functions.jsonl        # 3 个工具定义
│   │   ├── scripts/               # Bash wrapper 脚本
│   │   │   ├── rag_search.sh
│   │   │   ├── rag_ingest.sh
│   │   │   └── rag_status.sh
│   │   ├── engine.py              # Python 引擎（ChromaDB + BGE-M3）
│   │   └── README.md
│   │
│   ├── memory/                    # 记忆与偏好 Subagent
│   │   ├── functions.jsonl        # 3 个工具定义
│   │   ├── scripts/
│   │   │   ├── memory_remember.sh
│   │   │   ├── memory_recall.sh
│   │   │   └── memory_set_reminder.sh
│   │   ├── engine.py              # SQLite + ChromaDB 引擎
│   │   └── README.md
│   │
│   ├── writing/                   # 写作润色翻译 Subagent
│   │   ├── functions.jsonl        # 4 个工具定义
│   │   ├── scripts/
│   │   │   ├── writing_generate.sh
│   │   │   ├── writing_polish.sh
│   │   │   ├── writing_translate.sh
│   │   │   └── writing_humanize.sh
│   │   ├── engine.py              # 上游 LLM 调用 + 模板系统
│   │   └── README.md
│   │
│   ├── schedule/                  # 日程与任务 Subagent
│   │   ├── functions.jsonl        # 5 个工具定义
│   │   ├── scripts/
│   │   │   ├── schedule_create_event.sh
│   │   │   ├── schedule_query.sh
│   │   │   ├── schedule_create_task.sh
│   │   │   ├── schedule_list_tasks.sh
│   │   │   └── schedule_complete_task.sh
│   │   ├── engine.py              # SQLite + dateparser 引擎
│   │   └── README.md
│   │
│   └── chat/                      # 闲聊陪伴 Subagent
│       ├── functions.jsonl        # 1 个工具定义
│       ├── scripts/
│       │   └── chat_light.sh
│       ├── engine.py              # 路由模型直回 + 记忆注入
│       └── README.md
│
├── templates/                     # 写作模板（共享资源）
│   ├── weekly_report.md
│   ├── email_formal.md
│   ├── email_casual.md
│   ├── tech_doc.md
│   ├── meeting_minutes.md
│   ├── article.md
│   └── ppt_outline.md
│
├── config/                        # 预置配置
│   ├── config.example.json        # Prometheus 配置模板
│   ├── system_prompt.txt          # Prometheus 系统提示词
│   └── functions.jsonl            # 聚合后的完整工具定义（自动生成）
│
├── scripts/                       # 安装脚本（已有，扩展）
│   ├── install.sh                 # MTClaw 核心安装（已有）
│   ├── install-prometheus.sh      # Prometheus 扩展安装（新增）
│   ├── restart.sh                 # 重启（已有，复用）
│   └── uninstall.sh               # 卸载（已有，扩展）
│
├── examples/                      # MTClaw 原有示例（已有）
├── plugins/                       # MTClaw 原有插件（已有）
├── tests/                         # 测试
└── pyproject.toml                 # Python 包配置
```

### 4.3 各 Subagent 内部结构规范

每个 Subagent 目录遵循统一结构：

```
{subagent_name}/
├── functions.jsonl    # 该 Subagent 的工具定义（每行一个 JSON）
├── scripts/           # Bash wrapper 脚本（文件名 = 工具名.sh）
│   └── {tool_name}.sh
├── engine.py          # Python 引擎（被 wrapper 脚本调用）
└── README.md          # Subagent 文档
```

### 4.4 wrapper 脚本标准模板

```bash
#!/bin/bash
# {tool_name}.sh — {Subagent} Subagent 工具
# 接收 stdin JSON，输出 stdout JSON

set -euo pipefail

# 读取 stdin
INPUT=$(cat)

# 定位 Python 引擎
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMETHEUS_DIR="${HOME}/.prometheus"
ENGINE="${PROMETHEUS_DIR}/python_tools/{subagent_name}_engine.py"

# 调用 Python 引擎
echo "$INPUT" | python3 "$ENGINE" {tool_name} \
    --data-dir "${PROMETHEUS_DIR}/data" \
    --templates-dir "${PROMETHEUS_DIR}/templates"
```

### 4.5 Python 引擎模块设计

每个 `engine.py` 使用统一的 CLI 接口：

```python
# engine.py 标准结构
import sys
import json
import argparse

def tool_function(args):
    """工具主函数，args 包含从 stdin JSON 解析的参数。"""
    # 业务逻辑
    return {"result": "ok", "data": ...}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("tool_name", help="要执行的工具名")
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--templates-dir", default=None)
    args = parser.parse_args()

    # 从 stdin 读取参数
    input_data = json.loads(sys.stdin.read() or "{}")

    # 分发到对应工具函数
    if args.tool_name == "rag_search":
        result = rag_search(input_data, args)
    elif args.tool_name == "rag_ingest":
        result = rag_ingest(input_data, args)
    else:
        result = {"error": f"unknown tool: {args.tool_name}"}

    print(json.dumps(result, ensure_ascii=False))

if __name__ == "__main__":
    main()
```

### 4.6 subagents/ 目录与 FR 运行时的关系

```
安装时:
  subagents/rag/scripts/rag_search.sh     ──复制──►  ~/.function-router/scripts/rag_search.sh
  subagents/rag/engine.py                 ──复制──►  ~/.prometheus/python_tools/rag_engine.py
  subagents/rag/functions.jsonl           ──聚合──►  ~/.function-router/functions.jsonl

运行时:
  FR 路由模型命中 "rag_search"
    → execute_tool("rag_search", args_json)
    → bash ~/.function-router/scripts/rag_search.sh
    → stdin: args_json
    → 调用 python3 ~/.prometheus/python_tools/rag_engine.py rag_search
    → stdout: JSON result
    → FR 返回结果给路由模型
```

---

## 五、functions.jsonl 聚合方式

### 5.1 现有加载机制分析

`load_tools()` (L543-582) 的加载流程：

```
1. 读取 functions_path 指定的 JSONL 文件（每行一个 JSON 对象）
2. 逐行解析为 {"type": "function", "function": {...}}
3. 收集已定义的工具名
4. 遍历 builtin 工具（function-builtin.jsonl）
5. 同名 builtin 跳过（用户优先）
6. 返回合并后的完整工具列表
```

**关键约束**：
- `functions_file` 配置项指定**单个** JSONL 文件路径
- 该文件包含**所有**用户工具定义
- 不支持目录扫描或通配符

### 5.2 聚合方案设计

由于 FR 只能加载单个 functions.jsonl 文件，需要将 5 个 Subagent 的工具定义聚合为一个文件。

#### 5.2.1 聚合脚本 — `aggregate_functions.py`

```python
#!/usr/bin/env python3
"""聚合所有 Subagent 的 functions.jsonl 为单个文件。"""

import json
import argparse
from pathlib import Path


def aggregate(subagents_dir: Path, output_path: Path) -> int:
    """聚合所有 Subagent 的 functions.jsonl。

    Args:
        subagents_dir: subagents/ 目录路径
        output_path: 输出文件路径

    Returns:
        聚合的工具数量
    """
    all_functions: list[dict] = []
    seen_names: set[str] = set()

    # 按目录名排序保证聚合顺序稳定
    for subagent_dir in sorted(subagents_dir.iterdir()):
        if not subagent_dir.is_dir():
            continue
        func_file = subagent_dir / "functions.jsonl"
        if not func_file.exists():
            continue

        with func_file.open("r", encoding="utf-8") as f:
            for line_num, raw_line in enumerate(f, start=1):
                line = raw_line.strip()
                if not line:
                    continue
                func_obj = json.loads(line)
                name = func_obj.get("name", "")
                if not name:
                    continue
                if name in seen_names:
                    print(f"Warning: duplicate tool name '{name}' "
                          f"in {func_file}:{line_num}, skipping")
                    continue
                seen_names.add(name)
                all_functions.append(func_obj)
                print(f"  [{subagent_dir.name}] {name}")

    # 写入聚合文件
    with output_path.open("w", encoding="utf-8") as f:
        for func_obj in all_functions:
            f.write(json.dumps(func_obj, ensure_ascii=False) + "\n")

    print(f"\nAggregated {len(all_functions)} tools -> {output_path}")
    return len(all_functions)


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate Subagent functions.jsonl files"
    )
    parser.add_argument(
        "--subagents-dir",
        type=Path,
        default=Path(__file__).parent,
        help="Directory containing Subagent folders",
    )
    parser.add_argument(
        "--output",
        type=Path,
        required=True,
        help="Output aggregated functions.jsonl path",
    )
    args = parser.parse_args()

    count = aggregate(args.subagents_dir, args.output)
    print(f"Total: {count} tools")


if __name__ == "__main__":
    main()
```

#### 5.2.2 聚合流程

```
开发时（各 Subagent 独立维护）:
  subagents/rag/functions.jsonl          → 3 个工具定义
  subagents/memory/functions.jsonl       → 3 个工具定义
  subagents/writing/functions.jsonl      → 4 个工具定义
  subagents/schedule/functions.jsonl     → 5 个工具定义
  subagents/chat/functions.jsonl         → 1 个工具定义
  ─────────────────────────────────────
  合计: 16 个 Prometheus 工具定义

安装时（聚合为一个文件）:
  python3 subagents/aggregate_functions.py
    --subagents-dir subagents/
    --output ~/.function-router/functions.jsonl

运行时（FR 加载）:
  load_tools(~/.function-router/functions.jsonl)
    → 16 个用户工具
    +  5 个 builtin 工具 (find/ls/cat/grep/sleep)
    = 21 个工具暴露给路由模型
```

#### 5.2.3 聚合后的 functions.jsonl 格式

```jsonl
{"name":"rag_search","description":"在本地知识库中搜索相关文档片段...","parameters":{"type":"object","properties":{"query":{"type":"string",...},...},"required":["query"]}}
{"name":"rag_ingest","description":"将本地文件或目录导入知识库...","parameters":{"type":"object",...}}
{"name":"rag_status","description":"查询知识库状态...","parameters":{"type":"object","properties":{}}}
{"name":"memory_remember","description":"记录用户偏好...","parameters":{"type":"object",...}}
{"name":"memory_recall","description":"检索与当前上下文相关的用户记忆...","parameters":{"type":"object",...}}
{"name":"memory_set_reminder","description":"设置提醒...","parameters":{"type":"object",...}}
{"name":"writing_generate","description":"生成各类文档...","parameters":{"type":"object",...}}
{"name":"writing_polish","description":"润色已有文本...","parameters":{"type":"object",...}}
{"name":"writing_translate","description":"翻译文本...","parameters":{"type":"object",...}}
{"name":"writing_humanize","description":"去AI化改写...","parameters":{"type":"object",...}}
{"name":"schedule_create_event","description":"创建日程事件...","parameters":{"type":"object",...}}
{"name":"schedule_query","description":"查询日程...","parameters":{"type":"object",...}}
{"name":"schedule_create_task","description":"创建任务...","parameters":{"type":"object",...}}
{"name":"schedule_list_tasks","description":"查询任务列表...","parameters":{"type":"object",...}}
{"name":"schedule_complete_task","description":"标记任务完成...","parameters":{"type":"object",...}}
{"name":"chat_light","description":"轻量闲聊...","parameters":{"type":"object",...}}
```

### 5.3 工具名命名规范

为确保路由模型的判断精度，工具名采用 `{subagent_prefix}_{action}` 命名规范：

| Subagent | 前缀 | 工具名示例 | 工具数 |
|----------|------|-----------|--------|
| RAG 知识库 | `rag_` | rag_search, rag_ingest, rag_status | 3 |
| 记忆与偏好 | `memory_` | memory_remember, memory_recall, memory_set_reminder | 3 |
| 写作润色翻译 | `writing_` | writing_generate, writing_polish, writing_translate, writing_humanize | 4 |
| 日程与任务 | `schedule_` | schedule_create_event, schedule_query, schedule_create_task, schedule_list_tasks, schedule_complete_task | 5 |
| 闲聊陪伴 | `chat_` | chat_light | 1 |

**前缀命名的优势**：
- 路由模型可通过前缀快速关联工具到领域
- 避免不同 Subagent 间的工具名冲突
- `description` 中可重复前缀关键词增强路由精度
- builtin 工具（find/ls/cat/grep/sleep）无前缀，天然不冲突

### 5.4 工具数量与路由精度

| 来源 | 工具数 | 说明 |
|------|--------|------|
| Prometheus Subagent | 16 | 5 个领域 |
| MTClaw Builtin | 5 | find/ls/cat/grep/sleep |
| **总计暴露给路由模型** | **21** | |

研究表明 LLM function calling 在工具数 <15 时准确率最高。21 个工具略超最佳线，但通过以下设计保持路由精度：

1. **清晰的前缀命名**：路由模型可通过前缀快速缩小搜索范围
2. **详细的 description**：每个工具描述包含触发关键词和用法说明
3. **5 个 Subagent 的明确划分**：每个领域 1-5 个工具，领域间无语义重叠
4. **temperature=0.0**：确保路由决策的确定性

---

## 六、完整集成方案

### 6.1 集成步骤总览

```
Step 1: Fork MTClaw 仓库
  ↓
Step 2: 创建 subagents/ 目录结构（§4.2）
  ↓
Step 3: 编写各 Subagent 的 functions.jsonl（16 个工具定义）
  ↓
Step 4: 编写 wrapper 脚本和 Python 引擎
  ↓
Step 5: 编写聚合脚本 aggregate_functions.py（§5.2.1）
  ↓
Step 6: 编写 install-prometheus.sh（§3.3）
  ↓
Step 7: 修改 server.py（仅 S-01~S-06，§2.5）
  ↓
Step 8: 编写系统提示词 config/system_prompt.txt
  ↓
Step 9: 编写配置模板 config/config.example.json
  ↓
Step 10: 端到端测试
```

### 6.2 配置文件示例

`config/config.example.json`（Prometheus 版本）:

```json
{
  "listen_host": "0.0.0.0",
  "listen_port": 18790,
  "tools_base_dir": "~/.prometheus/scripts",
  "fr_completion_check": {
    "enabled": true,
    "mode": "permissive"
  },
  "fr_context_history": {
    "enabled": true
  },
  "fr_context_preserve": {
    "enabled": false
  },
  "delegate_tools_to_openclaw": {
    "enabled": false
  },
  "routing": {
    "base_url": "https://your-routing-model-api/v1",
    "model": "qwen3-30b-a3b-instruct-2507",
    "api_key": "${ROUTING_API_KEY}"
  },
  "upstream": {
    "base_url": "https://your-upstream-model-api/v1",
    "model": "deepseek-v4-pro",
    "api_key": "${UPSTREAM_API_KEY}"
  },
  "functions_file": "functions.jsonl",
  "scripts_dir": "scripts",
  "max_tool_rounds": 6,
  "tool_exec_timeout_s": 30,
  "routing_timeout_s": 10.0,
  "debug_logging": {
    "enabled": true
  },
  "prometheus": {
    "data_dir": "~/.prometheus/data",
    "preference_cron": "0 2 * * *",
    "max_memories_per_user": 1000,
    "embedding_model": "BAAI/bge-m3",
    "embedding_device": "cpu"
  }
}
```

### 6.3 数据流总览

```
用户输入 "帮我找一下上周关于 GPU 算力的笔记"
  │
  ▼
Hermes Agent
  │  POST http://127.0.0.1:18790/v1/chat/completions
  │  body: {"messages": [{"role":"user","content":"..."}], "model":"function-router"}
  │
  ▼
MTClaw Function Router (server.py)
  │
  ├── 1. 元数据清洗: _strip_openclaw_metadata()
  │     (可扩展为 _strip_hermes_metadata)
  │
  ├── 2. Session 提取: derive_session_key()
  │     (从 Hermes 请求中提取 session 标识)
  │
  ├── 3. 路由模型调用: call_qwen()
  │     payload: 21 个工具定义 + 用户消息
  │     → 命中 rag_search 工具
  │
  ├── 4. 工具执行: execute_tool("rag_search", '{"query":"GPU 算力"}')
  │     → bash ~/.function-router/scripts/rag_search.sh
  │     → stdin: {"query":"GPU 算力","top_k":5}
  │     → python3 ~/.prometheus/python_tools/rag_engine.py rag_search
  │     → ChromaDB 语义检索
  │     → stdout: {"matches":[{"source":"...","content":"...","score":0.89}]}
  │
  ├── 5. Completion Check: call_qwen_completion_check()
  │     → TASK_COMPLETE
  │
  └── 6. 直接返回（快路径，不经过上游 LLM）
        → _build_completion_response()
        → 返回给 Hermes → 展示给用户
```

---

## 七、风险与缓解

### 7.1 技术风险

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| server.py 修改导致 FR 核心功能回归 | 高 | 使用配置化修改（S-01~S-03），不修改核心路由引擎；保持向下兼容（有默认值） |
| 21 个工具导致路由精度下降 | 中 | 前缀命名 + 详细 description；50 条路由准确率测试集验证 |
| BGE-M3 嵌入延迟过高 | 中 | 预加载模型到内存；缓存热点查询向量；支持 GPU 加速 |
| wrapper 脚本执行超时 | 低 | `tool_exec_timeout_s=30s` 兜底；写作 Subagent 走上游 LLM 时单独配置超时 |
| Session 上下文内存丢失（重启） | 低 | FR 已有 fallback 到上游 LLM；长期需持久化（P1 优先级） |

### 7.2 集成风险

| 风险 | 影响 | 缓解方案 |
|------|------|---------|
| MTClaw 上游更新导致冲突 | 中 | subagents/ 目录与 function_router/ 完全解耦；仅 server.py 的少量修改需要 rebase |
| OpenClaw 耦合代码影响 Prometheus | 低 | `delegate_tools_to_openclaw=false` 禁用所有 OpenClaw 依赖路径 |
| install.sh 与 install-prometheus.sh 的执行顺序依赖 | 低 | install-prometheus.sh 在开头检查 MTClaw 是否已安装 |

---

## 八、与 spec.md 的对照检查

### 8.1 spec.md §8 文件结构对照

spec.md §8 描述的文件结构与本方案的差异：

| spec.md 描述 | 本方案 | 差异说明 |
|-------------|--------|---------|
| `subagents/rag/functions.jsonl` | ✅ 一致 | 每个 Subagent 独立 functions.jsonl |
| `subagents/rag/scripts/` | ✅ 一致 | Bash wrapper 脚本目录 |
| `subagents/rag/engine.py` | ✅ 一致 | Python 引擎 |
| `config/functions.jsonl` | ✅ 一致 | 聚合后的完整工具定义（自动生成） |
| `install/install.sh` | ⚠️ 调整 | 本方案将安装脚本放在 `scripts/` 而非 `install/`，与 MTClaw 现有结构一致 |
| `dashboard/route_tracer.html` | 不在本报告范围 | 路由追踪面板通过 `/v1/tool_history` API 轮询实现 |

### 8.2 spec.md §9 安装部署对照

spec.md §9.1 描述的「源码合入 MTClaw」方案与本方案完全一致：

- ✅ 代码合入 MTClaw 仓库的 `subagents/` 目录
- ✅ 使用 MTClaw 自带安装脚本（扩展版）
- ✅ 不独立维护安装/配置体系

---

## 九、结论

### 9.1 集成可行性评估

| 维度 | 评估 | 说明 |
|------|------|------|
| **技术可行性** | ✅ 高 | FR 核心路由引擎无需修改，扩展点设计清晰 |
| **侵入度** | ✅ 低 | server.py 仅需 6 处修改（S-01~S-06），均为配置化改造 |
| **可维护性** | ✅ 高 | subagents/ 与 function_router/ 完全解耦 |
| **向下兼容** | ✅ 完全 | 所有修改有默认值，不影响 MTClaw 原有功能 |
| **工具系统兼容** | ✅ 完全 | wrapper 脚本约定（stdin JSON → stdout JSON）直接复用 |

### 9.2 核心结论

1. **server.py 的扩展点充分**：工具加载、工具执行、Session 管理、元数据清洗、上游代理均可直接复用。需要修改的仅有系统提示词配置化（S-01）、完成检查提示词配置化（S-02）、心跳关键词配置化（S-03）和 logprobs 透传（S-04），均为低侵入改造。

2. **install.sh 采用双脚本策略**：保持 MTClaw 原有 `install.sh` 不变，新增 `install-prometheus.sh` 作为扩展安装脚本。两者解耦，互不影响。

3. **subagents/ 目录设计为自包含结构**：每个 Subagent 包含 functions.jsonl + scripts/ + engine.py，通过聚合脚本合并为 FR 可加载的单一文件。

4. **functions.jsonl 聚合为自动化流程**：`aggregate_functions.py` 扫描所有 Subagent 目录，按稳定顺序聚合并去重，输出单个 functions.jsonl。16 个 Prometheus 工具 + 5 个 builtin = 21 个工具暴露给路由模型。

### 9.3 推荐实施顺序

```
Phase 1 (第1周): 创建 subagents/ 目录骨架 + 聚合脚本 + 16 个 functions.jsonl
Phase 2 (第2周): 实现 5 个 Python 引擎模块 + 16 个 wrapper 脚本
Phase 3 (第3周): 修改 server.py (S-01~S-04) + install-prometheus.sh
Phase 4 (第4周): 端到端测试 + 路由准确率测试集
```
