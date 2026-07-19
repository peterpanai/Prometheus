# ADD - Skills 三级加载系统

> 版本：v1.0 | 日期：2026-07-18 | 状态：draft | 模块名：`skills`
>
> **定位**：扩展性创新点（加分项）。为普罗米修斯引入轻量级、可复用的“技能（Skill）”层，与 Subagent（重）形成“重/轻”双层扩展体系。

## 1. 背景

### 1.1 问题描述

v3.1 方案已有两层扩展能力，但仍存在空白：

| 已有能力 | 单位 | 激活方式 | 安装成本 | 局限 |
|---------|------|---------|---------|------|
| Subagent（5 个官方） | functions.jsonl + scripts/ + engine.py | Router 路由分发 | 重（含 Python 依赖、引擎、工具注册、FR 热重载） | 适合“新增一类能力”，不适合“复用一段 know-how” |
| 即时偏好引擎 | memory 表中的 key/value | 请求前注入 | 轻 | 只记内容生成偏好（格式/风格），无法承载多步流程、模板、校验清单 |

真实场景里，用户常需要"一段可复用的做事方法"：

- "我们团队的周报必须含里程碑章节和风险红绿灯"——一段写作规范，不是新 Subagent。
- "这个研究项目的笔记统一用某套标签体系"——一段约定，不该写死进系统。
- "我个人习惯先把待办按四象限分类再排优先级"——一段个人工作流。

这些是**指令级**的复用（一段 Markdown 流程 + 可选脚本/模板），既没必要新增一个带工具的 Subagent，也超出了偏好引擎的 key/value 表达力。OpenClaw 与 Hermes 均通过 `SKILL.md` 技能机制解决该问题，且都采用"多目录分层 + 按名称优先级覆盖"的加载模型。

### 1.2 设计目标

| 目标 | 说明 |
|------|------|
| **三级分层** | 系统级 / 用户级 / 项目级三个目录，职责清晰 |
| **优先级覆盖** | 同名技能按 项目级 > 用户级 > 系统级 覆盖 |
| **轻量无安装** | 一个 `SKILL.md` 即一个技能，丢进目录即生效，无需 pip/重载依赖 |
| **按需加载** | 技能索引（name+description）常驻路由提示词；正文按需 `skill_load` 拉取，控制 token 成本 |
| **Subagent 感知** | 技能可声明 `applies_to`，只注入到相关 Subagent 上下文 |
| **项目上下文自适应** | 普罗米修斯作为个人认知智能体，能根据"当前所在项目"自动加载项目级技能 |
| **独立分发** | 技能随仓库版本控制或手工放置，独立分发 |

### 1.3 与赛题加分项的关系

赛题列出三个加分项（Router 自学习、可视化路由追踪、开箱即用）。Prometheus 实现 Router 自学习与开箱即用，并新增 Skills 三级加载作为**扩展性创新点**，强化产品化与可扩展性：

- 强化"开箱即用"——系统级预置一批通用技能，装好即用；
- 强化"可复用与可扩展性"（设计方案 §8.5）——标准 `SKILL.md` 格式，社区可贡献；
- 为 Router 自学习喂料——技能可声明触发关键词，参与路由权重学习（§6.1）。

## 2. 调研

### 2.1 OpenClaw 技能系统

调研对象：`~/ws/openclaw/src/skills/`。

**六级加载源与优先级**（`src/skills/loading/workspace.ts:1149-1235`），从低到高：

| 优先级 | source 标签 | 目录 |
|--------|------------|------|
| 1（最低） | `openclaw-extra` | `config.skills.load.extraDirs[]` + 插件技能符号链接 |
| 2 | `openclaw-bundled` | `<packageRoot>/skills`（随应用发布） |
| 3 | `openclaw-managed` | `~/.openclaw/skills` |
| 4 | `agents-skills-personal` | `~/.agents/skills` |
| 5 | `agents-skills-project` | `<workspace>/.agents/skills` |
| 6（最高） | `openclaw-workspace` | `<workspace>/skills` |

**优先级机制**（`workspace.ts:1216-1235`）：按"低→高"顺序向 `Map<name, record>` 逐层 `set`，**后写入者覆盖先写入者**（last-write-wins），以 frontmatter `name` 为键。由 `workspace-precedence.test.ts`、`agents-directory.test.ts` 测试覆盖。

**SKILL.md 格式**（`src/skills/loading/frontmatter.ts`、`local-loader.ts:62-66`）：

```yaml
---
name: 1password                    # 必填，优先级 Map 键
description: "Set up and use ..."  # 必填，触发短语，渲染进提示词
homepage: https://...              # 可选
metadata: { "openclaw": { "emoji": "🔐", "requires": { "bins": ["op"] },
  "install": [{"kind":"brew","formula":"1password-cli"}] } }  # JSON5
allowed-tools: ["message"]         # 可选，工具白名单
user-invocable: true               # 可选，默认 true，生成 /<name> 斜杠命令
disable-model-invocation: false    # 可选，默认 false，对模型隐藏
version: 1.0.0                     # 可选
---
```

缺 `name` 或 `description` 的技能在加载时被拒绝。

**混合调用**（`skill-contract.ts:34-58`、`command-specs.ts`）：
- 模型驱动：技能以 `<available_skills>` 注入系统提示词，模型用 `read` 工具按 `description` 匹配加载；
- 命令驱动：每个 `user-invocable` 技能生成 `/<skill-name>` 斜杠命令。

**按 Agent 过滤**（`agent-filter.ts:25-37`、`filter.ts:8-13`）：三态语义——`undefined`=全部启用、`[]`=全禁用、非空=白名单。

**安装落点**（`lifecycle/archive-install.ts:67-78`）：所有安装写入最高优先级的 `<workspace>/skills/<slug>`，使安装立即覆盖内置。

**可借鉴点**：① 有序 Map 后写覆盖的优先级模型简洁可证；② `name`+`description` 最小契约；③ 混合调用（模型驱动 + 斜杠命令）；④ 按 Agent 白名单三态过滤；⑤ 安装落最高层。

### 2.2 Hermes 技能系统

调研对象：`~/ws/hermes-agent/`。

**两级运行时 + 同步期播种**（`tools/skills_tool.py:695-699`、`agent/skill_commands.py:336-339`）：

| 层 | 目录 | 性质 |
|----|------|------|
| 本地（user） | `~/.hermes/skills/` | 唯一读写源，总是最先扫描 |
| 外部（external） | `config.yaml: skills.external_dirs[]` | 只读，可配多条（如 `~/.agents/skills`、`/home/shared/team-skills`） |

**优先级机制**（`skills_tool.py:716-739`）：按扫描顺序**先到先得**（first-writer-wins），`seen_names` 去重，本地优先。**无项目级（cwd 相对）目录**，项目技能只能手工加进 `external_dirs`。

**同步期播种**（`tools/skills_sync.py:483-660`）：bundled（`skills/`）随安装/更新复制进 `~/.hermes/skills/`；optional（`optional-skills/`）需 `hermes skills install <id>` 显式安装。带 manifest（`.bundled_manifest`）记录 origin hash，**用户改过的副本不被覆盖**（`:635-640`）。

**SKILL.md 格式**（`tools/skill_manager_tool.py:524-560` 校验器）：仅强校验 `name`（≤64，正则 `^[a-z0-9][a-z0-9._-]*$`）与 `description`（≤1024）；约定字段 `version/author/license/platforms/metadata.hermes.{tags,related_skills,config}`；全文 ≤ 100k 字符。

**渐进式披露**（`agent/prompt_builder.py:1460-1690`）：
- Tier-1：`skills_list` 仅 name+description 进系统提示词（分类分组）；
- Tier-2：`skill_view(name)` 拉取完整 SKILL.md；
- Tier-3：`skill_view(name, file_path="references/x.md")` 拉取引用文件。

**禁用**（`hermes_cli/skills_config.py`）：`skills.disabled`（全局）+ `skills.platform_disabled`（按平台，与全局取并集）。

**可借鉴点**：① 渐进式披露控制 token 成本（索引常驻、正文按需）；② 同步 manifest 保护用户修改不被覆盖；③ `external_dirs` 配置项是项目级目录的自然落点；④ 平台/环境门控字段。

### 2.3 结论

| 设计决策 | 来源 | 取舍 |
|---------|------|------|
| 三级目录（系统/用户/项目） | OpenClaw 六级简化 | 砍掉 extra/plugin/workspace，保留 bundled→personal→project 三层，对个人智能体够用且易解释 |
| 优先级：项目 > 用户 > 系统 | OpenClaw 后写覆盖 | 比 Hermes 的"先到先得"更直观地表达"项目覆盖用户覆盖系统" |
| `SKILL.md` 最小契约 `name`+`description` | 两者一致 | 行业事实标准（Anthropic Skill 格式） |
| 渐进式披露 | Hermes | 索引常驻路由提示词，正文 `skill_load` 按需拉取 |
| 混合调用（模型驱动 + 斜杠命令） | OpenClaw | 路由模型/Subagent 按描述加载 + `/skill` 直达 |
| 按 Subagent 过滤（三态） | OpenClaw 按 Agent 过滤 | `applies_to` 字段，空=全部 |
| 安装落用户级 | OpenClaw 落最高层、Hermes 落本地 | 技能轻量，`skills create` 默认写用户级，项目级用 `--tier project` |
| 同步保护 | Hermes manifest | 系统级技能升级时不覆盖用户/项目级同名覆盖 |

## 3. 设计决策

### 3.1 三级架构

```
优先级（低 → 高）:
  系统级  ~/.function-router/skills/   ← 随 MTClaw FR 安装/管理，全机共享
    ──►  用户级  ~/.agents/skills/        ← 用户个人技能，跨项目共享
      ──►  项目级  ./.agents/skills/       ← 随项目版本控制，仅当前项目

后加载覆盖先加载: project > user > system
```

| 层级 | 目录 | 职责 | 类比 OpenClaw | 写入者 |
|------|------|------|--------------|--------|
| 系统级 | `~/.function-router/skills/` | 随 MTClaw FR 发布的通用技能（写作规范、检索技巧、通用模板） | `openclaw-managed` + `openclaw-bundled` | FR 安装脚本 / `prometheus skills install` |
| 用户级 | `~/.agents/skills/` | 用户个人技能与工作流，跨所有项目生效 | `agents-skills-personal` | `prometheus skills create --tier user` |
| 项目级 | `./.agents/skills/` | 当前项目专属技能，随仓库版本控制 | `agents-skills-project` | `prometheus skills create --tier project` / 手工提交 |

**路径可配置**（§4.1）：三级路径均可用环境变量或 config 覆盖，便于赛题评委设备适配与测试。

**为何系统级放在 `~/.function-router/`**：系统级技能属于 MTClaw FR 平台资产（随 FR 安装、随 FR 升级），与普罗米修斯的用户数据 `~/.prometheus/` 分离——平台技能不混入用户数据，升级互不干扰。这与 OpenClaw 把 managed 技能放 `~/.openclaw/skills`、把用户数据另存的设计一致。

### 3.2 Skill 目录结构

```
~/.function-router/skills/weekly-report/     # 一个技能 = 一个目录
  ├── SKILL.md            # 必填：frontmatter + 指令正文
  ├── templates/          # 可选：模板/样例
  │   └── three-section.md
  ├── scripts/            # 可选：辅助脚本（Bash/Python）
  │   └── extract_milestones.sh
  └── references/         # 可选：渐进式披露的引用文档
      └── style-guide.md
```

最小技能只需一个 `SKILL.md`（无 scripts/templates）。`scripts/` 内脚本通过 `skill_load(name, file_path="scripts/x.sh")` 按需读取，不自动执行。

### 3.3 SKILL.md 清单格式

```yaml
---
name: weekly-report-zh                       # 必填，kebab-case，优先级键
description: "中文周报写作技能。用户要求写周报、本周总结、weekly report 时加载。提供三段式结构与 Markdown 排版规范。"  # 必填，触发短语
version: 1.0.0                               # 可选，语义化版本
category: writing                            # 可选，knowledge/writing/schedule/chat/memory/other
applies_to: [writing]                        # 可选，生效 Subagent 列表；空/缺省=全部
user_invocable: true                         # 可选，默认 true，生成 /weekly-report-zh 斜杠命令
disable_model_invocation: false              # 可选，默认 false，对路由模型隐藏
metadata:                                    # 可选，JSON 对象
  emoji: "📝"
  requires: { bins: [], python: [] }
  trigger_keywords: ["周报", "本周总结"]       # 可选，喂给 Router 自学习（§6.1）
---

# 中文周报技能

## 何时使用
- 用户说"写周报"/"本周总结"/"weekly report"
- 写作 Subagent 收到 doc_type=weekly_report

## 流程
1. 调 memory_recall 注入用户周报偏好
2. 按"本周完成 / 下周计划 / 风险与问题"三段式生成
3. ...

## 校验清单
- [ ] 含本周完成项
- [ ] 含下周计划
- [ ] 风险用红/黄/绿标记
```

**字段说明**：

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 唯一标识（kebab-case，正则 `^[a-z0-9][a-z0-9._-]*$`，≤64 字符），优先级 Map 键 |
| `description` | 是 | 触发短语，渲染进路由提示词 `<available_skills>`，≤512 字符 |
| `version` | 否 | 语义化版本，用于升级比对 |
| `category` | 否 | 分类，便于组织与检索 |
| `applies_to` | 否 | 生效 Subagent 名列表（rag/memory/writing/schedule/chat）；空/缺省=对所有 Subagent 生效 |
| `user_invocable` | 否 | 默认 true；true 则生成 `/<name>` 斜杠命令 |
| `disable_model_invocation` | 否 | 默认 false；true 则不进 `<available_skills>`（仅斜杠命令可达） |
| `metadata` | 否 | JSON：`emoji`、`requires`（依赖提示）、`trigger_keywords`（喂路由学习） |

**校验规则**（`validate_skill_manifest()`）：缺 `name`/`description` 拒绝；`name` 不合正则拒绝；`description` 超长截断并告警；全文 ≤ 100k 字符。

### 3.4 优先级解析算法

采用 OpenClaw 的"有序加载 + 后写覆盖"（last-write-wins）：

```python
# skills_engine.py
TIERS = [
    ("system",  "~/.function-router/skills"),   # 最低
    ("user",    "~/.agents/skills"),
    ("project", "./.agents/skills"),             # 最高
]

def load_all_skills(cwd: str = None) -> dict[str, SkillRecord]:
    """三级加载，project > user > system（后加载覆盖先加载）。"""
    merged: dict[str, SkillRecord] = {}
    for tier_name, tier_dir in TIERS:
        tier_dir = resolve_path(tier_dir, cwd=cwd)
        if not tier_dir.exists():
            continue
        for skill_dir in iter_skill_dirs(tier_dir):
            skill = parse_skill_md(skill_dir / "SKILL.md")
            if skill is None:
                continue  # 校验失败的技能跳过并记日志
            merged[skill.name] = SkillRecord(
                skill=skill,
                tier=tier_name,
                source_path=skill_dir,
                overridden_by=[],  # 见下
            )
    # 标注覆盖关系：被高优先级覆盖的记录标记 overridden
    return merged
```

**覆盖关系可观测**：`SkillRecord` 记录最终生效层与被覆盖层，`skills info <name>` 与 `skills doctor` 展示覆盖链（`system → user → project`），让用户清楚为何某技能行为如此。

**与 Hermes 同步保护的差异**：普罗米修斯不做"复制进本地"的播种，而是**运行时直接扫描三级目录**——系统级升级后立即生效，用户/项目级覆盖不被改写（因为它们本就在更高优先级目录，不会被系统级覆盖）。

### 3.5 加载与发现流程

```
FR 启动 / POST /v1/reload
  │
  ├── 1. 扫描三级目录（system → user → project）
  ├── 2. 解析每个 SKILL.md，校验 name+description
  ├── 3. 按名称后写覆盖，得到 merged 技能表
  ├── 4. 过滤禁用项（config.skills.disabled）+ 平台门控
  ├── 5. 构建 Tier-1 索引：[{name, description, category, applies_to}]
  ├── 6. 索引快照写入 ~/.prometheus/skills/.skills_index.json（加速重启）
  └── 7. 将索引注入路由提示词 <available_skills>（仅 name+description，省 token）

运行时调用（渐进式披露）:
  路由模型 / Subagent 看到 <available_skills>
    │
    ├── Tier-1: skills_list() → 返回索引（已在提示词中，零额外成本）
    ├── Tier-2: skill_load(name) → 返回完整 SKILL.md 正文（按需）
    └── Tier-3: skill_load(name, file_path="references/x.md") → 返回引用文件
```

**`<available_skills>` 注入示例**（路由提示词片段）：

```
<available_skills>
  <skill>
    <name>weekly-report-zh</name>
    <description>中文周报写作技能...</description>
    <category>writing</category>
    <applies_to>writing</applies_to>
    <version>1.0.0</version>
  </skill>
  <skill> ... </skill>
</available_skills>
当任务匹配某技能 description 时，调用 skill_load(name) 加载并遵循其指令。
```

### 3.6 发现与调用

**双通道调用**（参考 OpenClaw 混合模式）：

| 通道 | 机制 | 触发 | 适用 |
|------|------|------|------|
| 模型驱动 | 路由模型/Subagent 按 `description` 匹配，调用 `skill_load(name)` | 自动 | 日常使用，用户无感 |
| 斜杠命令 | `/<skill-name>` 或 `/skill <name> [args]` | 用户主动 | 精确指定技能 |

**模型驱动调用流程**：

```
用户: "写周报"
  │
  ├── FR 路由 → writing Subagent
  ├── writing Subagent 上下文含 <available_skills>
  ├── 路由模型判断 weekly-report-zh 描述匹配 → 调 skill_load("weekly-report-zh")
  ├── 返回 SKILL.md 正文 → 注入 Subagent 上下文
  └── writing_generate 按"三段式 + 红黄绿风险"生成周报
```

**按 Subagent 过滤**（`applies_to`）：构建某 Subagent 上下文时，只注入 `applies_to` 含该 Subagent（或为空）的技能索引，减少噪声。三态语义同 OpenClaw：`applies_to` 缺省=对所有 Subagent 生效；`[]`=对任何 Subagent 都不自动注入（仅斜杠命令可达）；非空=白名单。

### 3.7 与 MTClaw FR 的集成（分层）

沿用本方案既有的"分层落点"模式（FR 暴露通用能力，普罗米修斯外层做差异化，见 [add-router-learning.md](add-router-learning.md) §3.6）：

**FR 层（通用能力，可上游贡献）**：

- FR 暴露 builtin 工具 `skill_load(name, file_path=None)` 与 `skills_list()`：读取指定目录的技能文件并返回内容。纯文件读取，不含优先级逻辑，对任何 FR 用户通用。
- 若 MTClaw FR 尚无该 builtin，提小 PR 补充（与 `find/ls/cat/grep/sleep` 同级，属通用文件工具）。

**普罗米修斯层（差异化）**：

- 三级目录扫描 + 优先级覆盖（§3.4）
- 索引构建 + `<available_skills>` 注入路由提示词（§3.5）
- 按 Subagent 过滤（§3.6）
- CLI `prometheus skills ...`（§4.3）
- 与 Router 自学习联动（§6.1）

```
FR 启动流程（普罗米修斯扩展）:
  ├── 加载基础配置 + subagents 工具定义（安装时静态聚合）
  ├── [新增] skills_engine.load_all_skills() 扫描三级目录
  ├── [新增] 构建 Tier-1 索引，注入路由提示词
  ├── [新增] 注册 skill_load / skills_list 为 FR builtin 工具
  └── 启动 FR 服务
```

### 3.8 CLI

```bash
# 浏览
prometheus skills list [--tier system|user|project] [--category <cat>]
  -> 列出所有生效技能，标注来源层级与是否被覆盖

prometheus skills info <name>
  -> 显示正文摘要、来源层级、覆盖链、applies_to、版本

prometheus skills paths
  -> 显示三级目录实际路径（含环境变量解析后）

# 创建
prometheus skills create <name> [--tier user|project] [--category <cat>]
  -> 在指定层级生成 SKILL.md 骨架（默认 user）

# 管理
prometheus skills reload
  -> 重建索引并热重载 FR（POST /v1/reload）

prometheus skills enable <name> / disable <name>
  -> 写入 config.skills.disabled（禁用不删文件）

prometheus skills doctor
  -> 诊断：覆盖冲突、缺 name/description 的非法技能、孤儿引用文件
```

### 3.9 与 Subagent 的关系

| 维度 | Subagent | Skill（三级加载） |
|------|----------|------------------|
| 单位 | functions.jsonl + scripts/ + engine.py | SKILL.md（+ 可选 templates/scripts/references） |
| 性质 | 可执行工具集 | 指令/流程/模板（上下文） |
| 激活 | Router 路由分发 | 模型按描述加载 / 斜杠命令 |
| 安装成本 | 重（依赖、引擎、工具注册、FR 热重载） | 轻（丢进目录即生效） |
| 分发 | 随仓库版本控制（subagents/ 目录） | 随仓库版本控制 / 手工放置 |
| 影响 | 新增一类能力 | 复用一段 know-how，增强已有 Subagent |

**协同方式**：

1. **技能增强 Subagent**：技能 `applies_to` 指定 Subagent，注入其上下文（如 `weekly-report-zh` 增强 writing Subagent）。
2. **技能不新增工具**：技能只提供指令与模板，不注册 functions.jsonl 工具，避免膨胀路由模型工具数（保持 16 工具的准确率优势）。

### 3.10 预置系统级技能

随 MTClaw FR 安装时预置到 `~/.function-router/skills/`（开箱即用）：

| 技能 | category | applies_to | 说明 |
|------|----------|-----------|------|
| `weekly-report-zh` | writing | writing | 中文三段式周报规范 |
| `meeting-minutes-zh` | writing | writing | 会议纪要（议题/讨论/决议/待办） |
| `note-tagging` | knowledge | rag | 笔记标签体系约定 |
| `task-eisenhower` | schedule | schedule | 四象限待办分类法 |
| `polish-academic` | writing | writing | 学术润色要点 |

预置技能可被用户级/项目级同名技能覆盖（演示三级覆盖的素材）。

### 3.11 演示剧本

```
评委: "技能系统的三级覆盖怎么体现？"

演示:
  # 1. 系统级有通用周报技能
  prometheus skills list --tier system
  -> weekly-report-zh (system) - 通用三段式周报

  # 2. 用户级覆盖：用户自定义周报格式
  prometheus skills info weekly-report-zh
  -> 生效来源: user (覆盖 system)
  -> 路径: ~/.agents/skills/weekly-report-zh/SKILL.md
  -> 差异: 含个人签名档

  # 3. 项目级再覆盖：当前项目有特殊周报要求
  cd ~/hicool-project && prometheus skills info weekly-report-zh
  -> 生效来源: project (覆盖 user > system)
  -> 路径: ./.agents/skills/weekly-report-zh/SKILL.md
  -> 差异: 含项目里程碑章节

  # 4. 实际效果：写周报自动用项目级技能
  用户: "写周报"
  -> 路由 writing Subagent
  -> skill_load(weekly-report-zh) 加载项目级版本
  -> 生成含里程碑章节的周报

  # 5. 切换项目即切换技能集
  cd ~/personal-notes && prometheus skills info weekly-report-zh
  -> 生效来源: user (项目级不存在，回退用户级)
  -> 展示"项目上下文自适应"
```

## 4. 模块规格

### 4.1 配置

```json
{
  "skills": {
    "tier_dirs": {
      "system": "~/.function-router/skills",
      "user": "~/.agents/skills",
      "project": "./.agents/skills"
    },
    "disabled": [],
    "max_skills_in_prompt": 20,
    "max_skill_file_bytes": 51200,
    "auto_reload_fr": true,
    "index_snapshot": true
  }
}
```

环境变量覆盖（优先于 config）：`PROMETHEUS_SKILLS_SYSTEM_DIR` / `PROMETHEUS_SKILLS_USER_DIR` / `PROMETHEUS_SKILLS_PROJECT_DIR`。项目级目录相对当前工作目录解析。

### 4.2 Python 引擎接口

```python
# skills_engine.py

def load_all_skills(cwd: str = None) -> dict[str, SkillRecord]:
    """三级扫描 + 后写覆盖，返回生效技能表。"""

def get_skill_index(subagent: str = None) -> list[dict]:
    """Tier-1 索引：[{name, description, category, applies_to, version}]。
    subagent 非空时按 applies_to 过滤。"""

def load_skill(name: str, file_path: str = None) -> dict:
    """Tier-2/3：返回 SKILL.md 正文或引用文件内容。"""

def parse_skill_md(path: Path) -> Skill | None:
    """解析 + 校验 SKILL.md frontmatter。"""

def validate_skill_manifest(skill: Skill) -> tuple[bool, str]:
    """校验 name/description 合法性。"""

def create_skill(name: str, tier: str, category: str = None) -> dict:
    """在指定层级生成 SKILL.md 骨架。"""

def reload_skills() -> dict:
    """重建索引 + 热重载 FR。"""

def list_overrides(name: str) -> list[dict]:
    """返回某技能的覆盖链（system→user→project 各层是否存在）。"""

def doctor() -> dict:
    """诊断覆盖冲突、非法技能、孤儿引用。"""
```

### 4.3 CLI 完整命令

```bash
prometheus skills list [--tier <tier>] [--category <cat>]
prometheus skills info <name>
prometheus skills paths
prometheus skills create <name> [--tier user|project] [--category <cat>]
prometheus skills reload
prometheus skills enable <name>
prometheus skills disable <name>
prometheus skills doctor
```

### 4.4 FR builtin 工具定义（functions.jsonl 片段）

```jsonl
{"name":"skills_list","description":"列出当前可用的技能（name+description 索引）。可选按 subagent 过滤。","parameters":{"type":"object","properties":{"subagent":{"type":"string","description":"可选：仅列出对该 Subagent 生效的技能"}},"required":[]}}
{"name":"skill_load","description":"加载某技能的完整指令正文（SKILL.md），用于遵循其做事流程。当任务匹配某技能描述时调用。","parameters":{"type":"object","properties":{"name":{"type":"string","description":"技能名（kebab-case）"},"file_path":{"type":"string","description":"可选：技能目录内引用文件的相对路径，如 references/x.md"}},"required":["name"]}}
```

> 这 2 个 builtin 工具计入 FR 暴露给路由模型的工具集。v3.1 为 16 自定义 + 5 MTClaw builtin = 21；新增 2 个 skill builtin 后为 16 + 7 = 23。研究表明工具数 <15 时准确率最高 [推测]，23 略超最佳线，但 skill_load/skills_list 属"元工具"（仅在需要加载技能时调用，不参与意图路由判断），对路由准确率影响可控；若实测有损，可将 `skills_list` 从提示词工具集移出（索引已直接注入提示词，无需路由模型主动列出）。

## 5. 实现 Checklist

### 数据层

- [ ] SKL-001 定义 `SKILL.md` frontmatter schema（JSON Schema）
- [ ] SKL-002 定义 `SkillRecord` 数据结构（skill + tier + source_path + overridden_by）
- [ ] SKL-003 创建 `~/.prometheus/skills/.skills_index.json` 索引快照格式
- [ ] SKL-004 创建 `config.skills` 配置 schema（tier_dirs / disabled / limits）

### 加载与优先级

- [ ] SKL-005 实现 `parse_skill_md()` - frontmatter 解析（YAML）
- [ ] SKL-006 实现 `validate_skill_manifest()` - name/description 校验
- [ ] SKL-007 实现三级目录扫描（system → user → project）
- [ ] SKL-008 实现后写覆盖优先级（Map by name，project > user > system）
- [ ] SKL-009 实现覆盖链标注（`list_overrides()`）
- [ ] SKL-010 实现路径解析（环境变量覆盖 + 项目级相对 cwd）
- [ ] SKL-011 实现禁用过滤（config.skills.disabled）

### 发现与调用

- [ ] SKL-012 实现 `get_skill_index()` - Tier-1 索引构建
- [ ] SKL-013 实现按 Subagent 过滤（applies_to 三态语义）
- [ ] SKL-014 实现 `<available_skills>` 提示词片段渲染
- [ ] SKL-015 实现 `load_skill()` - Tier-2 正文加载
- [ ] SKL-016 实现 `load_skill(file_path=)` - Tier-3 引用文件加载
- [ ] SKL-017 实现索引快照写入/读取（加速重启）

### FR 集成（分层）

> 分层落点：FR 暴露 `skill_load`/`skills_list` 通用 builtin（可上游贡献），普罗米修斯外层做三级优先级与注入（差异化）。

**FR 层（通用能力）**：
- [ ] SKL-018 [FR·配置] FR 暴露 `skill_load` / `skills_list` builtin 工具（若 MTClaw 无，提小 PR 补充）

**普罗米修斯层（差异化）**：
- [ ] SKL-019 FR 启动时调用 `load_all_skills()` 扫描三级目录
- [ ] SKL-020 将 Tier-1 索引注入路由提示词 `<available_skills>`
- [ ] SKL-021 注册 `skill_load`/`skills_list` 到 functions.jsonl
- [ ] SKL-022 实现 `POST /v1/reload` 触发技能重载

### CLI

- [ ] SKL-023 实现 `prometheus skills list`（含 --tier / --category 过滤）
- [ ] SKL-024 实现 `prometheus skills info <name>`（含覆盖链展示）
- [ ] SKL-025 实现 `prometheus skills paths`
- [ ] SKL-026 实现 `prometheus skills create <name>`（骨架生成）
- [ ] SKL-027 实现 `prometheus skills reload`
- [ ] SKL-028 实现 `prometheus skills enable/disable`
- [ ] SKL-029 实现 `prometheus skills doctor`（诊断冲突/非法/孤儿）

### 预置与演示

- [ ] SKL-030 预置 5 个系统级技能（weekly-report-zh / meeting-minutes-zh / note-tagging / task-eisenhower / polish-academic）
- [ ] SKL-031 准备演示用用户级覆盖技能（weekly-report-zh 含签名档）
- [ ] SKL-032 准备演示用项目级覆盖技能（weekly-report-zh 含里程碑章节）
- [ ] SKL-033 演示剧本：三级覆盖 + 项目上下文自适应

### 测试

- [ ] SKL-034 单元测试：SKILL.md 解析（合法/非法 frontmatter）
- [ ] SKL-035 单元测试：三级优先级覆盖（同名 project>user>system）
- [ ] SKL-036 单元测试：按 Subagent 过滤（applies_to 三态）
- [ ] SKL-037 单元测试：路径解析（环境变量 + cwd 相对）
- [ ] SKL-038 集成测试：skill_load 端到端（路由 → 加载 → 注入 → 生成）
- [ ] SKL-039 集成测试：FR 热重载（新增技能后立即可用）
- [ ] SKL-040 集成测试：项目切换后技能集变化（项目级回退用户级）

## 6. 与其他模块的关系

### 6.1 与 Router 自学习引擎的关系

Router 自学习引擎（[add-router-learning.md](add-router-learning.md)）从技能的 `metadata.trigger_keywords` 与 `applies_to` 读取路由线索：

- 技能声明的 `trigger_keywords` 作为路由关键词权重的初始种子（喂给 `routing_keyword_weights` 表）；
- 技能 `applies_to` 暗示"含这些关键词的请求应路由到该 Subagent"；
- 用户对"技能是否被正确加载"的反馈，可作为路由修正信号（如加载了 `weekly-report-zh` 但用户说"不是这种格式"→ 记录修正）。

### 6.2 与即时偏好引擎的关系

即时偏好引擎（设计方案 §2.6.7）负责内容生成偏好（key/value），技能负责多步流程/模板。两者互补：

- 偏好："writing_format=markdown"（值）
- 技能："weekly-report-zh"（流程：先 recall 偏好 → 三段式 → 红黄绿风险）

技能在流程中调用 `memory_recall` 消费偏好，两者协同而非重叠。

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| 工具数膨胀影响路由准确率 | `skill_load`/`skills_list` 为元工具，不参与意图路由；`skills_list` 可移出工具集（索引已注入提示词） |
| 技能正文过长撑爆上下文 | 渐进式披露：索引常驻（仅 name+desc），正文按需 `skill_load`；`max_skills_in_prompt` / `max_skill_file_bytes` 限制 |
| 项目级技能随仓库泄露隐私 | 项目级 `.agents/skills/` 随仓库版本控制，文档提示用户勿放敏感信息；`skills doctor` 检测疑似密钥 |
| 三级覆盖导致行为不可预期 | `skills info`/`skills doctor` 展示覆盖链；系统级升级不覆盖更高优先级层 |
| 技能质量参差 | 系统级由官方维护；用户/项目级自担；`disable_model_invocation` 可让低质量技能仅斜杠命令可达 |
| 技能脚本执行安全 | `scripts/` 不自动执行，仅 `skill_load(file_path=)` 按需读取；执行需经 Bash 工具受既有路径白名单约束 |
| 索引重建慢 | 索引快照 `.skills_index.json` 加速重启；仅 `reload` 时全量扫描 |

## 8. 参考

- OpenClaw 技能系统：`~/ws/openclaw/src/skills/`
  - 加载与优先级：`loading/workspace.ts:1149-1235`、`loading/frontmatter.ts`、`loading/local-loader.ts`
  - 发现与调用：`discovery/skill-index.ts`、`discovery/command-specs.ts`、`discovery/agent-filter.ts`
  - 生命周期：`lifecycle/install.ts`、`lifecycle/archive-install.ts`
- Hermes 技能系统：`~/ws/hermes-agent/`
  - 加载与优先级：`tools/skills_tool.py:695-739`、`agent/skill_commands.py:336-339`
  - 同步播种：`tools/skills_sync.py:483-660`
  - 渐进式披露：`agent/prompt_builder.py:1460-1690`
  - 校验：`tools/skill_manager_tool.py:524-560`
  - 技能创作指南：`skills/software-development/hermes-agent-skill-authoring/SKILL.md`
- Anthropic Claude Skill 格式（行业事实标准）：`name`+`description` frontmatter + SKILL.md 正文 + 渐进式 references/scripts/templates
