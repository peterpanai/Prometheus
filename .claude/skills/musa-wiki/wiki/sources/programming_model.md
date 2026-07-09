---
title: "编程模型 — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources:
  - programming_model.md
  - programming_model_host_device_model.md
  - programming_model_thread_hierarchy.md
  - programming_model_memory_hierarchy.md
  - programming_model_execution_model.md
  - programming_model_thread_indexing.md
  - programming_model_l2_cache_management.md
  - programming_model_advanced_memory.md
tags: [musa, programming-model, simt, threads, memory, l2-cache, cluster, streams]
---

# MUSA 编程模型 (Programming Model)

The MUSA programming model is the abstraction layer between the developer and the MT GPU hardware. It defines how work is organized, how data moves, and how threads cooperate. The model has four pillars:

1. **Host/Device model** — CPU controls, GPU computes; separate memory spaces.
2. **Thread hierarchy** — Grid → Block → Thread, with Warp as the hardware execution unit.
3. **Memory hierarchy** — registers, shared, L1/L2, constant, global, plus host-side pinned/mapped/WC.
4. **Execution model** — SIMT with warp-level scheduling, branch divergence serialization, latency hiding via warp swapping.

## Source Pages

| Raw File | Title | Covers |
|----------|-------|--------|
| `programming_model.md` | MUSA 编程模型 | Chapter index — links to the 7 sub-pages |
| `programming_model_host_device_model.md` | Host/Device 编程模型 | Host vs Device responsibilities, memory mgmt, data transfer, streams, events, kernel launch |
| `programming_model_thread_hierarchy.md` | 线程层次结构 | Grid/Block/Thread, block sizing, warp concept, occupancy, sync |
| `programming_model_memory_hierarchy.md` | 内存层次结构 | Registers, shared, global, constant, host memory types, coalescing, bank conflicts, AoS vs SoA |
| `programming_model_execution_model.md` | 执行模型 | SIMT vs SIMD, warp execution, branch divergence, latency hiding, atomics overview, warp primitives |
| `programming_model_thread_indexing.md` | 线程索引计算 | 1D/2D/3D index formulas, boundary checks, grid size calc, integer overflow |
| `programming_model_l2_cache_management.md` | L2 缓存管理 | L2 persistence, access policy window, streaming vs persisting accesses |
| `programming_model_advanced_memory.md` | 高级内存优化 | Pinned memory, zero-copy, write-combined, L2 set-aside, Cluster memory, async execution |

## Key Takeaways per Pillar

### 1. Host/Device Model

- Host = sequential control flow; Device = parallel kernel execution.
- Separate address spaces — data must be copied via `musaMemcpy` / `musaMemcpyAsync`.
- Unified memory (`musaMallocManaged`) is available but has page-migration overhead on first access.
- Streams enable concurrent kernel execution; events enable inter-stream sync and timing.

### 2. Thread Hierarchy

| Level | Scope | Sync | Memory Shared |
|-------|-------|------|---------------|
| Thread | 1 thread | — | registers (private) |
| Block | ≤ 1024 threads | `__syncthreads()` works | shared memory |
| Grid | all blocks | NO cross-block sync | global memory |
| Warp | hardware unit (32 or 128) | `__syncwarp()` | shuffle/ballot |

- **Block size**: must be a multiple of warp size. Common values: 128, 256, 512.
- **Max block dims**: (1024, 1024, 64); max threads/block = 1024; shared mem/block = 48-96 KB.
- **Max grid dims**: (2³¹−1, 65535, 65535).
- **Why no cross-block sync**: blocks can be scheduled in any order, on any MP; requiring inter-block sync would break portability across GPU core counts.

### 3. Memory Hierarchy

| Memory | Speed | Capacity | Visibility | Allocation |
|--------|-------|----------|------------|------------|
| Register | ⚡⚡⚡ 1 cycle | small, per-thread | thread-private | compiler |
| Shared | ⚡⚡ 1-2 cycles | 48-96 KB/block | block | `__shared__` |
| Constant | ⚡⚡ cached | ~64 KB | global read-only | `__constant__` |
| Global | ⚡ 100+ cycles | GB | all threads + host | `musaMalloc` |
| Host: Pageable | slow | large | CPU only | `malloc` |
| Host: Pinned | async-able | large | CPU + DMA | `musaMallocHost` |
| Host: Mapped | zero-copy | large | CPU + GPU | `musaMallocHost(..., musaHostAllocMapped)` |
| Host: Write-Combined | optimized writes | large | CPU + GPU | `musaMallocHost(..., musaHostAllocWriteCombined)` |

**Critical optimization rules**:
- **Coalesced access**: consecutive threads must access consecutive addresses. Stride-1 = 1 transaction = 100% bandwidth; stride-2 = 2 transactions = 50%; random = 32 transactions = ~3%.
- **SoA over AoS**: Structure-of-Arrays enables coalescing; Array-of-Structures wastes bandwidth when threads touch only one field.
- **Shared memory bank conflicts**: 32 banks of 4 bytes each. Same-bank-different-address → serialization. Same-bank-same-address → broadcast (free). Fix with padding (`float[32][33]` instead of `float[32][32]`).

### 4. Execution Model (SIMT)

- **SIMT vs SIMD**: SIMT lets each thread branch independently (hardware serializes divergent paths); SIMD requires explicit vector instructions.
- **Warp size**: 32 on MP31 (MTT S5000); 128 on MP21/MP22 (MTT M1000/S4000). Use the `warpSize` built-in.
- **Latency hiding**: when a warp stalls on memory, the MP switches to another ready warp. Need high occupancy (many active warps) to hide 100+ cycle memory latency.
- **Occupancy** = active warps / max warps per MP. Limited by registers-per-thread and shared-memory-per-block.
- **Branch divergence**: `if (threadIdx.x % 2 == 0)` causes both branches to execute serially across the warp. Replace with branchless predicates when possible.

## Thread Indexing Cheatsheet

```cpp
// 1D
int idx = blockIdx.x * blockDim.x + threadIdx.x;

// 2D (row-major)
int x = blockIdx.x * blockDim.x + threadIdx.x;
int y = blockIdx.y * blockDim.y + threadIdx.y;
int idx = y * width + x;

// 3D
int idx = (z * height + y) * width + x;

// Grid size (ceil division)
int gridSize = (n + blockSize - 1) / blockSize;

// Multi-element per thread (stride loop)
for (int i = idx; i < n; i += blockDim.x * gridDim.x) { ... }
```

Always check bounds: `if (idx < n) { ... }`. For very large n, use `long long` to avoid int overflow.

## Streams & Events

```cpp
// Stream: parallel execution queue
musaStream_t s; musaStreamCreate(&s);
kernel<<<grid, block, 0, s>>>(data);          // launched on stream s
musaMemcpyAsync(d, h, sz, musaMemcpyHostToDevice, s);
musaStreamSynchronize(s);                     // block until done
musaStreamDestroy(s);

// Event: sync point + timing marker
musaEvent_t e; musaEventCreate(&e);
musaEventRecord(e, s);                        // mark point in stream s
musaStreamWaitEvent(s2, e, 0);                // s2 waits for e
float ms; musaEventElapsedTime(&ms, e1, e2);  // timing
```

- Default stream (stream=0) is implicit and serializes.
- High-priority stream: `musaStreamCreateWithPriority()`.

## L2 Cache Management

For data accessed repeatedly across multiple kernels (e.g., neural network weights), pin it in L2:

```cpp
musaDeviceSetLimit(musaLimitPersistingL2CacheSize,
                   min(prop.l2CacheSize * 0.75, prop.persistingL2CacheMaxSize));

musaStreamAttrValue attr;
attr.accessPolicyWindow.base_ptr  = data_ptr;
attr.accessPolicyWindow.num_bytes = window_size;
attr.accessPolicyWindow.hitRatio  = 0.6;
attr.accessPolicyWindow.hitProp   = musaAccessPropertyPersisting;
attr.accessPolicyWindow.missProp  = musaAccessPropertyStreaming;
musaStreamSetAttribute(stream, musaStreamAttributeAccessPolicyWindow, &attr);

// Run kernels that reuse data...
// Then RESET or the persisting region stays reserved:
musaCtxResetPersistingL2Cache();
```

- L2 set-aside is a **global device resource** shared by all streams. Sum of (window × hitRatio) across concurrent streams must not exceed the set-aside size.
- Typical S5000: `l2CacheSize` = 4 MB, `persistingL2CacheMaxSize` = 3 MB, `accessPolicyMaxWindowSize` = 2 MB.
- Max set-aside = 75% of total L2.

## Advanced Memory: Cluster Memory

Cluster memory (distributed shared memory) lets threads in **different blocks** share data and sync — useful for multi-block reductions, scans, histograms:

```cpp
#include <cooperative_groups.h>
using namespace cooperative_groups;

__global__ void clusterExample(float* data) {
    cluster_group g = this_cluster();
    clusterShared float buf[1024];  // visible across cluster blocks
    int rank = g.thread_rank();
    buf[rank] = data[rank];
    g.sync();                       // cross-block sync within cluster
    // read neighbors' data
}
```

- **Shared memory**: single-block scope.
- **Cluster shared memory**: multi-block scope, with cross-block sync.
- Use cases: multi-block reductions, scans, histograms with bin accumulation.

## Cross-References

- **Concept pages**: [[simt-execution-model]], [[thread-hierarchy]], [[memory-hierarchy]], [[warp-functions]], [[atomic-functions]], [[stream-and-event-model]], [[l2-cache-management]], [[cluster-memory]], [[kernel-launch-syntax]], [[thread-indexing]]
- **Source chapters**: [[what-is-musa]] (basics), [[musa-cpp-syntax]] (syntax for these concepts), [[api-guides]] (Runtime/Driver APIs for memory/streams), [[features]] (Graphs, Green Context)
- **Optimization**: [[performance-tuning]] — turn these concepts into performance
