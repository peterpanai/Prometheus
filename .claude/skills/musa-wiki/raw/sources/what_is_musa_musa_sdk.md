<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/what/is_musa_musa_sdk
Title: MUSA 软件栈
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# MUSA 软件栈

**MUSA SDK**（Software Development Kit）是摩尔线程推出的完整软件开发工具包，为开发者提供基于 MT GPU 的并行计算和人工智能开发、运行环境。

## MUSA SDK 架构

MUSA SDK 在 MT Linux Driver 的基础上，包含编译器、运行时、MUSA-X 计算加速库、深度学习加速库、CUDA 兼容工具以及调试和性能分析工具等。

## MUSA SDK 模块详解

### MUSA Toolkits

| 子模块             | 功能描述                                                                    |
|--------------------|-----------------------------------------------------------------------------|
| **mcc**            | 编译器，支持 MUSA C/C++ 语法                                                |
| **MUSA Runtime**   | MUSA 运行时库                                                               |
| **musify**         | CUDA 到 MUSA 一键转换工具                                                   |
| **MUSA-X Library** | 计算加速数学库（muBLAS、muBLASLt、muFFT、muSPARSE、muSOLVER、muPP、muRAND） |

### 数据通信加速库 MCCL

| 子模块   | 功能描述                                   |
|----------|--------------------------------------------|
| **MCCL** | 数据通信加速库，支持单机多卡和多机多卡场景 |

### 深度学习加速库 muDNN

| 子模块    | 功能描述       |
|-----------|----------------|
| **muDNN** | 深度学习加速库 |

### 编译器工具

| 子模块            | 功能描述        |
|-------------------|-----------------|
| **Triton-MUSA**   | Triton 编译器   |
| **TileLang-MUSA** | TileLang 编译器 |

### MUSA OpenLibs

| 子模块      | 功能描述                                         |
|-------------|--------------------------------------------------|
| **MATE**    | 推理算子加速库                                   |
| **MUTLASS** | 用于在 MUSA 上实现高性能矩阵乘法运算的纯头文件库 |

### 工具

| 子模块         | 功能描述                             |
|----------------|--------------------------------------|
| **Moore Perf** | 性能分析工具                         |
| **muPTI**      | Profiling and Tracing Infrastructure |

------------------------------------------------------------------------

### 兼容性保证

为保证应用兼容性，MUSA 从 **5.1 版本** 开始提供 MUSA SDK 与 MUSA Driver 之间的兼容性保证，即不再强制要求用户使用相同版本的 MUSA SDK 和 MUSA Driver， 允许用户单独升级其中一个。

**前向兼容**：

- 用户仅升级 MUSA SDK，不升级 MUSA Driver 时，基于升级后更高版本的 MUSA SDK 开发的应用程序，可以在 **5.2.x 版本** MUSA Driver 上保持“非驱动功能升级部分”正常工作。

**后向兼容**：

- 用户仅升级 MUSA Driver，不升级 MUSA SDK 时，基于 **5.2.x 版本** MUSA SDK 开发的应用程序，在升级后的更高版本的 MUSA Driver 上仍可保持兼容运行。

------------------------------------------------------------------------

## 相关文档

- [GPU 并行计算基础](/musa-sdk/musa-sdk-doc-online/programming_guide/what_is_musa/gpu_parallel_basics)
- [快速入门：第一个 Kernel](/musa-sdk/musa-sdk-doc-online/programming_guide/getting_started_first_kernel)
