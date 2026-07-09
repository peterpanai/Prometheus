---
title: "GEMV 优化"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_gemm_gemv_optimization.md, performance_tuning_memory_optimization.md]
tags: [musa, gemv, matrix-vector, memory-bound, vectorized]
---

# GEMV 优化 (GEMV Optimization)

GEMV (General Matrix-Vector Multiply, `y = αA×x + βy`) is the **M=1 special case of GEMM**. With one of the dimensions collapsed to a vector, GEMV is **memory-bound** — there's not enough arithmetic per byte loaded to saturate the compute units.

## Roofline Position

```
AI_GEMV = 2 * N / (4 * (N + N + 1)) ≈ 1/2  (for matrix N×N × vector N)
```

AI ≈ 0.5 FLOPs/Byte — far to the left of the ridge point. **Always memory-bound**. The goal is **maximize bandwidth utilization**, not FLOPS/s.

## Why GEMV is Different from GEMM

| Aspect | GEMM | GEMV |
|--------|------|------|
| Compute-bound? | Yes (for K large) | No |
| Tensor Cores useful? | Yes | Usually not (underutilized) |
| Goal | Saturate FLOPS/s | Saturate DRAM bandwidth |
| Inner loop | Reuse A and B heavily | A loaded once, x reused via cache |

## Two Layouts

### Row-Major A: each thread computes one output element

```cpp
// y[i] = sum_j A[i,j] * x[j]
__global__ void gemv_row(const float* A, const float* x, float* y, int M, int N) {
    int row = blockIdx.x * blockDim.x + threadIdx.x;
    if (row < M) {
        float acc = 0.0f;
        for (int j = 0; j < N; j++) {
            acc += A[row * N + j] * x[j];      // A coalesced, x broadcast via cache
        }
        y[row] = acc;
    }
}
```

- **A access**: coalesced across threads in a warp (each thread reads its own row's elements contiguously).
- **x access**: all threads read the same `x[j]` at the same time → broadcast through L2.
- Bandwidth: close to peak for A; x is essentially free.

### Column-Major A: each warp reduces a column

```cpp
// y[i] = sum_j A[j,i] * x[j] — column-major A
__global__ void gemv_col(const float* A, const float* x, float* y, int M, int N) {
    int col = blockIdx.x;
    int tid = threadIdx.x;

    // Each thread accumulates a partial sum for this column
    float partial = 0.0f;
    for (int j = tid; j < M; j += blockDim.x) {
        partial += A[j * N + col] * x[j];      // A access is strided!
    }

    // Warp/block reduction to combine partials
    partial += __shfl_down_sync(0xffffffff, partial, 16);
    partial += __shfl_down_sync(0xffffffff, partial, 8);
    // ... etc

    __shared__ float shared[32];
    if (tid % 32 == 0) shared[tid / 32] = partial;
    __syncthreads();
    // Reduce across warps...

    if (tid == 0) y[col] = shared[0];
}
```

- **A access**: strided across threads (column-major), but **contiguous across iterations within a thread**.
- **x access**: strided — each thread reads `x[tid], x[tid+blockDim], ...`. Cache-friendly if M is small.

Column-major GEMV is harder — the strided A access limits bandwidth. Use shared memory or transpose first if M is large.

## Vectorized Loads

Use `float4` to load 4 elements at once:

```cpp
// Row-major, vectorized
float4* A4 = (float4*)A;
float4* x4 = (float4*)x;
int N4 = N / 4;
float acc = 0.0f;
for (int j = 0; j < N4; j++) {
    float4 a = A4[row * N4 + j];
    float4 x_ = x4[j];
    acc += a.x * x_.x + a.y * x_.y + a.z * x_.z + a.w * x_.w;
}
// Handle tail (last N%4 elements) with scalar code
```

4× fewer load instructions.

## Multi-Element Per Thread (Grid-Stride)

For large M, each thread computes multiple rows:

```cpp
int row = blockIdx.x * blockDim.x + threadIdx.x;
int stride = blockDim.x * gridDim.x;
for (int r = row; r < M; r += stride) {
    float acc = 0.0f;
    for (int j = 0; j < N; j++) acc += A[r * N + j] * x[j];
    y[r] = acc;
}
```

Keeps the GPU fed with independent work.

## Warp-Level Approach (Better for Column-Major)

Have each warp compute one output element, using shuffle for the reduction:

```cpp
// 32 threads collaborate on one column
int warp_col = blockIdx.x;
int lane = threadIdx.x;
float partial = 0.0f;

for (int j = lane; j < M; j += 32) {
    partial += A[j * N + warp_col] * x[j];
}

// Warp shuffle reduction
for (int offset = 16; offset > 0; offset >>= 1)
    partial += __shfl_down_sync(0xffffffff, partial, offset);

if (lane == 0) y[warp_col] = partial;
```

Better than the per-thread approach because the 32 threads can coordinate cache reuse on `x`.

## Tensor Cores — Usually Not Helpful

Tensor Cores want tile shapes like 16×16×16. For GEMV, one dimension is 1, so the TC would be 95%+ idle. Stick with FP32 / FP16 scalar unless the matrix is unusually shaped.

**Exception**: Batched GEMV (many vectors) becomes GEMM. If you have B vectors to multiply, treat it as `C[M,B] = A[M,N] × X[N,B]` and use full GEMM optimization.

## Batched GEMV

For `y_k = A_k × x_k` with K independent (A_k, x_k) pairs, batch them into a single kernel:

```cpp
__global__ void gemvBatched(float** As, float** xs, float** ys, int M, int N) {
    int batch = blockIdx.y;
    int row = blockIdx.x * blockDim.x + threadIdx.x;
    if (row < M) {
        float* A = As[batch];
        float* x = xs[batch];
        float acc = 0.0f;
        for (int j = 0; j < N; j++) acc += A[row * N + j] * x[j];
        ys[batch][row] = acc;
    }
}
```

Or use the `muBLAS` library's `gemvStridedBatched` for production.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Column-major with strided A access | Use warp-level approach with shuffle reduction |
| Scalar loads (`float` instead of `float4`) | Vectorize for 4× throughput |
| One thread per row with very large N | Each thread does too much work; split across multiple warps |
| Forgetting to handle tail (N not multiple of 4) | Add scalar tail loop |
| Output y access strided | Each block writes contiguous chunk → coalesced |

## When to Use a Library

For production GEMV, use **muBLAS** (`mublasSgemv`, `mublasHgemv`). It auto-selects the best kernel based on M, N, layout, and dtype — typically outperforms hand-written code by 10-30%.

## Cross-References

- [[gemm-optimization]] — the general case; batched GEMV is GEMM
- [[roofline-model]] — GEMV's memory-bound position
- [[coalesced-access]] — critical for GEMV
- [[warp-shuffle]] — used in column-major reduction
- [[reduction-patterns]] — same pattern
- → raw: `performance_tuning_gemm_gemv_optimization.md`
