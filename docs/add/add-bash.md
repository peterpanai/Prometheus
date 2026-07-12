# ADD — Bash 命令行 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`bash`

## 1. 背景

用户需要通过 AI 执行本地 Bash 命令来完成文件管理、服务启停、脚本运行等操作。这要求严格的命令安全校验，防止破坏性操作。

## 2. 调研

### 2.1 Hermes

- **Terminal Tool**：`~/ws/hermes-agent/tools/terminal_tool.py`（134KB，最大的工具文件）— 最完整的 Shell 执行参考
- **多后端支持**：local（subprocess.Popen）、docker、modal、SSH、singularity、daytona
- **安全机制**：危险命令检测（`approval.py`）、sudo 密码缓存、PTY 支持
- **后台任务**：`background: bool` 参数、watch patterns 监控输出
- **代码执行**：`~/ws/hermes-agent/tools/code_execution_tool.py` — sanctioned tools 白名单

### 2.2 OpenClaw

- **Nodes 工具**：`~/ws/openclaw/src/agents/tools/nodes-tool.ts` — 节点执行（invoke, device_status）
- **命令执行**：`~/ws/openclaw/src/agents/tools/nodes-tool-commands.ts` — 通过 gateway RPC 执行
- **安全审批**：`~/ws/openclaw/src/infra/exec-approvals.ts` — 执行审批系统
- **安全分析**：`~/ws/openclaw/src/infra/exec-safety.ts` — 命令安全检查
- **安全二进制策略**：`~/ws/openclaw/src/infra/exec-safe-bin-policy.ts`
- **Shell 环境**：`~/ws/openclaw/src/infra/shell-env.ts`

### 2.3 Codex

- **Shell Spec**：`~/ws/codex/codex-rs/core/src/tools/handlers/shell_spec.rs` — Shell 工具规格定义
- **Shell Command**：`~/ws/codex/codex-rs/core/src/tools/handlers/shell/shell_command.rs` — 命令执行实现
- **Unified Exec**：`~/ws/codex/codex-rs/core/src/tools/handlers/unified_exec.rs` — PTY-backed 统一执行
- **Orchestrator**：`~/ws/codex/codex-rs/core/src/tools/orchestrator.rs` — 审批 + 沙箱选择 + 重试
- **沙箱**：bubblewrap (Linux) / Windows sandbox
- **后台任务**：agent_jobs 系统支持长时间任务

### 2.4 结论

三个代码库都有成熟的 Shell 执行机制。Hermes 的 terminal_tool 功能最丰富（多后端、后台监控），OpenClaw 的安全审批链最完善（approvals → safety → safe-bin-policy），Codex 的 orchestrator 模式最清晰（审批 + 沙箱 + 重试分离）。Prometheus 采纳三者优点：白名单/黑名单双重校验（简单有效）+ 后台进程管理（参考 Hermes）+ 审批链（参考 OpenClaw）。

## 3. 设计决策

### 3.1 命令安全模型

参考 Hermes 的 dangerous command detection 和 OpenClaw 的 exec-safety：

```python
# 白名单（允许的命令）
ALLOWED_COMMANDS = [
    'find', 'grep', 'cat', 'ls', 'wc', 'head', 'tail', 'awk', 'sed',
    'sort', 'uniq', 'curl', 'wget', 'git', 'python3', 'node', 'npm',
    'pip', 'df', 'du', 'ps', 'top', 'free', 'echo', 'date', 'env',
    'mkdir', 'touch', 'cp', 'mv', 'chmod', 'chown'
]

# 黑名单（绝对禁止的模式）
BLACKLIST_PATTERNS = [
    r'rm\s+(-rf?\s+)?/',      # rm -rf /
    r'dd\s+if=',                # dd 磁盘操作
    r'mkfs\.',                  # 格式化
    r'shutdown',                # 关机
    r'reboot',                  # 重启
    r'>\s*/dev/',               # 写入设备文件
    r':\(\)\s*\{\s*:\|:&\s*\}\s*;:',  # fork bomb
    r'chmod\s+777\s+/',        # 危险权限
]
```

### 3.2 后台进程管理

参考 Hermes 的 background task 模式：

```sql
CREATE TABLE bash_processes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pid INTEGER NOT NULL,
    label TEXT,
    command TEXT NOT NULL,
    workdir TEXT,
    status TEXT DEFAULT 'running',
    started_at TEXT DEFAULT (datetime('now')),
    stopped_at TEXT
);
```

进程监控：定期检查 PID 存活状态，更新 status。

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "bash",
  "version": "1.0.0",
  "description": "Bash 命令行 Subagent — 安全执行本地命令与后台进程管理",
  "enabled": true,
  "priority": 8,
  "requires": {
    "packages": []
  },
  "provides": {
    "tools": ["bash_exec", "bash_spawn", "bash_status"],
    "engines": ["bash_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["运行", "执行", "查看文件", "ls", "cat", "启动服务", "后台运行"],
    "trigger_patterns": ["运行.*命令", "执行.*脚本", "查看.*文件", "启动.*服务"],
    "match_priority": "normal"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.6，3 个工具：`bash_exec`、`bash_spawn`、`bash_status`。

### 4.3 Python 引擎接口

```python
# bash_engine.py
def exec_cmd(command: str, workdir: str = ".", timeout: int = 30) -> dict
def spawn_process(command: str, workdir: str = ".", label: str = "") -> dict
def list_processes(label: str = None) -> list[dict]
def kill_process(pid: int) -> dict
```

## 5. 实现 Checklist

### 安全模块

- [ ] SHL-001 实现命令白名单校验器
- [ ] SHL-002 实现命令黑名单正则匹配器
- [ ] SHL-003 实现写入操作确认检查（rm/mv/cp 等文件变更操作）
- [ ] SHL-004 实现命令参数消毒（防止命令注入）

### 命令执行

- [ ] SHL-005 实现 `exec_cmd()` — subprocess.run() 沙箱执行
- [ ] SHL-006 实现 timeout 机制（默认 30s，硬上限 120s）
- [ ] SHL-007 实现输出截断（合并 stdout+stderr，上限 10000 字符）
- [ ] SHL-008 实现 workdir 路径校验（限制在允许的目录范围内）

### 后台进程管理

- [ ] SHL-009 创建 SQLite 表 `bash_processes`
- [ ] SHL-010 实现 `spawn_process()` — subprocess.Popen() 后台启动
- [ ] SHL-011 实现 `list_processes()` — 查询 SQLite 进程表
- [ ] SHL-012 实现 `kill_process()` — os.kill(pid, SIGTERM)
- [ ] SHL-013 实现进程存活监控（定期检查 PID，更新 status）

### Wrapper 脚本

- [ ] SHL-014 编写 `bash_exec.sh`
- [ ] SHL-015 编写 `bash_spawn.sh`
- [ ] SHL-016 编写 `bash_status.sh`

### 测试

- [ ] SHL-017 单元测试：白名单验证（允许 + 拒绝）
- [ ] SHL-018 单元测试：黑名单匹配（所有危险模式）
- [ ] SHL-019 单元测试：命令注入防护
- [ ] SHL-020 单元测试：timeout 机制
- [ ] SHL-021 单元测试：输出截断
- [ ] SHL-022 集成测试：bash_exec → bash_spawn → bash_status 端到端
- [ ] SHL-023 集成测试：进程存活监控
- [ ] SHL-024 安全测试：禁止命令拒绝（dd/mkfs/shutdown/rm -rf /）

## 6. 参考

- Hermes Terminal Tool: `~/ws/hermes-agent/tools/terminal_tool.py:2010+`
- Hermes Approval: `~/ws/hermes-agent/tools/approval.py`
- OpenClaw Exec Safety: `~/ws/openclaw/src/infra/exec-safety.ts`
- OpenClaw Exec Approvals: `~/ws/openclaw/src/infra/exec-approvals.ts`
- Codex Shell Command: `~/ws/codex/codex-rs/core/src/tools/handlers/shell/shell_command.rs`
- Codex Orchestrator: `~/ws/codex/codex-rs/core/src/tools/orchestrator.rs`
