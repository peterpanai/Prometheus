<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/toolkits/musify
Title: musify 一键代码迁移
Fetched: 2026-07-10
This file is an immutable raw source. Do not edit.
-->

# musify 一键代码迁移

## 什么是 musify？

**musify** 是摩尔线程推出的一款 CUDA 到 MUSA 一键代码迁移工具，属于 MUSA Toolkits 的一部分。**musify** 通过命令行工具 `musify-text` 提供服务，采用**纯文本匹配**的方式进行代码转换，实现：

-   **轻量级**: 避免语法分析引入过重的依赖
-   **易部署**: 无需复杂的编译器基础设施
-   **灵活快速**: 工具小巧灵活

注意

由于仅基于文本匹配，musify 无法理解代码语义，可能会误改不该转换的内容。你可以在代码中添加排除标记（exclude markers），明确告诉工具哪些部分跳过处理。

------------------------------------------------------------------------

## 主要特性

-   **自动转换** - 自动将 CUDA API 调用转换为 MUSA API
-   **语法兼容** - 支持 CUDA C/C++ 语法转换
-   **批量处理** - 支持批量转换多个源文件
-   **原地转换** - 支持 `--inplace` 模式直接修改源文件
-   **双向转换** - 支持 CUDA→MUSA 和 MUSA→CUDA 双向转换
-   **自定义映射** - 支持用户自定义 API 映射表

------------------------------------------------------------------------

## 快速开始

### 安装

安装 MUSA SDK 后，`musify-text` 命令即可使用。

提示

如果需要在其他机器上单独使用 musify，或者 SDK 安装有问题，可以手动安装依赖。

### （可选）手动安装依赖

musify 使用 Python 编写，需要系统中安装有 Python 3。

    # Ubuntu 系统安装依赖
    sudo apt install python-is-python3 -y
    sudo apt install pip -y
    pip install ahocorapy

    # 如遇网络问题，可配置国内镜像源
    pip config set global.index-url https://pypi.mirrors.ustc.edu.cn/simple/

------------------------------------------------------------------------

### 基本示例

    # 转换单个文件（输出到新文件，默认行为）
    musify-text source.cu

    # 原地转换（直接修改源文件）
    musify-text --inplace source.cu

    # 输出到标准输出
    musify-text --terminal source.cu

    # 转换多个文件
    musify-text --inplace -- *.cu

### 转换示例

**CUDA 源代码** (`source.cu`)：

    #include 

    __global__ void vector_add(float* a, float* b, float* c, int n) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if (idx < n) {
            c[idx] = a[idx] + b[idx];
        }
    }

    int main() {
        float *d_a, *d_b, *d_c;
        cudaMalloc(&d_a, N * sizeof(float));
        cudaMalloc(&d_b, N * sizeof(float));
        cudaMalloc(&d_c, N * sizeof(float));
        
        vector_add<<>>(d_a, d_b, d_c, N);
        
        cudaFree(d_a);
        cudaFree(d_b);
        cudaFree(d_c);
        
        return 0;
    }

**转换后 MUSA 代码**：

    #include 

    __global__ void vector_add(float* a, float* b, float* c, int n) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if (idx < n) {
            c[idx] = a[idx] + b[idx];
        }
    }

    int main() {
        float *d_a, *d_b, *d_c;
        musaMalloc((void**)&d_a, N * sizeof(float));
        musaMalloc((void**)&d_b, N * sizeof(float));
        musaMalloc((void**)&d_c, N * sizeof(float));
        
        vector_add<<>>(d_a, d_b, d_c, N);
        
        musaFree(d_a);
        musaFree(d_b);
        musaFree(d_c);
        
        return 0;
    }

### 编译转换后的示例

    # 转换
    musify-text --inplace source.cu

    # 重命名为 .mu 后缀
    mv source.cu source.mu

    # 编译
    mcc source.mu -lmusart -L/usr/local/musa/lib -o app

------------------------------------------------------------------------

## 命令行选项

### 帮助信息

    $ musify-text -h
    usage: musify-text [-h] [-t | -c | -i] [-d {c2m,m2c}] [-m [MAPPING ...]] 
                       [--clear-mapping] [-l {DEBUG,INFO,WARNING}] [srcs ...]

    positional arguments:
      srcs                  source files to be transformed

    options:
      -h, --help            show this help message and exit
      -t, --terminal        print code to stdout
      -c, --create          write code to newly created file, default action
      -i, --inplace         modify code inplace
      -d {c2m,m2c}, --direction {c2m,m2c}
                            convert direction
      -m [MAPPING ...], --mapping [MAPPING ...]
                            api mapping
      --clear-mapping       clear default and previous mapping
      -l {DEBUG,INFO,WARNING}, --log-level {DEBUG,INFO,WARNING}
                            lowest log level to display

### 选项详解

  选项                说明
  ------------------- ---------------------------------------------------
  `-t, --terminal`    输出到标准输出（stdout）
  `-c, --create`      写入新文件（默认行为）
  `-i, --inplace`     原地修改源文件
  `-d, --direction`   转换方向：`c2m`（CUDA→MUSA）或 `m2c`（MUSA→CUDA）
  `-m, --mapping`     指定映射表 JSON 文件（可多个）
  `--clear-mapping`   清除默认映射表，只用 `-m` 指定的
  `-l, --log-level`   日志级别（DEBUG/INFO/WARNING）

重要提示

1.  **输出方式三选一**：`-t`、`-c`、`-i` 必须选择其一
2.  **文件路径保护**：在所有选项之后、文件路径之前，加上 `--`，防止以 `-` 开头的文件路径被识别为选项
3.  **映射表叠加**：`-m` 会添加新的映射表，不会覆盖默认映射表
4.  **映射表格式**：JSON 文件，内容为单层无嵌套的 JSON Object，每个 name-value 对分别表示相应的 CUDA 和 MUSA 命名

```{=html}
<!-- -->
```
    {
      "cudaMalloc": "musaMalloc",
      "cudaFree": "musaFree",
      "cudaMemcpy": "musaMemcpy"
    }

------------------------------------------------------------------------

## 高级用法

### 批量迁移

#### 使用 find 命令

    # 递归查找目录 ${DIR} 下所有后缀名为 cu、cuh、cpp 或 h 的文件并转化
    musify-text --inplace -- `find ${DIR} \
      -name '*.cu' \
      -o -name '*.cuh' \
      -o -name '*.cpp' \
      -o -name '*.h'`

#### （推荐）使用 ripgrep

[ripgrep](https://github.com/BurntSushi/ripgrep) 是一个现代化的快速文本搜索工具，可以用于文件遍历：

    # 安装 ripgrep
    sudo apt install ripgrep -y

    # 方式 1: 使用 rg --files 配合预设类型（cpp 类型已内置）
    musify-text --inplace -- `rg --files -tcpp ${DIR}`

    # 方式 2: 使用 rg --files 配合自定义类型（cuda 类型需要手动添加）
    musify-text --inplace -- `rg --files \
      --type-add 'cuda:*.cu' \
      --type-add 'cuda:*.cuh' \
      -tcuda -tcpp ${DIR}`

    # 方式 3: 使用 -g 选项直接指定后缀名（类似 find）
    musify-text --inplace -- `rg --files \
      -g '*.cu' \
      -g '*.cuh' \
      -g '*.cpp' \
      -g '*.h' ${DIR}`

### 自定义映射表

    # 使用自定义映射表（默认映射表仍生效）
    musify-text --inplace -m my_mapping.json -- source.cu

    # 清除默认映射表，只用自定义映射表
    musify-text --inplace --clear-mapping -m my_mapping.json -- source.cu

    # 使用多个映射表
    musify-text --inplace -m mapping1.json -m mapping2.json -- source.cu

### 调整日志级别

    # 显示 DEBUG 级别日志（最详细）
    musify-text -l DEBUG --inplace -- source.cu

    # 只显示 WARNING 及以上级别（最简洁）
    musify-text -l WARNING --inplace -- source.cu

------------------------------------------------------------------------

## 排除标记

由于 **musify** 是纯文本匹配，可能转换一些不需要转换的代码。为此，我们参考 lcov 行覆盖率工具的设计，加入了**排除标记**功能。

### 标记类型

  标记                  说明
  --------------------- ----------------------------------------------------------------
  `MUSIFY_EXCL_LINE`    包含本标记的行会被排除
  `MUSIFY_EXCL_START`   从包含本标记的行开始，直到 `MUSIFY_EXCL_STOP` 之间的行会被排除
  `MUSIFY_EXCL_STOP`    结束由 `MUSIFY_EXCL_START` 开启的排除

### 使用标记

#### 方式 1：（单独使用）LINE 标记

    // 被排除，不会转换
    char str[] = "cuInit"; // MUSIFY_EXCL_LINE

    // 被排除，不会转换
    printf("This is a cudaMalloc example"); // MUSIFY_EXCL_LINE

#### 方式 2：（成对使用）START/STOP 标记

    // MUSIFY_EXCL_START
    char *str_array[] = {
        "cuInit",
        "cuMalloc",
        "cuMemset",
        "cuLaunchKernel"
    };
    // MUSIFY_EXCL_STOP

    // 上述代码块中的所有 CUDA API 名称都不会被转换

注意

1.  `START` 和 `STOP` 必须**成对使用**，否则从 `START` 到文件末尾的所有内容都会被排除
2.  `START` 和 `STOP` 所在行**也会被排除**
3.  `LINE` 标记所在行**会被排除**

------------------------------------------------------------------------

## 转换方向

### CUDA → MUSA（默认）

    # 默认方向，无需指定
    musify-text --inplace -- source.cu

    # 显式指定
    musify-text -d c2m --inplace -- source.cu

### MUSA → CUDA

    # 反向转换（用于测试或回滚）
    musify-text -d m2c --inplace -- source_musa.cpp

------------------------------------------------------------------------

## API 映射对照表

### 常用 API

  CUDA API                 MUSA API
  ------------------------ ------------------------
  `cudaMalloc`             `musaMalloc`
  `cudaMallocHost`         `musaMallocHost`
  `cudaFree`               `musaFree`
  `cudaFreeHost`           `musaFreeHost`
  `cudaMallocManaged`      `musaMallocManaged`
  `cudaMemcpy`             `musaMemcpy`
  `cudaMemcpyAsync`        `musaMemcpyAsync`
  `cudaMemcpyToSymbol`     `musaMemcpyToSymbol`
  `cudaMemcpyFromSymbol`   `musaMemcpyFromSymbol`
  `cudaMemset`             `musaMemset`
  `cudaMemsetAsync`        `musaMemsetAsync`

### 设备管理 API

  CUDA API                   MUSA API
  -------------------------- --------------------------
  `cudaGetDevice`            `musaGetDevice`
  `cudaSetDevice`            `musaSetDevice`
  `cudaGetDeviceCount`       `musaGetDeviceCount`
  `cudaDeviceGetAttribute`   `musaDeviceGetAttribute`

### 流管理 API

  CUDA API                  MUSA API
  ------------------------- -------------------------
  `cudaStreamCreate`        `musaStreamCreate`
  `cudaStreamDestroy`       `musaStreamDestroy`
  `cudaStreamSynchronize`   `musaStreamSynchronize`
  `cudaStreamQuery`         `musaStreamQuery`

### 事件管理 API

  CUDA API                 MUSA API
  ------------------------ ------------------------
  `cudaEventCreate`        `musaEventCreate`
  `cudaEventDestroy`       `musaEventDestroy`
  `cudaEventRecord`        `musaEventRecord`
  `cudaEventSynchronize`   `musaEventSynchronize`
  `cudaEventElapsedTime`   `musaEventElapsedTime`

### 错误处理 API

  CUDA API               MUSA API
  ---------------------- ----------------------
  `cudaGetErrorString`   `musaGetErrorString`
  `cudaGetLastError`     `musaGetLastError`

### 内存拷贝类型枚举

  CUDA                         MUSA
  ---------------------------- ----------------------------
  `cudaMemcpyHostToHost`       `musaMemcpyHostToHost`
  `cudaMemcpyHostToDevice`     `musaMemcpyHostToDevice`
  `cudaMemcpyDeviceToHost`     `musaMemcpyDeviceToHost`
  `cudaMemcpyDeviceToDevice`   `musaMemcpyDeviceToDevice`
  `cudaMemcpyDefault`          `musaMemcpyDefault`

------------------------------------------------------------------------

## 最佳实践

### 版本控制

在使用 **musify** 之前，建议先将代码提交到版本控制系统：

    # 使用 git 管理
    git add .
    git commit -m "Before musify migration"

    # 然后再执行迁移
    musify-text --inplace -- `rg --files -tcpp src/`

    # 如果有问题，可以回滚
    git checkout .

### 增量迁移

对于大型项目，建议分批次迁移：

    # 先迁移一个模块
    musify-text --inplace -- `rg --files -tcpp src/module_a/`

    # 编译测试
    make clean && make

    # 确认无误后，继续下一个模块
    musify-text --inplace -- `rg --files -tcpp src/module_b/`

### 排除特殊代码

对于以下类型的代码，建议使用排除标记：

-   **字符串字面量**中的 CUDA API 名称
-   **注释**中的 CUDA API 名称
-   **日志输出**中的 CUDA API 名称
-   **测试代码**中需要保留的 CUDA 引用

```{=html}
<!-- -->
```
    // 日志中的 CUDA 引用，建议排除
    printf("Original implementation used cuInit API"); // MUSIFY_EXCL_LINE

------------------------------------------------------------------------

## 局限性

### 文本匹配的局限

由于 **musify** 采用纯文本匹配，存在以下局限：

  局限                 说明                                解决方案
  -------------------- ----------------------------------- ----------------
  **无法区分上下文**   字符串、注释中的 API 名也会被转换   使用排除标记
  **无法理解语义**     可能转换不该转换的标识符            转换后人工审查
  **不支持复杂模式**   无法处理需要语法分析的场景          手动修改

------------------------------------------------------------------------

## 故障排除

### 常见问题

Q1: 转换后代码无法编译

A: 检查是否有需要排除的代码未排除，或存在映射表中未覆盖的 API。可以查看 DEBUG 日志了解具体转换了哪些内容：

    musify-text -l DEBUG --inplace -- source.cu 2>&1 | grep -i "converted"

Q2: 某些 CUDA API 没有被转换

A: 检查映射表中是否包含该 API。如需添加，可以创建自定义映射表：

    cat >> my_mapping.json << EOF
    {
      "cudaCustomAPI": "musaCustomAPI"
    }
    EOF

    musify-text -m my_mapping.json --inplace -- source.cu

Q3: 转换引入了错误

A: 使用 `git diff` 查看具体变更，定位问题后可以：

    # 回滚
    git checkout source.cu

    # 添加排除标记后重新转换
    # 编辑 source.cu，在需要排除的行添加 // MUSIFY_EXCL_LINE
    musify-text --inplace -- source.cu

### 日志分析

    # 启用 DEBUG 日志
    musify-text -l DEBUG --inplace -- source.cu

    # 日志输出示例:
    # [INFO] Processing file: source.cu
    # [DEBUG] Line 42: cudaMalloc -> musaMalloc
    # [DEBUG] Line 43: cudaMemcpy -> musaMemcpy
    # [INFO] Converted 23 API calls

------------------------------------------------------------------------

## 相关工具

**[MUSA for VS Code](https://marketplace.visualstudio.com/items?itemName=mthreads.musa-for-vscode)** 是摩尔线程提供的 Visual Studio Code 插件，支持智能代码编辑、实时错误诊断、以及 **CUDA → MUSA 一键迁移**功能，可在 IDE 内直接使用 musify 进行代码转换，适合需要频繁进行迁移工作的开发者。

------------------------------------------------------------------------

## 相关文档

-   [MUSA SDK 概述](/musa-sdk/musa-sdk-doc-online/programming_guide/what_is_musa/musa_sdk)
-   [mcc 编译器](/musa-sdk/musa-sdk-doc-online/toolkits/mcc_compiler)

