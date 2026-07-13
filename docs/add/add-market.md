# ADD - Subagent 市场机制

> 版本：v1.0 | 日期：2026-07-14 | 状态：draft | 模块名：`market`
>
> **对应赛题加分项**："开箱即用：提供 MTT AIBOOK 一键安装包，含预置 Subagent **市场**"

## 1. 背景

### 1.1 问题描述

赛题加分项原文明确要求"含预置 Subagent **市场**"。v3.0 早期方案只是将 5 个 Subagent 代码合入 MTClaw 仓库的 `subagents/` 目录--这是"目录"，不是"市场"。市场需要具备：浏览、查询、安装、卸载、版本管理的机制。

### 1.2 设计目标

| 目标 | 说明 |
|------|------|
| **可浏览** | 用户能列出所有可用 Subagent（官方 + 社区） |
| **可安装** | 一条命令安装新 Subagent 并注册到 FR |
| **可卸载** | 一条命令卸载并反注册 |
| **可查询** | 查看详情、依赖、来源 |
| **预置即用** | 5 个官方 Subagent 默认预装，零配置可用 |
| **本地优先** | 市场索引可缓存到本地，离线可用 |

## 2. 调研

### 2.1 VS Code Extension Marketplace

- `code --list-extensions` / `code --install-extension <id>`
- 扩展清单（package.json）+ 市场 API（搜索 / 详情 / 下载）
- **可参考点**：CLI 命令设计、扩展元数据格式

### 2.2 npm registry

- `npm list` / `npm install <pkg>` / `npm uninstall <pkg>`
- 中央仓库 + 本地 node_modules
- **可参考点**：版本管理、依赖解析

### 2.3 OpenClaw plugin SDK

- `~/ws/openclaw/src/plugin-sdk/` - 插件定义 + 注册
- `definePluginEntry` + `registerTool` 机制
- **可参考点**：插件生命周期（discover / validate / load / activate）

### 2.4 Hermes plugin.yaml

- `~/ws/hermes-agent/plugins/*/plugin.yaml` - 插件清单
- YAML 格式，包含工具定义、路由配置、依赖
- **可参考点**：清单格式

### 2.5 结论

市场机制的核心是"清单 + CLI + 注册表"。结合 VS Code 的 CLI 设计和 OpenClaw 的插件生命周期，本设计实现一个轻量级 Subagent 市场。

## 3. 设计决策

### 3.1 市场架构

```
Subagent Registry (GitHub 仓库)
  └── registry.json (索引文件)
        ├── 官方 Subagent (5 个, 预置)
        └── 社区 Subagent (社区贡献)
              │
              ▼
prometheus market list  ←── 用户浏览
              │
              ▼
prometheus market install <name>
              │
              ├── 1. 从 registry 下载 Subagent 目录
              ├── 2. 校验 subagent.json 格式
              ├── 3. pip install 依赖
              ├── 4. 合并 functions.jsonl (注册工具到 FR)
              ├── 5. 更新 installed_subagents.json
              └── 6. 重启 FR 服务 (或热加载)
              │
              ▼
~/.prometheus/subagents/<name>/  (本地安装目录)
  ├── subagent.json
  ├── functions.jsonl
  ├── scripts/
  └── engine.py
```

### 3.2 Subagent 清单格式（subagent.json）

```json
{
  "name": "rag",
  "version": "1.0.0",
  "description": "本地知识库 RAG Subagent - 语义检索个人文档",
  "category": "knowledge",
  "source": "official",
  "author": "Prometheus Team",
  "repo": "MooreThreads/MTClaw",
  "path": "subagents/rag/",
  "user_friendly_name": "查文档",
  "dependencies": {
    "python": ["chromadb>=0.5", "sentence-transformers>=2.7", "pdfplumber"],
    "system": []
  },
  "provides": {
    "tools": ["rag_search", "rag_ingest", "rag_status"],
    "engines": ["engine.py"]
  },
  "routing": {
    "trigger_keywords": ["找一下", "搜索", "查一下", "文档"],
    "trigger_patterns": ["找.*", "搜.*", "查.*文档"],
    "base_priority": 4
  },
  "compatibility": {
    "mtclaw_min_version": "1.0.0",
    "aios_min_version": "1.4.0"
  }
}
```

**字段说明**：

| 字段 | 必填 | 说明 |
|------|------|------|
| name | 是 | 唯一标识（kebab-case） |
| version | 是 | 语义化版本 |
| description | 是 | 一句话描述（市场列表展示） |
| category | 是 | 分类：knowledge / writing / schedule / chat / memory / vision / data / other |
| source | 是 | official（官方预置）/ community（社区贡献） |
| user_friendly_name | 是 | 路由追踪面板和澄清问题中展示的中文名 |
| dependencies.python | 否 | Python 依赖列表 |
| dependencies.system | 否 | 系统依赖（如 ffmpeg / tesseract） |
| provides.tools | 是 | 提供的工具列表 |
| routing.base_priority | 是 | 基础路由优先级（1-6） |
| compatibility | 是 | 兼容性要求 |

### 3.3 市场索引（registry.json）

存放于 GitHub 仓库（`MooreThreads/MTClaw` 的 `subagents/registry.json`）：

```json
{
  "version": "1.0.0",
  "updated_at": "2026-07-14T10:00:00Z",
  "subagents": [
    {
      "name": "rag",
      "version": "1.0.0",
      "description": "本地知识库 RAG Subagent",
      "category": "knowledge",
      "source": "official"
    },
    {
      "name": "memory",
      "version": "1.0.0",
      "description": "记忆与偏好 Subagent",
      "category": "memory",
      "source": "official"
    },
    {
      "name": "writing",
      "version": "1.0.0",
      "description": "写作润色翻译 Subagent",
      "category": "writing",
      "source": "official"
    },
    {
      "name": "schedule",
      "version": "1.0.0",
      "description": "日程与任务 Subagent",
      "category": "schedule",
      "source": "official"
    },
    {
      "name": "chat",
      "version": "1.0.0",
      "description": "闲聊陪伴 Subagent",
      "category": "chat",
      "source": "official"
    },
    {
      "name": "weather",
      "version": "0.3.2",
      "description": "天气查询 Subagent (社区贡献)",
      "category": "other",
      "source": "community",
      "author": "@user123"
    },
    {
      "name": "finance",
      "version": "0.1.0",
      "description": "股票行情查询 Subagent (社区贡献)",
      "category": "other",
      "source": "community",
      "author": "@user456"
    }
  ]
}
```

### 3.4 CLI 命令

```bash
# 浏览市场
prometheus market list
  -> 显示所有可用 Subagent (官方 + 社区)
  -> 标注已安装状态

prometheus market list --category knowledge
  -> 按分类过滤

prometheus market list --source official
  -> 按来源过滤

# 查询详情
prometheus market info <name>
  -> 显示版本、描述、依赖、工具列表、路由配置

prometheus market search <keyword>
  -> 关键词搜索 (名称 + 描述)

# 安装管理
prometheus market install <name>
  -> 下载 + 校验 + 安装依赖 + 注册 + 重启 FR

prometheus market install <name>@1.0.0
  -> 指定版本

prometheus market remove <name>
  -> 卸载 + 反注册 + 重启 FR

prometheus market update <name>
  -> 更新到最新版本

prometheus market update --all
  -> 更新所有已安装 Subagent

# 本地状态
prometheus market installed
  -> 列出已安装 Subagent

prometheus market outdated
  -> 列出可更新的 Subagent
```

### 3.5 安装流程

```python
def install_subagent(name: str, version: str = None) -> dict:
    """安装 Subagent 的完整流程"""
    
    # 1. 从 registry 查找
    entry = lookup_registry(name, version)
    if not entry:
        return {"status": "error", "reason": "not_found"}
    
    # 2. 兼容性检查
    if not check_compatibility(entry):
        return {"status": "error", "reason": "incompatible"}
    
    # 3. 下载 Subagent 目录
    target_dir = f"~/.prometheus/subagents/{name}/"
    download_subagent(entry["repo"], entry["path"], target_dir)
    
    # 4. 校验 subagent.json
    manifest = load_manifest(target_dir + "subagent.json")
    validate_manifest(manifest)
    
    # 5. 安装 Python 依赖
    if manifest["dependencies"]["python"]:
        pip_install(manifest["dependencies"]["python"])
    
    # 6. 安装系统依赖（提示用户）
    if manifest["dependencies"]["system"]:
        prompt_system_deps(manifest["dependencies"]["system"])
    
    # 7. 注册到 FR
    merge_functions_jsonl(target_dir + "functions.jsonl")
    
    # 8. 更新本地状态
    update_installed_subagents(name, version)
    
    # 9. 重启 FR (或热加载)
    reload_fr()
    
    return {"status": "installed", "name": name, "version": version}
```

### 3.6 卸载流程

```python
def remove_subagent(name: str) -> dict:
    """卸载 Subagent"""
    
    # 1. 检查是否为官方预置（不允许卸载）
    if is_official_preset(name):
        return {"status": "error", "reason": "cannot_remove_official"}
    
    # 2. 反注册工具
    unmerge_functions_jsonl(name)
    
    # 3. 删除本地目录
    remove_dir(f"~/.prometheus/subagents/{name}/")
    
    # 4. 更新本地状态
    remove_from_installed_subagents(name)
    
    # 5. 重启 FR
    reload_fr()
    
    return {"status": "removed", "name": name}
```

### 3.7 本地状态管理

```
~/.prometheus/market/
  ├── installed_subagents.json     # 已安装列表
  │     {
  │       "installed": [
  │         {"name": "rag", "version": "1.0.0", "installed_at": "..."},
  │         {"name": "weather", "version": "0.3.2", "installed_at": "..."}
  │       ]
  │     }
  │
  └── registry_cache.json          # 远程索引缓存 (定期刷新)
        {
          "cached_at": "2026-07-14T10:00:00Z",
          "ttl_seconds": 86400,
          "registry": { ... }
        }
```

### 3.8 与 MTClaw FR 的集成

```
MTClaw FR 启动流程 (Prometheus 扩展):
  │
  ├── 1. 加载基础配置
  ├── 2. [新增] 扫描 ~/.prometheus/subagents/*/
  │     ├── 读取每个 subagent.json
  │     ├── 聚合 functions.jsonl (所有已安装 Subagent 的工具定义)
  │     └── 聚合路由配置 (trigger_keywords / base_priority)
  ├── 3. [新增] 应用动态优先级 (来自 router_learning 的 adjustment)
  ├── 4. 启动 FR 服务 (加载聚合后的 functions.jsonl)
  └── 5. 注册 reload API (供 market install/remove 调用)

热加载 API:
  POST /v1/reload
    -> 重新扫描 subagents 目录
    -> 重新聚合 functions.jsonl
    -> 热重启 FR (不中断现有连接)
```

### 3.9 官方预置 Subagent

5 个官方 Subagent 在安装时默认预装：

| Subagent | 分类 | user_friendly_name | 说明 |
|----------|------|-------------------|------|
| rag | knowledge | 查文档 | 本地知识库 RAG |
| memory | memory | 查记忆 | 记忆与偏好 |
| writing | writing | 写文档 | 写作润色翻译 |
| schedule | schedule | 查日程 | 日程与任务 |
| chat | chat | 闲聊 | 闲聊陪伴 |

**预置保护**：官方预置 Subagent 不允许通过 `market remove` 卸载（防止用户误删导致系统不可用），但可以 `market update` 更新。

### 3.10 演示剧本

```
评委: "你们说的 Subagent 市场在哪里？"

演示:
  # 1. 展示预置 Subagent
  prometheus market list
  -> 显示 5 个官方 Subagent (已安装) + 2 个社区 Subagent (未安装)
  
  # 2. 安装社区 Subagent
  prometheus market install weather
  -> 下载 + 安装依赖 + 注册 + FR 热重载
  -> "今天北京天气怎么样" -> 路由到 weather Subagent
  
  # 3. 查看详情
  prometheus market info weather
  -> 显示版本、依赖、工具、路由配置
  
  # 4. 卸载
  prometheus market remove weather
  -> 反注册 + FR 热重载
  -> "今天天气怎么样" -> 路由回兜底 (上游 LLM)
```

### 3.11 社区贡献流程

```
1. 开发者按 subagent.json 格式开发新 Subagent
2. 提交到自己的 GitHub 仓库
3. 向 MTClaw 仓库的 registry.json 提 PR (添加索引条目)
4. 官方审核 (格式 / 安全 / 不与现有重复)
5. 合并后, 所有用户 `market list` 可见
6. 用户 `market install <name>` 即可使用
```

## 4. 模块规格

### 4.1 配置

```json
{
  "market": {
    "registry_url": "https://raw.githubusercontent.com/MooreThreads/MTClaw/main/subagents/registry.json",
    "cache_ttl_seconds": 86400,
    "install_dir": "~/.prometheus/subagents/",
    "allow_community": true,
    "auto_reload_fr": true
  }
}
```

### 4.2 Python 引擎接口

```python
# market_engine.py

def fetch_registry(force_refresh: bool = False) -> dict:
    """获取市场索引 (带缓存)"""

def list_subagents(category: str = None, source: str = None) -> list[dict]:
    """列出所有可用 Subagent"""

def search_subagents(keyword: str) -> list[dict]:
    """关键词搜索"""

def get_subagent_info(name: str) -> dict:
    """获取详情"""

def install_subagent(name: str, version: str = None) -> dict:
    """安装"""

def remove_subagent(name: str) -> dict:
    """卸载"""

def update_subagent(name: str) -> dict:
    """更新"""

def list_installed() -> list[dict]:
    """列出已安装"""

def list_outdated() -> list[dict]:
    """列出可更新"""

def validate_manifest(manifest: dict) -> tuple[bool, str]:
    """校验 subagent.json 格式"""

def merge_functions_jsonl(subagent_dir: str) -> None:
    """合并工具定义到 FR"""

def unmerge_functions_jsonl(subagent_name: str) -> None:
    """从 FR 反注册工具定义"""

def reload_fr() -> None:
    """热重载 FR 服务"""
```

### 4.3 CLI 完整命令

```bash
prometheus market list [--category <cat>] [--source <src>]
prometheus market info <name>
prometheus market search <keyword>
prometheus market install <name>[@version]
prometheus market remove <name>
prometheus market update <name> | --all
prometheus market installed
prometheus market outdated
prometheus market refresh          # 刷新索引缓存
```

## 5. 实现 Checklist

### 数据层

- [ ] MKT-001 定义 `subagent.json` schema（JSON Schema）
- [ ] MKT-002 定义 `registry.json` schema
- [ ] MKT-003 创建 `installed_subagents.json` 本地状态文件
- [ ] MKT-004 创建 `registry_cache.json` 缓存机制

### Registry

- [ ] MKT-005 创建 `subagents/registry.json` 索引文件（5 个官方条目）
- [ ] MKT-006 实现 `fetch_registry()` - 带缓存的远程索引拉取
- [ ] MKT-007 实现缓存 TTL 机制（默认 24 小时）
- [ ] MKT-008 实现离线降级（缓存过期但网络不可用时，使用旧缓存）

### CLI

- [ ] MKT-009 实现 `prometheus market list` - 列出所有 Subagent
- [ ] MKT-010 实现 `prometheus market list --category` / `--source` 过滤
- [ ] MKT-011 实现 `prometheus market info <name>` - 详情展示
- [ ] MKT-012 实现 `prometheus market search <keyword>` - 关键词搜索
- [ ] MKT-013 实现 `prometheus market install <name>` - 安装流程
- [ ] MKT-014 实现 `prometheus market install <name>@version` - 指定版本
- [ ] MKT-015 实现 `prometheus market remove <name>` - 卸载流程
- [ ] MKT-016 实现 `prometheus market update <name>` - 更新流程
- [ ] MKT-017 实现 `prometheus market update --all` - 批量更新
- [ ] MKT-018 实现 `prometheus market installed` - 已安装列表
- [ ] MKT-019 实现 `prometheus market outdated` - 可更新列表
- [ ] MKT-020 实现 `prometheus market refresh` - 刷新缓存

### 安装/卸载引擎

- [ ] MKT-021 实现 `validate_manifest()` - subagent.json 校验
- [ ] MKT-022 实现 `install_subagent()` - 完整安装流程
- [ ] MKT-023 实现 `remove_subagent()` - 完整卸载流程
- [ ] MKT-024 实现官方预置保护（不允许卸载官方 Subagent）
- [ ] MKT-025 实现依赖检查与安装（Python pip + 系统依赖提示）
- [ ] MKT-026 实现兼容性检查（MTClaw / AIOS 版本）

### FR 集成

- [ ] MKT-027 实现 `merge_functions_jsonl()` - 工具定义合并
- [ ] MKT-028 实现 `unmerge_functions_jsonl()` - 工具定义反注册
- [ ] MKT-029 实现 FR 启动时扫描已安装 Subagent
- [ ] MKT-030 实现 FR 热重载 API (`POST /v1/reload`)
- [ ] MKT-031 实现 FR 热重载不中断现有连接

### 演示与文档

- [ ] MKT-032 准备 1-2 个社区示例 Subagent（weather / finance）用于演示
- [ ] MKT-033 编写社区贡献指南（subagent.json 规范 + PR 流程）
- [ ] MKT-034 演示剧本：market list / install / remove 完整流程

### 测试

- [ ] MKT-035 单元测试：subagent.json 校验（合法/非法格式）
- [ ] MKT-036 单元测试：registry 缓存机制
- [ ] MKT-037 集成测试：install -> list installed -> remove 端到端
- [ ] MKT-038 集成测试：FR 热重载（安装后立即可用）
- [ ] MKT-039 集成测试：官方预置保护
- [ ] MKT-040 集成测试：离线模式（缓存可用，远程不可达）

## 6. 与其他模块的关系

### 6.1 与 Router 自学习引擎的关系

Router 自学习引擎（[add-router-learning.md](add-router-learning.md)）的动态优先级调整作用于市场安装的 Subagent：
- 市场安装时，从 subagent.json 读取 `routing.base_priority` 作为基础优先级
- Router 自学习引擎的 `adjust_subagent_priority()` 在基础优先级上叠加 `dynamic_adjustment`
- 卸载 Subagent 时，同步清除该 Subagent 的路由学习数据

### 6.2 与路由追踪面板的关系

路由追踪面板（[design-proposal.md](../design-proposal.md) §7.3）新增展示：
- 已安装 Subagent 列表（带来源标记 official/community）
- 各 Subagent 的动态优先级（base + adjustment）

### 6.3 与 MTClaw 仓库的关系

市场索引文件 `subagents/registry.json` 存放于 MTClaw 仓库，5 个官方 Subagent 的代码也合入 MTClaw 仓库的 `subagents/` 目录。社区 Subagent 可以存放于贡献者自己的仓库，通过 registry.json 索引。

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 社区 Subagent 安全风险 | 注册时人工审核 + subagent.json 声明权限 + 来源标记 |
| FR 热重载失败 | 失败回滚到上一版本 functions.jsonl + 报错提示 |
| 依赖安装冲突 | 使用 venv 隔离 + 冲突时提示用户手动解决 |
| 网络不可达 | registry 缓存 + 离线模式 + 官方预置本地可用 |
| 版本不兼容 | subagent.json 声明 compatibility + 安装前检查 |
| 社区 Subagent 质量参差 | 来源标记 + 评分机制（产品化阶段） |

## 8. 参考

- VS Code Extension Marketplace: CLI 设计参考
- npm registry: 版本管理参考
- OpenClaw plugin SDK: `~/ws/openclaw/src/plugin-sdk/`
- Hermes plugin.yaml: `~/ws/hermes-agent/plugins/`
