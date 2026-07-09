---
title: "双缓冲"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_memory_optimization.md, performance_tuning_gemm_gemv_optimization.md]
tags: [musa, double-buffering, pipelining, async-copy, latency-hiding]
---

# 双缓冲 (Double Buffering)

Double buffering is a **pipelining technique** that overlaps the next iteration's memory loads with the current iteration's compute. By keeping two buffers in shared memory and alternating between them, the kernel hides memory latency behind arithmetic.

## The Pattern

Without double buffering:

```
iter 0: [load tile 0] [compute tile 0] [load tile 1] [compute tile 1] ...
                                            ↑ SM idle during load
```

With double buffering:

```
iter 0: [load tile 0]
iter 1: [compute tile 0 || load tile 1]
iter 2: [compute tile 1 || load tile 2]
...
last:   [compute tile N]
```

Memory latency is hidden behind compute as long as `compute_time ≥ load_time`.

## Implementation

```cpp
__shared__ float A_buf[2][BM][BK];
__shared__ float B_buf[2][BK][BN];

// Pre-load tile 0 into buffer 0
loadTile(A_buf[0], B_buf[0], 0);

for (int k = 0; k < K; k += BK) {
    int cur = (k / BK) % 2;
    int nxt = 1 - cur;

    // Issue async load of tile k+BK into buffer nxt
    // (MUSA cp.async equivalent)
    if (k + BK < K) {
        asyncLoadTile(A_buf[nxt], B_buf[nxt], k + BK);
    }

    // Compute on current tile (cur)
    computeTile(A_buf[cur], B_buf[cur]);

    // Wait for next tile to be ready
    __syncthreads();  // or wait on async copy completion
}
```

## Async Copy (MUSA Equivalent of cp.async)

The key primitive is an **async memory copy** that doesn't block the SM:

```cpp
// Pseudocode — actual MUSA intrinsic may differ
__shared__ float buf[256];
musa::memcpy_async(buf, d_global, sizeof(float) * 256, barrier);
// ... SM continues executing other instructions ...
musa::wait(barrier);   // blocks only if copy hasn't completed
```

Combined with `__pipeline_memcpy_async` and `__pipeline_commit` / `__pipeline_wait_prior`, you can build a multi-stage pipeline (not just 2-buffer).

## Multi-Stage Pipelines

Generalize from 2 to N buffers for deeper pipelining:

```cpp
const int STAGES = 4;
__shared__ float A_buf[STAGES][BM][BK];
__shared__ float B_buf[STAGES][BK][BN];

// Pre-load STAGES-1 tiles
for (int s = 0; s < STAGES - 1; s++)
    asyncLoadTile(A_buf[s], B_buf[s], s * BK);

for (int k = 0; k < K; k += BK) {
    int cur = (k / BK) % STAGES;
    int nxt = (k / BK + STAGES - 1) % STAGES;

    // Issue load for tile k + (STAGES-1)*BK
    if (k + (STAGES-1) * BK < K)
        asyncLoadTile(A_buf[nxt], B_buf[nxt], k + (STAGES-1) * BK);

    // Compute current
    computeTile(A_buf[cur], B_buf[cur]);

    __pipeline_wait_prior(STAGES - 1);  // wait for the next tile we need
}
```

4-stage pipeline typically gives near-100% memory/compute overlap.

## Trade-offs

| Aspect | Cost |
|--------|------|
| Shared memory | N× the buffer size — pressures occupancy |
| Complexity | More code, harder to debug |
| Synchronization | Need careful `__pipeline_wait_prior` or barriers |
| Cold start | First N-1 iterations can't overlap |

Choose N to balance: enough stages to hide latency, but small enough to preserve occupancy.

## When Double Buffering Helps

| Workload | Helps? | Why |
|----------|--------|-----|
| GEMM with large tiles | ✅ | Each tile load is significant; compute is heavy enough to overlap |
| Stencil codes | ✅ | Load next halo while computing current cell |
| Reduction | ❌ | No reuse — load is one-shot |
| Elementwise | ❌ | Compute is too cheap to overlap |
| Convolution | ✅ | Same as GEMM, tile-based |

## Required Primitives

| Primitive | MUSA |
|-----------|------|
| Async global→shared copy | `musa::memcpy_async` or `__pipeline_memcpy_async` |
| Pipeline commit | `__pipeline_commit()` |
| Pipeline wait | `__pipeline_wait_prior(N)` |
| Barrier with arrival/wait split | `musa::barrier` (arrival + wait) |

If your MUSA version lacks any of these, you can fall back to:
- Issue normal `musaMemcpyAsync` (host-launched) — limited.
- Use `__syncthreads` between load and compute — no overlap, but correct.
- Use shared mem atomics + flags — manual, fragile.

## Common Bugs

| Bug | Fix |
|-----|-----|
| Forgetting `__pipeline_wait_prior` before reading the buffer | Add explicit wait |
| Indexing buffer with wrong modulo | Use clear `cur`/`nxt` variables, not raw math |
| Buffer too small → bank conflicts | Size tiles to avoid 32-bank aliasing |
| All threads issuing async copy (redundant) | Gate the load with `if (threadIdx.x < loadThreads)` |

## Cross-References

- [[gemm-optimization]] — primary use case (level 5)
- [[memory-hierarchy]] — shared memory capacity limits
- [[bank-conflicts]] — multi-buffer can introduce new conflicts
- [[stream-and-event-model]] — host-side async, conceptually similar
- → raw: `performance_tuning_memory_optimization.md`
