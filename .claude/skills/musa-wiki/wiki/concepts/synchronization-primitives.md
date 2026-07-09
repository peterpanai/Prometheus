---
title: "同步原语"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [musa_cpp_syntax_atomic_functions.md, musa_cpp_syntax_warp_functions.md, programming_model_execution_model.md]
tags: [musa, synchronization, barrier, syncthreads, syncwarp, fence]
---

# 同步原语 (Synchronization Primitives)

MUSA's synchronization primitives divide into three scopes — **warp**, **block**, and **grid** — plus memory fences for ordering. Choosing the cheapest primitive that is correct is critical for performance: barriers are not free, and using a grid-level sync where a warp sync would do serializes the whole GPU.

## Scope Hierarchy

| Primitive | Scope | Cost | Memory Guaranteed? |
|-----------|-------|------|---------------------|
| `__syncwarp(mask)` | Warp | 1 instr | Yes (within mask) |
| `__syncthreads()` | Block | 1 instr | Yes (block-visible) |
| `musaClusterSync()` | Cluster | few instr | Yes (cluster) |
| `musaDeviceSynchronize()` | Device | host round-trip | Yes (device) |
| Atomic ops | Any | per-op | Per-op |

## Warp-Level

### `__syncwarp(mask)` — Warp Barrier

```cpp
void __syncwarp(unsigned mask = 0xffffffff);
```

All non-exited lanes in `mask` must reach the barrier. Guarantees memory visibility **between participating lanes**.

Use when:
- One warp produces data another lane in the same warp will read.
- The data is in shared memory (shuffle doesn't need a sync).

```cpp
data[lane] = compute();
__syncwarp();                    // ensure writes visible
v = data[(lane + 1) % warpSize]; // safe
```

> `__syncwarp` is **not free** — it is a real barrier. Don't sprinkle it "for safety".

### Warp Vote / Ballot — NOT Barriers

`__all_sync`, `__any_sync`, `__ballot_sync`, `__activemask` compute a value across the warp but **do not** guarantee memory ordering. If you need ordering, pair them with `__syncwarp`.

See [[warp-functions]].

## Block-Level

### `__syncthreads()` — Block Barrier

```cpp
void __syncthreads();
```

All threads in the block must reach the barrier. Guarantees all shared-memory writes by any thread are visible to all other threads in the block.

```cpp
__shared__ float tile[256];
tile[threadIdx.x] = data[threadIdx.x];
__syncthreads();                          // ensure tile fully populated
float sum = 0;
for (int i = 0; i < 256; i++) sum += tile[i];
```

> **Critical**: `__syncthreads()` must be reached by **all** threads in the block, or **none**. Putting it inside a divergent `if` causes a hang.

```cpp
// ❌ HANGS — only odd threads reach the barrier
if (threadIdx.x & 1) __syncthreads();

// ✅ Move condition inside or restructure
__syncthreads();
if (threadIdx.x & 1) { ... }
```

### Block-Reduction Synthetics

Combine `__syncthreads` with a count/vote across the block:

| Function | Returns |
|----------|---------|
| `__syncthreads_count(pred)` | Count of threads with non-zero `pred` |
| `__syncthreads_and(pred)` | Non-zero iff ALL threads' `pred` is non-zero |
| `__syncthreads_or(pred)` | Non-zero iff ANY thread's `pred` is non-zero |

## Cluster-Level

See [[cluster-memory]]. `musaClusterSync()` is the cluster-wide barrier.

## Grid-Level (No Native Primitive!)

MUSA has **no native cross-block sync inside a kernel**. Two workarounds:

1. **End the kernel** — let the host re-launch the next one.
2. **Spin on global memory atomics** — works but is fragile:

```cpp
// Block 0 waits until block 1 signals via global atomic
if (blockIdx.x == 0) {
    while (atomicAdd(flag, 0) == 0) { /* spin */ }
    // Block 1 has finished writing d_buf
    use(d_buf);
}
if (blockIdx.x == 1) {
    fill(d_buf);
    __threadfence();              // make writes globally visible
    atomicExch(flag, 1);
}
```

> The `__threadfence` is essential — without it, the atomic write may become visible before the buffer writes.

## Memory Fences

Fences guarantee **ordering of memory operations** without halting execution. Three scopes:

| Fence | Scope |
|-------|-------|
| `__threadfence_block()` | Block |
| `__threadfence()` | Device (all threads on this GPU) |
| `__threadfence_system()` | System (across GPUs and host) |

```cpp
data[idx] = computed_value;
__threadfence();              // writes to data[idx] now visible device-wide
ready[idx] = 1;               // safe for other blocks to spin on ready[idx]
```

Use fences when:
- Publishing data via a flag (write-then-flag pattern).
- Implementing custom synchronization with atomics.
- Avoiding the cost of a full barrier when only ordering is needed.

## Volatile — Bypass the Compiler Cache

```cpp
volatile int* vflag = flag;
while (*vflag == 0) { }   // re-read every iteration; compiler can't cache in register
```

`volatile` forces the compiler to emit a real load every iteration — required for spin loops. Without it, the compiler may hoist the load out of the loop and hang.

## Acquire / Release Semantics via Atomics

Atomic ops with `_block`/`_system` variants provide implicit ordering:

```cpp
// Producer
data[idx] = value;
__threadfence();
atomicExch_system(&flag[idx], 1);          // release

// Consumer
while (atomicAdd_system(&flag[idx], 0) == 0) { /* spin */ }  // acquire
use(data[idx]);
```

## Choosing the Right Primitive

| Situation | Use |
|-----------|-----|
| Same-warp data exchange | `__syncwarp` or `__shfl_*_sync` |
| All threads in block share data via shared mem | `__syncthreads` |
| Block needs a count + barrier | `__syncthreads_count` |
| Multiple blocks in cluster share data | `musaClusterSync` |
| Cross-block sync inside kernel | atomic spin + `__threadfence` (rare — prefer kernel split) |
| Cross-GPU sync | `__threadfence_system` + `_system` atomics |
| Just ordering, no halt | `__threadfence*` |

## Cross-References

- [[warp-functions]] — warp-level vote/shuffle
- [[atomic-functions]] — atomic primitives and scope variants
- [[cluster-memory]] — `musaClusterSync`
- [[stream-and-event-model]] — host-side sync (different layer)
- → raw: `musa_cpp_syntax_atomic_functions.md`, `musa_cpp_syntax_warp_functions.md`
