---
title: "Warp 函数"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [musa_cpp_syntax_warp_functions.md, programming_model_execution_model.md]
tags: [musa, warp, shuffle, vote, ballot, syncwarp]
---

# Warp 函数 (Warp Functions)

Warp functions provide **warp-level** synchronization, voting, and data exchange without using shared memory. They operate on the warp's lanes directly via hardware intrinsics.

## Warp Size — Architecture-Dependent

| GPU | Warp size |
|-----|-----------|
| MTT S5000 (MP31) | 32 lanes |
| MTT M1000/S4000 (MP21/MP22) | 128 lanes |

Query at runtime via the `warpSize` built-in. Lane index within a warp: `int lane = threadIdx.x % warpSize;`

## Warp Synchronization

### `__syncwarp(mask)`

```cpp
void __syncwarp(unsigned mask = 0xffffffff);
```

Warp-level barrier. All lanes in `mask` must execute `__syncwarp` with the same mask before any can proceed. Guarantees memory ordering between participating lanes.

```cpp
__global__ void warpSyncExample(float* data) {
    int tid = threadIdx.x;
    int lane = tid % warpSize;
    data[tid] = lane * 1.0f;
    __syncwarp();                                  // ensure all writes visible
    float fromLane0 = data[tid - lane];            // safe read
}
```

## Vote Functions

Return a single value computed across the warp.

### `__all_sync(mask, pred)`

Returns non-zero iff **ALL** lanes in `mask` have non-zero `pred`.

```cpp
int all = __all_sync(0xffffffff, predicate);
```

### `__any_sync(mask, pred)`

Returns non-zero iff **ANY** lane in `mask` has non-zero `pred`.

### `__ballot_sync(mask, pred)`

Returns a bitmask: bit `i` = `pred` of lane `i`. If 4 lanes have predicate=1 (lanes 0, 2, 5, 7), returns `0b10100101 = 165`.

```cpp
unsigned mask = __ballot_sync(0xffffffff, predicate);
```

### `__activemask()`

Returns bitmask of currently-active (non-exited) lanes. No predicate argument.

> **Note**: Vote functions are NOT barrier synchronizations — they do not guarantee memory ordering.

## Shuffle Functions — Register-to-Register Exchange

Allow lanes to exchange values directly without shared memory or `__syncthreads()`.

```cpp
T __shfl_sync(mask, T var, int srcLane, int width = warpSize);        // copy from srcLane
T __shfl_up_sync(mask, T var, unsigned delta, int width = warpSize);  // from lane - delta
T __shfl_down_sync(mask, T var, unsigned delta, int width = warpSize); // from lane + delta
T __shfl_xor_sync(mask, T var, int laneMask, int width = warpSize);   // from lane ^ laneMask
```

**Supported types `T`**: `int`, `unsigned int`, `long`, `unsigned long`, `long long`, `unsigned long long`, `float`, `double`.

### `__shfl_sync` — Direct Copy

```cpp
// All lanes get lane 0's value
float v = __shfl_sync(0xffffffff, my_val, 0);
```

### `__shfl_down_sync` — Reduce Pattern

```cpp
// Tree reduction: each step halves active lanes
v += __shfl_down_sync(0xffffffff, v, 16);
v += __shfl_down_sync(0xffffffff, v, 8);
v += __shfl_down_sync(0xffffffff, v, 4);
v += __shfl_down_sync(0xffffffff, v, 2);
v += __shfl_down_sync(0xffffffff, v, 1);
// Lane 0 now has the sum
```

### `__shfl_xor_sync` — Butterfly Pattern

```cpp
// Swap with neighbor (lane ^ 1)
float neighbor = __shfl_xor_sync(0xffffffff, v, 1);
```

Useful for tree reductions and broadcast patterns.

### `__shfl_up_sync` — Prefix Sum (Scan)

```cpp
float t;
t = __shfl_up_sync(0xffffffff, v, 1);  if (lane >= 1)  v += t;
t = __shfl_up_sync(0xffffffff, v, 2);  if (lane >= 2)  v += t;
t = __shfl_up_sync(0xffffffff, v, 4);  if (lane >= 4)  v += t;
t = __shfl_up_sync(0xffffffff, v, 8);  if (lane >= 8)  v += t;
t = __shfl_up_sync(0xffffffff, v, 16); if (lane >= 16) v += t;
// Lane i now has prefix sum of lanes 0..i
```

## `width` Parameter

The optional `width` parameter segments a warp into sub-groups. Must be a power of 2 and ≤ `warpSize`. Shuffle stays within the segment.

```cpp
// Only shuffle within first 16 lanes (and last 16 separately)
v = __shfl_sync(0xffffffff, v, srcLane, 16);
```

## Mask Consistency Rules

| Rule | Consequence if violated |
|------|-------------------------|
| Each calling lane must set its own bit in `mask` | Undefined behavior |
| All non-exited lanes in `mask` must execute the same intrinsic with the same mask | Undefined behavior |
| `width` must be power of 2, ≤ `warpSize` | Undefined behavior |

## Block-Level Synthetics (combined sync + vote)

| Function | Returns |
|----------|---------|
| `__syncthreads_count(pred)` | Count of threads where `pred` is non-zero |
| `__syncthreads_and(pred)` | Non-zero iff ALL threads' `pred` is non-zero |
| `__syncthreads_or(pred)` | Non-zero iff ANY thread's `pred` is non-zero |

These combine `__syncthreads()` with a warp/block reduction.

## Cross-References

- [[simt-execution-model]] — what a warp is
- [[synchronization-primitives]] — block-level sync
- [[atomic-functions]] — alternative for cross-thread data sharing
- [[reduction-patterns]] — canonical use of `__shfl_down_sync`
- → raw: `musa_cpp_syntax_warp_functions.md`
