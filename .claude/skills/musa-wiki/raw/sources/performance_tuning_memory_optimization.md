<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/performance/tuning_memory_optimization
Title: 内存优化
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# 内存优化

内存优化核心原则

1.  最大化全局内存带宽利用率（合并访存、向量化）
2.  最小化全局内存访问次数（共享内存缓存、寄存器重用）
3.  避免共享内存 Bank Conflict（padding、swizzle 地址映射）

------------------------------------------------------------------------

## 全局内存合并访问

### 合并访存原理

在 GPU 编程中，**合并访存**是指线程束中的线程按照特定规则访问全局内存时，硬件能够将这些分散的内存请求合并为更少的内存事务（transaction），从而显著提高内存访问效率。

**MT GPU S5000 的合并机制**：

- 一个线程束包含 32 个线程
- 每 4 个或 8 个线程为粒度，经过合并单元聚合
- 聚合为多个 128B 的请求（L2 缓存行大小）
- 内存子系统下游均以 128B 事务为单位处理

### 合并访存规则

**完全合并访问**（推荐）：

```cpp
// ✅ Good: 完全合并访问
// 线程 0,1,2,3... 访问地址 0,1,2,3...（连续对齐）
__global__ void coalescedAccess(float* data) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    data[idx] = data[idx] * 2.0f;
}
```

**非合并访问**（避免）：

```cpp
// ❌ Bad: 跨步访问，带宽利用率极低
// 线程 0,1,2,3... 访问地址 0,1024,2048,3072...
__global__ void stridedAccess(float* data, int stride) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    data[idx * stride] = data[idx * stride] * 2.0f;
}
// 带宽利用率：4B/128B = 1/32 ≈ 3%
```

### 访存模式对比

| 访问模式                        | 描述       | 事务数    | 带宽利用率 |
|---------------------------------|------------|-----------|------------|
| 连续 32 线程访问连续 32 地址    | 完全合并   | 1 个事务  | 100%       |
| **连续 32 线程访问间隔 2 地址** | 2-way 跨步 | 2 个事务  | 50%        |
| **连续 32 线程访问间隔 4 地址** | 4-way 跨步 | 4 个事务  | 25%        |
| **随机访问**                    | 无规律     | 32 个事务 | ~3%        |

------------------------------------------------------------------------

## 向量化访存

### 为什么需要向量化？

即使满足合并访存，固定的访问数据量会产生固定数量的 128B 事务（transaction）。但向量化访存仍有以下优势：

1.  **减少访存指令数量**：一条 `float4` 指令替代 4 条 `float` 指令
2.  **降低 LSU**（加载/存储单元）：Load/Store Unit 处理能力有上限，指令过多会导致瓶颈
3.  **提高带宽利用率**：MT GPU S5000 支持最大 1024bit 单指令访问

### 向量化访存示例

```cpp
// ✅ 使用 float4 向量化加载（128bit）
__global__ void vectorLoad(float* in, float* out, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    
    // 将 float 指针转换为 float4 指针
    float4* in_vec  = (float4*)in;
    float4* out_vec = (float4*)out;
    
    // 一次加载 4 个 float
    float4 v = in_vec[idx];
    
    // 计算
    v.x = v.x * 2.0f;
    v.y = v.y * 2.0f;
    v.z = v.z * 2.0f;
    v.w = v.w * 2.0f;
    
    // 一次存储 4 个 float
    out_vec[idx] = v;
}

// 启动配置（线程数减少为 1/4）
int n = 4096;
int threads = n / 4;  // 每个线程处理 4 个元素
VectorLoad<<<1, threads>>>(d_in, d_out, n);
```

### 向量化类型选择

| 数据类型 | 单指令加载 | 适用场景                   |
|----------|------------|----------------------------|
| `float`  | 32-bit     | 基础类型，灵活性高         |
| `float2` | 64-bit     | 小型向量运算               |
| `float4` | 128-bit    | **推荐**，平衡性能与灵活性 |
| `int4`   | 128-bit    | INT8 量化场景              |

------------------------------------------------------------------------

## 共享内存存储体冲突消除

### 存储体冲突（Bank Conflict）原理

共享内存分为 32 个存储体（bank），每个存储体宽度为 4 字节（32 位）。

**存储体冲突**（Bank Conflict）：

- 同一线程束（Warp）中多个线程访问**同一存储体的不同地址** → 序列化访问
- 同一线程束（Warp）中多个线程访问**同一存储体的同一地址** → 广播（无冲突）

存储体冲突（Bank Conflict）示例

```cpp
// ❌ Bad: 32 路存储体冲突
// 所有线程访问第 0 列 → 所有线程访问 bank 0
__shared__ float matrix[32][32];
__global__ void badAccess() {
    int col = 0;
    float value = matrix[threadIdx.x][col];  // 32 路冲突！
}
// 性能下降：串行为 32 次访问

// ✅ Good: 无冲突访问
// 每个线程访问不同 bank
__shared__ float matrix[32][32];
__global__ void goodAccess() {
    int row = 0;
    float value = matrix[row][threadIdx.x];  // 无冲突
}
```

### 解决方案 1：填充（Padding）（简单但浪费容量）

```cpp
// ❌ 32×32 数组，列访问冲突
__shared__ float sharedA[32][32];
value = sharedA[threadIdx.x][col];  // 32 路冲突

// ✅ 添加 padding，32×33 数组
__shared__ float sharedB[32][33];  // 每行多 1 个元素
value = sharedB[threadIdx.x][col];  // 无冲突
// 原理：偏移了 bank 映射，打破对齐
// 缺点：浪费 32 * 4B = 128B 共享内存
```

### 解决方案 2：交错映射（Swizzle）（推荐）

交错映射（Swizzle）通过地址哈希（hash）映射，将连续地址分散到不同存储体（bank）：

```text
原始地址 → Bank 映射（线性）:
地址 0,1,2,3 → Bank 0,1,2,3
地址 4,5,6,7 → Bank 0,1,2,3  (重复)

Swizzle 地址映射（哈希）:
地址 0,1,2,3 → Bank 0,8,16,24
地址 4,5,6,7 → Bank 1,9,17,25  (分散)
```

**MT GPU 硬件支持**：

- MT GPU S5000 及后续架构支持硬件交错映射（swizzle）
- 无需手动填充（padding），编译器自动优化
- 通过访问模式触发（编译器检测）

**代码示例**：

```cpp
// 编译器自动优化 swizzle 的场景
__shared__ float smem[256];
__global__ void swizzleOptimized() {
    // 跨步访问可能触发 swizzle
    int idx = (threadIdx.x * 33) % 256;
    float val = smem[idx];
}
```

### 存储体冲突（Bank Conflict）检查清单

**2D 数组列访问**：检查是否所有线程访问同一列

**动态索引**：避免 `smem[threadIdx.x * stride]` 模式

**填充**（Padding）：容量充足时使用填充

**交错映射**（Swizzle）：利用硬件自动优化

**广播场景**：同一地址访问无需担心冲突

------------------------------------------------------------------------

## 数据结构优化（结构数组 AoS vs 数组结构 SoA）

### 结构数组（AoS，Array of Structures）- 不推荐

```cpp
struct Point {
    float x, y, z, w;  // 16 字节
};

__global__ void processAoS(Point* points, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    // 只访问 x 分量，但会加载整个结构
    float x = points[idx].x * 2.0f;
}
// 带宽浪费：每个线程实际只用了 4B/16B = 25%
```

### 数组结构（SoA，Structure of Arrays）- 推荐

```cpp
struct Points {
    float* x;
    float* y;
    float* z;
    float* w;
};

__global__ void processSoA(Points points, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    // 连续访问 x 数组，实现合并访问
    float x = points.x[idx] * 2.0f;
}
// 带宽利用率：100%，只加载需要的数据
```

### 转换建议

| 场景                        | 推荐布局 | 理由               |
|-----------------------------|----------|--------------------|
| 所有字段频繁访问            | AoS      | 空间局部性好       |
| 部分字段频繁访问            | SoA      | 按需加载，节省带宽 |
| SIMD（单指令多数据）/向量化 | SoA      | 易于向量化加载     |
| 可变长度数据                | SoA      | 内存管理灵活       |

------------------------------------------------------------------------

## 共享内存优化模式

### 矩阵乘法中的共享内存

```cpp
__global__ void matMulShared(float* A, float* B, float* C, int N) {
    __shared__ float tileA[16][16];
    __shared__ float tileB[16][16];
    
    int row = blockIdx.y * 16 + threadIdx.y;
    int col = blockIdx.x * 16 + threadIdx.x;
    
    float sum = 0.0f;
    
    // 分块加载到共享内存
    for (int t = 0; t < (N + 15) / 16; t++) {
        // 从全局内存加载到共享内存（合并访问）
        tileA[threadIdx.y][threadIdx.x] = A[row * N + (t * 16 + threadIdx.x)];
        tileB[threadIdx.y][threadIdx.x] = B[(t * 16 + threadIdx.y) * N + col];
        __syncthreads();
        
        // 在共享内存中计算
        for (int k = 0; k < 16; k++) {
            sum += tileA[threadIdx.y][k] * tileB[k][threadIdx.x];
        }
        __syncthreads();
    }
    
    C[row * N + col] = sum;
}
```

**优化要点**：

1.  分块大小 16×16：平衡占用率与共享内存使用
2.  合并访问加载：`threadIdx.x` 映射到连续地址
3.  共享内存重用：每个元素访问 16 次，减少全局内存访问

### 归约（Reduction）中的共享内存

参考 [归约（Reduction）算法优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/reduction_optimization) 获取详细实现。

------------------------------------------------------------------------

## 性能优化检查清单

### 全局内存优化

**访存是否合并？**

- 线程 ID 是否连续映射到内存地址
- 避免 `idx * stride` 跨步模式

**是否使用向量化？**

- 使用 `float4` 替代 4 次 `float` 访问
- 确保数据对齐（4B 边界，推荐）

**数据结构是否优化？**

- AoS → SoA 转换
- 数据预排序保证连续性

### 共享内存优化

**容量是否充分利用？**

- 优先缓存重复访问的数据
- 平  衡占用率与共享内存使用

**存储体冲突**（Bank Conflict）：

- 检查 2D 数组列访问
- 使用填充（padding）或交错映射（swizzle）

**同步是否正确？**

- `__syncthreads()` 位置合理
- 避免不必要的同步开销

### 寄存器优化

**是否避免溢出？**

- 减少大数组使用
- 溢出到局部内存性能下降 100 倍

**是否充分利用？**

- 循环展开增加寄存器使用
- 平衡占用率与寄存器压力

------------------------------------------------------------------------

## 实战案例：向量加法优化

### 基础版本（带宽利用率 25%）

```cpp
// ❌ 非合并访问 + 标量加载
__global__ void vectorAddSlow(float* a, float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}
```

### 优化版本（带宽利用率 100%）

```cpp
// ✅ 合并访问 + float4 向量化
__global__ void vectorAddFast(float* a, float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    int vec_idx = idx * 4;
    
    if (vec_idx + 3 < n) {
        // 向量化加载
        float4 va = ((float4*)a)[idx];
        float4 vb = ((float4*)b)[idx];
        
        // 向量化计算
        float4 vc;
        vc.x = va.x + vb.x;
        vc.y = va.y + vb.y;
        vc.z = va.z + vb.z;
        vc.w = va.w + vb.w;
        
        // 向量化存储
        ((float4*)c)[idx] = vc;
    }
}

// 启动配置
int n = 4096;
int threads = n / 4;  // 线程数减少为 1/4
vectorAddFast<<<1, threads>>>(d_a, d_b, d_c, n);
```

### 性能对比

| 版本     | 带宽利用率 | 相对性能 |
|----------|------------|----------|
| 基础版本 | 25%        | 1.0x     |
| 优化版本 | 100%       | 3.8x     |

------------------------------------------------------------------------

## 常见问题

Q1: 如何检测存储体冲突（Bank Conflict）？

**A**: 使用 Moore Perf Compute 分析：

```bash
mcu --metrics shared_mem_efficiency -o report ./application
```

- `shared_mem_efficiency` \< 80% 可能存在存储体冲突（Bank Conflict）

Q2: 填充（Padding）会浪费多少共享内存？

**A**: 以 32×32 float 数组为例：

- 原始：32×32×4B = 4096B
- Padding 后：32×33×4B = 4224B
- 浪费：128B (3.1%)

Q3: 向量化访存有什么限制？

**A**: MT GPU S5000 对向量化访问限制较少：

- 数据地址建议 4B 对齐
- 边界处理需特殊判断（确保不越界访问）
- 线程数无需为 4 的倍数
- 硬件会自动处理向量化访存

> **注意**：未来架构可能会有更严格的限制，届时需参考具体架构文档。

------------------------------------------------------------------------

## 相关文档

- [计算优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/compute_optimization)：计算优化
- [Reduction 算法优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/reduction_optimization)：Reduction 算法
- [GEMM/GEMV 优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/gemm_gemv_optimization)：GEMM/GEMV 优化
- [内存层次结构](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/memory_hierarchy)：内存层次结构
- [高级内存优化](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/advanced_memory)：高级内存优化
- [性能分析工具](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/perf_tools)：性能分析工具
