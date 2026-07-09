<!--
Source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/features/musa_graphs
Title: MUSA Graphs
Fetched: 2026-07-07
This file is an immutable raw source. Do not edit.
-->

# MUSA Graphs

图是由一系列操作（如内核启动、数据传输等）通过依赖关系连接形成的工作流程，其定义阶段与执行阶段相互分离。

## 概述

### 什么是 MUSA Graphs

MUSA Graphs 是 MUSA 的一种工作提交模式。图是由一系列操作（如内核启动、数据传输等）通过依赖关系连接形成的工作流程，其定义阶段与执行阶段相互分离。使用该机制，图只需定义一次，之后可重复启动执行。

将图的定义与执行解耦，可实现以下优化：

1.  **降低 CPU 启动开销**：相比于流（stream）方式，大部分设置工作已提前完成
2.  **支持全局优化**：将完整工作流程一次性提交给 MUSA，使一些在流的逐段提交模式下难以实现的优化成为可能

### 优化原理

当将内核放入流中时，主机驱动程序会执行一系列操作，为 GPU 上的内核执行做准备。这些内核设置和启动所需的操作，构成了每次内核启动的固定开销。对于执行时间较短的内核而言，这部分开销可能占总执行时间的很大比例。

通过创建包含多次重复执行的工作流程的 MUSA Graph，这些开销仅在图实例化时产生一次，之后图便可反复启动，且每次启动的开销极低。

### 使用场景

| 场景             | 传统流方式               | 使用 Graph                 |
|------------------|--------------------------|----------------------------|
| **神经网络推理** | 多次内核启动，CPU 开销大 | 单次图执行，降低启动开销   |
| **图像处理管道** | 串行操作，依赖管理复杂   | 流水线图，自动依赖管理     |
| **迭代算法**     | 迭代间同步开销大         | 图重复启动，开销极低       |
| **多租户环境**   | 资源竞争，性能不稳定     | 固定图结构，性能可预测     |
| **低延迟服务**   | CPU 提交延迟占比高       | 一次实例化，多次低开销启动 |

### 核心优势

| 特性           | 传统模式         | Graph 模式                       |
|----------------|------------------|----------------------------------|
| **CPU 开销**   | 每次启动都有开销 | 捕获后重复执行，开销极低         |
| **执行确定性** | 依赖驱动调度     | 图结构固定，执行顺序确定         |
| **多流协调**   | 需手动同步       | 图内依赖自动管理                 |
| **全局优化**   | 局部优化         | 完整工作流一次提交，支持全局优化 |

### 与流式提交的对比

| 维度     | 流式提交             | 图提交               |
|----------|----------------------|----------------------|
| CPU 开销 | 每次启动都需设置     | 一次设置，多次启动   |
| 优化机会 | 局部优化             | 全局优化             |
| 灵活性   | 高，动态工作负载     | 中，适合重复工作负载 |
| 适用场景 | 动态、不可预测的工作 | 固定、重复的工作流程 |

### 快速上手示例

使用流捕获创建一个简单的图：

```cpp
#include <musa_runtime.h>

__global__ void myKernel(float* data, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        data[idx] = data[idx] * 2.0f;
    }
}

int main() {
    float *d_data;
    musaMalloc(&d_data, 1024 * sizeof(float));
    
    musaStream_t stream;
    musaStreamCreate(&stream);
    
    // 1. 开始捕获
    musaStreamBeginCapture(stream, musaStreamCaptureModeGlobal);
    
    // 2. 提交工作（将被捕获到图中）
    myKernel<<<4, 256, 0, stream>>>(d_data, 1024);
    
    // 3. 结束捕获，获取图
    musaGraph_t graph;
    musaStreamEndCapture(stream, &graph);
    
    // 4. 实例化图
    musaGraphExec_t graphExec;
    musaGraphInstantiate(&graphExec, graph, 0);
    
    // 5. 执行图（可重复执行）
    musaGraphLaunch(graphExec, stream);
    musaStreamSynchronize(stream);
    
    // 6. 清理
    musaGraphExecDestroy(graphExec);
    musaGraphDestroy(graph);
    musaStreamDestroy(stream);
    musaFree(d_data);
    
    return 0;
}
```

## 图结构

### 节点与边

在 Graph 中，每个操作构成一个**节点**，操作之间的依赖关系则形成**边**。依赖关系限定了操作的执行顺序。

当某个节点依赖的所有前置节点执行完毕后，该节点对应的操作即可被调度执行。具体调度工作由 MUSA 系统自动管理。

### 节点类型

MUSA Graph 支持以下节点类型：

| 节点类型                  | 常量                                       | 描述             |
|---------------------------|--------------------------------------------|------------------|
| Kernel                    | `musaGraphNodeTypeKernel`                  | GPU 内核执行     |
| Memcpy                    | `musaGraphNodeTypeMemcpy`                  | 内存拷贝         |
| Memset                    | `musaGraphNodeTypeMemset`                  | 内存填充         |
| Host                      | `musaGraphNodeTypeHost`                    | CPU 函数调用     |
| Empty                     | `musaGraphNodeTypeEmpty`                   | 空节点（同步点） |
| Event Record              | `musaGraphNodeTypeEventRecord`             | 记录 MUSA 事件   |
| Event Wait                | `musaGraphNodeTypeEventWait`               | 等待 MUSA 事件   |
| External Semaphore Signal | `musaGraphNodeTypeExternalSemaphoreSignal` | 信号量通知       |
| External Semaphore Wait   | `musaGraphNodeTypeExternalSemaphoreWait`   | 等待外部信号量   |
| Child Graph               | `musaGraphNodeTypeChildGraph`              | 子图节点         |
| MemAlloc                  | `musaGraphNodeTypeMemAlloc`                | 内存分配         |
| MemFree                   | `musaGraphNodeTypeMemFree`                 | 内存释放         |
| Conditional               | `musaGraphNodeTypeConditional`             | 条件节点         |

**对应 API**：

- Kernel 节点：`musaGraphAddKernelNode()`
- Memcpy 节点：`musaGraphAddMemcpyNode()`
- Memset 节点：`musaGraphAddMemsetNode()`
- Host 节点：`musaGraphAddHostNode()`
- Empty 节点：`musaGraphAddEmptyNode()`
- Event Record 节点：`musaGraphAddEventRecordNode()`
- Event Wait 节点：`musaGraphAddEventWaitNode()`
- External Semaphore Signal 节点：`musaGraphAddExternalSemaphoresSignalNode()`
- External Semaphore Wait 节点：`musaGraphAddExternalSemaphoresWaitNode()`
- Child Graph 节点：`musaGraphAddChildGraphNode()`
- MemAlloc 节点：`musaGraphAddMemAllocNode()`
- MemFree 节点：`musaGraphAddMemFreeNode()`
- Conditional 节点：`musaGraphAddNode()`

### 依赖关系

- **上游节点 → 下游节点**：依赖关系决定执行顺序
- **根节点**：无依赖的节点，可立即执行
- **叶节点**：无后续依赖的节点，图执行的结束点

### 边数据（Edge Data）

备注

MUSA 5.1.0 版本目前仅支持默认边。

MUSA 5.1.0 版本引入了对 MUSA Graphs 边数据的支持。边数据用于调整一条边所定义的依赖关系，包含三个部分：

| 组成部分     | 说明                         | 默认值                |
|--------------|------------------------------|-----------------------|
| **输出端口** | 决定关联的边何时触发         | 0（等待整个任务完成） |
| **输入端口** | 指定节点中依赖该边的具体部分 | 0（阻塞整个任务）     |
| **类型**     | 用于调整端点间的关系         | 0（完整依赖）         |

在所有情况下，**零初始化的边数据代表默认行为**。

## 图的工作流程

使用 MUSA Graph 进行任务提交分为四个阶段：

| 阶段                  | API                                            | 说明                           |
|-----------------------|------------------------------------------------|--------------------------------|
| **阶段 1：创建/定义** | `musaGraphCreate()`                            | 描述图中的操作及其依赖         |
| **阶段 2：实例化**    | `musaGraphInstantiate()`                       | 对图模板进行快照、验证和初始化 |
| **阶段 3：执行**      | `musaGraphLaunch()`                            | 将可执行图启动到流中           |
| **阶段 4：销毁**      | `musaGraphExecDestroy()`, `musaGraphDestroy()` | 释放图资源                     |

### 阶段 1：创建

```cpp
musaGraph_t graph;
musaGraphCreate(&graph, 0);

// 添加节点和依赖
musaGraphNode_t kernelNode;
musaKernelNodeParams kernelParams = {0};
kernelParams.func = (void*)myKernel;
kernelParams.gridDim = dim3(256, 1, 1);
kernelParams.blockDim = dim3(256, 1, 1);
kernelParams.sharedMemBytes = 0;
kernelParams.kernelParams = args;

musaGraphAddKernelNode(&kernelNode, graph, NULL, 0, &kernelParams);
```

### 阶段 2：实例化

```cpp
musaGraphExec_t graphExec;
musaGraphInstantiate(&graphExec, graph, 0);
```

### 阶段 3：执行

```cpp
musaStream_t stream;
musaStreamCreate(&stream);
musaGraphLaunch(graphExec, stream);
musaStreamSynchronize(stream);
```

### 阶段 4：销毁

```cpp
musaGraphExecDestroy(graphExec);
musaGraphDestroy(graph);
musaStreamDestroy(stream);
```

## 阶段 1：图创建

图可通过两种机制创建：**使用显式图 API** 或 **通过流捕获**。

### 方法 1：显式图 API

#### 步骤 1：创建空图

```cpp
/**
 * @brief 创建一个空的 MUSA 图
 * @param graph[out] 返回的图句柄
 * @param flags[in] 创建标志（保留供未来使用，传 0）
 * @return musaSuccess, musaErrorInvalidValue
 */
musaError_t musaGraphCreate(musaGraph_t* graph, unsigned int flags);
```

#### 步骤 2：添加内核节点

```cpp
/**
 * @brief 向图中添加一个内核节点
 * @param pGraphNode[out] 返回的节点句柄
 * @param graph[in] 目标图
 * @param pDependencies[in] 依赖节点数组
 * @param numDependencies[in] 依赖节点数量
 * @param pNodeParams[in] 内核节点参数
 */
musaError_t musaGraphAddKernelNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    const struct musaKernelNodeParams *pNodeParams
);
```

**内核节点参数结构：**

```cpp
struct musaKernelNodeParams {
    void* func;              // 内核函数指针
    dim3 gridDim;            // 网格维度
    dim3 blockDim;           // 块维度
    unsigned int sharedMemBytes;  // 共享内存大小
    void **kernelParams;     // 内核参数数组
    void **extra;            // 额外参数
};
```

**示例：**

```cpp
__global__ void vectorAdd(float *a, float *b, float *c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

// 创建图
musaGraph_t graph;
musaGraphCreate(&graph, 0);

// 准备内核参数
float *d_a, *d_b, *d_c;
int n = 1024;
void *args[] = {&d_a, &d_b, &d_c, &n};

musaKernelNodeParams kernelParams = {0};
kernelParams.func = (void*)vectorAdd;
kernelParams.gridDim = dim3((n + 255) / 256, 1, 1);
kernelParams.blockDim = dim3(256, 1, 1);
kernelParams.sharedMemBytes = 0;
kernelParams.kernelParams = args;

// 添加内核节点
musaGraphNode_t kernelNode;
musaGraphAddKernelNode(&kernelNode, graph, NULL, 0, &kernelParams);
```

#### 步骤 3：添加内存拷贝节点

```cpp
musaError_t musaGraphAddMemcpyNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    const struct musaMemcpy3DParms *pCopyParams
);
```

**内存拷贝参数结构：**

```cpp
struct musaMemcpy3DParms {
    musaPitchedPtr srcPtr;
    musaPos srcPos;
    musaPitchedPtr dstPtr;
    musaPos dstPos;
    musaExtent extent;
    enum musaMemcpyKind kind;
};
```

**示例：**

```cpp
// Host 到 Device 拷贝
musaMemcpy3DParms copyParams = {0};
copyParams.srcPtr = make_musaPitchedPtr(h_src, width * sizeof(float), width, 1);
copyParams.dstPtr = make_musaPitchedPtr(d_dst, width * sizeof(float), width, 1);
copyParams.extent = make_musaExtent(width * sizeof(float), 1, 1);
copyParams.kind = musaMemcpyHostToDevice;

musaGraphNode_t memcpyNode;
musaGraphAddMemcpyNode(&memcpyNode, graph, NULL, 0, &copyParams);
```

#### 步骤 4：添加内存填充节点

```cpp
musaError_t musaGraphAddMemsetNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    const struct musaMemsetParams *pMemsetParams
);
```

**内存填充参数结构：**

```cpp
/**
 * @brief 内存填充节点参数结构
 * @note 元素大小必须为 1、2 或 4 字节
 */
struct musaMemsetParams {
    void *dst;           // 目标内存地址
    unsigned int value;  // 填充值
    size_t pitch;        // 跨距（为 0 表示 1D）
    size_t elementSize;  // 元素大小（1、2 或 4 字节）
    size_t width;        // 宽度（元素个数）
    size_t height;       // 高度
};
```

#### 步骤 5：添加空节点

```cpp
musaError_t musaGraphAddEmptyNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies
);
```

空节点不执行任何操作，常用于：

- 作为同步点
- 作为依赖关系的汇合点

#### 步骤 6：添加事件节点

```cpp
// 添加事件记录节点
musaError_t musaGraphAddEventRecordNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    musaEvent_t event
);

// 添加事件等待节点
musaError_t musaGraphAddEventWaitNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    musaEvent_t event
);
```

#### 步骤 7：添加外部信号量节点

**版本要求**: `__MUSART_API_VERSION >= 10200`

```cpp
/**
 * @brief 向图中添加外部信号量通知节点
 * @param pGraphNode[out] 返回的节点句柄
 * @param graph[in] 目标图
 * @param pDependencies[in] 依赖节点数组
 * @param numDependencies[in] 依赖数量
 * @param nodeParams[in] 信号量通知参数
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10200
 */
musaError_t musaGraphAddExternalSemaphoresSignalNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    const struct musaExternalSemaphoreSignalNodeParams *nodeParams
);

/**
 * @brief 向图中添加外部信号量等待节点
 * @param pGraphNode[out] 返回的节点句柄
 * @param graph[in] 目标图
 * @param pDependencies[in] 依赖节点数组
 * @param numDependencies[in] 依赖数量
 * @param nodeParams[in] 信号量等待参数
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10200
 */
musaError_t musaGraphAddExternalSemaphoresWaitNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    const struct musaExternalSemaphoreWaitNodeParams *nodeParams
);
```

#### 步骤 8：添加依赖关系

```cpp
musaError_t musaGraphAddDependencies(
    musaGraph_t graph,
    const musaGraphNode_t *from,
    const musaGraphNode_t *to,
    size_t numDependencies
);
```

### 方法 2：流捕获

流捕获提供了一种通过现有流 API 创建图的机制。任何向流提交工作的代码段，都可通过捕获 API 生成图。

#### 步骤 1：开始捕获

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 捕获模式枚举
 */
enum musaStreamCaptureMode {
    musaStreamCaptureModeGlobal,       // 捕获上下文中所有流（默认）
    musaStreamCaptureModeThreadLocal,  // 仅捕获调用线程的流
    musaStreamCaptureModeRelaxed       // 宽松模式，允许部分额外操作
};

/**
 * @brief 开始流捕获
 * @param stream[in] 要捕获的流
 * @param mode[in] 捕获模式
 * @note 捕获必须在同一流上结束
 */
musaError_t musaStreamBeginCapture(musaStream_t stream, enum musaStreamCaptureMode mode);
```

**捕获模式：**

| 模式                               | 说明                       |
|------------------------------------|----------------------------|
| `musaStreamCaptureModeGlobal`      | 捕获上下文中所有流（默认） |
| `musaStreamCaptureModeThreadLocal` | 仅捕获调用线程的流         |
| `musaStreamCaptureModeRelaxed`     | 宽松模式，允许部分额外操作 |

#### 步骤 2：捕获到现有图

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 开始流捕获到现有图
 * @param stream[in] 要捕获的流
 * @param graph[in] 要捕获到的现有图
 * @param dependencies[in] 依赖节点数组
 * @param dependencyData[in] 依赖边数据数组
 * @param numDependencies[in] 依赖数量
 * @param mode[in] 捕获模式
 * @note 此 API 允许将工作捕获到用户提供的现有图中
 */
musaError_t musaStreamBeginCaptureToGraph(
    musaStream_t stream,
    musaGraph_t graph,
    const musaGraphNode_t *dependencies,
    const musaGraphEdgeData *dependencyData,
    size_t numDependencies,
    enum musaStreamCaptureMode mode
);
```

#### 步骤 3：结束捕获

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 结束流捕获，返回构建的图
 * @param stream[in] 要结束捕获的流
 * @param pGraph[out] 返回的图句柄
 * @note 必须在开始捕获的同一流上调用
 */
musaError_t musaStreamEndCapture(
    musaStream_t stream,
    musaGraph_t *pGraph
);
```

#### 基本捕获示例

```cpp
musaGraph_t graph;
musaStream_t stream;
musaStreamCreate(&stream);

// 开始捕获
musaStreamBeginCapture(stream, musaStreamCaptureModeGlobal);

// 提交工作（这些操作将被捕获到图中）
kernel_A<<<grid, block, 0, stream>>>(...);
kernel_B<<<grid, block, 0, stream>>>(...);
kernel_C<<<grid, block, 0, stream>>>(...);

// 结束捕获，返回图
musaStreamEndCapture(stream, &graph);
```

#### 跨流依赖

流捕获能够处理通过 `musaEventRecord()` 和 `musaStreamWaitEvent()` 表达的跨流依赖关系，前提是所等待的事件被记录在同一捕获图中。

```cpp
musaStream_t stream1, stream2;
musaStreamCreate(&stream1);
musaStreamCreate(&stream2);
musaEvent_t event1, event2;
musaEventCreate(&event1);
musaEventCreate(&event2);
musaGraph_t graph;

// stream1 是原始流
musaStreamBeginCapture(stream1, musaStreamCaptureModeGlobal);

kernel_A<<<..., stream1>>>(...);

// 分叉到 stream2
musaEventRecord(event1, stream1);
musaStreamWaitEvent(stream2, event1);

kernel_B<<<..., stream1>>>(...);
kernel_C<<<..., stream2>>>(...);

// 汇合 stream2 回到原始流
musaEventRecord(event2, stream2);
musaStreamWaitEvent(stream1, event2);

kernel_D<<<..., stream1>>>(...);

// 在原始流中结束捕获
musaStreamEndCapture(stream1, &graph);

// stream1 和 stream2 不再处于捕获模式
```

#### 捕获内省

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 流捕获状态枚举
 */
enum musaStreamCaptureStatus {
    musaStreamCaptureStatusNone,         // 未捕获
    musaStreamCaptureStatusActive,       // 捕获进行中
    musaStreamCaptureStatusInvalidated   // 捕获已失效
};

/**
 * @brief 查询流捕获信息
 * @param stream[in] 要查询的流
 * @param captureStatus_out[out] 捕获状态
 * @param id_out[out] 捕获的唯一 ID
 * @param graph_out[out] 底层图对象
 * @param dependencies_out[out] 依赖关系数组
 * @param numDependencies_out[out] 依赖数量
 * @note 此 API 用于检查活跃的流捕获操作
 */
musaError_t musaStreamGetCaptureInfo(
    musaStream_t stream,
    enum musaStreamCaptureStatus *captureStatus_out,
    unsigned long long *id_out,
    musaGraph_t *graph_out,
    const musaGraphNode_t **dependencies_out,
    size_t *numDependencies_out
);

/**
 * @brief 查询流是否处于捕获状态
 * @param stream[in] 要查询的流
 * @return musaSuccess (捕获中), musaErrorInvalidValue (非捕获中)
 */
musaError_t musaStreamIsCapturing(musaStream_t stream);
```

#### 步骤 4：更新捕获依赖

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 更新流捕获的依赖关系
 * @param stream[in] 要更新的流
 * @param dependencies[in] 依赖节点数组
 * @param numDependencies[in] 依赖数量
 * @param flags[in] 更新标志（默认为 0）
 * @note 此 API 用于在捕获过程中动态修改依赖关系
 */
musaError_t musaStreamUpdateCaptureDependencies(
    musaStream_t stream,
    musaGraphNode_t *dependencies,
    size_t numDependencies,
    unsigned int flags __dv(0)
);
```

### 捕获模式

| 模式            | 行为                                         | 使用场景           |
|-----------------|----------------------------------------------|--------------------|
| **Global**      | 如果同上下文中其他流有捕获，会加入同一捕获图 | 默认推荐，多流协作 |
| **ThreadLocal** | 仅捕获当前线程，禁止与其他流合并             | 多线程隔离场景     |
| **Relaxed**     | 允许更多操作，但需谨慎使用                   | 特殊高级场景       |

## 阶段 2：图实例化

### 基本实例化

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 实例化图为可执行图
 * @param pGraphExec[out] 返回的可执行图句柄
 * @param graph[in] 要实例化的图
 * @param flags[in] 实例化标志（默认为 0）
 * @note flags 参数默认值为 0
 */
musaError_t musaGraphInstantiate(
    musaGraphExec_t *pGraphExec,
    musaGraph_t graph,
    unsigned long long flags __dv(0)
);
```

### 带标志的实例化

**版本要求**: `__MUSART_API_VERSION >= 10400`

```cpp
/**
 * @brief 使用标志实例化图为可执行图
 * @param pGraphExec[out] 返回的可执行图句柄
 * @param graph[in] 要实例化的图
 * @param flags[in] 实例化标志
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
musaError_t musaGraphInstantiateWithFlags(
    musaGraphExec_t *pGraphExec,
    musaGraph_t graph,
    unsigned long long flags __dv(0)
);
```

**实例化标志：**

| 标志                                       | 说明                           |
|--------------------------------------------|--------------------------------|
| `musaGraphInstantiateFlagAutoFreeOnLaunch` | 启动时自动释放未释放的内存分配 |
| `musaGraphInstantiateFlagDeviceLaunch`     | 启用设备端图启动               |
| `musaGraphInstantiateFlagUseNodePriority`  | 使用节点优先级而非流优先级     |

### 带参数的实例化

**版本要求**: `__MUSART_API_VERSION >= 10400`

```cpp
/**
 * @brief 图实例化结果枚举
 */
typedef enum {
    musaGraphInstantiateSuccess = 0,              // 实例化成功
    musaGraphInstantiateError = 1,                // 无效参数或意外错误
    musaGraphInstantiateInvalidStructure = 2,     // 图结构无效
    musaGraphInstantiateNodeOperationNotSupported = 3,  // 节点操作不支持
    musaGraphInstantiateMultipleDevicesNotSupported = 4 // 多设备不支持
} musaGraphInstantiateResult;

/**
 * @brief 图实例化参数结构
 */
typedef struct {
    unsigned long long flags;           // 实例化标志
    musaGraphNode_t errNode_out;        // 出错节点输出
    musaGraphInstantiateResult result_out; // 实例化结果输出
} musaGraphInstantiateParams;

/**
 * @brief 使用参数实例化图为可执行图
 * @param pGraphExec[out] 返回的可执行图句柄
 * @param graph[in] 要实例化的图
 * @param instantiateParams[in] 实例化参数
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
musaError_t musaGraphInstantiateWithParams(
    musaGraphExec_t *pGraphExec,
    musaGraph_t graph,
    musaGraphInstantiateParams *instantiateParams
);
```

**实例化结果：**

| 结果值                                            | 说明               |
|---------------------------------------------------|--------------------|
| `musaGraphInstantiateSuccess`                     | 成功               |
| `musaGraphInstantiateError`                       | 无效参数或意外错误 |
| `musaGraphInstantiateInvalidStructure`            | 图结构无效         |
| `musaGraphInstantiateNodeOperationNotSupported`   | 节点操作不支持     |
| `musaGraphInstantiateMultipleDevicesNotSupported` | 多设备不支持       |

### 实例化示例

```cpp
musaGraphExec_t graphExec;
musaGraphInstantiateParams params = {0};
params.flags = musaGraphInstantiateFlagAutoFreeOnLaunch;

musaError_t err = musaGraphInstantiateWithParams(&graphExec, graph, &params);
if (err != musaSuccess) {
    printf("Instantiate failed: %d, node: %p, result: %d\n",
           err, params.errNode_out, params.result_out);
}
```

## 阶段 3：图执行

### 启动图

```cpp
musaError_t musaGraphLaunch(
    musaGraphExec_t graphExec,
    musaStream_t stream
);
```

### 执行示例

```cpp
musaStream_t stream;
musaStreamCreate(&stream);

// 启动图
musaGraphLaunch(graphExec, stream);
musaStreamSynchronize(stream);

// 清理
musaStreamDestroy(stream);
```

## 图更新

### 整图更新

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 图执行更新结果枚举
 */
typedef enum {
    musaGraphExecUpdateSuccess = 0,           // 更新成功
    musaGraphExecUpdateError = 1,             // 无效参数或意外错误
    musaGraphExecUpdateErrorTopologyChanged = 2,    // 图拓扑结构改变
    musaGraphExecUpdateErrorNodeTypeChanged = 3,    // 节点类型改变
    musaGraphExecUpdateErrorFunctionChanged = 4,    // 内核函数改变
    musaGraphExecUpdateErrorParametersChanged = 5,  // 参数改变不支持
    musaGraphExecUpdateErrorAttributesChanged = 6,  // 属性改变不支持
    musaGraphExecUpdateErrorNotSupported = 7        // 不支持的操作
} musaGraphExecUpdateResult;

/**
 * @brief 图执行更新结果信息结构
 */
typedef struct {
    musaGraphExecUpdateResult result;      // 更新结果代码
    musaGraphNode_t errorNode;             // 出错节点（如果有）
    musaGraphNode_t errorFromNode;         // 依赖不匹配的源节点（如果有）
} musaGraphExecUpdateResultInfo;

/**
 * @brief 更新已实例化的图
 * @param hGraphExec[in] 要更新的可执行图
 * @param hGraph[in] 包含更新参数的图
 * @param resultInfo[out] 更新结果信息
 */
musaError_t musaGraphExecUpdate(
    musaGraphExec_t hGraphExec,
    musaGraph_t hGraph,
    musaGraphExecUpdateResultInfo *resultInfo
);
```

**更新结果：**

| 结果值                                      | 说明           |
|---------------------------------------------|----------------|
| `musaGraphExecUpdateSuccess`                | 更新成功       |
| `musaGraphExecUpdateErrorTopologyChanged`   | 图拓扑结构改变 |
| `musaGraphExecUpdateErrorNodeTypeChanged`   | 节点类型改变   |
| `musaGraphExecUpdateErrorFunctionChanged`   | 内核函数改变   |
| `musaGraphExecUpdateErrorParametersChanged` | 参数改变不支持 |
| `musaGraphExecUpdateErrorAttributesChanged` | 属性改变不支持 |
| `musaGraphExecUpdateErrorNotSupported`      |   不支持的操作   |

### 内核节点更新

```cpp
musaError_t musaGraphExecKernelNodeSetParams(
    musaGraphExec_t hGraphExec,
    musaGraphNode_t node,
    const struct musaKernelNodeParams *pNodeParams
);
```

### 内存拷贝节点更新

```cpp
musaError_t musaGraphExecMemcpyNodeSetParams(
    musaGraphExec_t hGraphExec,
    musaGraphNode_t node,
    const struct musaMemcpy3DParms *pNodeParams
);
```

### 内存填充节点更新

```cpp
musaError_t musaGraphExecMemsetNodeSetParams(
    musaGraphExec_t hGraphExec,
    musaGraphNode_t node,
    const struct musaMemsetParams *pNodeParams
);
```

### 节点启用与禁用

```cpp
musaError_t musaGraphNodeSetEnabled(
    musaGraphExec_t hGraphExec,
    musaGraphNode_t hNode,
    unsigned int isEnabled
);

musaError_t musaGraphNodeGetEnabled(
    musaGraphExec_t hGraphExec,
    musaGraphNode_t hNode,
    unsigned int *isEnabled
);
```

### 更新限制

| 节点类型 | 可更新内容              | 不可更新内容         |
|----------|-------------------------|----------------------|
| Kernel   | 参数值、grid/block 维度 | 函数指针（某些情况） |
| Memcpy   | 源/目的指针、大小       | 内存类型、传输类型   |
| Memset   | 值、指针、大小          | 内存类型             |

## 内存节点

### 内存分配节点

**版本要求**: `__MUSART_API_VERSION >= 10400`

```cpp
/**
 * @brief 内存分配节点参数结构
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
struct musaMemAllocNodeParams {
    musaMemPoolProps poolProps;      // 内存池属  性
    musaMemAccessDesc *accessDescs;  // 访问描述符数组
    size_t accessDescCount;          // 访问描述符数量
    size_t bytesize;                 // 分配大小（字节）
    void *dptr;                      // 返回的分配地址（输出）
};

/**
 * @brief 向图中添加内存分配节点
 * @param pGraphNode[out] 返回的节点句柄
 * @param graph[in] 目标图
 * @param pDependencies[in] 依赖节点数组
 * @param numDependencies[in] 依赖数量
 * @param nodeParams[in/out] 分配参数（dptr 字段为输出）
 */
musaError_t musaGraphAddMemAllocNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    struct musaMemAllocNodeParams *nodeParams
);
```

### 内存释放节点

**版本要求**: `__MUSART_API_VERSION >= 10400`

```cpp
/**
 * @brief 向图中添加内存释放节点
 * @param pGraphNode[out] 返回的节点句柄
 * @param graph[in] 目标图
 * @param pDependencies[in] 依赖节点数组
 * @param numDependencies[in] 依赖数量
 * @param dptr[in] 要释放的设备内存地址
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
musaError_t musaGraphAddMemFreeNode(
    musaGraphNode_t *pGraphNode,
    musaGraph_t graph,
    const musaGraphNode_t *pDependencies,
    size_t numDependencies,
    void *dptr
);
```

### 图内存管理

**版本要求**: `__MUSART_API_VERSION >= 10400`

```cpp
/**
 * @brief 图内存属性类型枚举
 */
enum musaGraphMemAttributeType {
    musaGraphMemAttrUsedMemCurrent = 1,      // 当前已使用的图内存
    musaGraphMemAttrUsedMemHigh = 2,         // 历史最高使用量
    musaGraphMemAttrReservedMemCurrent = 3,  // 当前预留的图内存
    musaGraphMemAttrReservedMemHigh = 4      // 历史最高预留量
};

/**
 * @brief 查询图内存属性
 * @param device[in] 设备 ID
 * @param attr[in] 要查询的属性类型
 * @param value[out] 返回的属性值
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
musaError_t musaDeviceGetGraphMemAttribute(
    int device,
    enum musaGraphMemAttributeType attr,
    void* value
);

/**
 * @brief 设置图内存属性
 * @param device[in] 设备 ID
 * @param attr[in] 要设置的属性类型
 * @param value[in] 属性值
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
musaError_t musaDeviceSetGraphMemAttribute(
    int device,
    enum musaGraphMemAttributeType attr,
    void* value
);

/**
 * @brief 修剪图内存，释放未使用的缓存内存回操作系统
 * @param device[in] 设备 ID
 * @note 此 API 需要 MUSA Runtime API 版本 >= 10400
 */
musaError_t musaDeviceGraphMemTrim(int device);
```

## 查询与调试

### 图查询 API

**版本要求**: `__MUSART_API_VERSION >= 10000`

```cpp
/**
 * @brief 获取图的所有节点
 * @param graph[in] 要查询的图
 * @param nodes[out] 节点数组（可为 NULL，仅获取数量）
 * @param numNodes[in/out] 输入：数组大小；输出：实际节点数量
 * @note 如果 nodes 为 NULL，则返回节点总数
 */
musaError_t musaGraphGetNodes(
    musaGraph_t graph,
    musaGraphNode_t *nodes,
    size_t *numNodes
);

/**
 * @brief 获取图的根节点（无依赖的节点）
 * @param graph[in] 要查询的图
 * @param pRootNodes[out] 根节点数组（可为 NULL，仅获取数量）
 * @param pNumRootNodes[in/out] 输入：数组大小；输出：实际根节点数量
 */
musaError_t musaGraphGetRootNodes(
    musaGraph_t graph,
    musaGraphNode_t *pRootNodes,
    size_t *pNumRootNodes
);

/**
 * @brief 获取图的边（依赖关系）
 * @param graph[in] 要查询的图
 * @param from[out] 源节点数组
 * @param to[out] 目标节点数组
 * @param numEdges[in/out] 输入：数组大小；输出：实际边数量
 */
musaError_t musaGraphGetEdges(
    musaGraph_t graph,
    musaGraphNode_t *from,
    musaGraphNode_t *to,
    size_t *numEdges
);
```

### 节点查询 API

```cpp
// 获取节点类型
musaError_t musaGraphNodeGetType(
    musaGraphNode_t node,
    enum musaGraphNodeType *pType
);

// 获取节点依赖
musaError_t musaGraphNodeGetDependencies(
    musaGraphNode_t node,
    musaGraphNode_t *pDependencies,
    size_t *pNumDependencies
);

// 获取节点的后继节点
musaError_t musaGraphNodeGetDependentNodes(
    musaGraphNode_t node,
    musaGraphNode_t *pDependentNodes,
    size_t *pNumDependentNodes
);
```

### 可视化调试

```cpp
/**
 * @brief 将图导出为 DOT 格式
 * @param graph[in] 要导出的图
 * @param path[in] 输出文件路径
 * @param flags[in] 导出标志
 */
musaError_t musaGraphDebugDotPrint(
    musaGraph_t graph,
    const char *path,
    unsigned int flags
);
```

**使用 Graphviz 渲染：**

```bash
# 转换为 PNG
dot -Tpng my_graph.dot -o my_graph.png

# 转换为 PDF
dot -Tpdf my_graph.dot -o my_graph.pdf
```

### 克隆图

```cpp
musaError_t musaGraphClone(
    musaGraph_t *pGraphClone,
    musaGraph_t originalGraph
);

musaError_t musaGraphNodeFindInClone(
    musaGraphNode_t *pNode,
    musaGraphNode_t originalNode,
    musaGraph_t clonedGraph
);
```

## 完整示例

### 示例 1：向量加法

查看示例代码

```cpp
#include <musa_runtime.h>
#include <stdio.h>

#define N 1024

__global__ void scaleKernel(const float* input, float* output, float scale, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        output[idx] = input[idx] * scale;
    }
}

__global__ void addKernel(const float* a, const float* b, float* c, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        c[idx] = a[idx] + b[idx];
    }
}

int main() {
    // 分配内存
    float *h_a = (float*)malloc(N * sizeof(float));
    float *h_b = (float*)malloc(N * sizeof(float));
    float *h_c = (float*)malloc(N * sizeof(float));
    
    float *d_a, *d_b, *d_temp, *d_c;
    musaMalloc(&d_a, N * sizeof(float));
    musaMalloc(&d_b, N * sizeof(float));
    musaMalloc(&d_temp, N * sizeof(float));
    musaMalloc(&d_c, N * sizeof(float));
    
    // 初始化数据
    for (int i = 0; i < N; i++) {
        h_a[i] = (float)i;
        h_b[i] = (float)(i * 2);
    }
    
    // 创建图
    musaGraph_t graph;
    musaGraphCreate(&graph, 0);
    
    musaGraphNode_t nodes[4];
    
    // 节点 0: Host 到 Device 拷贝 a
    musaMemcpy3DParms copyA = {0};
    copyA.srcPtr = make_musaPitchedPtr(h_a, N * sizeof(float), N, 1);
    copyA.dstPtr = make_musaPitchedPtr(d_a, N * sizeof(float), N, 1);
    copyA.extent = make_musaExtent(N * sizeof(float), 1, 1);
    copyA.kind = musaMemcpyHostToDevice;
    musaGraphAddMemcpyNode(&nodes[0], graph, NULL, 0, &copyA);
    
    // 节点 1: Host 到 Device 拷贝 b
    musaMemcpy3DParms copyB = {0};
    copyB.srcPtr = make_musaPitchedPtr(h_b, N * sizeof(float), N, 1);
    copyB.dstPtr = make_musaPitchedPtr(d_b, N * sizeof(float), N, 1);
    copyB.extent = make_musaExtent(N * sizeof(float), 1, 1);
    copyB.kind = musaMemcpyHostToDevice;
    musaGraphAddMemcpyNode(&nodes[1], graph, NULL, 0, &copyB);
    
    // 节点 2: a * 2 -> temp（依赖于节点 0）
    void *args1[] = {&d_a, &d_temp, &(float){2.0f}, &(int){N}};
    musaKernelNodeParams params1 = {0};
    params1.func = (void*)scaleKernel;
    params1.gridDim = dim3((N + 255) / 256, 1, 1);
    params1.blockDim = dim3(256, 1, 1);
    params1.kernelParams = args1;
    musaGraphAddKernelNode(&nodes[2], graph, &nodes[0], 1, &params1);
    
    // 节点 3: b * 3 -> b（依赖于节点 1）
    void *args2[] = {&d_b, &d_b, &(float){3.0f}, &(int){N}};
    musaKernelNodeParams params2 = {0};
    params2.func = (void*)scaleKernel;
    params2.gridDim = dim3((N + 255) / 256, 1, 1);
    params2.blockDim = dim3(256, 1, 1);
    params2.kernelParams = args2;
    musaGraphAddKernelNode(&nodes[3], graph, &nodes[1], 1, &params2);
    
    // 节点 4: temp + b -> c（依赖于节点 2 和 3）
    musaGraphNode_t addDeps[] = {nodes[2], nodes[3]};
    void *args3[] = {&d_temp, &d_b, &d_c, &(int){N}};
    musaKernelNodeParams params3 = {0};
    params3.func = (void*)addKernel;
    params3.gridDim = dim3((N + 255) / 256, 1, 1);
    params3.blockDim = dim3(256, 1, 1);
    params3.kernelParams = args3;
    musaGraphNode_t addNode;
    musaGraphAddKernelNode(&addNode, graph, addDeps, 2, &params3);
    
    // 节点 5: Device 到 Host 拷贝结果（依赖于节点 4）
    musaMemcpy3DParms copyC = {0};
    copyC.srcPtr = make_musaPitchedPtr(d_c, N * sizeof(float), N, 1);
    copyC.dstPtr = make_musaPitchedPtr(h_c, N * sizeof(float), N, 1);
    copyC.extent = make_musaExtent(N * sizeof(float), 1, 1);
    copyC.kind = musaMemcpyDeviceToHost;
    musaGraphNode_t memcpyC;
    musaGraphAddMemcpyNode(&memcpyC, graph, &addNode, 1, &copyC);
    
    // 实例化图
    musaGraphExec_t graphExec;
    musaGraphInstantiate(&graphExec, graph, 0);
    
    // 执行图
    musaStream_t stream;
    musaStreamCreate(&stream);
    musaGraphLaunch(graphExec, stream);
    musaStreamSynchronize(stream);
    
    // 验证结果
    printf("Results (first 10):\n");
    for (int i = 0; i < 10; i++) {
        printf("  c[%d] = %f (expected: %f)\n", i, h_c[i], h_a[i]*2 + h_b[i]*3);
    }
    
    // 清理
    musaGraphExecDestroy(graphExec);
    musaGraphDestroy(graph);
    musaStreamDestroy(stream);
    musaFree(d_a);
    musaFree(d_b);
    musaFree(d_temp);
    musaFree(d_c);
    free(h_a);
    free(h_b);
    free(h_c);
    
    return 0;
}
```

### 示例 2：流捕获

查看示例代码

```cpp
#include <musa_runtime.h>

__global__ void kernelA(float *data, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) data[i] *= 2.0f;
}

__global__ void kernelB(float *data, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) data[i] += 1.0f;
}

int main() {
    float *d_data;
    float *h_data = (float*)malloc(1024 * sizeof(float));
    musaMalloc(&d_data, 1024 * sizeof(float));
    
    // 初始化
    for (int i = 0; i < 1024; i++) h_data[i] = (float)i;
    musaMemcpy(d_data, h_data, 1024 * sizeof(float), musaMemcpyHostToDevice);
    
    // 创建流
    musaStream_t stream;
    musaStreamCreate(&stream);
    
    musaGraph_t graph;
    
    // 开始捕获
    musaStreamBeginCapture(stream, musaStreamCaptureModeGlobal);
    
    // 提交工作（将被捕获）
    kernelA<<<4, 256, 0, stream>>>(d_data, 1024);
    kernelB<<<4, 256, 0, stream>>>(d_data, 1024);
    kernelA<<<4, 256, 0, stream>>>(d_data, 1024);
    
    // 结束捕获
    musaStreamEndCapture(stream, &graph);
    
    // 实例化并执行
    musaGraphExec_t graphExec;
    musaGraphInstantiate(&graphExec, graph, 0);
    
    // 可重复执行
    for (int i = 0; i < 100; i++) {
        musaGraphLaunch(graphExec, stream);
    }
    musaStreamSynchronize(stream);
    
    // 清理
    musaGraphExecDestroy(graphExec);
    musaGraphDestroy(graph);
    musaStreamDestroy(stream);
    musaFree(d_data);
    free(h_data);
    
    return 0;
}
```

## 限制与注意事项

### 限制 1：流捕获限制

| 限制               | 说明                                                     |
|--------------------|----------------------------------------------------------|
| 不能同步捕获中的流 | 在捕获期间对正在被捕获的流进行同步是无效的               |
| 不能使用传统流     | 当非阻塞流正在捕获时，不能使用 `musaStreamLegacy`        |
| 不能调用同步 API   | 如 `musaMemcpy()` 等同步 API 在捕获期间无效              |
| 不能合并独立捕获图 | 试图通过等待来自不同捕获图的事件来合并两个捕获图是无效的 |

### 限制 2：图更新限制

| 节点类型 | 限制                                               |
|----------|----------------------------------------------------|
| Kernel   | 不能改变所属上下文，不能从无动态并行改为有动态并行 |
| Memcpy   | 不能改变内存类型、传输类型                         |
| Memset   | 不能改变内存类型                                   |
| 所有节点 | 拓扑结构不能改变                                   |

### 限制 3：一般性限制

1.  **线程安全**：`musaGraph_t` 对象不是线程安全的
2.  **并发执行**：同一 `musaGraphExec_t` 不能与自身并发执行
3.  **内存管理**：图销毁不自动释放内存（除非使用 `AutoFreeOnLaunch` 标志）
4.  **设备限制**：图的节点必须位于同一设备上

### 限制 4：无效操作

| 场景                 | 结果                 |
|----------------------|----------------------|
| 捕获期间同步         | 返回错误，捕获图失效 |
| 等待不同捕获图的事件 | 无效操作             |
| 使用不支持的 API     | 返回错误             |

------------------------------------------------------------------------

## 相关文档

- [MUSA Runtime API](/musa-sdk/musa-sdk-doc-online/libraries/core_api/runtime_api_reference)：完整 API 参考
- [流和事件](/musa-sdk/musa-sdk-doc-online/programming_guide/programming_model/host_device_model)：MUSA 流模型
- [性能优化](/musa-sdk/musa-sdk-doc-online/programming_guide/performance_tuning/)：性能优化技巧
