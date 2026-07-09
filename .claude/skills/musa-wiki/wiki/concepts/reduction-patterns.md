---
title: "归约模式"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_reduction_optimization.md, performance_tuning_quickstart_optimization.md]
tags: [musa, reduction, sum, max, min, warp-shuffle, tree-reduction]
---

# 归约模式 (Reduction Patterns)

Reduction is the canonical "compute one scalar from N inputs" pattern (sum, max, min, product, etc.). It is **memory-bound** for small element sizes, so the goal is to **minimize traffic** and **maximize per-thread work**.

## The Naive Baseline (Bad)

```cpp
__global__ void naiveReduce(float* in, float* out, int n) {
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) atomicAdd(out, in[idx]);   // 1 global atomic per element
}
```

This serializes on a single address. Bandwidth: ~0.1% of peak. **Never do this** for large N.

## Two-Stage Reduction (The Right Approach)

```
Stage 1: Each block reduces ~1024 elements → 1 partial sum per block → shared mem
Stage 2: Single small kernel reduces the partials → final answer
```

### Stage 1 — Block Reduction

```cpp
__global__ void blockReduceKernel(float* in, float* partials, int n) {
    __shared__ float shared[256];
    int tid = threadIdx.x;
    int idx = blockIdx.x * blockDim.x + tid;

    // Load + accumulate (grid-stride loop for n > blockDim)
    float v = 0.0f;
    while (idx < n) {
        v += in[idx];
        idx += blockDim.x * gridDim.x;
    }
    shared[tid] = v;
    __syncthreads();

    // Tree reduction in shared memory
    for (int s = blockDim.x / 2; s > 32; s >>= 1) {
        if (tid < s) shared[tid] += shared[tid + s];
        __syncthreads();
    }

    // Last warp reduces via shuffle (no sync needed)
    if (tid < 32) {
        float w = shared[tid];
        for (int s = 32; s > 0; s >>= 1)
            w += __shfl_down_sync(0xffffffff, w, s);
        if (tid == 0) partials[blockIdx.x] = w;
    }
}
```

### Stage 2 — Final Reduce

```cpp
__global__ void finalReduceKernel(float* partials, float* out, int n_partials) {
    __shared__ float shared[256];
    int tid = threadIdx.x;
    float v = (tid < n_partials) ? partials[tid] : 0.0f;
    shared[tid] = v;
    __syncthreads();

    // ... same tree reduction as above ...
    if (tid == 0) *out = shared[0];
}
```

Launch with one block of `nextPow2(n_partials)` threads.

## The Single-Kernel Reduction (Advanced)

Avoid the second kernel launch by allocating enough shared memory to hold partials and doing both stages in one block:

```cpp
__global__ void singleKernelReduce(float* in, float* out, int n) {
    extern __shared__ float shared[];
    int tid = threadIdx.x;
    int* partials = (int*)shared;     // first numBlocks floats are partials

    // ... compute this block's partial ...
    if (tid == 0) partials[blockIdx.x] = blockPartial;
    __syncthreads();

    // Last block finishes the reduction
    if (blockIdx.x == gridDim.x - 1) {
        float v = (tid < gridDim.x) ? partials[tid] : 0.0f;
        // ... tree reduce ...
        if (tid == 0) *out = finalResult;
    }
}
```

How does the last block know it's the last? Use an atomic counter:

```cpp
__shared__ bool amLast;
__device__ unsigned int retirementCount = 0;
if (tid == 0) {
    partials[blockIdx.x] = blockPartial;
    __threadfence();                  // make write visible
    unsigned int ticket = atomicAdd(&retirementCount, 1);
    amLast = (ticket == gridDim.x - 1);
}
__syncthreads();

if (amLast) {
    // reduce partials and write final answer
}
```

Saves one kernel launch but adds complexity. Worth it for short reductions called many times.

## Vectorized Load Optimization

Read 4 floats at once via `float4` to amortize instruction overhead:

```cpp
float4* in4 = (float4*)in;
int n4 = n / 4;
float v = 0.0f;
int idx = blockIdx.x * blockDim.x + threadIdx.x;
while (idx < n4) {
    float4 e = in4[idx];
    v += e.x + e.y + e.z + e.w;
    idx += blockDim.x * gridDim.x;
}
```

4× fewer load instructions. Make sure `n` is a multiple of 4 (handle tail separately if not).

## Generic Reductions (max, min, etc.)

Replace `+` with the reduction's binary op:

```cpp
// Max
v = fmaxf(v, __shfl_down_sync(0xffffffff, v, 16));
// ...
shared[tid] = fmaxf(shared[tid], shared[tid + s]);
```

Common reduction ops and their identities:

| Op | Identity |
|----|----------|
| Sum | 0 |
| Product | 1 |
| Max | -INF |
| Min | +INF |
| Bitwise AND | all-ones |
| Bitwise OR | 0 |
| Logical AND | true |

## Performance Pitfalls

| Pitfall | Fix |
|---------|-----|
| `__syncthreads` inside `if (tid < s)` | All-or-nothing; restructure if needed |
| Bank conflicts in shared reduction | Pad or use stride-1 access |
| Strided global access | Use `idx += blockDim*gridDim` (grid-stride) — coalesced |
| Atomic on global for partial | One atomic per **block**, not per element |
| Using float for summing millions of elements | Use double or Kahan summation |

## Float Precision Note

Summing N floats in FP32 accumulates rounding error ~`O(sqrt(N) * eps)`. For N > 10^7, the result can be off by 1%. Use `double` for the accumulator, or **Kahan summation**:

```cpp
float sum = 0, c = 0;
while (...) {
    float y = v - c;
    float t = sum + y;
    c = (t - sum) - y;
    sum = t;
}
```

## Workload Distribution

For very large N (e.g. 10^9 elements), each thread should process many elements (grid-stride loop), keeping occupancy high. Aim for ~10-100 elements per thread.

```cpp
int elements_per_thread = 32;
int blockSize = 256;
int gridStride = blockSize * gridSize;
int gridSize = (n + blockSize * elements_per_thread - 1) / (blockSize * elements_per_thread);
// Cap gridSize to a multiple of the SM count for best occupancy
```

## Cross-References

- [[warp-shuffle]] — used in the final warp reduction
- [[atomic-functions]] — used for the final global merge
- [[bank-conflicts]] — shared memory reduction can hit these
- [[roofline-model]] — reduction's roofline position
- → raw: `performance_tuning_reduction_optimization.md`
