<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/getting_started_first_kernel
Title: 快速开始
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# 编写你的第一个内核

15 分钟快速上手 MTGPU 编程——从环境验证到完整 Kernel（内核函数）程序的编写、编译和运行。

## 前提条件

- **了解 C/C++ 基础语法**
- **操作系统**：Ubuntu 22.04（内核 5.15.x）
- **硬件**：MTT M1000/S4000/S5000 系列 GPU
- **软件**：[MUSA SDK 5.2.0](/musa-sdk/musa-sdk-doc-online/install_guide) - 包括驱动、Toolkit、环境变量配置等

## 步骤 1. 验证环境

打开终端，验证 MUSA SDK 是否正确安装：

```bash
# 查看 GPU 信息（验证驱动安装）
mthreads-gmi

# 查看 MUSA 版本（验证 Toolkit 安装）
musa_version_query
```

预期输出：

```text
# mthreads-gmi 输出示例
+-------------------------------------------------------------------+
| mthreads-gmi                                    Driver Version:   |
+===============================+===============================+
| GPU  Name                      | 0 MTT S5000                     |
+-------------------------------+-------------------------------+
| Memory Usage                  | 79.91 GiB Total : 0.59 GiB Used |
+-------------------------------+-------------------------------+
```

**遇到问题？** 如果命令未找到，请检查环境变量配置：

```bash
export PATH=$MUSA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$MUSA_HOME/lib:$LD_LIBRARY_PATH
```

## 步骤 2. 创建项目

```bash
mkdir -p ~/musa_projects/vector_add
cd ~/musa_projects/vector_add
```

## 步骤 3. 编写内核代码

创建 `vectorAdd.mu` 文件：

```cpp
#include <stdio.h>
#include <stdlib.h>
#include <musa_runtime.h>

// 内核函数：c[i] = a[i] + b[i]
__global__ void vectorAdd(const float *A, const float *B, float *C, int numElements) {
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i < numElements) {
        C[i] = A[i] + B[i];
    }
}

int main(void) {
    musaError_t err = musaSuccess;
    int numElements = 50000;
    size_t size = numElements * sizeof(float);
    float *h_A = (float *)malloc(size);
    float *h_B = (float *)malloc(size);
    float *h_C = (float *)malloc(size);
    if (h_A == NULL || h_B == NULL || h_C == NULL) {
        fprintf(stderr, "Failed to allocate host vectors!\n");
        exit(EXIT_FAILURE);
    }
    for (int i = 0; i < numElements; ++i) {
        h_A[i] = rand()/(float)RAND_MAX;
        h_B[i] = rand()/(float)RAND_MAX;
    }

    // 分配设备内存
    float *d_A = NULL;
    err = musaMalloc((void **)&d_A, size);
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to allocate device vector A (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }
    float *d_B = NULL;
    err = musaMalloc((void **)&d_B, size);
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to allocate device vector B (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }
    float *d_C = NULL;
    err = musaMalloc((void **)&d_C, size);
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to allocate device vector C (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }

    // 拷贝数据到设备
    err = musaMemcpy(d_A, h_A, size, musaMemcpyHostToDevice);
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to copy vector A from host to device (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }
    err = musaMemcpy(d_B, h_B, size, musaMemcpyHostToDevice);
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to copy vector B from host to device (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }

    // 配置内核参数并启动
    int threadsPerBlock = 256;
    int blocksPerGrid = (numElements + threadsPerBlock - 1) / threadsPerBlock;
    printf("内核启动：%d 个块，每块 %d 线程\n", blocksPerGrid, threadsPerBlock);
    vectorAdd<<<blocksPerGrid, threadsPerBlock>>>(d_A, d_B, d_C, numElements);
    err = musaGetLastError();
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to launch vectorAdd kernel (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }

    // 拷贝结果回主机
    err = musaDeviceSynchronize();
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to synchronize device (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }
    err = musaMemcpy(h_C, d_C, size, musaMemcpyDeviceToHost);
    if (err != musaSuccess) {
        fprintf(stderr, "Failed to copy vector C from device to host (error code %s)!\n", musaGetErrorString(err));
        exit(EXIT_FAILURE);
    }

	    // 验证结果
	    for (int i = 0; i < numElements; ++i) {
	        float diff = (h_A[i] + h_B[i]) - h_C[i];
	        if (diff > 1e-5f || diff < -1e-5f) {
	            fprintf(stderr, "Result verification failed at element %d!\n", i);
	            exit(EXIT_FAILURE);
	        }
	    }
	    printf("测试通过\n");

    // 释放内存
    musaFree(d_A);
    musaFree(d_B);
    musaFree(d_C);
    free(h_A);
    free(h_B);
    free(h_C);
    printf("完成\n");
    return 0;
}
```

## 步骤 4. 编译与运行

```bash
# 使用 MCC 编译器
mcc vectorAdd.mu -lmusart -L/usr/local/musa/lib -o vectorAdd

# 运行程序
./vectorAdd
```

预期输出：

```text
内核启动：196 个块，每块 256 线程
测试通过
完成
```

## （可选）步骤 5. 使用 CMake 构建

对于多文件项目，推荐使用 CMake：

**CMakeLists.txt**：

```cmake
cmake_minimum_required(VERSION 3.10)
project(VectorAdd LANGUAGES CXX)

# 载入 MUSA 模块
list(APPEND CMAKE_MODULE_PATH /usr/local/musa/cmake)
find_package(MUSA REQUIRED)

# 添加可执行文件
musa_add_executable(vectorAdd vectorAdd.mu)
```

**构建步骤**：

```bash
mkdir build && cd build
cmake ..
make
./vectorAdd
```

------------------------------------------------------------------------

## 概念解析

### 内核函数

```cpp
__global__ void vectorAdd(const float* a, const float* b, float* c, int n)
```

| 关键字       | 说明                                          |
|--------------|-----------------------------------------------|
| `__global__` | 声明为 GPU 内核函数，由 CPU 调用，在 GPU 执行 |
| `void`       | 内核函数必须返回 void                         |

### 线程索引计算

```cpp
int idx = blockIdx.x * blockDim.x + threadIdx.x;
``` ```text
全局 ID = 线程块索引 × 线程块大小 + 线程索引
```

| 变量          | 说明                                       |
|---------------|--------------------------------------------|
| `blockIdx.x`  | 线程块在**网格**中的索引                   |
| `blockDim.x`  | 每个**线程块**的线程数（通常 128/256/512） |
| `threadIdx.x` | 线程在**线程块**中的索引                   |

### 内核启动配置

```cpp
int blockSize = 256;
int gridSize = (N + blockSize - 1) / blockSize;  // 向上取整
vectorAdd<<<gridSize, blockSize>>>(d_a, d_b, d_c, N);
```

| 参数        | 说明                       |
|-------------|----------------------------|
| `gridSize`  | **网格**中**线程块**的数量 |
| `blockSize` | 每个**线程块**中的线程数量 |

### 程序执行流程

------------------------------------------------------------------------

## API 速查

### 内存管理

| API                       | 说明         | 示例                               |
|---------------------------|--------------|------------------------------------|
| `musaMalloc()`            | 分配设备内存 | `musaMalloc((void**)&ptr, size)`   |
| `musaMemcpy()`            | 内存拷贝     | `musaMemcpy(dst, src, size, kind)` |
| `musaFree()`              | 释放设备内存 | `musaFree(ptr)`                    |
| `musaDeviceSynchronize()` | 等待设备完成 | `musaDeviceSynchronize()`          |

**拷贝类型**：

| 类型                       | 说明        |
|----------------------------|-------------|
| `musaMemcpyHostToDevice`   | 主机 → 设备 |
| `musaMemcpyDeviceToHost`   | 设备 → 主机 |
| `musaMemcpyDeviceToDevice` | 设备 → 设备 |

### 编译命令

```bash
# 基本编译
mcc app.mu -lmusart -L/usr/local/musa/lib -o app

# 指定优化级别
mcc -O2 app.mu -lmusart -L/usr/local/musa/lib -o app

# 指定目标架构
mcc --offload-arch=mp_21 app.mu -lmusart -L/usr/local/musa/lib -o app
```

------------------------------------------------------------------------

## 内存管理进阶

### 统一内存

```cpp
// 统一内存：CPU 和 GPU 共享同一块内存
float* data;
musaMallocManaged((void**)&data, N * sizeof(float));

// CPU 和 GPU 都可以直接访问
for (int i = 0; i < N; i++) {
    data[i] = float(i);  // CPU 访问
}

vectorAdd<<<gridSize, blockSize>>>(data, data, data, N);  // GPU 访问
```

| 特性           | 设备内存              | 统一内存              |
|----------------|-----------------------|-----------------------|
| **分配 API**   | `musaMalloc()`        | `musaMallocManaged()` |
| **数据拷贝**   | 需要手动 `musaMemcpy` | 自动迁移              |
| **编程复杂度** | 较高                  | 简单                  |
| **适用场景**   | 性能关键应用          | 快速原型              |

### 异步拷贝与计算重叠

使用 **多流（Multi-Stream）** 可以实现数据传输与计算的重叠，提升性能：

```cpp
#include <musa_runtime.h>

// 创建两个流
musaStream_t stream1, stream2;
musaStreamCreate(&stream1);
musaStreamCreate(&stream2);

// 流 1：异步拷贝数据到设备
musaMemcpyAsync(d_a, h_a, size, musaMemcpyHostToDevice, stream1);

// 流 2：在另一个流上执行内核
kernel<<<grid, block, 0, stream2>>>(otherData_d);

// 等待所有流完成
musaStreamSynchronize(stream1);
musaStreamSynchronize(stream2);

// 销毁流
musaStreamDestroy(stream1);
musaStreamDestroy(stream2);
```

**关键点：**

- `musaMemcpyAsync`：异步内存拷贝，立即返回，不阻塞 CPU
- **流（Stream）**：独 立的执行队列，不同流中的操作可以并行执行
- 最后一个参数 `stream`：指定操作在哪个流上执行

------------------------------------------------------------------------

## 常见问题

Q1: `mcc` 命令未找到

**原因**：MUSA SDK 未正确安装或环境变量未配置。

**解决方案**：

```bash
# 检查 MUSA_HOME 是否设置
echo $MUSA_HOME

# 手动设置
export PATH=$MUSA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$MUSA_HOME/lib:$LD_LIBRARY_PATH
```

Q2: 运行时 “invalid device ordinal”

**原因**：GPU 驱动未正确加载或设备未识别。

**解决方案**：

```bash
# 查看可用设备
mthreads-gmi

# 检查驱动状态
lsmod | grep musa

# 重新加载驱动
sudo modprobe -r musa
sudo modprobe musa
```

Q3: 结果不正确或为 0

**原因**：内核可能未执行完成就拷贝结果。

**解决方案**：确保内核完成后再拷贝结果。

```cpp
vectorAdd<<<gridSize, blockSize>>>(...);
musaDeviceSynchronize();  // ← 这行不能少
musaMemcpy(h_c, d_c, size, musaMemcpyDeviceToHost);
```

Q4: 内存泄漏

**解决方案**：确保释放所有分配的内存。

```cpp
// 主机内存
free(h_a); free(h_b); free(h_c);

// 设备内存
musaFree(d_a); musaFree(d_b); musaFree(d_c);
```

Q5: 编译时 “cannot find -lmusart”

**解决方案**：

```bash
# 检查库路径
ls /usr/local/musa/lib/libmusart.so

# 添加库路径
export LD_LIBRARY_PATH=/usr/local/musa/lib:$LD_LIBRARY_PATH
mcc app.mu -lmusart -L/usr/local/musa/lib -o app
```

------------------------------------------------------------------------

## 相关文档

| 主题             | 文档                                                                                                                                                                        |
|------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **内存管理详解** | [高级内存优化](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/l2_cache_management) - Pinned 内存、异步拷贝、共享内存                                     |
| **编译与构建**   | [MCC 编译器](/musa-sdk/musa-sdk-doc-online/toolkits/mcc_compiler) - MCC 选项、CMake 宏、调试工具                                                                            |
| **编程模型**     | [编程模型](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/) - 线程层次、内存层次、流与事件                                                               |
| **性能优化**     | [性能优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/) - Occupancy、内存合并、共享内存                                                             |
| **API 参考**     | [Runtime API](/musa-sdk/musa-sdk-doc-online/libraries/core_api/runtime_api_reference) / [Driver API](/musa-sdk/musa-sdk-doc-online/libraries/core_api/driver_api_reference) |
