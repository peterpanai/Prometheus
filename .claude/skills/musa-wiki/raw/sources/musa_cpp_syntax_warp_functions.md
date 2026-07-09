<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/musa/cpp_syntax_warp_functions
Title: Warp 函数
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# Warp 函数

Warp 函数提供**线程束** (Warp) 级别的同步、投票和数据交换操作。这些函数允许同一 warp 内的线程进行高效协作，而无需使用共享内存。

备注

Warp 是 MTGPU 的基本执行单元。Warp 大小因设备而异：

- MTT S5000 系列：warpSize = 32 线程
- MTT M1000/S4000 系列：warpSize = 128 线程

使用 `warpSize` 内置变量获取当前设备的实际 Warp 大小。

## 同步函数

### \_\_syncthreads()

```cpp
void __syncthreads();
```

在线程块中的所有线程都达到这一点之前等待，并使 `__syncthreads()` 之前进行的所有全局和共享内存访问对块中的所有线程可见。

**用途**: 协调同一 block 内线程之间的通信。

```cpp
__global__ void sharedMemoryExample(float* data) {
    __shared__ float shared[256];
    int tid = threadIdx.x;
    
    // 加载数据到共享内存
    shared[tid] = data[tid];
    
    // 等待所有线程完成加载
    __syncthreads();
    
    // 安全地使用共享内存
    float result = shared[tid] * 2.0f;
}
```

### \_\_syncthreads_count()

```cpp
int __syncthreads_count(int predicate);
```

基本功能与 `__syncthreads()` 相同，附加功能是会针对块的所有线程计算 `predicate`，并返回计算结果为非零的线程数。

```cpp
__global__ void countActive(float* data, int* count, int n) {
    int tid = threadIdx.x;
    int active = (tid < n && data[tid] > 0.0f) ? 1 : 0;
    
    // 计算 block 内活跃的线程数
    int activeCount = __syncthreads_count(active);
    
    if (tid == 0) {
        *count = activeCount;
    }
}
```

### \_\_syncthreads_and()

```cpp
int __syncthreads_and(int predicate);
```

基本功能与 `__syncthreads()` 相同，附加功能是会针对块的所有线程计算 `predicate`，并当且仅当所有线程的计算结果都为非零时返回非零值。

```cpp
__global__ void checkAllPositive(float* data, bool* allPositive, int n) {
    int tid = threadIdx.x;
    int isPositive = (tid < n && data[tid] > 0.0f) ? 1 : 0;
    
    // 检查所有线程的数据是否都是正数
    int all = __syncthreads_and(isPositive);
    
    if (tid == 0) {
        *allPositive = (all != 0);
    }
}
```

### \_\_syncthreads_or()

```cpp
int __syncthreads_or(int predicate);
```

基本功能与 `__syncthreads()` 相同，附加功能是会针对块的所有线程计算 `predicate`，并当且仅当至少一个线程的计算结果为非零时返回非零值。

```cpp
__global__ void checkAnyPositive(float* data, bool* anyPositive, int n) {
    int tid = threadIdx.x;
    int isPositive = (tid < n && data[tid] > 0.0f) ? 1 : 0;
    
    // 检查是否有任意线程的数据是正数
    int any = __syncthreads_or(isPositive);
    
    if (tid == 0) {
        *anyPositive = (any != 0);
    }
}
```

备注

`__syncthreads()` 在条件代码中是允许的，但前提是条件在整个线程块中的计算方式相同，否则代码执行可能会挂起或产生意外的副作用。

------------------------------------------------------------------------

## Warp 同步函数

### \_\_syncwarp()

```cpp
void __syncwarp(unsigned mask = 0xffffffff);
```

将导致执行线程等待，直到掩码中覆盖的同一线程束内所有线程都执行了一次 `__syncwarp()`（使用相同的掩码），然后再恢复执行。

**用途**: Warp 级别的同步，保证参与栅栏同步的线程之间的内存顺序。

```cpp
__global__ void warpSyncExample(float* data) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;  // warp 内的 lane 索引
    
    // 写入数据
    data[tid] = laneId * 1.0f;
    
    // Warp 级别同步
    __syncwarp();
    
    // 读取其他 lane 的数据（保证可见）
    float fromLane0 = data[tid - laneId];
}
```

------------------------------------------------------------------------

## Warp 投票函数

Warp 投票函数允许给定线程束的线程执行归约和广播操作。

### \_\_all_sync()

```cpp
int __all_sync(unsigned mask, int predicate);
```

评估 `mask` 所包含的所有未退出线程的 `predicate` 值，当且仅当所有线程的计算结果为非零时返回非零值。

```cpp
__global__ void allPositiveCheck(float* data, bool* result, int n) {
    int tid = threadIdx.x;
    int predicate = (tid < n && data[tid] > 0.0f);
    
    // 检查 warp 内所有线程是否都满足条件
    int all = __all_sync(0xffffffff, predicate);
    
    if (threadIdx.x == 0) {
        result[blockIdx.x] = (all != 0);
    }
}
```

### \_\_any_sync()

```cpp
int __any_sync(unsigned mask, int predicate);
```

评估 `mask` 所包含的所有未退出线程的 `predicate` 值，当且仅当至少一个线程的计算结果为非零时返回非零值。

```cpp
__global__ void anyPositiveCheck(float* data, bool* result, int n) {
    int tid = threadIdx.x;
    int predicate = (tid < n && data[tid] > 0.0f);
    
    // 检查 warp 内是否有任意线程满足条件
    int any = __any_sync(0xffffffff, predicate);
    
    if (threadIdx.x == 0) {
        result[blockIdx.x] = (any != 0);
    }
}
```

### \_\_ballot_sync()

```cpp
unsigned __ballot_sync(unsigned mask, int predicate);
```

评估 `mask` 所包含的所有未退出线程的 `predicate` 值，并将结果作为一个 32 位整数返回。每个线程的返回值都对应整数一位，如果线程未退出且 `predicate` 值非零则该位为 1，否则为 0。

```cpp
__global__ void ballotExample(float* data, unsigned* result, int n) {
    int tid = threadIdx.x;
    int predicate = (tid < n && data[tid] > 0.0f);
    
    // 获取 warp 内所有线程的条件位掩码
    unsigned ballot = __ballot_sync(0xffffffff, predicate);
    
    if (threadIdx.x == 0) {
        result[blockIdx.x] = ballot;
    }
}
```

**示例**: 如果 warp 内有 4 个线程，线程 0 和 2 的 predicate 为 1，线程 1 和 3 的 predicate 为 0，则返回值为 `0b0101 = 5`。

### \_\_activemask()

```cpp
unsigned __activemask();
```

返回一个 32 位整数，每个线程都对应整数的一位。如果线程未退出则该位为 1，否则为 0。

```cpp
__global__ void activeMaskExample(unsigned* result) {
    int tid = threadIdx.x;
    
    // 获取当前 warp 内活跃线程的掩码
    unsigned activeMask = __activemask();
    
    if (tid == 0) {
        result[blockIdx.x] = activeMask;
    }
}
```

备注

Warp 投票函数并不意味着栅栏同步。它们不保证任何访存顺序。

------------------------------------------------------------------------

## Warp 值交换函数

线程束值交换函数允许在线程束内的线程间交换一个值，而无需使用共享内存。

### 函数原型

```cpp
T __shfl_sync(unsigned mask, T var, int srcLane, int width = warpSize);
T __shfl_up_sync(unsigned mask, T var, unsigned int delta, int width = warpSize);
T __shfl_down_sync(unsigned mask, T var, unsigned int delta, int width = warpSize);
T __shfl_xor_sync(unsigned mask, T var, int laneMask, int width = warpSize);
```

其中 `T` 可以是以下类型：

- 整数类型：`int`, `unsigned int`, `long`, `unsigned long`, `long long`, `unsigned long long`
- 浮点类型：`float`, `double`

### \_\_shfl_sync() - 直接索引拷贝

从 `srcLane` 指定的通道中直接拷贝 `var` 值。

```cpp
__global__ void shflExample(float* output) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;
    
    float value = laneId * 1.0f;
    
    // 从 lane 0 获取值
    float fromLane0 = __shfl_sync(0xffffffff, value, 0);
    
    output[tid] = fromLane0;  // 所有线程都得到 lane 0 的值
}
```

### \_\_shfl_up_sync() - 向上拷贝

从相较于调用线程索引更低的通道中拷贝（向上移动 `delta` 个通道）。

```cpp
__global__ void shflUpExample(float* data) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;
    
    float value = data[tid];
    
    // 从上方 (laneId - 2) 的线程获取值
    float fromUpper = __shfl_up_sync(0xffffffff, value, 2);
    
    // lane 0 和 1 会收到自己的值（不会环绕）
    if (laneId >= 2) {
        data[tid] = fromUpper;
    }
}
```

### \_\_shfl_down_sync() - 向下拷贝

从相较于调用线程索引更高的通道中拷贝（向下移动 `delta` 个通道）。

```cpp
__global__ void shflDownExample(float* data) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;
    
    float value = data[tid];
    
    // 从下方 (laneId + 2) 的线程获取值
    float fromLower = __shfl_down_sync(0xffffffff, value, 2);
    
    // lane 30 和 31 会收到自己的值（不会环绕）
    if (laneId < warpSize - 2) {
        data[tid] = fromLower;
    }
}
```

### \_\_shfl_xor_sync() - 异或索引拷贝

从调用线程索引的异或结果通道中拷贝。实现蝴蝶寻址模式，用于树归约和广播。

```cpp
__global__ void shflXorExample(float* data) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;
    
    float value = data[tid];
    
    // 与 laneId ^ 1 的线程交换值（相邻线程交换）
    float fromNeighbor = __shfl_xor_sync(0xffffffff, value, 1);
    
    data[tid] = fromNeighbor;
}
```

------------------------------------------------------------------------

## 应用示例

### Warp 内归约求和

```cpp
__device__ float warpReduceSum(float value) {
    value += __shfl_xor_sync(0xffffffff, value, 16);
    value += __shfl_xor_sync(0xffffffff, value, 8);
    value += __shfl_xor_sync(0xffffffff, value, 4);
    value += __shfl_xor_sync(0xffffffff, value, 2);
    value += __shfl_xor_sync(0xffffffff, value, 1);
    return value;
}

__global__ void reduceSumKernel(float* input, float* output, int n) {
    __shared__ float shared[1024];
    int tid = threadIdx.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // 加载数据
    shared[tid] = (idx < n) ? input[idx] : 0.0f;
    __syncthreads();
    
    // 块内归约
    for (int s = blockDim.x / 2; s >= warpSize; s >>= 1) {
        if (tid < s) {
            shared[tid] += shared[tid + s];
        }
        __syncthreads();
    }
    
    // Warp 内归约
    float partialSum = shared[tid];
    if (tid < warpSize) {
        float reduced = warpReduceSum(partialSum);
        if (tid == 0) {
            atomicAdd(output, reduced);
        }
    }
}
```

### Warp 内广播

```cpp
__device__ float warpBroadcast(float value, int broadcastLane) {
    return __shfl_sync(0xffffffff, value, broadcastLane);
}

__global__ void broadcastExample(float* data, float* result) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;
    
    // 读取数据
    float value = data[tid];
    
    // 从 lane 0 广播
    float broadcasted = warpBroadcast(value, 0);
    
    result[tid] = broadcasted;
}
```

### Warp 级别前缀和（Scan）

```cpp
__device__ float warpScanInclusive(float value) {
    float temp = __shfl_up_sync(0xffffffff, value, 1);
    if (threadIdx.x % warpSize >= 1) value += temp;
    
    temp = __shfl_up_sync(0xffffffff, value, 2);
    if (threadIdx.x % warpSize >= 2) value += temp;
    
    temp = __shfl_up_sync(0xffffffff, value, 4);
    if (threadIdx.x % warpSize >= 4) value += temp;
    
    temp = __shfl_up_sync(0xffffffff, value, 8);
    if (threadIdx.x % warpSize >= 8) value += temp;
    
    temp = __shfl_up_sync(0xffffffff, value, 16);
    if (threadIdx.x % warpSize >= 16) value += temp;
    
    return value;
}

__global__ void scanKernel(float* input, float* output, int n) {
    int tid = threadIdx.x;
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    float value = (idx < n) ? input[idx] : 0.0f;
    
    // Warp 级前缀和
    float result = warpScanInclusive(value);
    
    if (idx < n) {
        output[idx] = result;
    }
}
```

### 使用 ballot 进行动态并行

```cpp
__global__ void dynamicParallelism(float* data, int n) {
    int tid = threadIdx.x;
    int laneId = tid % warpSize;
    
    // 检查哪些线程需要处理
    int needsWork = (tid < n && data[tid] > 1.0f) ? 1 : 0;
    
    // 获取需要处理的线程掩码
    unsigned ballot = __ballot_sync(0xffffffff, needsWork);
    
    if (ballot != 0) {
        // 至少有一个线程需要工作
        // 可以进一步处理...
    }
}
```

------------------------------------------------------------------------

## 使用注意事项

| 注意事项       | 说明                                                           |
|----------------|----------------------------------------------------------------|
| **掩码一致性** | 每个调用线程必须在掩码中设置自己的位                           |
| **收敛要求**   | 掩码中包含的所有非退出线程必须使用相同的掩码执行相同的内部函数 |
| **未定义行为** | 如果掩码不一致或线程未正确收敛，结果是未定义的                 |
| **非栅栏同步** | Warp 投票函数和值交换函数不保证任何访存顺序                    |
| **width 参数** | 必 须是 2 的幂，且不能大于 warpSize                             |

------------------------------------------------------------------------

## 类型支持

| 函数类型                                    | 支持的类型                                                                                           |
|---------------------------------------------|------------------------------------------------------------------------------------------------------|
| `__shfl_*`                                  | `int`, `unsigned int`, `long`, `unsigned long`, `long long`, `unsigned long long`, `float`, `double` |
| `__all_sync`, `__any_sync`, `__ballot_sync` | `predicate`: 任何可转换为 bool 的类型                                                                |
| `__activemask`                              | 无参数，返回 `unsigned`                                                                              |

------------------------------------------------------------------------

## 相关文档

- [原子函数](/musa-sdk/musa-sdk-doc-online/programming_guide/musa_cpp_syntax/atomic_functions)
- [MUSA C++ 语言扩展](/musa-sdk/musa-sdk-doc-online/programming_guide/musa_cpp_syntax/intro_to_musa_cpp)
