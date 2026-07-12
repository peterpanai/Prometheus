# ADD - Prometheus 插件系统架构

> 版本：v1.0 | 日期：2026-07-12 | 状态：**shelved** | 归档日期：2026-07-12
>
> **v3.0 变更**：插件系统已在 v3.0 中搁置。比赛阶段直接写死 5 个 Subagent 配置，不做插件化。本文档保留作为产品化阶段的参考。

## 搁置原因

1. 比赛不需要插件系统，评委不会因为插件系统加分
2. 插件管理器（discover/validate/load/activate）开发量大（~1 周）
3. 5 个 Subagent 直接写死配置更简单可靠，演示不会出问题
4. 产品化阶段可以再引入插件系统

## 产品化阶段恢复计划

如果 Prometheus 从比赛 demo 发展为产品：

1. 恢复 plugin_manager.py（discover/validate/load/activate）
2. 恢复 plugin.json schema 校验
3. 恢复 functions.jsonl 合并器
4. 恢复路由提示词自动生成
5. 开放社区贡献 Subagent 插件

## 原始设计（参考）

详细设计见 git 历史 commit `a619c31`。核心要点：

- plugin.json 清单规范（JSON，MTClaw 生态一致）
- 无损接入 MTClaw（functions.jsonl 合并 + scripts_dir 聚合）
- 插件生命周期（discover -> validate -> load -> activate -> run -> unload）
- 插件间依赖拓扑排序
- CLI 管理（prometheus plugin list/enable/disable/install）
