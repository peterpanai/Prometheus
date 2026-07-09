---
title: "MUSA C++ 语法 — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources:
  - musa_cpp_syntax.md
  - musa_cpp_syntax_syntax_overview.md
  - musa_cpp_syntax_intro_to_musa_cpp.md
  - musa_cpp_syntax_atomic_functions.md
  - musa_cpp_syntax_warp_functions.md
tags: [musa, syntax, cpp, atomics, warp, shfl, kernel-launch]
---

# MUSA C++ 语法 (MUSA C++ Syntax)

MUSA C++ is the language layer that bridges the programming model (Grid/Block/Thread, memory hierarchy, SIMT) to actual executable code. It is implemented as a set of extensions to standard C++ processed by the `mcc` compiler. The extension set mirrors CUDA's: function qualifiers, memory qualifiers, built-in variables, kernel launch syntax, and device-side intrinsics.

## Source Pages

| Raw File | Title | Covers |
|----------|-------|--------|
| `musa_cpp_syntax.md` | MUSA C++ 语法 | Chapter index |
| `musa_cpp_syntax_syntax_overview.md` | MUSA C++ 语法概述 | Syntax layer role, Runtime vs Driver API layering, code comparison |
| `musa_cpp_syntax_intro_to_musa_cpp.md` | MUSA C++ 语言扩展 | Function/memory qualifiers, built-in vars, kernel config, intrinsics overview, error handling |
| `musa_cpp_syntax_atomic_functions.md` | 原子函数 | atomicAdd/Sub/Exch/Inc/Dec/CAS/And/Or/Xor, type support matrix, perf notes |
| `musa_cpp_syntax_warp_functions.md` | Warp 函数 | `__syncthreads*`, `__syncwarp`, `__all_sync`, `__any_sync`, `__ballot_sync`, `__activemask`, `__shfl_*_sync` |

## Key Takeaways

- **Four extension categories**: function qualifiers, memory qualifiers, built-in variables, kernel launch syntax.
- **Two API layers**: Runtime (high-level, `musa*` prefix, automatic context) vs Driver (low-level, `mu*` prefix, manual context). Pick one per project; mixing is possible but adds complexity.
- **Device-side intrinsics** fall into: synchronization, atomics, warp primitives, math (standard + fast `__sinf` etc.).
- **Type support is uneven across atomics** — e.g., `atomicAdd` supports int/uint/ullong/float/double but NOT short; `atomicCAS` supports short but not float. Consult the matrix.
- **Warp primitives require a mask** (typically `0xffffffff`); the mask must be consistent across all participating threads or behavior is undefined.
- **`width` parameter** in `__shfl_*_sync` must be a power of 2 and ≤ `warpSize`.

## Function Qualifiers

| Qualifier | Where it runs | Called from |
|-----------|---------------|-------------|
| `__global__` | Device | Host (or Device via dynamic parallelism) |
| `__device__` | Device | Device only |
| `__host__` | Host | Host (default if no qualifier) |
| `__device__ __host__` | Both | Both — compiled twice |

Kernel (`__global__`) must return `void`. Called via `<<<grid, block, sharedMem, stream>>>(args)`.

## Memory Qualifiers

| Qualifier | Memory | Lifetime | Visibility |
|-----------|--------|----------|------------|
| `__shared__` | Shared | block | block |
| `__constant__` | Constant | program | all threads (read-only) |
| `__managed__` | Unified | program | host + device |
| `__device__` (on var) | Global | program | all threads |
| `__restrict__` | — (hint) | — | tells compiler pointer is non-aliased |

Dynamic shared memory:
```cpp
extern __shared__ float buf[];   // size passed at launch
kernel<<<grid, block, N * sizeof(float)>>>(args);
```

## Built-in Variables

| Variable | Type | Meaning |
|----------|------|---------|
| `threadIdx` | `dim3` | thread index within block (x, y, z) |
| `blockIdx` | `dim3` | block index within grid (x, y, z) |
| `blockDim` | `dim3` | block dimensions (threads per block) |
| `gridDim` | `dim3` | grid dimensions (blocks per grid) |
| `warpSize` | `int` | warp size (32 on S5000, 128 on M1000/S4000) |

## Kernel Launch Syntax

```cpp
kernel<<<gridDim, blockDim, sharedMem, stream>>>(args);
```

- `gridDim`, `blockDim`: `dim3` (1D/2D/3D)
- `sharedMem`: optional, dynamic shared memory size in bytes (default 0)
- `stream`: optional, `musaStream_t` (default stream if omitted)

## Synchronization Primitives

| Function | Scope | Purpose |
|----------|-------|---------|
| `__syncthreads()` | Block | Barrier — all threads in block reach point; makes prior global/shared writes visible |
| `__syncthreads_count(pred)` | Block | Like `__syncthreads()` + returns count of threads where `pred` is non-zero |
| `__syncthreads_and(pred)` | Block | Returns non-zero iff ALL threads' `pred` is non-zero |
| `__syncthreads_or(pred)` | Block | Returns non-zero iff ANY thread's `pred` is non-zero |
| `__syncwarp(mask)` | Warp | Warp-level barrier; default mask = `0xffffffff` |
| `__threadfence()` | System | Memory fence — makes writes visible to all threads system-wide |
| `__threadfence_block()` | Block | Block-scoped memory fence |

> `__syncthreads()` inside conditional code is allowed ONLY if the condition evaluates identically across the entire block — otherwise the program may hang.

## Atomic Functions

Operate on data in **global or shared memory**. All return the old value.

| Function | Supported types |
|----------|-----------------|
| `atomicAdd` | int, uint, ullong, **float, double** |
| `atomicSub` | int, uint |
| `atomicExch` | int, uint, ullong, float |
| `atomicInc` | uint |
| `atomicDec` | uint |
| `atomicCAS` | int, uint, ullong, **short** |
| `atomicAnd/Or/Xor` | int, uint, ullong |

- Any atomic can be built on `atomicCAS` (e.g., the custom `atomicAdd(double*)` example in the source).
- **Performance**: same-address atomics serialize. Use shared-memory atomics first, then a single global atomic per block.
- Common patterns: counters, histograms (block-local bins → global atomic merge), spin locks.

## Warp Primitives

### Vote Functions (return int / unsigned)

| Function | Returns |
|----------|---------|
| `__all_sync(mask, pred)` | non-zero iff ALL threads in mask have non-zero `pred` |
| `__any_sync(mask, pred)` | non-zero iff ANY thread in mask has non-zero `pred` |
| `__ballot_sync(mask, pred)` | bitmask: bit i = `pred` of thread i |
| `__activemask()` | bitmask of currently-active (non-exited) threads in warp |

> Vote functions are NOT barrier synchronizations — they do not guarantee memory ordering.

### Shuffle Functions (return value from another lane)

```cpp
T __shfl_sync(mask, T var, int srcLane, int width = warpSize);       // direct copy from srcLane
T __shfl_up_sync(mask, T var, unsigned delta, int width = warpSize); // from lane - delta
T __shfl_down_sync(mask, T var, unsigned delta, int width = warpSize); // from lane + delta
T __shfl_xor_sync(mask, T var, int laneMask, int width = warpSize);  // from lane ^ laneMask
```

Supported `T`: int, uint, long, ulong, longlong, ullong, float, double.

### Classic Warp Reduction

```cpp
__device__ float warpReduceSum(float v) {
    v += __shfl_xor_sync(0xffffffff, v, 16);
    v += __shfl_xor_sync(0xffffffff, v, 8);
    v += __shfl_xor_sync(0xffffffff, v, 4);
    v += __shfl_xor_sync(0xffffffff, v, 2);
    v += __shfl_xor_sync(0xffffffff, v, 1);
    return v;
}
```

### Warp Scan (Prefix Sum)

```cpp
__device__ float warpScanInclusive(float v) {
    float t;
    t = __shfl_up_sync(0xffffffff, v, 1);  if (lane % 1  >= 1) v += t;
    t = __shfl_up_sync(0xffffffff, v, 2);  if (lane % 2  >= 2) v += t;
    t = __shfl_up_sync(0xffffffff, v, 4);  if (lane % 4  >= 4) v += t;
    t = __shfl_up_sync(0xffffffff, v, 8);  if (lane % 8  >= 8) v += t;
    t = __shfl_up_sync(0xffffffff, v, 16); if (lane % 16 >= 16) v += t;
    return v;
}
```

## Math Functions: Standard vs Fast

| Variant | Precision | Speed | Example |
|---------|-----------|-------|---------|
| Standard | High | Medium | `sin(x)`, `cos(x)`, `exp(x)`, `log(x)`, `sqrt(x)` |
| Fast (`__` prefix) | Low | High | `__sinf(x)`, `__cosf(x)`, `__expf(x)`, `__logf(x)`, `__sqrtf(x)` |

## Compiler Pragmas

```cpp
#pragma unroll            // hint to unroll next loop
__forceinline__           // force inlining
__noinline__              // prevent inlining
```

## Error Handling

```cpp
typedef enum {
    musaSuccess = 0,
    musaErrorInvalidValue = 1,
    musaErrorMemoryAllocation = 2,
    musaErrorInitializationError = 3,
    musaErrorInvalidDevice = 101,
    musaErrorInvalidKernel = 300,
    musaErrorLaunchFailure = 400,
    // ...
} musaError_t;
```

Always check return values:
```cpp
musaError_t err = musaMalloc(&ptr, sz);
if (err != musaSuccess) { /* handle */ }
```

## Runtime API vs Driver API

| Aspect | Runtime API | Driver API |
|--------|-------------|------------|
| Init | Automatic (first call) | Manual `muInit(0)` |
| Context | Implicit primary context | Explicit `muCtxCreate()` |
| Module | Auto from PTX/binary | Manual `muModuleLoad()` |
| Complexity | Low | High |
| Flexibility | Limited | Full control |
| Use case | Apps, prototypes | Frameworks, libraries, multi-tenant |

Same operation, two styles:
```cpp
// Runtime
musaMalloc(&d, sz);
myKernel<<<grid, block>>>(d);
musaDeviceSynchronize();

// Driver
muInit(0); muCtxCreate(&ctx, 0, dev);
muModuleLoad(&mod, "kernel.mubin");
muModuleGetFunction(&k, mod, "myKernel");
muMemAlloc(&d, sz);
muLaunchKernel(k, grid, block, ...);
muCtxSynchronize(ctx);
```

## Cross-References

- **Concept pages**: [[atomic-functions]], [[warp-functions]], [[kernel-launch-syntax]], [[synchronization-primitives]], [[runtime-vs-driver-api]]
- **Source chapters**: [[programming-model]] (the abstractions this syntax expresses), [[api-guides]] (the API layer below this syntax)
- **Entity pages**: [[mcc-compiler]] (the compiler that implements these extensions)
