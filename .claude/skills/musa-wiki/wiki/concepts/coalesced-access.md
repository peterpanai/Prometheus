---
title: "合并访问"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_memory_optimization.md, programming_model_memory_hierarchy.md]
tags: [musa, coalesced-access, memory-bandwidth, global-memory]
---

# 合并访问 (Coalesced Access)

Coalescing is the most important memory optimization in MUSA. When the threads of a warp access **contiguous, aligned** memory locations in the same transaction, the hardware combines them into a single wide load — turning 32 (or 128) separate requests into one DRAM/L2 transaction.

## The Transaction Size

| GPU | Warp size | Transaction width |
|-----|-----------|-------------------|
| MTT S5000 (MP31) | 32 lanes | 128 bytes (32 × 4B) |
| MTT M1000/S4000 (MP21/MP22) | 128 lanes | 512 bytes (128 × 4B) |

A coalesced access issues **one transaction** for the whole warp. An uncoalesced access may issue up to `warpSize` transactions — wasting 99% of bandwidth in the worst case.

## Coalescing Rules

For a 4-byte (e.g. `float`, `int`) access to be fully coalesced:

1. **Thread `i` accesses address `base + i * 4`** (consecutive, unit-stride).
2. **`base` is aligned to 128 bytes** (the transaction width on S5000).

```cpp
// ✅ Coalesced — thread i accesses d[i]
float v = d[threadIdx.x + offset];

// ✅ Coalesced — same pattern with any constant offset
float v = d[threadIdx.x + 1024];

// ❌ Stride 2 — needs 2 transactions, 50% bandwidth
float v = d[threadIdx.x * 2];

// ❌ Random — needs warpSize transactions
float v = d[hash(threadIdx.x)];
```

## Effect on Bandwidth

| Access pattern | Transactions | Effective BW |
|----------------|---------------|--------------|
| 32 contiguous, aligned | 1 | 100% |
| Stride 2 | 2 | 50% |
| Stride 4 | 4 | 25% |
| Permute (random) | 32 | ~3% |
| Misaligned by 1 byte | 2 | ~50% |

## Misalignment

If `base` is not aligned to the transaction width, the access straddles two transactions:

```cpp
// ❌ Misaligned — thread 0 reads at offset 1, splits across two 128B transactions
float* d_mis = (float*)((char*)d + 1);
float v = d_mis[threadIdx.x];
```

`musaMalloc` returns 256-byte aligned pointers, so `d[0]`, `d[128]`, etc. are properly aligned. Alignment problems come from:
- Casting `char*` to `float*` after arbitrary offset
- `struct` layouts with mixed types
- Pointer arithmetic with non-multiple offsets

## AoS vs SoA

```cpp
// ❌ AoS — every thread reads .x but the load fetches y and z too
struct Point { float x, y, z; };
Point* points;
float x = points[idx].x;        // loads 12B, uses 4B → 33% efficient

// ✅ SoA — contiguous floats, fully coalesced
struct Points { float *x, *y, *z; };
float x = points.x[idx];        // loads 4B, uses 4B → 100% efficient
```

## 2D Access Patterns

```cpp
// ✅ Row-major, threads in x — coalesced
int x = threadIdx.x + blockIdx.x * blockDim.x;
int y = threadIdx.y + blockIdx.y * blockDim.y;
float v = d[y * width + x];     // consecutive threads → consecutive addresses

// ❌ Column-major access of row-major data — stride = width
float v = d[x * height + y];    // thread i reads d[i*height] → stride H
```

For column-major data, transpose the data or use a different thread mapping.

## Vectorized Loads

Read 4 floats at once via `float4`:

```cpp
// 4× fewer transactions
float4* d4 = (float4*)d;
float4 v = d4[threadIdx.x];     // 16 bytes per thread, 1 transaction per 8 threads
```

| Type | Bytes per thread | Threads per 128B transaction |
|------|------------------|------------------------------|
| `char` | 1 | 128 (full warp on M1000) |
| `short` | 2 | 64 |
| `int`/`float` | 4 | 32 (full warp on S5000) |
| `int2`/`float2` | 8 | 16 |
| `int4`/`float4` | 16 | 8 |

Larger vector types reduce instruction count and improve bandwidth utilization.

## Diagnosing Coalescing Issues

- **`mcu`**: reports load/store efficiency. Look for "L2 throughput" vs. "DRAM throughput" gaps.
- **`msys`**: shows per-kernel memory metrics.
- Code review: any access of the form `d[idx * stride]` with `stride > 1` is suspicious.

## Common Patterns

### Coalesced Read, Coalesced Write

```cpp
// Both reads and writes are coalesced
__global__ void scaleKernel(float* out, float* in, float s, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) out[idx] = in[idx] * s;
}
```

### Coalesced Read, Strided Write (e.g. Scatter)

```cpp
// Read coalesced, write strided — write efficiency = 1/stride
__global__ void scatter(float* out, int* indices, float* in, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) out[indices[idx]] = in[idx];
}
```

Scatter is inherently inefficient. If possible, **transpose** so writes become coalesced (gather becomes scatter and vice versa — gather is usually cheaper because of cache).

### Strided Read, Coalesced Write (e.g. Gather)

```cpp
// Read strided, write coalesced — read may hit cache if indices are local
__global__ void gather(float* out, int* indices, float* in, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) out[idx] = in[indices[idx]];
}
```

Often acceptable because L2 caches the gather pattern.

## Cross-References

- [[memory-hierarchy]] — coalescing affects global memory transactions
- [[bank-conflicts]] — the shared-memory analog
- [[roofline-model]] — coalescing changes effective arithmetic intensity
- → raw: `performance_tuning_memory_optimization.md`
