---
title: "原子函数"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [musa_cpp_syntax_atomic_functions.md, programming_model_execution_model.md]
tags: [musa, atomic, atomicadd, atomiccas, synchronization]
---

# 原子函数 (Atomic Functions)

Atomic functions perform **read-modify-write** operations on data in global or shared memory without race conditions. They are the primary tool for cross-thread data sharing when warp shuffles aren't applicable (e.g., cross-block, cross-warp).

## Overview

- Operate on **global memory** or **shared memory**.
- Can only be used in **device functions** (`__device__`, `__global__`).
- All return the **old value** at `address`.
- Any atomic can be built on `atomicCAS()` (compare-and-swap).

## Type Support Matrix

| Function | int | uint | ullong | float | double | short | Global | Shared |
|----------|-----|------|--------|-------|--------|-------|--------|--------|
| `atomicAdd` | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| `atomicSub` | ✅ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| `atomicExch` | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ |
| `atomicInc` | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| `atomicDec` | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| `atomicCAS` | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ |
| `atomicAnd` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| `atomicOr` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |
| `atomicXor` | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ | ✅ | ✅ |

Note: `atomicAdd` for `double` is supported (since some MUSA versions); if unavailable, implement via `atomicCAS` (see below).

## Arithmetic Atomics

### `atomicAdd(address, val)` — most common

```cpp
int atomicAdd(int* address, int val);
unsigned int atomicAdd(unsigned int* address, unsigned int val);
unsigned long long int atomicAdd(unsigned long long int* address, unsigned long long int val);
float atomicAdd(float* address, float val);
double atomicAdd(double* address, double val);
```

Returns `old`; stores `old + val`.

```cpp
__global__ void countKernel(int* counter, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) atomicAdd(counter, 1);
}
```

### `atomicSub`, `atomicExch`, `atomicInc`, `atomicDec`

```cpp
atomicSub(addr, val);   // stores old - val
atomicExch(addr, val);  // stores val
atomicInc(addr, val);   // stores ((old >= val) ? 0 : old+1) — circular counter
atomicDec(addr, val);   // stores ((old==0 || old>val) ? val : old-1)
```

## Compare-And-Swap — The Universal Primitive

```cpp
int atomicCAS(int* address, int compare, int val);
// If *address == compare, then *address = val. Returns old *address.
```

Any atomic can be built on CAS via a retry loop:

```cpp
__device__ double atomicAdd(double* address, double val) {
    unsigned long long int* a = (unsigned long long int*)address;
    unsigned long long int old = *a, assumed;
    do {
        assumed = old;
        old = atomicCAS(a, assumed,
                        __double_as_longlong(val + __longlong_as_double(assumed)));
    } while (assumed != old);  // use integer compare to handle NaN
    return __longlong_as_double(old);
}
```

## Bitwise Atomics

`atomicAnd`, `atomicOr`, `atomicXor` — operate on int/uint/ullong.

## Common Patterns

### Counter

```cpp
atomicInc(counter, UINT_MAX);
```

### Histogram (with optimization)

```cpp
// ❌ All threads atomicAdd to global bins — high contention
__global__ void badHistogram(float* data, int* bins, int n, int binCount) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        int bin = min((int)(data[idx] * binCount), binCount - 1);
        atomicAdd(&bins[bin], 1);
    }
}

// ✅ Block-local bins in shared mem, single global merge per bin
__global__ void goodHistogram(float* data, int* bins, int n, int binCount) {
    __shared__ int sharedBins[256];
    for (int i = threadIdx.x; i < binCount; i += blockDim.x) sharedBins[i] = 0;
    __syncthreads();
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        int bin = min((int)(data[idx] * binCount), binCount - 1);
        atomicAdd(&sharedBins[bin], 1);              // shared mem — low latency
    }
    __syncthreads();
    for (int i = threadIdx.x; i < binCount; i += blockDim.x) {
        atomicAdd(&bins[i], sharedBins[i]);          // one global atomic per bin per block
    }
}
```

### Spin Lock (via CAS)

```cpp
__device__ void lock(int* mutex) {
    while (atomicCAS(mutex, 0, 1) != 0) { /* spin */ }
}
__device__ void unlock(int* mutex) {
    atomicExch(mutex, 0);
}
```

### Reduction (block-local → global merge)

```cpp
__global__ void reduceKernel(float* input, float* output, int n) {
    __shared__ float shared[256];
    /* ... block-level reduction into shared[0] ... */
    if (threadIdx.x == 0) atomicAdd(output, shared[0]);
}
```

## Performance Notes

| Concern | Mitigation |
|---------|-----------|
| Same-address atomics serialize | Use shared-memory atomics first, then a single global atomic per block |
| Global atomics are slow | Block-local reduction before global atomic |
| High contention on a few bins | Privatize bins per block, merge at end |
| Use atomics when shuffle would work | Prefer `__shfl_*_sync` for warp-local reductions — no memory traffic |

## Scope Variants

Atomic functions support `_block` and `_system` variants for block-scoped and system-scoped operations:

```cpp
atomicAdd_block(...);    // block scope
atomicAdd_system(...);   // system scope (multi-GPU)
```

## Cross-References

- [[warp-functions]] — preferred for warp-local data exchange (no memory traffic)
- [[synchronization-primitives]] — barrier-based alternatives
- [[reduction-patterns]] — block-local reduction + single global atomic
- → raw: `musa_cpp_syntax_atomic_functions.md`
