<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/performance/tuning_perf_tools
Title: 性能分析工具
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# 性能分析工具

## 快速开始

### Moore Perf System (系统级)

```bash
# 收集 MT GPU 和 GPU 信息
msys -t musa --gpu-metrics-set=0 -o report ./application

# 查看报告
# 方式 1：点击桌面 "msys-ui" 图标启动程序，选择 "文件 > 打开" 加载 .msys-rep 文件
# 方式 2：命令行打开
msys-ui report.msys-rep
```

### Moore Perf Compute（内核级）

```bash
# 分析所有内核
mcu -o report ./application

# 分析指定内核（使用 -k 参数）
mcu -k vectorAdd -o report ./application
```

## 分析流程

## 相关文档

- [性能瓶颈分析](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/performance_bottleneck)
- [快速优化检查清单](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/quickstart_optimization)
- [Moore Perf Tools 文档](https://docs.mthreads.com/mooreperf/mooreperf-doc-online/introduction/)：完整工具文档
