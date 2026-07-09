<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/musa_mapping
Title: 使用 MUSA Mapping 在编译期实现 CUDA 兼容
Fetched: 2026-07-10
This file is an immutable raw source. Do not edit.
-->

# 使用 MUSA Mapping 在编译期实现 CUDA 兼容

## 什么是 MUSA Mapping？

**MUSA Mapping**（安装路径 `$MUSA_HOME/tools/musamapping`）是 MUSA Toolkits 提供的 **编译期 CUDA 兼容层**。它在 `mcc` 编译过程中加载 Clang 前端插件 `libMusaMapping.so`，对源码进行预处理与 AST 重写，将 CUDA 风格的：

-   `#include` 头文件路径（如 `cuda_runtime.h` → `musa_runtime.h`）
-   API / 宏 / 类型标识符（如 `cudaMalloc` → `musaMalloc`，`CUBLAS` → `MUBLAS`）
-   部分生态专用头（PyTorch、cuDNN、CuTe/CUTLASS 等）

自动替换为 MUSA 对应符号，**源文件仍保持 CUDA 写法**。

与 musify 的区别

  维度       **musify**                         **MUSA Mapping**
  ---------- ---------------------------------- ---------------------------------------------------------
  时机       编译前，离线改源文件               编译时，不改磁盘上的源文件
  实现       Python 文本匹配（`musify-text`）   Clang 插件（语义感知重写）
  典型场景   一次性迁移、可审查 diff            直接编译未改的 `.cu`、CMake 伪装 `nvcc`、大型第三方工程
  输出       生成 MUSA 风格源码                 生成目标文件 / 可执行文件

两者可配合使用：先用 musify 做粗迁移，再用 MUSA Mapping 编译仍含 CUDA 名的依赖或宏。

------------------------------------------------------------------------

## 工作原理

      CUDA 风格源码 (.cu / .c / .h)
               │
               ▼
      mcc + libMusaMapping.so (-fplugin, -x musa)
               │
               ├── 读取 mapping/*.json、custom_defines.h
               ├── 重写 #include、标识符、宏
               └── 编译为 MUSA 设备 / Host 目标代码
               │
               ▼
      链接 libmusart、libmusa 等 → 可执行文件

插件在编译时会：

1.  根据 `MUSAMAPPING_PATH` 加载映射表；
2.  在预处理阶段处理 `#include` 等（`MusaMappingPPCallback`）；
3.  在 AST 阶段做标识符替换（`MusaMappingASTConsumer`）；
4.  注入 `custom_defines.h` 中的宏定义，保证宏展开前已完成 CUDA→MUSA 映射。

------------------------------------------------------------------------

## 安装与目录结构

安装 MUSA SDK 后，工具位于默认路径（可通过 `MUSA_HOME` 覆盖）：

    $MUSA_HOME/tools/musamapping/
    ├── libMusaMapping.so      # Clang 插件（核心）
    ├── mcc_wrapper            # 兼容 nvcc 调用方式的包装脚本
    ├── custom_defines.h       # 宏映射表（与 JSON 对应，约 3 万行）
    ├── mapping/
    │   ├── general.json       # 标识符 / 宏（约 3 万条）
    │   ├── include.json       # CUDA SDK 头文件映射
    │   ├── torch-include.json # PyTorch CUDA 头 → torch_musa
    │   ├── dnn-header.json    # cuDNN 等
    │   └── other-include.json # CuTe/CUTLASS（cute/ → mute/）等
    └── cmake/Modules/         # CMake CUDA 工具链兼容模块（支持 project(... LANGUAGES CUDA)）

**前提条件：**

-   已安装 MUSA SDK（`mcc`、`libmusart.so`、MUSA 头文件）；
-   编译时需能加载 `libMusaMapping.so`（与 `mcc` 同套 LLVM/Clang 构建）；
-   设置 `MUSA_HOME`（默认 `/usr/local/musa`）。

------------------------------------------------------------------------

## 快速开始

以下示例在 **不修改 CUDA 源码** 的前提下，用 MUSA Mapping 编译并运行一个向量 +1 内核。

### 示例源码 `add_one.cu`

    #include 
    #include 

    __global__ void add_one(float* data, int n) {
        int i = blockIdx.x * blockDim.x + threadIdx.x;
        if (i < n) {
            data[i] += 1.0f;
        }
    }

    int main(void) {
        const int n = 4;
        float h[4] = {0.f, 1.f, 2.f, 3.f};
        float* d_data = NULL;

        if (cudaMalloc((void**)&d_data, n * sizeof(float)) != cudaSuccess) {
            fprintf(stderr, "cudaMalloc failed\n");
            return 1;
        }
        if (cudaMemcpy(d_data, h, n * sizeof(float), cudaMemcpyHostToDevice) != cudaSuccess) {
            fprintf(stderr, "cudaMemcpy H2D failed\n");
            return 1;
        }

        const int threads = 256;
        const int blocks = (n + threads - 1) / threads;
        add_one<<>>(d_data, n);
        if (cudaGetLastError() != cudaSuccess) {
            fprintf(stderr, "kernel launch failed\n");
            return 1;
        }

        if (cudaMemcpy(h, d_data, n * sizeof(float), cudaMemcpyDeviceToHost) != cudaSuccess) {
            fprintf(stderr, "cudaMemcpy D2H failed\n");
            return 1;
        }
        cudaFree(d_data);
        cudaDeviceSynchronize();

        printf("result:");
        for (int i = 0; i < n; ++i) {
            printf(" %.1f", h[i]);
        }
        printf("\n");
        return 0;
    }

### 编译与运行

    export MUSA_HOME=/usr/local/musa
    export MUSAMAPPING_PATH=$MUSA_HOME/tools/musamapping
    export MUSA_INCLUDE_PATH=$MUSA_HOME/include

    mcc -x musa -I. \
      -fplugin=$MUSAMAPPING_PATH/libMusaMapping.so \
      --offload-arch=mp_22 \
      -DCCCL_DISABLE_NVFP8_SUPPORT \
      -I$MUSA_HOME/include \
      add_one.cu \
      -L$MUSA_HOME/lib -lmusart -lmusa \
      -o add_one

    ./add_one

**预期输出：**

    result: 1.0 2.0 3.0 4.0

### Makefile 示例

    MUSA_HOME ?= /usr/local/musa
    MUSAMAPPING_PATH ?= $(MUSA_HOME)/tools/musamapping
    MCC ?= $(MUSA_HOME)/bin/mcc

    PLUGIN := -fplugin=$(MUSAMAPPING_PATH)/libMusaMapping.so
    MUSA_FLAGS := -x musa -I. $(PLUGIN) --offload-arch=mp_22 -DCCCL_DISABLE_NVFP8_SUPPORT
    MAPPING_ENV := MUSA_HOME=$(MUSA_HOME) MUSAMAPPING_PATH=$(MUSAMAPPING_PATH) \
                   MUSA_INCLUDE_PATH=$(MUSA_HOME)/include

    add_one: add_one.cu
        $(MAPPING_ENV) $(MCC) $(MUSA_FLAGS) -I$(MUSA_HOME)/include add_one.cu \
          -L$(MUSA_HOME)/lib -lmusart -lmusa -o $@

关于编译日志中的提示

编译时可能出现类似 `add_one.cu:2:10` 的简短提示，表示插件正在处理 `#include <cuda_runtime.h>` 的映射，一般不影响编译结果。

------------------------------------------------------------------------

## 编译方式

### 1. 直接使用 mcc（推荐用于手写工程）

**必备参数：**

  参数 / 环境变量                    说明
  ---------------------------------- ------------------------------------------------
  `-fplugin=.../libMusaMapping.so`   加载 MUSA Mapping 插件
  `-x musa`                          按 MUSA 语言模式编译
  `-I.`                              当前目录，便于插件解析 `custom_defines.h`
  `MUSAMAPPING_PATH`                 映射表根目录（`mapping/`、`custom_defines.h`）
  `MUSA_INCLUDE_PATH`                MUSA 头文件根目录
  `--offload-arch=mp_XX`             目标 GPU 架构（按实际硬件选择）

    export MUSA_HOME=/usr/local/musa
    export MUSAMAPPING_PATH=$MUSA_HOME/tools/musamapping
    export MUSA_INCLUDE_PATH=$MUSA_HOME/include

    mcc -x musa -I. -fplugin=$MUSAMAPPING_PATH/libMusaMapping.so \
        --offload-arch=mp_22 \
        -I$MUSA_HOME/include \
        -c kernel.cu -o kernel.o

警告

普通 `-c` 编译路径下，需 **显式** 传入 `-fplugin` 与 `-x musa`。仅调用 `mcc_wrapper` 而不带 `-fatbin`/`-ptx` 时，包装脚本不会自动注入插件。

### 2. 使用 mcc_wrapper（兼容 nvcc / CMake CUDA）

`mcc_wrapper` 用于替代构建系统中的 `nvcc`：过滤部分 CUDA 专有参数，并在 `-fatbin` / `-ptx` 场景下自动追加插件与 `-x musa`。

    export MUSA_HOME=/usr/local/musa
    $MUSA_HOME/tools/musamapping/mcc_wrapper -fatbin -c kernel.cu -o kernel.fatbin

包装脚本还会：

-   过滤 `--extended-lambda`、`--expt-relaxed-constexpr` 等 MUSA 暂不支持的 nvcc  参数；
-   追加 `--offload-arch=mp_22`、`mp_31` 等默认架构；
-   为 torch_musa、mutlass 等生态追加常用 include 路径（可按部署环境调整脚本）。

在 CMake 中，应通过 `CMAKE_MODULE_PATH` 显式加载 `musamapping/cmake/Modules`，并将 `CMAKE_CXX_COMPILER` 指向 `mcc_wrapper`；模块会接管 CUDA 语言探测，使 `project(... LANGUAGES CUDA)` 可用，并把 `CUDA::cudart` 等目标重定向到 `libmusart.so` 等 MUSA 库。

### 3. CMake 集成概要

推荐在配置阶段传入模块路径与包装编译器：

    cmake -S . -B build \
      -DCMAKE_MODULE_PATH=/usr/local/musa/tools/musamapping/cmake/Modules \
      -DCMAKE_CXX_COMPILER=/usr/local/musa/tools/musamapping/mcc_wrapper

`CMAKE_MODULE_PATH` 不建议省略；当前交付方式通过该参数加载 Mapping 的 CMake Modules，不应假设这些模块已经预置在系统 CMake 安装目录中。

之后工程中可以继续使用 CMake 内置 CUDA 语言声明：

    project(my_app LANGUAGES CXX CUDA)

    add_executable(my_app main.cu)

警告

当前兼容模块支持 `project(xxx LANGUAGES CUDA)` / `enable_language(CUDA)` 这类 CUDA 语言启用方式，但 `set(CMAKE_CUDA_STANDARD 11)` 暂不生效。需要指定 C++ 标准时，请在项目的 C++ 配置或显式编译参数中传递（如 `CMAKE_CXX_STANDARD`、`target_compile_options` 或项目已有编译选项），并以实际编译命令为准。

具体变量（如 `MUSAMAPPING_PATH`、`CUDA_HOME`）由 `CMakeDetermineCUDACompiler.cmake`、`CMakeCUDAInformation.cmake` 预设，便于未改 CMake 逻辑的第三方 CUDA 项目接入。

------------------------------------------------------------------------

## 映射规则

### 命名规律（general.json / custom_defines.h）

  CUDA 前缀 / 模式      MUSA 对应示例
  --------------------- -------------------
  `cuda*` / `CUDA*`     `musa*` / `MUSA*`
  `cu*`（Driver API）   `mu*`
  `cublas*`             `mublas*`
  `cudnn*`              `mudnn*`
  `nccl*`               `mccl*`
  `nv*` / `NV*`         `mt*` / `MT*`
  `cute/`（CuTe）       `mute/`

### 分文件职责

  文件                           条数（约）        用途
  ------------------------------ ----------------- --------------------------------------------------
  `mapping/general.json`         30,000+           宏、函数名、类型名等标识符
  `mapping/include.json`         100+              `cuda_runtime.h` → `musa_runtime.h` 等 SDK 头
  `mapping/torch-include.json`   16                `ATen/cuda/*` → `ATen/musa/*`、`torch_musa` 路径
  `mapping/dnn-header.json`      4                 `cudnn.h` → `mudnn.h` 等
  `mapping/other-include.json`   190+              CUTLASS/CuTe 头路径
  `custom_defines.h`             与 general 同步   以 `#define` 形式在编译期注入

扩展映射时，应同时维护 JSON 与 `custom_defines.h`（若涉及宏），并重新部署到 `tools/musamapping`。

------------------------------------------------------------------------

## 环境变量

  变量                  说明
  --------------------- -----------------------------------------------------
  `MUSA_HOME`           MUSA SDK 根目录；`mcc_wrapper` 据此定位插件
  `MUSAMAPPING_PATH`    映射工具根目录，默认 `$MUSA_HOME/tools/musamapping`
  `MUSA_INCLUDE_PATH`   MUSA 头文件路径，默认 `$MUSA_HOME/include`

------------------------------------------------------------------------

## 典型使用场景

-   **第三方 CUDA 工程**：CMake/`nvcc` 构建脚本改为调用 `mcc_wrapper`，源码保持 CUDA 命名；
-   **PyTorch 扩展 / torch_musa**：`torch-include.json` 将 `c10/cuda`、`ATen/cuda` 等映射到 MUSA 实现；
-   **推理框架**（如 vLLM、SGLang）：通过包装脚本过滤 Python 扩展相关编译参数；
-   **CUTLASS / mutlass**：`other-include.json` 将 `cute/` 映射为 `mute/`；
-   **与 musify 组合**：musify 处理业务代码，Mapping 编译仍含 CUDA 符号的依赖或生成代码。

------------------------------------------------------------------------

## 局限性与注意事项

  项目                  说明
  --------------------- -----------------------------------------------------------------------------------------------------------
  **非运行时模拟**      仅做源码级映射，不保证所有 CUDA API 在 MUSA 上语义完全一致
  **映射表覆盖**        未收录的 API / 头文件需自行扩展 JSON 或改源码
  **架构参数**          `--offload-arch` 须与目标 GPU 匹配；`mcc_wrapper` 默认架构可按环境修改
  **CMake CUDA 标准**   `project(... LANGUAGES CUDA)` 可用；`CMAKE_CUDA_STANDARD` 暂不生效，请改用显式编译参数或项目 C++ 标准配置
  **FP8 等特性**        当前常配合 `-DCCCL_DISABLE_NVFP8_SUPPORT` 使用
  **插件与 mcc 版本**   `libMusaMapping.so` 须与 SDK 自带 `mcc`/Clang 版本匹配
  **无插件源码**        发行包仅含二进制插件，逻辑修改需在 musa-mapping 源码工程中完成

------------------------------------------------------------------------

## 故障排除

Q1: 找不到 cuda_runtime.h / 未发生头文件映射

确认已加载插件并设置路径：

    # 必须同时存在
    -fplugin=$MUSAMAPPING_PATH/libMusaMapping.so
    -x musa
    export MUSAMAPPING_PATH=...
    export MUSA_INCLUDE_PATH=$MUSA_HOME/include

若仍失败，检查 `mapping/include.json` 是否包含对应头，以及 `musa_runtime.h` 是否存在于 `$MUSA_HOME/include`。

Q2: 使用了 mcc_wrapper 但仍报 CUDA 符号未定义

`mcc_wrapper` 仅在 `-fatbin` / `-ptx` 时自动注入插件。普通 `-c` 请改用完整 `mcc` 命令（见上文「直接使用 mcc」），或在 CMake 中确认 `MUSA_MAPPING_FLAGS` 已生效。

Q3: unsupported CUDA gpu architecture: mp_XX

未加 `-x musa` 时，`mcc` 可能按 CUDA 架构解析 `--offload-arch`。请使用本文推荐的 `mcc -x musa ...` 组合，并指定 MUSA 架构（如 `mp_22`）。

Q4: 链接阶段 undefined reference to cuda\* / 混用 C/C++

-   确认链接 `-lmusart -lmusa` 及 `-L$MUSA_HOME/lib`；
-   多文件工程注意 `extern "C"` 与 `.cu`/`.c` 混编时的符号修饰；
-   单文件 `.cu` 示例可避免 Host/Device 分文件链接问题。

Q5: 与 musify 如何选择？

-   **希望仓库里长期保存 MUSA 源码、做 Code Review** → 优先 [musify](/musa-sdk/musa-sdk-doc-online/toolkits/musify)；
-   **希望零改动编译上游 CUDA 工程、或集成进现有 nvcc CMake** → 优先 MUSA Mapping；
-   **大型迁移** → musify 改业务代码 + Mapping 编译未改依赖。

------------------------------------------------------------------------

## 相关文档

-   [musify 一键代码迁移](/musa-sdk/musa-sdk-doc-online/toolkits/musify) --- 离线源码转换
-   [mcc 编译器](/musa-sdk/musa-sdk-doc-online/toolkits/mcc_compiler) --- 编译驱动与阶段控制
-   [MUSA 运行时库](/musa-sdk/musa-sdk-doc-online/toolkits/musa_runtime) --- `libmusart` 与 Runtime API
-   [MUSA Toolkits 概述](/musa-sdk/musa-sdk-doc-online/toolkits/)

