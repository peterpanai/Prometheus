---
title: "Tensor Cores"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_compute_optimization.md, performance_tuning_gemm_gemv_optimization.md]
tags: [musa, tensor-cores, wmma, mma, fp16, bf16, tf32]
---

# Tensor Cores

Tensor Cores are specialized hardware units that perform **matrix multiply-accumulate** (MMA) in a single cycle: `D = A × B + C`, where A, B, C, D are small tile matrices. They deliver 5-20× the FLOPS/s of regular FP32 CUDA cores for matrix-heavy workloads.

## What Tensor Cores Compute

A single MMA operation computes:

```
D[m,n] = A[m,k] × B[k,n] + C[m,n]
```

Where the tile dimensions are architecture-specific (e.g. 16×16×16). The hardware does this in one cycle instead of M*N*K scalar multiply-accumulates.

## Supported Data Types

| Type | A | B | C/D | Notes |
|------|---|---|-----|-------|
| FP16 | fp16 | fp16 | fp16/fp32 | Most common; accumulate in fp32 |
| BF16 | bf16 | bf16 | fp16/fp32 | Better range than fp16, training-friendly |
| TF32 | tf32 | tf32 | fp32 | Looks like fp32 to code, runs at ~2× fp32 |
| INT8 | int8 | int8 | int32 | Quantized inference |
| FP64 | fp64 | fp64 | fp64 | Some architectures, much lower throughput |

## WMMA API — The High-Level Interface

```cpp
#include <musa_wmma.h>

using namespace nvcuda::wmma;

fragment<matrix_a, 16, 16, 16, __half, row_major> a_frag;
fragment<matrix_b, 16, 16, 16, __half, row_major> b_frag;
fragment<accumulator, 16, 16, 16, float> c_frag;

load_matrix_sync(a_frag, d_A, K);     // load 16x16 tile from global
load_matrix_sync(b_frag, d_B, N);
fill_fragment(c_frag, 0.0f);

mma_sync(c_frag, a_frag, b_frag, c_frag);   // D = A*B + C in one op

store_matrix_sync(d_C, c_frag, N, mem_row_major);
```

Key points:
- **Fragment**: a tile distributed across warp lanes. You don't see individual elements — only the API touches them.
- **`load_matrix_sync`**: cooperative load by the whole warp; leading dimension (K or N) must be specified.
- **`mma_sync`**: the actual MMA op. All lanes in the warp participate.
- **`store_matrix_sync`**: write the result back to global/shared memory.

## Tile Sizes

Common tile shapes (architecture-dependent):

```
16 × 16 × 16     — most universal
32 × 8 × 16
8 × 32 × 16
16 × 16 × 8      (TF32)
```

Choose based on the matrix shape — for square matrices, 16×16×16 is typical.

## Performance

| Unit | Approximate throughput (MTT S5000, FP16) |
|------|-------------------------------------------|
| FP32 CUDA core | ~40 TFLOPS total |
| FP16 Tensor Core | ~160 TFLOPS total |

The peak is only achieved when:
- A and B have **good layout** (row-major or column-major matching the fragment type).
- The K dimension is **large enough** to amortize load/setup cost.
- Tiles are **large enough** to fill the Tensor Core pipeline.

## Memory Layout Requirements

Tensor Core fragments expect data in a specific layout:

```cpp
// Row-major A:
load_matrix_sync(a_frag, d_A + row * K + col, K);  // stride K, row_major
//                                            ^ leading dim

// Column-major A:
fragment<...,col_major> a_frag;
load_matrix_sync(a_frag, d_A + row + col * M, M);
```

If your data is not in the right layout, you must either:
- Re-layout on the host before launch (one-time cost).
- Transpose in shared memory inside the kernel.

## Usage Pattern: Tiled GEMM

```cpp
__global__ void gemm_kernel(__half* A, __half* B, float* C,
                            int M, int N, int K) {
    const int WM = 16, WN = 16, WK = 16;
    int warpM = (blockIdx.x * blockDim.x + threadIdx.x) / 32;  // each warp = 1 tile
    int warpN = blockIdx.y;

    fragment<matrix_a, WM, WN, WK, __half, row_major> a_frag;
    fragment<matrix_b, WM, WN, WK, __half, row_major> b_frag;
    fragment<accumulator, WM, WN, WK, float> c_frag;
    fill_fragment(c_frag, 0.0f);

    // Loop over K dimension in tiles of WK
    for (int k = 0; k < K; k += WK) {
        load_matrix_sync(a_frag, A + warpM * WM * K + k, K);
        load_matrix_sync(b_frag, B + k * N + warpN * WN, N);
        mma_sync(c_frag, a_frag, b_frag, c_frag);
    }

    store_matrix_sync(C + warpM * WM * N + warpN * WN, c_frag, N, mem_row_major);
}
```

> This is the **textbook minimum**. Production GEMM uses shared memory tiling, double buffering, and vectorized loads. See [[gemm-optimization]] and consider MUTLASS.

## When to Use Tensor Cores

| Workload | Use TC? |
|----------|---------|
| GEMM (M, N, K ≥ 64) | ✅ |
| GEMV (M or N = 1) | ❌ TC underutilized; use plain FP16 |
| Convolution (im2col + GEMM) | ✅ |
| Attention (Q×Kᵀ, ×V) | ✅ (see [[flash-attention]]) |
| Reduction, scan | ❌ Not matrix-shaped |
| Elementwise ( relu, sigmoid) | ❌ |

## Pitfalls

| Pitfall | Fix |
|---------|-----|
| K not multiple of WK | Pad K or handle tail with scalar code |
| M, N not multiple of WM, WN | Pad or handle tail |
| Misaligned leading dimension | Align to 16 bytes (or use shared mem) |
| Wrong fragment layout | Verify `row_major`/`col_major` matches data |
| Warp divergence inside TC code | Keep all lanes active in TC region |

## MUTLASS

For production GEMM, use **MUTLASS** (MUSA Tensor Library Analogous to cuTLASS). It provides parameterized templates for GEMM, conv, and other TC workloads — handles tiling, double buffering, and tail handling for you.

```cpp
#include <mutlass/...>
// Define tile shapes, data types, epilogue
// MUTLASS generates optimal kernel
```

## Cross-References

- [[gemm-optimization]] — canonical TC workload
- [[flash-attention]] — TC in attention
- [[roofline-model]] — TC raises the compute ceiling
- [[mutlass]] — high-level library entity
- → raw: `performance_tuning_compute_optimization.md`
