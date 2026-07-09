<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/programming/model_thread_indexing
Title: 线程索引计算
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# 线程索引计算

本文档是线程索引计算的速查手册，提供常用的索引计算公式和模式。

## 内置变量

每个线程通过内置变量获取其在层次结构中的位置：

| 变量        | 含义                       | 维度      |
|-------------|----------------------------|-----------|
| `threadIdx` | 线程在线程块内的索引       | (x, y, z) |
| `blockIdx`  | 线程块在网格内的索引       | (x, y, z) |
| `blockDim`  | 线程块的维度大小（线程数） | (x, y, z) |
| `gridDim`   | 网格的维度大小（线程块数） | (x, y, z) |

------------------------------------------------------------------------

## 索引计算公式

### 一维索引（最常用）

```cpp
// 全局线程 ID
int idx = blockIdx.x * blockDim.x + threadIdx.x;
``` ```text
全局 ID = 线程块索引 × 线程块大小 + 线程索引
```

**示例**：

```cpp
__global__ void vectorAdd(const float* a, const float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}
```

### 二维索引（图像处理常用）

```cpp
// 二维线程块内的线程 ID
int x = blockIdx.x * blockDim.x + threadIdx.x;
int y = blockIdx.y * blockDim.y + threadIdx.y;

// 转换为一维索引（行优先）
int idx = y * width + x;
```

**示例**：

```cpp
__global__ void imageKernel(float* input, float* output, int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    
    if (x < width && y < height) {
        int idx = y * width + x;
        output[idx] = input[idx] * 2.0f;
    }
}
```

### 三维索引（体积数据常用）

```cpp
int x = blockIdx.x * blockDim.x + threadIdx.x;
int y = blockIdx.y * blockDim.y + threadIdx.y;
int z = blockIdx.z * blockDim.z + threadIdx.z;

// 转换为一维索引
int idx = (z * height + y) * width + x;
```

### 边界检查

```cpp
// 始终检查边界，防止越界访问
if (idx < n) {
    // 安全访问
    data[idx] = data[idx] * 2.0f;
}
```

------------------------------------------------------------------------

## 常用索引计算模式

### 矩阵索引（行主序）

```cpp
// 二维矩阵处理
__global__ void matrixKernel(float* matrix, int rows, int cols) {
    int row = blockIdx.y * blockDim.y + threadIdx.y;
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (row < rows && col < cols) {
        // 行主序：row * cols + col
        int idx = row * cols + col;
        matrix[idx] = matrix[idx] * 2.0f;
    }
}

// 启动配置
dim3 blockSize(16, 16);
dim3 gridSize((cols + 15) / 16, (rows + 15) / 16);
```

### 3D 数据索引

```cpp
// 3D 体积数据处理
__global__ void volumeKernel(float* volume, int depth, int height, int width) {
    int z = blockIdx.z * blockDim.z + threadIdx.z;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    
    if (z < depth && y < height && x < width) {
        // 3D 转 1D：(z * height + y) * width + x
        int idx = (z * height + y) * width + x;
        volume[idx] = volume[idx] * 2.0f;
    }
}
```

### 带偏移的索引

```cpp
// 处理有偏移的数据
int baseIdx = blockIdx.x * blockDim.x + threadIdx.x;
int idx = baseIdx + offset;

if (idx < n) {
    data[idx] = data[idx] * 2.0f;
}
```

### 多线程处理多个元素

```cpp
// 每个线程处理多个元素（提高带宽利用率）
__global__ void multiElementKernel(float* data, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int stride = blockDim.x * gridDim.x;  // 总线程数
    
    for (int i = idx; i < n; i += stride) {
        data[i] = data[i] * 2.0f;
    }
}

// 启动配置（线程数可以减少）
int blockSize = 256;
int gridSize = (n + blockSize * 4 - 1) / (blockSize * 4);
multiElementKernel<<<gridSize, blockSize>>>(data, n);
```

------------------------------------------------------------------------

## 网格大小计算

### 向上取整

```cpp
// 通用公式：向上取整
int gridSize = (n + blockSize - 1) / blockSize;
```

### 二维网格

```cpp
dim3 blockSize(16, 16);
dim3 gridSize((width + 15) / 16, (height + 15) / 16);
```

### 三维网格

```cpp
dim3 blockSize(8, 8, 8);
dim3 gridSize(
    (width + 7) / 8,
    (height + 7) / 8,
    (depth + 7) / 8
);
```

------------------------------------------------------------------------

## 索引计算速查表

| 场景            | 索引公式                                      |
|-----------------|-----------------------------------------------|
| 一维数组        | `idx = blockIdx.x * blockDim.x + threadIdx.x` |
| 二维矩阵（行）  | `row = blockIdx.y * blockDim.y + threadIdx.y` |
| 二维矩阵（列）  | `col = blockIdx.x * blockDim.x + threadIdx.x` |
| 矩阵 1D 索引    | `idx = row * cols + col`                      |
| 3D 体积 1D 索引 | `idx = (z * height + y) * width + x`          |
| 多元素处理      | `for (i = idx; i < n; i += stride)`           |

------------------------------------------------------------------------

## 注意事项

### 整数溢出

```cpp
// 大尺寸数据使用 long long
long long idx = (long long)blockIdx.x * blockDim.x + threadIdx.x;
```

### 边界检查

```cpp
// 必须检查边界
if (idx < n) {
    // 安全访问
}
```

### 对齐访问

```cpp
// 向量化访问需要地址对齐
if (idx % 4 == 0 && idx + 3 < n) {
    float4 v = ((float4*)data)[idx / 4];
}
```

------------------------------------------------------------------------

## 相关文档

- [线程层次结构](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/thread_hierarchy)：Grid/Block/Thread 组织
- [执行模型](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/execution_model)：SIMT 并行执行
- [内存层次结构](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/memory_hierarchy)：寄存器/共享内存/全局内存
