---
title: "内存层次结构"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_gpu_parallel_basics.md, programming_model_memory_hierarchy.md, programming_model_advanced_memory.md]
tags: [musa, memory, registers, shared-memory, global-memory, pinned-memory]
---

# 内存层次结构 (Memory Hierarchy)

MUSA exposes several memory types, each with different speed, capacity, visibility, and allocation patterns. Choosing the right memory type for each piece of data is the single biggest lever for GPU performance.

## GPU-Side Memory

| Memory | Speed | Capacity | Visibility | Allocation |
|--------|-------|----------|------------|------------|
| **Register** | ⚡⚡⚡ 1 cycle | small, per-thread | thread-private | compiler (auto) |
| **Shared** | ⚡⚡ 1-2 cycles | 48-96 KB / block | block | `__shared__` |
| **L1/L2 Cache** | ⚡⚡ cached | hardware-managed | — | automatic |
| **Constant** | ⚡⚡ cached (hit) | ~64 KB | global read-only | `__constant__` |
| **Global** | ⚡ 100+ cycles | GB | all threads + host | `musaMalloc` |

```
Access speed ↑
              │ Register        — per-thread, 1 cycle
              │ Shared Memory   — per-block, 1-2 cycles
              │ L1/L2 Cache     — hardware-managed
              │ Constant Memory — read-only, cached
              │ Global Memory   — all threads, 100+ cycles
              ↓
```

## Host-Side Memory

| Type | Allocation API | Transfer | Performance |
|------|----------------|----------|-------------|
| **Pageable** | `malloc()` | Sync copy | Blocks CPU, slow — needs staging buffer |
| **Pinned** | `musaMallocHost()` | Async copy | Direct PCIe, supports overlap |
| **Mapped Pinned** | `musaMallocHost(..., musaHostAllocMapped)` | Zero-copy | GPU accesses host mem directly |
| **Write-Combined** | `musaMallocHost(..., musaHostAllocWriteCombined)` | Async copy | Optimized for write bandwidth |

## Register Pressure

The compiler auto-assigns registers, but large per-thread arrays spill to **local memory** (which lives in global memory — 100× slower):

```cpp
// ❌ Likely register spill
__global__ void bad() {
    float temp[100];
    for (int i = 0; i < 100; i++) temp[i] = data[i];
}

// ✅ Use shared memory for block-shared data
__shared__ float tile[256];
```

## Shared Memory — The Block-Collaboration Buffer

```cpp
__global__ void kernel(float* data) {
    __shared__ float shared_data[256];
    shared_data[threadIdx.x] = data[threadIdx.x];
    __syncthreads();                              // wait for all writes
    float neighbor = shared_data[(threadIdx.x + 1) % 256];  // read other thread's data
}
```

- Visible to all threads in the block.
- Lifetime = block lifetime.
- Allocated per-block; counts against occupancy limit.

## Global Memory — The Host-Visible Buffer

```cpp
float* d_data;
musaMalloc(&d_data, size * sizeof(float));        // allocate
musaMemcpy(d_data, h_data, sz, musaMemcpyHostToDevice);  // H2D
__global__ void k(float* d) { d[threadIdx.x] *= 2; }   // kernel access
musaFree(d_data);                                  // free
```

> **Note**: `musaMalloc` and `muMemCreate` do NOT zero-initialize memory.

## Constant Memory

```cpp
__constant__ float coefficients[10];               // global declaration

__global__ void k(float* d) {
    float r = d[threadIdx.x] * coefficients[0];    // all threads read same address → broadcast
}

// Host-side init:
musaMemcpyToSymbol(coefficients, h_data, sizeof(float) * 10);
```

- 64 KB total.
- Best when all threads read the **same** address (broadcast = free).
- Worst when threads read different addresses (serializes).

## Coalesced Access — The Critical Optimization

| Access pattern | Transactions | Bandwidth |
|----------------|--------------|-----------|
| 32 contiguous addresses | 1 | 100% |
| Stride 2 | 2 | 50% |
| Stride 4 | 4 | 25% |
| Random | 32 | ~3% |

```cpp
// ✅ Coalesced: thread i → address i
data[idx] = data[idx] * 2.0f;

// ❌ Strided: thread i → address i*stride
data[idx * stride] = data[idx * stride] * 2.0f;
```

See [[coalesced-access]].

## AoS vs SoA

```cpp
// ❌ AoS — wastes bandwidth when only one field is used
struct Point { float x, y, z; };
Point* points;
float x = points[idx].x;   // loads 12B, uses 4B

// ✅ SoA — coalesced access to one field
struct Points { float *x, *y, *z; };
float x = points.x[idx];   // loads 4B
```

## Shared Memory Bank Conflicts

32 banks × 4 bytes each. Same-bank-different-address → serialization. Same-bank-same-address → broadcast (free).

```cpp
// ❌ 32-way conflict
__shared__ float m[32][32];
v = m[threadIdx.x][0];            // all threads hit bank 0

// ✅ Padding breaks the alignment
__shared__ float m[32][33];
v = m[threadIdx.x][0];            // each thread hits different bank
```

See [[bank-conflicts]].

## Pinned Memory & Async Transfer

```cpp
float* h_pinned;
musaMallocHost(&h_pinned, sz);                    // pin host memory

musaStream_t s; musaStreamCreate(&s);
musaMemcpyAsync(d, h_pinned, sz, musaMemcpyHostToDevice, s);  // async
kernel<<<grid, block, 0, s>>>(d);                 // overlaps with next H2D
musaStreamSynchronize(s);

musaFreeHost(h_pinned);
```

## Zero-Copy (Mapped Pinned)

```cpp
float* h_mapped;
musaMallocHost(&h_mapped, sz, musaHostAllocMapped);
float* d_mapped;
musaHostGetDevicePointer(&d_mapped, h_mapped, 0);
// GPU reads/writes h_mapped directly via d_mapped — no explicit copy
kernel<<<grid, block>>>(d_mapped);
```

Use cases: infrequent small transfers, read-only data with `musaMemAdvise`.

## Cross-References

- [[thread-hierarchy]] — block scope of shared memory
- [[coalesced-access]] — the most important global-mem optimization
- [[bank-conflicts]] — shared-mem access patterns
- [[l2-cache-management]] — L2 persistence policy
- [[advanced-memory]] — Cluster memory, pinned, zero-copy
- → raw: `programming_model_memory_hierarchy.md`, `programming_model_advanced_memory.md`
