<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/
Title: MUSA Toolkits
Fetched: 2026-07-10
This file is an immutable raw source. Do not edit.
-->

# MUSA Toolkits

MUSA Toolkits 为开发人员提供了一套完整的开发工具，用于编译、调试和优化 MUSA 应用程序。这些工具涵盖了从代码编译到性能分析的完整开发周期，帮助开发者高效地构建基于 MUSA 架构的高性能应用程序。

### 核心工具

-   [mcc 编译器](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/mcc_compiler) - mcc 编译器用户手册
-   [MTRTC 运行时编译](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/mtrtc_runtime_compilation) - MUSA SDK 5.2.0 的 MTRTC 运行时编译用户指南
-   [MUSA 运行时库](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/musa_runtime) - MUSA 运行时库（MUSA Runtime）是 MUSA SDK 的核心组件，提供 GPU 设备管理、内存管理、内核执行等基础功能
-   [musify 一键代码迁移](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/musify) - musify 语言转换工具------自动将 CUDA 代码转换为 MUSA 代码，支持批量迁移、排除标记、自定义映射表
-   [muPTI 开发者指南](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/mupti) - MUSA Performance Tools Interface 使用指南
-   [Moore Perf 性能分析工具](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/moore_perf) - MT GPU 性能分析工具套件，包含 Compute、System 等工具
-   [使用 MUSA Mapping 在编译期实现 CUDA 兼容](https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/musa_mapping) - 使用 MUSA Mapping，在 mcc 编译期通过 Clang 插件将 CUDA 源码、头文件与宏自动映射为 MUSA，无需修改源文件即可编译大量 CUDA 生态项目

## 快速入门

### 编译 MUSA 程序

    # 基本编译
    mcc main.mu -lmusart -L/usr/local/musa/lib -o app

    # 启用优化
    mcc -O3 main.mu -lmusart -L/usr/local/musa/lib -o app

    # 指定目标架构
    mcc --offload-arch=mp_21 main.mu -lmusart -L/usr/local/musa/lib -o app

    # CUDA 兼容模式
    mcc -mtgpu -cuda_wrapper main.cu -lcuda2musa -lmusart -L/usr/local/musa/lib -o app

### 性能分析

    # 使用 Moore Perf Compute 收集性能数据
    mcu --collect ./app

    # 生成性能报告
    mcu --report ./app.profile

### 代码迁移

    # 使用 Musify 转换 CUDA 代码
    musify-text --inplace -- source.cu

