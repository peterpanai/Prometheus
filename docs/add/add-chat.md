# ADD — 闲聊陪伴 Subagent

> 版本：v1.0 | 日期：2026-07-12 | 状态：draft | 插件名：`chat`

## 1. 背景

轻量级直回闲聊，零工具调用，路由模型直接生成回复，无需经过上游 LLM。这是赛题"快准狠"中"快"的核心体现--将闲聊延迟从 15-40s 降至 1-3s。

## 2. 调研

### 2.1 Hermes

- **无专门闲聊 Subagent**：所有对话通过通用 agent 循环处理
- **路由模型 vs 上游模型分离**：Hermes 的模型配置支持 primary/secondary 模型切换，但不在路由层做决策
- **会话管理**：`gateway/session.py` 管理长会话和上下文

### 2.2 OpenClaw

- **Skills 系统**：`~/ws/openclaw/src/skills/` — 可通过加载 personality/chitchat skill 来调整对话风格
- **无专门闲聊路由**：所有消息经过完整的 LLM 流程
- **Agent harness**：`registerAgentHarness()` 可以自定义 agent 行为

### 2.3 Codex

- **无专门闲聊路由**：全部请求走 Responses API
- **角色系统**：`codex-rs/core/src/agent/role.rs` — default/explorer/worker 三种角色有不同行为

### 2.4 结论

三个代码库都没有专门的"轻量闲聊快速通道"。这是 Prometheus 的创新点——利用路由模型的小参数、低延迟特性，对纯粹闲聊意图走捷径。关键技术挑战在于**准确识别闲聊意图**，避免将需要上游 LLM 的复杂推理误判为闲聊。

## 3. 设计决策

### 3.1 闲聊意图识别

```
路由模型判断 → chat_light 触发条件（全部满足）：
  1. 无文件路径引用
  2. 无数据查询意图
  3. 无知识检索需求
  4. 消息长度 < 200 字
  5. 包含社交/情感/寒暄语义：
     - 问候类：你好/嗨/hey/早上好/晚安
     - 情感类：开心/难过/无聊/好累/烦死了
     - 娱乐类：笑话/故事/谜语/冷笑话/有趣
     - 简单问答：今天星期几/你叫什么/天气怎么样
```

### 3.2 对话风格映射

| mood 参数 | 路由模型提示词策略 |
|-----------|-----------------|
| casual | 自然日常对话，语气轻松 |
| humor | 优先讲笑话/段子/趣事，风趣幽默 |
| comfort | 共情倾听，温暖安慰 |
| curious | 拓展话题，提出有趣问题 |
| auto | 从用户消息中自动判断情感基调 |

### 3.3 记忆注入策略

闲聊 Subagent 仍然注入记忆上下文（用户昵称、兴趣、最近话题），使闲聊更有"人情味"：
```
[用户画像]
- 昵称：小明
- 兴趣：编程、篮球、科幻电影
- 最近话题：HICOOL 比赛准备（已连续讨论 3 天）
```

## 4. 插件规格

### 4.1 plugin.json

```json
{
  "name": "chat",
  "version": "1.0.0",
  "description": "闲聊陪伴 Subagent — 轻量直回，路由模型零工具调用",
  "enabled": true,
  "priority": 9,
  "requires": {
    "plugins": ["memory"],
    "packages": []
  },
  "provides": {
    "tools": ["chat_light"],
    "engines": []
  },
  "routing": {
    "trigger_keywords": ["你好", "嗨", "笑话", "无聊", "累了", "晚安", "早安", "开心", "难过"],
    "trigger_patterns": ["讲个.*", "陪我.*", "好.*啊"],
    "match_priority": "low"
  }
}
```

### 4.2 工具定义

见 `spec.md` §3.5，1 个工具：`chat_light`。

### 4.3 关键设计

```
chat_light 是唯一不走上游 LLM 的 Subagent：
  ├── 路由模型直接生成回复（利用路由模型轻量高效特性）
  ├── 注入 memory_recall 结果（用户画像上下文）
  ├── Completion Check → permissive 模式，直接返回
  └── 延迟：1-3s（vs 上游 15-40s）
```

## 5. 实现 Checklist

### 意图识别

- [ ] CHT-001 实现闲聊意图判断规则引擎（5 条规则）
- [ ] CHT-002 实现消息分类器：greeting / emotion / entertainment / simple_qa / complex
- [ ] CHT-003 实现 mood 自动检测（情感分析 → casual/humor/comfort/curious）
- [ ] CHT-004 实现误判保护：complex 类消息禁止路由到 chat_light

### 响应生成

- [ ] CHT-005 实现路由模型直回 prompt 构造（含 mood 策略）
- [ ] CHT-006 实现记忆注入上下文拼接
- [ ] CHT-007 实现 Completion Check permissive 模式配置
- [ ] CHT-008 实现响应后处理（表情符号适当化、长度控制）

### Wrapper 脚本

- [ ] CHT-009 编写 `chat_light.sh`（调用路由模型 API 生成回复）

### 测试

- [ ] CHT-010 单元测试：5 类意图识别准确率
- [ ] CHT-011 单元测试：mood 自动检测
- [ ] CHT-012 单元测试：complex 消息误判保护
- [ ] CHT-013 集成测试：闲聊延迟 < 3s
- [ ] CHT-014 集成测试：记忆注入（用户昵称出现在回复中）
- [ ] CHT-015 集成测试：连续 10 轮闲聊 → 不走上游 LLM

## 6. 参考

- OpenClaw Agent Harness: `~/ws/openclaw/src/agents/`
- OpenClaw Skills (personality): `~/ws/openclaw/skills/`
- Codex Role System: `~/ws/codex/codex-rs/core/src/agent/role.rs`
- MTClaw Completion Check: `fr_completion_check.mode = "permissive"`
