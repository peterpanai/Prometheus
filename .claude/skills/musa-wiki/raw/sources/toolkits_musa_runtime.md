<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/musa_runtime
Title: MUSA 运行时库
Fetched: 2026-07-10
This file is an immutable raw source. Do not edit.
-->

# MUSA Runtime（运行时库）

MUSA 运行时库（MUSA Runtime）是 MUSA SDK 的核心运行时库，提供 GPU 编程所需的基础功能，包括：

-   **设备管理**：设备枚举、属性查询、上下文管理
-   **内存管理**：设备内存分配、主机内存分配、统一内存、内存拷贝
-   **内核执行**：内核启动、动态并行
-   **流与事件**：异步执行、流同步、事件计时

------------------------------------------------------------------------

## 安装方式

MUSA 运行时库 随 MUSA SDK 自动安装，无需单独配置。

    # 安装 MUSA SDK 后，MUSA 运行时库位于
    /usr/local/musa/lib/libmusart.so

    # 查询 Runtime 版本
    musa_version_query

------------------------------------------------------------------------

## 基本使用

### 链接 MUSA 运行时库

    # 编译时链接 musart 库
    mcc app.mu -L/usr/local/musa/lib -lmusart -o app

### 环境变量

    # 设置库路径（如未自动加载）
    export LD_LIBRARY_PATH=/usr/local/musa/lib:$LD_LIBRARY_PATH

    # 设置可见设备
    export MUSA_VISIBLE_DEVICES=0,1,2,3

------------------------------------------------------------------------

## Runtime vs Driver API

  特性             Runtime API                  Driver API
  ---------------- ---------------------------- ------------------------
  **初始化**       隐式（首次调用自动初始化）   显式（`muInit()`）
  **上下文管理**   自动（primary context）      手动创建和销毁
  **代码复杂度**   低                           高
  **灵活性**       低                           高
  **适用场景**     应用程序、快速原型           多 GPU、多进程、库开发

**选择建议**：

-   **推荐 Runtime API**：大多数应用场景，代码更简洁
-   **使用 Driver API**：需要精细控制的高级场景（多 GPU、多进程、库开发）

------------------------------------------------------------------------

## 常见问题

Q: MUSA 运行时库版本如何查询？

    musa_version_query

输出示例：

    musa_runtime:
    {
        "version":      "5.1.0",
        "git branch":   "release_musa_5.1.0",
        "commit id":    "xxxxxx"
    }

Q: 找不到 libmusart.so 怎么办？

    # 检查库文件是否存在
    ls /usr/local/musa/lib/libmusart.so

    # 设置 LD_LIBRARY_PATH
    export LD_LIBRARY_PATH=/usr/local/musa/lib:$LD_LIBRARY_PATH

    # 或添加到系统库路径
    sudo ldconfig /usr/local/musa/lib

Q: Runtime API 和 Driver API 可以混用吗？

**不推荐混用**。两种 API 使用不同的上下文管理机制，混用可能导致：

-   上下文状态不一致
-   资源管理混乱
-   难以调试的问题

**建议**：选择一个 API 体系并坚持使用。

------------------------------------------------------------------------

## 相关文档

-   [Runtime API 指南](/musa-sdk/musa-sdk-doc-online/programming_guide/api_guides/runtime_api_guide)
-   [Runtime API 参考](/musa-sdk/musa-sdk-doc-online/libraries/core_api/runtime_api_reference)

