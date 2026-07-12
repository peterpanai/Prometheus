# ADD — Prometheus 插件系统架构

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft

## 1. 背景

Prometheus 的 8 个 Subagent 需要以**插件化、无损接入**的方式集成到 MTClaw Function Router 中。每个 Subagent 作为一个独立插件，包含工具定义（JSONL）、执行脚本（Shell Wrapper）和 Python 引擎模块。插件系统负责发现、校验、加载、激活插件，并提供标准化的生命周期管理。

## 2. 调研

### 2.1 Hermes 插件系统

- **文件**：`~/ws/hermes-agent/hermes_cli/plugins.py` (~2000 行)
- **发现机制**：4 级来源 — bundled plugins (`plugins/`)、user plugins (`~/.hermes/plugins/`)、project plugins (`./.hermes/plugins/`)、pip entry-points (`hermes_agent.plugins` group)
- **插件清单**：`plugin.yaml` + `__init__.py`，`register(ctx)` 函数为入口
- **注册能力**：`ctx.register_tool()`、`ctx.register_hook()`、`ctx.inject_message()`、`ctx.llm`
- **生命周期钩子**：`pre_tool_call`、`post_tool_call`、`pre_llm_call`、`post_llm_call`、`on_session_start`、`on_session_end` 等 20+ 个
- **工具覆盖**：支持 `override=True` 替换内置工具，受 `allow_tool_override` 配置控制

### 2.2 OpenClaw 插件系统

- **文件**：`~/ws/openclaw/src/plugins/manifest.ts`、`~/ws/openclaw/src/plugin-sdk/plugin-entry.ts`
- **发现机制**：bundled + workspace + global + package roots
- **插件清单**：`openclaw.plugin.json`，声明 `contracts`（能力契约：tools、providers、hooks 等）
- **注册模式**：`definePluginEntry({ id, register(api) })`，api 提供 `registerTool()`、`registerHook()`、`registerProvider()`、`registerWebSearchProvider()` 等
- **工具可用性**：`ToolAvailabilitySignal` — `always` / `auth` / `config` / `env` / `plugin-enabled` / `context`，支持 `allOf`/`anyOf` 组合
- **工具描述符**：`ToolDescriptor { name, description, inputSchema, owner, executor, availability }`

### 2.3 Codex 插件系统

- **文件**：`~/ws/codex/codex-rs/core-plugins/src/`、`~/ws/codex/codex-rs/plugin/src/manifest.rs`
- **发现机制**：`DISCOVERABLE_PLUGIN_MANIFEST_PATHS` 扫描 `plugin.toml`
- **插件清单**：`PluginManifest { name, version, description, paths: { skills, mcp_servers, apps, hooks } }`
- **扩展 API**：`ExtensionRegistry` 提供 `tool_contributors()`、`prompt_slot_fillers()`、`context_contributors()`
- **插件标识**：`<plugin_name>@<marketplace_name>` 格式（如 `github@openai-curated`）

### 2.4 关键结论

| 特性 | Hermes | OpenClaw | Codex | Prometheus 采纳 |
|------|--------|----------|-------|----------------|
| 清单格式 | plugin.yaml | openclaw.plugin.json | plugin.toml | **plugin.json**（JSON，MTClaw 生态一致） |
| 注册入口 | `register(ctx)` 函数 | `definePluginEntry({ register })` | Manifest 声明 + 扩展注册 | **声明式 manifest + Shell Wrapper 自注册** |
| 工具发现 | 模块 import 时自注册 | buildToolPlan 统一排序 | spec_plan.add_tool_sources | **functions.jsonl 合并**（MTClaw 原生格式） |
| 可用性控制 | check_fn + requires_env | ToolAvailabilitySignal | Feature flags | **enabled + requires_env + requires_config** |
| 生命周期钩子 | 20+ hooks | 40+ hooks | hooks 文件 | **pre_tool / post_tool / on_load / on_unload** |

## 3. 设计决策

### 3.1 插件目录结构

```
~/.prometheus/plugins/<plugin-name>/
├── plugin.json              # 插件清单（必需）
├── functions.jsonl          # 工具定义（每行一个 JSON 工具描述）
├── scripts/                 # Bash Wrapper 脚本
│   ├── <tool_name>.sh       # 每个工具一个 wrapper
│   └── ...
├── engine.py                # Python 引擎模块（可选）
└── requirements.txt         # 额外 Python 依赖（可选）
```

### 3.2 plugin.json 清单规范

```json
{
  "name": "rag",
  "version": "1.0.0",
  "description": "RAG 知识库 Subagent — 文档索引与语义检索",
  "author": "Prometheus Team",
  "enabled": true,
  "priority": 5,
  "requires": {
    "env": ["PROMETHEUS_DATA_DIR"],
    "config": ["embedding_model", "embedding_device"],
    "packages": ["chromadb", "sentence-transformers", "pdfplumber", "python-docx"]
  },
  "provides": {
    "tools": ["rag_search", "rag_ingest", "rag_status"],
    "engines": ["rag_engine.py"],
    "hooks": ["post_ingest_graph_update"]
  },
  "lifecycle": {
    "on_load": "scripts/setup.sh",
    "on_unload": null,
    "health_check": "scripts/health_check.sh"
  },
  "routing": {
    "trigger_keywords": ["找一下", "搜索", "查一下", "导入知识库", "知识库状态"],
    "trigger_patterns": ["帮我找.*", "搜索.*文档", "导入.*知识库"],
    "match_priority": "normal"
  }
}
```

### 3.3 插件生命周期

```
发现 (discover) → 校验 (validate) → 加载 (load) → 激活 (activate) → 运行 (run) → 卸载 (unload)
```

- **发现**：扫描 `~/.prometheus/plugins/` 下所有包含 `plugin.json` 的目录
- **校验**：检查 manifest 完整性、环境变量、Python 依赖、脚本可执行性
- **加载**：执行 `on_load` 脚本（如初始化数据库、下载模型），合并 functions.jsonl
- **激活**：工具注册到 MTClaw Function Router，路由规则生效
- **运行**：处理路由请求，执行 wrapper 脚本
- **卸载**：执行 `on_unload`，清理临时资源

### 3.4 无损接入 MTClaw 方案

MTClaw Function Router 通过 `--functions-file` 参数加载工具定义（JSONL 格式）。插件系统的无损接入策略：

1. **工具定义合并**：`plugin_manager.py` 在启动前扫描所有已启用插件的 `functions.jsonl`，合并写入 `/tmp/prometheus_functions.jsonl`，作为 FR 的 `--functions-file` 参数
2. **脚本目录聚合**：所有插件脚本统一通过符号链接或 PATH 前缀找到，FR 的 `scripts_dir` 指向 `~/.prometheus/plugins/` 的聚合目录
3. **Python 引擎隔离**：每个插件的 `engine.py` 在独立子进程中运行，通过 stdin/stdout JSON 通信，不共享全局状态
4. **路由规则注入**：插件 manifest 中的 `routing` 字段被编译为 system prompt 中的路由提示词，增强路由模型判断准确度

```
启动流程:
  1. plugin_manager.py discover → 找到 8 个插件
  2. plugin_manager.py validate → 校验依赖、环境变量
  3. plugin_manager.py activate → 合并 functions.jsonl
  4. plugin_manager.py generate_routing_hints → 生成路由提示词
  5. FR 启动时加载合并后的 functions.jsonl + routing hints
```

### 3.5 插件间依赖

```json
{
  "requires": {
    "plugins": ["memory"],
    "reason": "rag_ingest 后需要 memory_engine 记录交互日志"
  }
}
```

依赖图在加载时做拓扑排序，缺失依赖的插件自动禁用并告警。

## 4. 实现 Checklist

### Phase 1：插件框架核心

- [ ] PLG-001 创建 `prometheus/plugin/` 模块目录结构
- [ ] PLG-002 实现 `plugin_manager.py`：`discover()`, `validate()`, `load()`, `activate()`, `deactivate()`
- [ ] PLG-003 实现 `plugin.json` schema 校验（JSON Schema）
- [ ] PLG-004 实现 `functions.jsonl` 合并器（去重、冲突检测、优先级排序）
- [ ] PLG-005 实现路由提示词自动生成器（从各插件 `routing` 字段编译）
- [ ] PLG-006 实现插件依赖拓扑排序与循环检测
- [ ] PLG-007 实现 Python 依赖检查器（`pip list` 对比 requirements.txt）
- [ ] PLG-008 实现环境变量检查器（`os.environ` 对比 manifest `requires.env`）
- [ ] PLG-009 实现健康检查调度器（定时执行 `health_check` 脚本）
- [ ] PLG-010 实现 FR 启动参数自动生成（`--functions-file`, `--scripts-dir`）

### Phase 2：插件 CLI 管理

- [ ] PLG-011 实现 `prometheus plugin list` 命令（列出所有插件及状态）
- [ ] PLG-012 实现 `prometheus plugin enable/disable <name>` 命令
- [ ] PLG-013 实现 `prometheus plugin info <name>` 命令（显示详情）
- [ ] PLG-014 实现 `prometheus plugin validate <name>` 命令（校验单个插件）
- [ ] PLG-015 实现 `prometheus plugin install <path>` 命令（从目录/tar 安装插件）

### Phase 3：集成测试

- [ ] PLG-016 编写 `test_plugin_manager.py`（发现/校验/加载/激活 全流程）
- [ ] PLG-017 编写 `test_plugin_dependency.py`（依赖检测、循环检测、缺失降级）
- [ ] PLG-018 编写 `test_functions_merge.py`（合并器去重、冲突处理）
- [ ] PLG-019 编写 `test_routing_hints.py`（路由提示词生成正确性）
- [ ] PLG-020 端到端测试：8 插件全部激活 → FR 启动 → 路由分发验证

## 5. 文件清单

```
prometheus/
├── plugin/
│   ├── __init__.py
│   ├── manager.py              # 插件管理器核心
│   ├── manifest.py             # plugin.json schema 校验
│   ├── merger.py               # functions.jsonl 合并器
│   ├── routing_hints.py        # 路由提示词生成器
│   ├── dependency.py           # 依赖拓扑排序
│   ├── env_checker.py          # 环境检查器
│   ├── health.py               # 健康检查调度
│   └── cli.py                  # 插件管理 CLI
├── plugins/                    # 插件目录（8 个 Subagent 各一个子目录）
│   ├── rag/
│   ├── memory/
│   ├── writing/
│   ├── data/
│   ├── chat/
│   ├── bash/
│   ├── webfetch/
│   └── websearch/
└── tests/
    ├── test_plugin_manager.py
    ├── test_plugin_dependency.py
    ├── test_functions_merge.py
    └── test_routing_hints.py
```

## 6. 参考

- Hermes 插件系统：`~/ws/hermes-agent/hermes_cli/plugins.py:1-2000`
- OpenClaw Plugin SDK：`~/ws/openclaw/src/plugin-sdk/plugin-entry.ts:219-280`
- OpenClaw 工具可用性：`~/ws/openclaw/src/tools/types.ts:34-50`
- Codex 插件清单：`~/ws/codex/codex-rs/plugin/src/manifest.rs:8-58`
- MTClaw Function Router：`functions.jsonl` 格式，`--functions-file` 参数
