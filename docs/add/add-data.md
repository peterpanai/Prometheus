# ADD — 数据分析 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`data`

## 1. 背景

用户需要用自然语言查询和分析本地数据文件（CSV/Excel/SQLite），自动生成 pandas 代码并安全执行，可选生成图表。这是面向知识工作者的数据民主化场景。

## 2. 调研

### 2.1 Hermes

- **代码执行工具**：`~/ws/hermes-agent/tools/code_execution_tool.py`（100KB）— 最接近数据分析沙箱的参考
- **沙箱机制**：sanctioned tools 白名单 — `web_search`, `web_extract`, `read_file`, `write_file`, `search_files`, `patch`, `terminal`
- **双传输**：Local UDS 和 Remote file-based RPC
- **安全限制**：工具白名单、网络限制、文件系统隔离

### 2.2 OpenClaw

- **无专门数据分析工具**：通过 shell 执行 + PDF 工具 + 图片分析组合实现
- **PDF 工具**：`~/ws/openclaw/src/agents/tools/pdf-tool.ts`
- **Image 工具**：`~/ws/openclaw/src/agents/tools/image-tool.ts`
- **节点执行**：`~/ws/openclaw/src/agents/tools/nodes-tool.ts` — 在远程节点执行命令

### 2.3 Codex

- **Shell 执行**：`codex-rs/core/src/tools/handlers/shell_spec.rs` + `shell_command.rs`
- **Agent Jobs**：`codex-rs/core/src/tools/handlers/agent_jobs.rs` — CSV-backed batch processing
- **安全沙箱**：bubblewrap (Linux) / Windows sandbox
- **Orchestrator**：`codex-rs/core/src/tools/orchestrator.rs` — approval + sandbox + retry

### 2.4 结论

三个代码库都通过沙箱化 shell/代码执行来实现数据分析，而非提供专门的 pandas GUI。Codex 的 orchestrator（approval + sandbox selection + retry）是最完善的安全执行模式。对于 Prometheus，核心差异化在于**自然语言 → pandas 代码自动生成** + **图表自动选择**。

## 3. 设计决策

### 3.1 沙箱安全模型

参考 Codex orchestrator 和 Hermes code_execution 的安全设计：

```python
# 安全约束
ALLOWED_IMPORTS = {'pandas', 'matplotlib', 'numpy', 'json', 'datetime', 'collections', 'itertools'}
FORBIDDEN_IMPORTS = {'os', 'subprocess', 'sys', 'shutil', 'socket', 'requests', 'urllib'}
EXEC_TIMEOUT = 15  # 秒
MAX_OUTPUT_ROWS = 10000
MAX_OUTPUT_CHARS = 50000
```

### 3.2 NL → Pandas 代码生成

```
data_query(file_path, query, chart_type) →
  1. 加载文件 → df, schema info
  2. 构造 prompt:
     system: "You are a pandas expert. Generate ONLY Python code using pandas/matplotlib."
     user: f"Schema:\n{df.dtypes}\n{df.head(3)}\nSample rows:\n{df.sample(3)}\n\nQuery: {query}"
  3. 调用上游 LLM 生成 Python 代码
  4. 代码安全检查（AST 遍历，检查 import 白名单）
  5. 沙箱执行（restricted globals, timeout signal）
  6. 图表生成（matplotlib → PNG → 文件路径）
  7. 返回 {summary, chart_path, row_count}
```

### 3.3 图表类型自动选择

| 查询特征 | 图表类型 | matplotlib 模板 |
|---------|---------|----------------|
| "趋势"/"变化"/"时间" + 日期列 | line | `df.plot(x=date_col, y=value_col, kind='line')` |
| "排名"/"Top"/"对比" + 类别列 | bar | `df.plot(x=cat_col, y=value_col, kind='barh')` |
| "占比"/"比例"/"百分比" | pie | `df.plot.pie(y=value_col, labels=cat_col)` |
| "相关性"/"分布" | scatter | `df.plot.scatter(x=col1, y=col2)` |
| 默认 | table | 不生成图表 |

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "data",
  "version": "1.0.0",
  "description": "数据分析 Subagent — NL → Pandas → 图表",
  "enabled": true,
  "priority": 4,
  "requires": {
    "packages": ["pandas>=2.0", "matplotlib>=3.7", "openpyxl>=3.1"]
  },
  "provides": {
    "tools": ["data_query", "data_schema"],
    "engines": ["data_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["分析数据", "统计", "图表", "画个图", "数据概况"],
    "trigger_patterns": ["分析.*csv", "统计.*", "画.*图", "查看.*数据"],
    "match_priority": "normal"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.4，2 个工具：`data_query`、`data_schema`。

### 4.3 Python 引擎接口

```python
# data_engine.py
def query(file_path: str, query: str, chart_type: str = "auto",
          upstream_url: str = None, upstream_model: str = None, upstream_key: str = None) -> dict
def schema(file_path: str) -> dict
```

## 5. 实现 Checklist

### 数据加载

- [ ] DAT-001 实现 CSV 加载（pd.read_csv，自动检测编码）
- [ ] DAT-002 实现 Excel 加载（pd.read_excel，支持 .xls/.xlsx）
- [ ] DAT-003 实现 SQLite 加载（sqlite3.connect，只允许 SELECT）
- [ ] DAT-004 实现 schema 信息提取（dtypes, head, describe, null_count, row_count）

### 代码生成与执行

- [ ] DAT-005 实现 NL → pandas 代码 prompt 构造
- [ ] DAT-006 实现上游 LLM 调用生成 Python 代码
- [ ] DAT-007 实现代码安全校验（AST 遍历 + import 白名单检查）
- [ ] DAT-008 实现沙箱 exec（restricted globals, signal.SIGALRM timeout）
- [ ] DAT-009 实现结果截断（MAX_OUTPUT_ROWS, MAX_OUTPUT_CHARS）

### 图表生成

- [ ] DAT-010 实现 chart_type=auto 自动判断逻辑
- [ ] DAT-011 实现 line 图模板
- [ ] DAT-012 实现 bar 图模板
- [ ] DAT-013 实现 pie 图模板
- [ ] DAT-014 实现 scatter 图模板
- [ ] DAT-015 实现图表保存为 PNG（`~/.prometheus/data/charts/`）

### Wrapper 脚本

- [ ] DAT-016 编写 `data_query.sh`
- [ ] DAT-017 编写 `data_schema.sh`

### 测试

- [ ] DAT-018 单元测试：CSV 加载 + schema
- [ ] DAT-019 单元测试：Excel 加载
- [ ] DAT-020 单元测试：SQLite 加载（只读验证）
- [ ] DAT-021 单元测试：沙箱安全性（禁止 import os/subprocess）
- [ ] DAT-022 单元测试：超时机制
- [ ] DAT-023 单元测试：图表自动选择
- [ ] DAT-024 集成测试：data_query 端到端（"按月份统计销售额"）
- [ ] DAT-025 集成测试：大数据集截断

## 6. 参考

- Hermes Code Execution: `~/ws/hermes-agent/tools/code_execution_tool.py`
- Codex Orchestrator: `~/ws/codex/codex-rs/core/src/tools/orchestrator.rs`
- Codex Shell Spec: `~/ws/codex/codex-rs/core/src/tools/handlers/shell_spec.rs`
- pandas matplotlib integration: https://pandas.pydata.org/docs/user_guide/visualization.html
