<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/features/green_context
Title: Green Context
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# Green Context

## 概述

**Green Context (GC)** 是 MUSA SDK 5.1.0 引入的轻量级执行上下文机制，允许在创建时就将计算任务与特定的 **MP（Musa Processor）** 资源绑定，确保任务只能使用预留的 MP 资源。

### 面临的挑战

在标准 MUSA 编程模型中，开发者常遇到以下问题：

| 问题                       | 说明                                                   |
|----------------------------|--------------------------------------------------------|
| **无法精确控制 MP 分配**   | 启动计算任务时，无法直接指定使用的 MP 数量             |
| **资源竞争导致性能不稳定** | 多个任务并行运行时，会竞争相同的 MP 资源，造成性能抖动 |
| **延迟不可预期**           | 延迟敏感的任务可能因资源不足而被迫等待，影响服务质量   |

### Green Context 的解决方案

Green Context 通过**资源预留和隔离**机制解决上述问题：

```text
使用 Green Context 前:
时间 →
Kernel A ████████████████████████████████████████
Kernel B                         ████████████████████████████
问题：Kernel B 必须等待 Kernel A 释放 MP 资源

使用 Green Context 后:
时间 →
GC-A (16 MPs)  ██████████████████████████████
GC-B (8 MPs)              ████████████████████████████
解决：Kernel B 保证有 8 个 MP 可用，立即启动
```

### 工作原理

Green Context 的工作流程分为三个阶段：

1.  **资源获取**：查询设备上可用的 MP 资源
2.  **资源划分**：将 MP 资源划分为多个独立的分区
3.  **上下文创建**：为每个分区创建 Green Context，计算任务绑定到特定上下文执行

------------------------------------------------------------------------

## 核心特性

| 特性             | 说明                                   | 优势                             |
|------------------|----------------------------------------|----------------------------------|
| **MP 资源隔离**  | 每个 Green Context 独占分配的 MP 资源  | 避免任务间资源竞争，保证性能稳定 |
| **精确资源控制** | 支持 1-64 个 MP 的精细分配             | 满足不同场景的资源需求           |
| **内核代码透明** | 无需修改内核代码                       | 降低使用门槛，易于集成           |
| **多上下文并行** | 支持创建多个 Green Context 并行执行    | 提高 GPU 利用率                  |
| **与流集成**     | 通过标准流 API 启动任务                | 与现有编程模型无缝兼容           |
| **Event 支持**   | 支持在 Green Context 中记录/等待 Event | 实现复杂的同步依赖               |

------------------------------------------------------------------------

## 快速开始

### 安装

请参阅 [安装指南](/musa-sdk/musa-sdk-doc-online/install_guide) 获取完整的安装步骤。

### 准备工作

#### 硬件要求

- 支持 Green Context 的 MT GPU（S5000 及以上版本推荐）

#### 软件要求

| 要求         | 最低版本 |
|--------------|----------|
| MUSA SDK     | 5.1.0    |
| Linux Driver | 5.1.0    |
| GCC          | 11.4+    |
| CMake        | 3.22+    |

### 基础示例

```cpp
#include <musa.h>
#include <stdio.h>

#define CHECK_MU(call)                                                       \
  do {                                                                         \
    MUresult err = call;                                                     \
    if (err != MUSA_SUCCESS) {                                              \
      fprintf(stderr, "mu error at %s:%d: %s\n", __FILE__, __LINE__,         \
              musaGetErrorString(err));                                      \
      exit(EXIT_FAILURE);                                                    \
    }                                                                          \
  } while (0)

__global__ void vector_multiply(float* data, int size, float factor) {
  int idx = blockIdx.x * blockDim.x + threadIdx.x;
  if (idx < size) {
    data[idx] = data[idx] * factor;
  }
}

int main() {
  // 步骤 1: 获取 GPU 可用 MP 资源
  MUdevice device_id = 0;
  MUdevResource mp_resources;
  CHECK_MU(muDeviceGetDevResource(device_id, &mp_resources,
                                       MU_DEV_RESOURCE_TYPE_SM));

  // 步骤 2: 划分 MP 资源 (16 MPs)
  MUdevResource split_result[1];
  MUdevResource remaining;
  unsigned int actualGroups;

  CHECK_MU(muDevSmResourceSplitByCount(split_result, &actualGroups, &mp_resources,
                                       &remaining, 0, 16));

  // 步骤 3: 创建资源描述符
  MUdevResourceDesc resource_desc;
  CHECK_MU(muDevResourceGenerateDesc(&resource_desc, &split_result[0], 1));

  // 步骤 4: 创建 Green Context
  MUgreenCtx green_ctx;
  CHECK_MU(muGreenCtxCreate(&green_ctx, resource_desc, device_id, 0));

  // 步骤 5: 创建关联的流
  MUstream stream;
  CHECK_MU(muGreenCtxStreamCreate(&stream, green_ctx,
                                           MU_STREAM_DEFAULT, 0));

  // 步骤 6: 启动计算任务
  const int N = 1024 * 1024;
  MUdeviceptr d_data;
  CHECK_MU(muMemAlloc(&d_data, N * sizeof(float)));
  vector_multiply<<<256, 256, 0, stream>>>(d_data, N, 2.0f);
  CHECK_MU(muStreamSynchronize(stream));

  // 清理
  CHECK_MU(muMemFree(d_data));
  CHECK_MU(muStreamDestroy(stream));
  CHECK_MU(muGreenCtxDestroy(green_ctx));

  printf("执行完成！\n");
  return 0;
}
```

------------------------------------------------------------------------

## 运行原理

### 系统架构

备注

Green Context API 属于 **MUSA Driver API** 层级。

### MP 划分方案

#### 均等划分

```text
原始资源：64 MPs
均分为 4 个分区：
┌─────┬─────┬─────┬─────┐
│ 16  │ 16  │ 16  │ 16  │  MPs
└─────┴─────┴─────┴─────┘
   GC1   GC2   GC3   GC4
```

备注

最小 MP 划分数量为 2。

------------------------------------------------------------------------

## 详细 API 使用

### 创建和销毁

#### 创建 Green Context

```cpp
MUdevice device_id = 0;
MUdevResource mp_resources;
muDeviceGetDevResource(device_id, &mp_resources, MU_DEV_RESOURCE_TYPE_SM);

// 划分资源：从总资源中划分出 16 个 MP
MUdevResource split_result[1];
MUdevResource remaining;
unsigned int actualGroups;

muDevSmResourceSplitByCount(split_result, &actualGroups, &mp_resources, &remaining, 0, 16);

// 创建资源描述符
MUdevResourceDesc resource_desc;
muDevResourceGenerateDesc(&resource_desc, &split_result[0], 1);

// 创建 Green Context
MUgreenCtx green_ctx;
MUresult err = muGreenCtxCreate(&green_ctx, resource_desc, device_id, 0);
if (err != MUSA_SUCCESS) {
    // 处理错误
}
```

#### 销毁 Green Context

```cpp
muGreenCtxDestroy(green_ctx);
```

### 资源划分

#### 按数量均分

```cpp
unsigned int numGroups = 4;
unsigned int actualGroups;
MUdevResource result[4];
MUdevResource remaining;

// 自动均分：minPerGroup=0, totalToSplit=0 表示从 initial_resources 中自动均分为 numGroups 组
muDevSmResourceSplitByCount(result, &actualGroups, &initial_resources,
                               &remaining, 0, 0);
// actualGroups 会被设置为实际划分的组数
```

### 流创建

```cpp
MUstream stream;
muGreenCtxStreamCreate(&stream, green_ctx, MU_STREAM_DEFAULT, 0);
```

### 查询操作

#### 获取 Green Context 资源信息

```cpp
MUdevResource gc_resources;
muGreenCtxGetDevResource(green_ctx, &gc_resources);
printf("Green Context 有 %u 个 MPs\n", gc_resources.sm.smCount);
```

#### 从流获取 Green Context

```cpp
MUgreenCtx retrieved_ctx;
muStreamGetGreenCtx(stream, &retrieved_ctx);
```

------------------------------------------------------------------------

## 内存管理

### Green Context 中的内存分配

在 Green Context 中，内存分配通过标准 Driver API 进行，内存实际从 Green Context 绑定的资源中分配：

```cpp
// 在创建 Green Context 后分配内存
MUdeviceptr d_data;
size_t size = 1024 * sizeof(float);

// 使用 muMemAlloc 分配内存，内存与 Green Context 关联
CHECK_MU(muMemAlloc(&d_data, size));

// 使用内核
myKernel<<<blocks, threads, 0, stream>>>(d_data);

// 释放
CHECK_MU(muMemFree(d_data));
```

------------------------------------------------------------------------

## 高级特性

### 多 Green Context 管理

#### 创建多  个 Green Context

```cpp
MUgreenCtx gc_compute, gc_inference;

// 计算 Green Context - 使用较大资源池
MUdevResource compute_res = split_result[0];  // 32 MPs
MUdevResourceDesc compute_desc;
muDevResourceGenerateDesc(&compute_desc, &compute_res, 1);
muGreenCtxCreate(&gc_compute, compute_desc, device_id, 0);
```

------------------------------------------------------------------------

## 最佳实践

### 资源规划

#### 预留系统资源

```cpp
// 获取总 MP 数量
MUdevResource total_resources;
muDeviceGetDevResource(device_id, &total_resources, MU_DEV_RESOURCE_TYPE_SM);

unsigned int total_mp = total_resources.sm.smCount;
unsigned int reserve_mp = total_mp / 8;  // 预留 12.5% 给系统任务
unsigned int available_mp = total_mp - reserve_mp;

// 基于可用资源划分
MUdevResource split_result[1];
MUdevResource remaining;
unsigned int actualGroups;

muDevSmResourceSplitByCount(split_result, &actualGroups, &total_resources, &remaining, 0, available_mp);
```

#### 避免过度划分

```cpp
// ❌ 错误：尝试划分超过可用资源
// 如果只有 64 MPs，但尝试划分 140 MPs
muDevSmResourceSplitByCount(split_result, &actualGroups, &total_resources, &remaining, 0, 140);  // 会导致失败

// ✅ 正确：先查询再划分
MUdevResource resources;
muDeviceGetDevResource(device_id, &resources, MU_DEV_RESOURCE_TYPE_SM);
muDevSmResourceSplitByCount(split_result, &actualGroups, &resources, &remaining, 0, resources.sm.smCount - 8);
```

### 常见陷阱

#### 陷阱 1: 忘记销毁

```cpp
// ❌ 错误：资源泄漏
MUdevice device_id = 0;
MUgreenCtx gc;
MUdevResourceDesc desc;
muGreenCtxCreate(&gc, desc, device_id, 0);
// ... 使用中
// 忘记调用 muGreenCtxDestroy(gc);

// ✅ 正确
MUgreenCtx gc;
CHECK_MU(muGreenCtxCreate(&gc, desc, device_id, 0));
// ... 使用中
CHECK_MU(muGreenCtxDestroy(gc));
```

#### 陷阱 2: 未处理资源不足

```cpp
// ❌ 错误：未检查创建是否成功
MUdevice device_id = 0;
MUdevResourceDesc desc;
muGreenCtxCreate(&gc, desc, device_id, 0);
// 直接使用 gc...

// ✅ 正确
MUresult err = muGreenCtxCreate(&gc, desc, device_id, 0);
if (err == MUSA_ERROR_OUT_OF_MEMORY) {
    // 处理资源不足情况
    fprintf(stderr, "MP 资源不足\n");
}
```

#### 陷阱 3: 流与 Green Context 不匹配

```cpp
// ❌ 错误：使用了错误的流
MUstream stream_a, stream_b;
muGreenCtxStreamCreate(&stream_a, gc_a, 0, 0);
muGreenCtxStreamCreate(&stream_b, gc_b, 0, 0);

myKernel<<<blocks, threads, 0, stream_a>>>(data_b);  // 用 gc_a 的流操作 gc_b 的数据

// ✅ 正确：确保流与 Green Context 对应
myKernel<<<blocks, threads, 0, stream_a>>>(data_a);
myKernel<<<blocks, threads, 0, stream_b>>>(data_b);
```

#### 陷阱 4: 销毁顺序错误

```cpp
// ❌ 错误：先销毁 Green Context 再销毁流
muGreenCtxDestroy(gc);
muStreamDestroy(stream);  // 此时流已无效

// ✅ 正确：先销毁流，再销毁 Green Context
muStreamDestroy(stream);
muGreenCtxDestroy(gc);
```

------------------------------------------------------------------------

## 限制与约束

### 资源限制

| 限制项                        | 值             | 说明                       |
|-------------------------------|----------------|----------------------------|
| 单个 Green Context 最大 MP 数 | 64             | 可配置的 MP 数量上限       |
| 单个 Green Context 最小 MP 数 | 2              | 最小 MP 数量               |
| 最小 MP 分区大小              | 2              | 最小对齐粒度               |
| 单设备最大 Green Context 数量 | 受限于系统资源 | 实际数量取决于可用 MP 资源 |

### API 限制

| 限制                                 | 说明                                  |
|--------------------------------------|---------------------------------------|
| Green Context 创建后不能动态调整资源 | 需要销毁后重建                        |
| Green Context 不能跨设备使用         | 每个设备需要单独创建                  |
| 仅支持 MP 资源类型划分               | Work Queue 资源划分将在未来版本中支持 |

### 硬件支持

| 硬件平台     | Green Context 支持 | 备注             |
|--------------|--------------------|------------------|
| S5000 及以上 | 完整支持           | 推荐使用         |
| 早期型号     | 基础支持           | 可能存在调度限制 |

### 性能监控

可以使用 [Moore Perf](https://docs.mthreads.com/mooreperf/mooreperf-doc-online/introduction/) 工具分析 Green Context 应用程序的性能。Moore Perf Compute 支持收集和分析性能数据，帮助开发者优化应用程序。

------------------------------------------------------------------------

## 故障排除

### 常见问题

Green Context 创建失败

- 可能原因：MP 资源不足
- 解决方案：减少请求的 MP 数量或销毁其他 GC

`MUSA_ERROR_OUT_OF_MEMORY`

- 可能原因：资源已耗尽
- 解决方案：检查是否有未销毁的 Green Context

`MUSA_ERROR_INVALID_VALUE`

- 可能原因：参数无效
- 解决方案：检查 MP 数量是否在对齐范围内

`MUSA_ERROR_INVALID_CONTEXT`

- 可能原因：Green Context 无效
- 解决方案：确认 Green Context 已正确创建且未销毁

Kernel 执行失败

- 可能原因：流未正确关联
- 解决方案：确认流是通过 `muGreenCtxStreamCreate` 创建的

Kernel 执行超时

- 可能原因：资源被占用
- 解决方案：检查是否存在死锁或资源竞争

### 诊断命令

```bash
# 查询设备信息
mthreads-gmi

# 查看 GPU 详细信息
mthreads-gmi -v
```

------------------------------------------------------------------------

## 性能调优

### MP 数量选择

| 应用场景     | 推荐 MP 范围 | 说明                           |
|--------------|--------------|--------------------------------|
| 延迟敏感推理 | 8-16 MPs     | 足够处理单个请求，避免资源浪费 |
| 批量训练任务 | 32-64 MPs    | 最大化并行度                   |
| 多租户共享   | 按需分配     | 根据 SLA 动态分配              |

### 划分方案对比

| 方案     | 吞吐 | 延迟 | 资源利用率 |
|----------|------|------|------------|
| 均等划分 | 中   | 低   | 高         |
| 异构划分 | 高   | 可变 | 中         |

提示

实际性能数据需根据具体应用场景测试获取。

------------------------------------------------------------------------

## API 参考

### 完整 API 列表

#### 资源管理

| API                        | 说明         |
|----------------------------|--------------|
| `muDeviceGetDevResource()` | 获取设备资源 |
| `muStreamGetDevResource()` | 获取流资源   |

#### 资源划分

| API                             | 说明           |
|---------------------------------|----------------|
| `muDevSmResourceSplitByCount()` | 按数量均分资源 |
| `muDevResourceGenerateDesc()`   | 生成资源描述符 |

#### Green Context

| API                          | 说明                    |
|------------------------------|-------------------------|
| `muGreenCtxCreate()`         | 创建 Green Context      |
| `muGreenCtxDestroy()`        | 销毁 Green Context      |
| `muGreenCtxGetDevResource()` | 获取 Green Context 资源 |

#### 流操作

| API                        | 说明                          |
|----------------------------|-------------------------------|
| `muGreenCtxStreamCreate()` | 创建与 Green Context 关联的流 |
| `muStreamGetGreenCtx()`    | 从流获取 Green Context        |

### 事件操作

#### 记录事件

在 Green Context 中记录事件，用于同步：

```cpp
muEvent_t event;
muEventCreate(&event);

muGreenCtxRecordEvent(green_ctx, event);
```

#### 等待事件

等待 Green Context 中记录的事件完成：

```cpp
muGreenCtxWaitEvent(green_ctx, event);
```

备注

Green Context 中的事件需要通过 `muGreenCtxRecordEvent` 和 `muGreenCtxWaitEvent` 进行操作，不能使用标准流事件 API。

### 错误码

| 错误码                                      | 说明               |
|---------------------------------------------|--------------------|
| `MUSA_SUCCESS`                              | 操作成功           |
| `MUSA_ERROR_INVALID_DEVICE`                 | 设备无效           |
| `MUSA_ERROR_INVALID_VALUE`                  | 参数无效           |
| `MUSA_ERROR_INVALID_RESOURCE_CONFIGURATION` | 资源配置无效       |
| `MUSA_ERROR_OUT_OF_MEMORY`                  | 内存/资源不足      |
| `MUSA_ERROR_INVALID_CONTEXT`                | Green Context 无效 |

------------------------------------------------------------------------

## 名词解释

| 术语    | 全称                            | 说明                                                 |
|---------|---------------------------------|------------------------------------------------------|
| **MP**  | MUSA Processor                  | MUSA 处理器，最小计算单元，含 128 个 FP32 单元       |
| **MPX** | MUSA Processor eXecution engine | MUSA 处理器执行引擎，2 个 MP 组成，共享 24KB L1 缓存 |
| **MPC** | MUSA Processor Cluster          | MUSA 处理器簇，2 个 MPX 组成，共享 512KB L2 缓存     |
| **GC**  | Green Context                   | 轻量级执行上下文                                     |
| **WG**  | Work Group                      | 工作组，等价于 thread block                          |
| **WQ**  | Work Queue                      | 工作队列，用于控制并发                               |

------------------------------------------------------------------------

## 附录：完整示例代码

### A.1 多 Green Context 并行

查看示例代码

```cpp
// 创建两个 Green Context 并 行执行
MUgreenCtx gc[2];
MUstream stream[2];

// ... 创建 gc[0] 和 gc[1]

for (int i = 0; i < 2; i++) {
    muGreenCtxStreamCreate(&stream[i], gc[i], 0, 0);
    kernel<<<blocks, threads, 0, stream[i]>>>(data[i]);
}

// 等待所有任务完成
for (int i = 0; i < 2; i++) {
    muStreamSynchronize(stream[i]);
}
```

------------------------------------------------------------------------

## 相关文档

- [MUSA Driver API](/musa-sdk/musa-sdk-doc-online/libraries/core_api/driver_api_reference)：完整 API 参考
- [MUSA 编程模型](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/host_device_model)：主机/设备模型
- [内存管理](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/memory_hierarchy)：内存层次结构
- [MUSA Graphs](/musa-sdk/musa-sdk-doc-online/programming_guide/features/musa_graphs)：图模式编程
