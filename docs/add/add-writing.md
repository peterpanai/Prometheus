# ADD — 写作润色翻译 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`writing`

## 1. 背景

用户需要场景化的文档生成（周报、邮件、技术文档）、文本润色和多语言翻译。核心能力依赖上游 LLM，Function Router 的价值在于自动注入用户偏好记忆、参数标准化、快速路由。

## 2. 调研

### 2.1 Hermes

- **无专门写作工具**：Hermes 通过通用 LLM 对话处理写作请求
- **代码执行可写文件**：`tools/code_execution_tool.py` 可程序化生成文档
- **delegate_task**：可 spawn 子 agent 专门处理写作任务
- **系统提示词**：`agent/system_prompt.py` 中包含写作指导

### 2.2 OpenClaw

- **无专门写作工具**：通过 LLM 直接生成文本
- **文件操作工具**：`write_file`、`patch`、`replace_file` 等可写入生成结果
- **Skills 系统**：可通过 skills 提供写作模板和指导
- **Subagent spawn**：`sessions_spawn` 可创建专门写作子代理

### 2.3 Codex

- **Apply Patch**：`apply_patch.rs` — 将 LLM 生成内容写入文件
- **无专门写作工具**：通过通用工具组合（shell + file + LLM）实现

### 2.4 结论

没有代码库提供专门的写作 Subagent。写作类功能完全依赖 LLM 的生成能力，工具层只做参数适配和格式注入。对于 Prometheus，写作 Subagent 的核心差异化在于**自动注入用户记忆中的写作偏好**（格式、风格、语言），实现"越用越懂你"的写作体验。

## 3. 设计决策

### 3.1 模板系统

预置常用文档模板，根据 `doc_type` 选择：

```
templates/
├── weekly_report.md      # 周报：本周完成 / 下周计划 / 风险与问题
├── email_formal.md       # 正式邮件：称呼 / 正文 / 签名
├── email_casual.md       # 非正式邮件
├── tech_doc.md           # 技术文档：概述 / 架构 / 接口 / 部署
├── meeting_minutes.md    # 会议纪要：议题 / 讨论 / 决议 / TODO
├── article.md            # 文章：标题 / 摘要 / 正文 / 结论
└── ppt_outline.md        # PPT 大纲：Slide-by-slide
```

### 3.2 偏好注入流水线

```
writing_generate(doc_type, topic, key_points, style, length) →
  1. memory_recall(context=f"writing {doc_type}") → 获取用户偏好
  2. 加载模板 templates/{doc_type}.md
  3. 构造 prompt:
     system: 模板 + 用户偏好 + 通用写作指导
     user: topic + key_points + style + length
  4. 调用上游 LLM 生成
  5. 返回 Markdown 格式文档
```

### 3.3 参数标准化

- `doc_type`：枚举 7 种类型，避免 LLM 歧义
- `style`：枚举 4 种风格（formal/casual/technical/academic），映射到不同的 prompt 指导
- `length`：枚举 3 种篇幅（short/medium/long），映射到 token 预算
- `goal`（润色）：枚举 5 种目标（more_professional/more_concise/more_friendly/fix_grammar/more_technical）

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "writing",
  "version": "1.0.0",
  "description": "写作润色翻译 Subagent — 场景化文档生成、润色、多语言翻译",
  "enabled": true,
  "priority": 6,
  "requires": {
    "plugins": ["memory"],
    "packages": []
  },
  "provides": {
    "tools": ["writing_generate", "writing_polish", "writing_translate"],
    "engines": ["writing_engine.py"]
  },
  "routing": {
    "trigger_keywords": ["帮我写", "生成", "起草", "润色", "翻译", "优化", "translate"],
    "trigger_patterns": ["帮我写.*", "生成一份.*", "起草.*", "翻译.*", "润色.*"],
    "match_priority": "normal"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.3，3 个工具：`writing_generate`、`writing_polish`、`writing_translate`。

### 4.3 Python 引擎接口

```python
# writing_engine.py
def generate(doc_type: str, topic: str, key_points: list[str], style: str, length: str,
             upstream_url: str, upstream_model: str, upstream_key: str) -> dict
def polish(text: str, goal: str, target_language: str,
           upstream_url: str, upstream_model: str, upstream_key: str) -> dict
def translate(text: str, source_lang: str, target_lang: str, keep_formatting: bool,
              upstream_url: str, upstream_model: str, upstream_key: str) -> dict
```

## 5. 实现 Checklist

### 模板系统

- [ ] WRT-001 创建 `templates/` 目录
- [ ] WRT-002 编写 `weekly_report.md` 模板
- [ ] WRT-003 编写 `email_formal.md` 模板
- [ ] WRT-004 编写 `tech_doc.md` 模板
- [ ] WRT-005 编写 `meeting_minutes.md` 模板
- [ ] WRT-006 编写 `article.md` 模板
- [ ] WRT-007 编写 `ppt_outline.md` 模板

### 核心引擎

- [ ] WRT-008 实现 `writing_engine.py` — `generate()` 主函数
- [ ] WRT-009 实现偏好注入：调用 `memory_engine.recall()` 获取用户写作偏好
- [ ] WRT-010 实现模板加载与渲染
- [ ] WRT-011 实现 prompt 构造（system: 模板 + 偏好 + 指导, user: 参数）
- [ ] WRT-012 实现上游 LLM 调用（httpx → OpenAI-compatible API）
- [ ] WRT-013 实现 `polish()` — 润色 prompt 模板 + 偏好注入
- [ ] WRT-014 实现 `translate()` — 翻译 prompt 模板 + 格式保持
- [ ] WRT-015 实现 `changes_summary` 生成（润色前后 diff 摘要）

### Wrapper 脚本

- [ ] WRT-016 编写 `writing_generate.sh`
- [ ] WRT-017 编写 `writing_polish.sh`
- [ ] WRT-018 编写 `writing_translate.sh`

### 测试

- [ ] WRT-019 单元测试：模板渲染正确性
- [ ] WRT-020 单元测试：prompt 构造（偏好注入验证）
- [ ] WRT-021 集成测试：generate → 格式符合偏好
- [ ] WRT-022 集成测试：translate → 格式保持
- [ ] WRT-023 集成测试：polish → goal 匹配
- [ ] WRT-024 集成测试：上游 LLM 不可用时的降级处理

## 6. 参考

- Hermes 系统提示词写作指导：`~/ws/hermes-agent/agent/system_prompt.py`
- OpenClaw Skills 系统：`~/ws/openclaw/src/skills/`
- Prompt 工程最佳实践：Anthropic Prompt Library
