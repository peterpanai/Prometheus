<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/musa/cpp_syntax_intro_to_musa_cpp
Title: MUSA C++ 语言扩展
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# MUSA C++ 语言扩展

## 概述

MUSA C++ 扩展是 MCC 编译器为 MTGPU 编程提供的语言扩展。它保持了与标准 C++ 的兼容性，同时添加了用于表达并行计算的语法结构。

**核心扩展内容**：

- 函数限定符：`__global__`, `__device__`, `__host__`
- 内存限定符：`__shared__`, `__constant__`, `__managed__`
- 内置变量：`threadIdx`, `blockIdx`, `gridDim`, `blockDim`
- Kernel 启动语法：`<<<grid, block>>>`

本文档详细介绍 MUSA C++ 扩展的语法和用法。

------------------------------------------------------------------------

## 变量限定符

### **device** 限定符

`__device__` 限定符声明的函数在 MUSA 设备上执行：

```cpp
__device__ float device_function(float x) {
    return x * x + 1.0f;
}
```

### **host** 限定符

`__host__` 限定符声明的函数在 MUSA 主机上执行：

```cpp
__host__ float host_function(float x) {
    return std::sqrt(x);
}
```

### **global** 限定符

`__global__` 限定符声明从主机调用、在设备上执行的函数（核函数）：

```cpp
__global__ void vector_add_kernel(
    const float *a, 
    const float *b, 
    float *c, 
    int n
) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}
```

### **device** **host** 组合

同时使用两个限定符可以使函数同时支持设备和主机：

```cpp
__device__ __host__ float compatible_function(float x) {
    return x * 2.0f;
}
```

------------------------------------------------------------------------

## 内置变量

MCC 提供了预定义的内置变量：

### 线程索引

```cpp
// 线程在块内的索引
threadIdx.x  // 0 到 blockDim.x - 1
threadIdx.y  // 0 到 blockDim.y - 1
threadIdx.z  // 0 到 blockDim.z - 1
```

### 块索引

```cpp
// 块在网格中的索引
blockIdx.x   // 0 到 gridDim.x - 1
blockIdx.y   // 0 到 gridDim.y - 1
blockIdx.z   // 0 到 gridDim.z - 1
```

### 块维度

```cpp
// 块的维度（线程数）
blockDim.x
blockDim.y
blockDim.z
```

### 网格维度

```cpp
// 网格的维度（块数）
gridDim.x
gridDim.y
gridDim.z
```

### Warp 信息

```cpp
// Warp 大小（取决于设备：S5000 为 32，M1000/S4000 为 128）
warpSize
```

------------------------------------------------------------------------

## 内置函数概览

MUSA 提供丰富的设备端内置函数，详细说明请参阅 [原子函数](/musa-sdk/musa-sdk-doc-online/programming_guide/musa_cpp_syntax/atomic_functions) 和 [Warp 函数](/musa-sdk/musa-sdk-doc-online/programming_guide/musa_cpp_syntax/warp_functions)。

### 同步函数

| 函数                    | 作用域 | 说明                             |
|-------------------------|--------|----------------------------------|
| `__syncthreads()`       | 线程块 | 块内所有线程的同步屏障           |
| `__threadfence()`       | 系统级 | 确保所有内存写操作对其他线程可见 |
| `__threadfence_block()` | 线程块 | 确保块内所有内存写操作可见       |
| `__syncwarp()`          | 线程束 | 线程束级同步屏障                 |

### 原子函数

| 函数                                       | 说明         |
|--------------------------------------------|--------------|
| `atomicAdd()`, `atomicSub()`               | 原子加减     |
| `atomicExch()`                             | 原子交换     |
| `atomicInc()`, `atomicDec()`               | 原子递增递减 |
| `atomicAnd()`, `atomicOr()`, `atomicXor()` | 原子位运算   |
| `atomicCAS()`                              | 原子比较交换 |

备注

原子函数支持 `_block` 和 `_system` 变体，分别用于块级和系统级作用域。

### Warp 级函数

| 函数                           | 说明                  |
|--------------------------------|-----------------------|
| `__shfl_sync()`                | Warp 内线程间数据交换 |
| `__all_sync()`, `__any_sync()` | Warp 投票             |
| `__ballot_sync()`              | 位选投票              |
| `__reduce_*_sync()`            | Warp 归约操作         |

### 数学函数

```cpp
// 标准精度
sin(x), cos(x), exp(x), log(x), sqrt(x)

// 快速版本（低精度，高性能）
__sinf(x), __cosf(x), __expf(x), __logf(x), __sqrtf(x)
```

| 函数类型 | 精度 | 性能 | 适用场景     |
|----------|------|------|--------------|
| 标准函数 | 高   | 中   | 精确计算     |
| 快速函数 | 低   | 高   | 性能敏感场景 |

------------------------------------------------------------------------

## 核函数配置

### 执行配置

核函数启动使用 `<<<grid, block, shared_mem, stream>>>` 语法：

```cpp
// grid: 网格维度（块数）
// block: 块维度（每块线程数）
// shared_mem: 动态共享内存大小（字节）
// stream: 执行流

kernel_name<<<grid_dim, block_dim, shared_mem, stream>>>(args);
```

### 示例

```cpp
// 一维配置
int n = 1024;
int block_size = 256;
int grid_size = (n + block_size - 1) / block_size;
kernel<<<grid_size, block_size>>>(args);

// 二维配置（图像处理）
dim3 block(16, 16);
dim3 grid((width + 15) / 16, (height + 15) / 16);
kernel<<<grid, block>>>(args);
```

------------------------------------------------------------------------

## 内存模型

MUSA 支持多种内存类型，详细说明请参考 [内存层次结构](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/memory_hierarchy)。

### 全局内存

```cpp
// 在全局内存中声明变量
__device__ float global_array[1024];

// 动态分配全局内存（Runtime API）
float* d_ptr;
musaMalloc(&d_ptr, size);
```

### 共享内存

```cpp
// 静态共享内存
__global__ void kernel1() {
    __shared__ float shared_mem[256];
    // 使用 shared_mem
}

// 动态共享内存（通过核函数配置传递）
__global__ void kernel2() {
    extern __shared__ float shared_mem[];
    // 使用 shared_mem
}

// 启动时指定大小
kernel2<<<grid, block, 256 * sizeof(float)>>>(args);
```

### 常量内存

```cpp
// 声明常量内存
__constant__ float const_array[1024];

// 从主机初始化
musaMemcpyToSymbol(const_array, h_data, size);
```

备注

纹理内存和表面函数的详细说明请参考 [内存层次结构](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/memory_hierarchy)。

------------------------------------------------------------------------

## 编译指示

### 循环展开

```cpp
#pragma unroll
for (int i = 0; i < 8; i++) {
    // 编译器展开循环，提高性能
}
```

### 强制内联

```cpp
__forceinline__ float fast_add(float a, float b) {
    return a + b;
}
```

------------------------------------------------------------------------

## 错误处理

MUSA 使用 `musaError_t` 类型表示错误：

```cpp
typedef enum musaError_enum {
    musaSuccess = 0,           // 成功
    musaErrorInvalidValue = 1, // 无效参数
    musaErrorMemoryAllocation = 2,  // 内存分配失败
    musaErrorInitializationError = 3,
    musaErrorInvalidDevice = 101,
    musaErrorInvalidKernel = 300,
    musaErrorLaunchFailure = 400,
    // ... 更多错误代码
} musaError_t;
```

**错误处理示例**：

```cpp
musaError_t err = musaMalloc(&ptr, size);
if (err != musaSuccess) {
    fprintf(stderr, "Memory allocation failed: %d\n", err);
    return -1;
}
```

------------------------------------------------------------------------

## 扩展关键字总览

| 关键字         | 描述       |
|----------------|------------|
| `__device__`   | 设备函数   |
| `__host__`     | 主机函数   |
| `__global__`   | 核函数     |
| `__shared__`   | 共享内存   |
| `__constant__` | 常量内存   |
| `__managed__`  | 统一内存   |
| `__restrict__` | 指针非别名 |
| `__inline__`   | 内联函数   |
| `__noinline__` | 不内联     |

------------------------------------------------------------------------

## 相关文档

- [MUSA SDK 概述](/musa-sdk/musa-sdk-doc-online/programming_guide/what_is_musa/gpu_parallel_basics)
- [编程模型概述](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/host_device_model)
- [原子函数](/musa-sdk/musa-sdk-doc-online/programming_guide/musa_cpp_syntax/atomic_functions)
- [Warp 函数](/musa-sdk/musa-sdk-doc-online/programming_guide/musa_cpp_syntax/warp_functions)

------------------------------------------------------------------------
