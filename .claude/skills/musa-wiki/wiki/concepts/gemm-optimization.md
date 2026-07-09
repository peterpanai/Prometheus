---
title: "GEMM 优化"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_gemm_gemv_optimization.md, performance_tuning_compute_optimization.md, performance_tuning_memory_optimization.md]
tags: [musa, gemm, matrix-multiply, tensor-cores, tiling, mutlass]
---

# GEMM 优化 (GEMM Optimization)

GEMM (General Matrix Multiply, `C = αA×B + βC`) is the **canonical compute-bound** workload and the foundation of neural network training/inference. Achievable performance spans **3 orders of magnitude** between naive and optimized implementations — it's worth doing right.

## Roofline Position

```
AI_GEMM = 2 * M * N * K / (4 * (M*N + M*K + K*N)) ≈ K / 2  (for large M, N)
```

For K = 4096, AI ≈ 2048 FLOPs/Byte — well to the right of the ridge point. GEMM is **compute-bound** once K is large enough; the goal is to **hit peak FLOPS/s** (typically Tensor Core peak).

## The Optimization Ladder

| Level | Throughput (% of peak) | What it does |
|-------|------------------------|--------------|
| 0. Naive | 0.5-2% | One thread per output element, scattered loads |
| 1. Shared mem tiling | 10-25% | Load A/B tiles into shared mem, reuse across threads |
| 2. Register tiling | 30-50% | Each thread accumulates a small output tile in registers |
| 3. Vectorized loads | 40-60% | `float4` / `int4` loads to amortize instruction overhead |
| 4. Tensor Cores (wmma) | 50-70% | Use `mma_sync` for the inner kernel |
| 5. Double buffering | 60-80% | Overlap next-tile load with current-tile compute |
| 6. MUTLASS-tuned | 80-95% | All of the above + auto-tuned tile sizes |

## Level 1: Shared Memory Tiling

```cpp
// Tile size: BM x BN output, BK inner dimension
const int BM = 64, BN = 64, BK = 16;

__global__ void gemm_v1(const float* A, const float* B, float* C, int M, int N, int K) {
    __shared__ float A_tile[BM][BK];
    __shared__ float B_tile[BK][BN];

    int bx = blockIdx.x, by = blockIdx.y;
    int tx = threadIdx.x, ty = threadIdx.y;

    float acc = 0.0f;
    for (int k = 0; k < K; k += BK) {
        // Cooperative load: A's tile and B's tile into shared mem
        A_tile[ty][tx] = A[(by * BM + ty) * K + k + tx];
        B_tile[ty][tx] = B[(k + ty) * N + bx * BN + tx];
        __syncthreads();

        // Compute partial product
        for (int i = 0; i < BK; i++) {
            acc += A_tile[ty][i] * B_tile[i][tx];
        }
        __syncthreads();
    }

    C[(by * BM + ty) * N + bx * BN + tx] = acc;
}
```

Each element of A and B is loaded **once per output tile** instead of N or M times — bandwidth amortized.

## Level 2: Register Tiling

Instead of one thread = one output element, have one thread compute a small **output tile** (e.g. 4×4 or 8×8) in registers:

```cpp
// Each thread computes 8x8 = 64 output elements
float regC[8][8] = {0};

for (int k = 0; k < K; k += BK) {
    // Load BK x 8 of A and 8 x BN of B into shared mem
    // ...
    __syncthreads();

    // Each thread reads its slice of A and B from shared mem,
    // accumulates into its 8x8 register tile
    for (int i = 0; i < BK; i++) {
        float a0 = A_tile[ty*8+0][i], ..., a7 = A_tile[ty*8+7][i];
        float b0 = B_tile[i][tx*8+0], ..., b7 = B_tile[i][tx*8+7];
        regC[0][0] += a0 * b0; regC[0][1] += a0 * b1; // ... 64 FMAs
        // ... etc
    }
    __syncthreads();
}
```

Why this is faster:
- **8× fewer shared mem loads** per output element (each `a` is reused 8 times).
- **Instruction-level parallelism** — the 64 FMAs per inner iteration pipeline well.

## Level 3: Vectorized Loads

```cpp
// Load 4 floats at once via float4
float4 a = *(float4*)&A_tile[ty][k];
float4 b0 = *(float4*)&B_tile[k][tx*4+0];
// ... process 4 K-elements per instruction
```

4× fewer load instructions. Combined with register tiling, this is where you start hitting 40-60% of peak.

## Level 4: Tensor Cores

Replace the inner FMA loop with `mma_sync`:

```cpp
using namespace nvcuda::wmma;
fragment<matrix_a, 16, 16, 16, __half, row_major> a_frag;
fragment<matrix_b, 16, 16, 16, __half, row_major> b_frag;
fragment<accumulator, 16, 16, 16, float> c_frag;
fill_fragment(c_frag, 0.0f);

for (int k = 0; k < K; k += 16) {
    load_matrix_sync(a_frag, A_shared + ..., 16);
    load_matrix_sync(b_frag, B_shared + ..., 16);
    mma_sync(c_frag, a_frag, b_frag, c_frag);
}
store_matrix_sync(C + ..., c_frag, N, mem_row_major);
```

5-20× speedup over scalar FP32 once tile sizes are tuned. See [[tensor-cores]].

## Level 5: Double Buffering

While computing on tile `i`, load tile `i+1`:

```cpp
__shared__ float A_buf[2][BM][BK];
__shared__ float B_buf[2][BK][BN];

// Load tile 0 into buf[0]
loadTile(A, B, A_buf[0], B_buf[0], 0);

for (int k = 0; k < K; k += BK) {
    int cur = (k / BK) % 2;
    int nxt = 1 - cur;

    // Start async load of next tile into buf[nxt]
    musaMemcpyAsync(A_buf[nxt], A + ..., ..., musaMemcpyDeviceToDevice, stream_in_block);
    // Or use cp.async (MUSA equivalent) for true async load

    // Compute on current tile
    computeTile(A_buf[cur], B_buf[cur], c_frag);

    // Wait for next tile to be loaded
    __syncthreads();
}
```

Hides memory latency behind compute. With Tensor Cores, this can push you to 80%+ of peak.

## Level 6: MUTLASS

```cpp
#include <mutlass/...>

using Gemm = typename cutlass::gemm::kernel::Gemm<
    cutlass::gemm::GemmShape<128, 128, 32>,    // tile shape
    cutlass::gemm::GemmShape<16, 8, 16>,       // warp shape (Tensor Core tile)
    cutlass::half_t, cutlass::RowMajor,        // A
    cutlass::half_t, cutlass::RowMajor,        // B
    float, cutlass::RowMajor,                  // C/D
    float,                                     // accumulator
    cutlass::arch::OpClassTensorOp,
    cutlass::arch::Sm80                        // target arch
>;

Gemm gemm;
gemm.run(args);   // optimal kernel for this configuration
```

MUTLASS auto-tunes tile sizes, layout, and epilogue. For any production GEMM, **start here** — don't roll your own unless you have a specific need MUTLASS doesn't cover.

## Tile Size Cheat Sheet

| Hardware | Tile (BM × BN × BK) | Notes |
|----------|---------------------|-------|
| S5000 FP16 TC | 128 × 128 × 32 | Sweet spot |
| S5000 FP32 | 64 × 64 × 16 | Without TC |
| M1000/S4000 FP16 TC | 64 × 64 × 16 | Smaller SMs |

These are starting points — profile with `mcu` and adjust based on matrix shape.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| K not multiple of tile | Pad K or handle tail |
| M, N not multiple of tile | Pad or handle tail with separate kernel |
| Mismatched layout (row vs col) | Match fragment type to data |
| Shared mem bank conflicts | Pad shared mem arrays |
| Wrong leading dimension | Verify LD is full stride, not tile stride |
| Output not coalesced | Write back in the right order |

## Cross-References

- [[tensor-cores]] — the inner kernel
- [[roofline-model]] — GEMM's compute-bound position
- [[coalesced-access]] — load patterns
- [[bank-conflicts]] — shared mem tiling pitfalls
- [[double-buffering]] — level 5 optimization
- [[mutlass]] — the production library
- → raw: `performance_tuning_gemm_gemv_optimization.md`
