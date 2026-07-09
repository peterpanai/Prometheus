---
title: "线程层次结构"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_gpu_parallel_basics.md, programming_model_thread_hierarchy.md, programming_model_thread_indexing.md]
tags: [musa, threads, grid, block, warp, indexing]
---

# 线程层次结构 (Thread Hierarchy)

MUSA organizes parallel work into a three-level hierarchy: **Grid → Block → Thread**. This is the central abstraction that makes MUSA code portable across GPUs with different MP counts.

## The Three Levels

| Level | What it is | Sync scope | Shared memory |
|-------|-----------|------------|---------------|
| **Thread** | Single execution unit | — | registers (private) |
| **Block (线程块)** | Group of threads (≤ 1024) | `__syncthreads()` works | shared memory (per-block) |
| **Grid (网格)** | All blocks in one kernel launch | NO cross-block sync | global memory |

```
Grid
├── Block (0, 0)
│   ├── Thread (0, 0)
│   ├── Thread (1, 0)
│   └── ...
├── Block (1, 0)
│   └── ...
└── Block (N, 0)
```

## Why No Cross-Block Sync?

Blocks can be scheduled to any MP in any order. If cross-block sync were allowed, programs would depend on a specific execution order, breaking portability across GPUs with different MP counts. MUSA requires that blocks be **independent** — any block can execute in any order, parallel or serial.

## Built-in Variables

| Variable | Type | Meaning |
|----------|------|---------|
| `threadIdx` | `dim3` | Thread index within block (x, y, z) |
| `blockIdx` | `dim3` | Block index within grid (x, y, z) |
| `blockDim` | `dim3` | Block dimensions (threads per block) |
| `gridDim` | `dim3` | Grid dimensions (blocks per grid) |
| `warpSize` | `int` | Warp size (32 on S5000, 128 on M1000/S4000) |

## Index Formulas

```cpp
// 1D — most common
int idx = blockIdx.x * blockDim.x + threadIdx.x;

// 2D (row-major) — image processing
int x = blockIdx.x * blockDim.x + threadIdx.x;
int y = blockIdx.y * blockDim.y + threadIdx.y;
int idx = y * width + x;

// 3D — volume data
int idx = (z * height + y) * width + x;

// Multi-element per thread (grid-stride loop)
int stride = blockDim.x * gridDim.x;
for (int i = idx; i < n; i += stride) { ... }
```

Always check bounds: `if (idx < n) { ... }`. For very large n, use `long long` to avoid int overflow.

## Limits

| Parameter | Max |
|-----------|-----|
| Threads per block | 1024 |
| Block dim (x, y) | 1024 |
| Block dim (z) | 64 |
| Shared memory per block | 48-96 KB |
| Grid dim (x) | 2³¹ − 1 |
| Grid dim (y, z) | 65535 |

## Block Size Selection

| Block size | Use case |
|------------|----------|
| 128 | Register-heavy kernels |
| 256 | General purpose — recommended starting point |
| 512 | Compute-intensive kernels |
| 1024 | Max occupancy scenarios |

Rules:
- Must be a multiple of `warpSize` (32 on S5000, 128 on M1000/S4000).
- Sweet spot is typically 256-1024.
- Cap shared memory at ~48 KB to preserve occupancy.

## Grid Size Calculation

```cpp
// 1D ceil division
int blockSize = 256;
int gridSize = (n + blockSize - 1) / blockSize;

// 2D
dim3 blockSize(16, 16);
dim3 gridSize((width + 15) / 16, (height + 15) / 16);

// 3D
dim3 blockSize(8, 8, 8);
dim3 gridSize((width + 7) / 8, (height + 7) / 8, (depth + 7) / 8);
```

## Cross-References

- [[simt-execution-model]] — how warps (sub-block units) actually execute
- [[memory-hierarchy]] — what memory each level can access
- [[kernel-launch-syntax]] — the `<<<grid, block>>>` syntax
- [[occupancy]] — how block size affects MP utilization
- → raw: `programming_model_thread_hierarchy.md`, `programming_model_thread_indexing.md`
