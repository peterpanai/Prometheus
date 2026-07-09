---
title: "MUTLASS"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_gemm_gemv_optimization.md, performance_tuning_compute_optimization.md]
tags: [musa, mutlass, cutlass-equivalent, gemm, template-library, tensor-cores]
---

# MUTLASS

MUTLASS (MUSA Template Library Analogous to cuTLASS) is a C++ template library for writing high-performance GEMM, convolution, and related kernels at the Tensor Core level. It is MUSA's analog of NVIDIA's cuTLASS.

## Why It Exists

Writing a high-performance GEMM from scratch is hard:

- Need to choose tile shapes (BM, BN, BK), warp shapes, instruction shapes
- Need to handle shared memory layout, bank conflicts, double buffering
- Need to use Tensor Cores correctly
- Need to handle tail cases (M, N, K not divisible by tile)
- Need to handle multiple data types and epilogues

MUTLASS provides parameterized templates that handle all of this — you specify the shape, dtype, and epilogue, it generates a tuned kernel.

## Template Composition

MUTLASS GEMM kernels are composed of several template parameters:

```cpp
#include <mutlass/...>

using Gemm = typename mutlass::gemm::kernel::Gemm<
    // Tile shapes
    mutlass::gemm::GemmShape<128, 128, 32>,        // BM x BN x BK
    mutlass::gemm::GemmShape<16, 8, 16>,            // warp tile (Tensor Core size)

    // Data types
    cutlass::half_t, mutlass::layout::RowMajor,    // A
    cutlass::half_t, mutlass::layout::RowMajor,    // B
    float,            mutlass::layout::RowMajor,    // C/D
    float,                                              // accumulator

    // Operation class & architecture
    mutlass::arch::OpClassTensorOp,
    mutlass::arch::Mp31,                              // target arch

    // Epilogue
    mutlass::epilogue::thread::LinearCombination<float, float, float, float>,

    // Threadblock swizzling
    mutlass::gemm::threadblock::GemmIdentityThreadblockSwizzle<>
>;
```

Each template parameter tunes one aspect. The library emits a specialized kernel for that exact configuration.

## Running a GEMM

```cpp
Gemm gemm;

typename Gemm::Arguments args{
    {M, N, K},                          // problem size
    {d_A, K},                           // A (with leading dim)
    {d_B, N},                           // B
    {d_C, N},                           // C (source)
    {d_D, N},                           // D (destination)
    {1.0f, 0.0f},                       // alpha, beta
    1                                   // batch count
};

gemm.run(args, stream);
```

The `run` method dispatches to the optimized kernel.

## Tuning Tile Sizes

The choice of tile shapes determines performance:

| Hardware | M, N, K | Recommended tile |
|----------|---------|------------------|
| S5000 FP16 TC | large (≥1024) | 128 × 128 × 32 |
| S5000 FP16 TC | medium (256-1024) | 64 × 64 × 32 |
| S5000 FP16 TC | small (<256) | 32 × 32 × 16 |
| S5000 FP32 | any | 64 × 64 × 16 |

MUTLASS includes a `mutlass-profiler` tool that benchmarks all tile shapes for a given problem — use it to find the optimal configuration.

## Epilogues

The epilogue is what happens after the MMA — typically a fused operation:

```cpp
// Linear combination: D = alpha * A*B + beta * C
mutlass::epilogue::thread::LinearCombination<...>

// ReLU: D = relu(alpha * A*B + beta * C)
mutlass::epilogue::thread::LinearCombinationRelu<...>

// Bias add: D = alpha * A*B + beta * C + bias
mutlass::epilogue::thread::LinearCombinationBias<...>

// Gelu: D = gelu(alpha * A*B + beta * C)
mutlass::epilogue::thread::LinearCombinationGelu<...>
```

Fusing the epilogue with the GEMM saves a separate kernel launch and a full read/write of the output — typically 10-30% speedup.

## Convolution

MUTLASS also supports implicit-GEMM convolution:

```cpp
using Conv = typename mutlass::conv::device::Conv2d<
    mutlass::conv::ConvType::kFprop,           // forward / backward_data / backward_filter
    cutlass::half_t, mutlass::layout::TensorNCHW,    // input
    cutlass::half_t, mutlass::layout::TensorNCHW,    // filter
    float,            mutlass::layout::TensorNCHW,    // output
    // ... tile, arch, epilogue ...
>;
```

Convolution is implemented as an implicit GEMM (im2col + GEMM fused).

## GroupedGemm and TrackedGemm

For batched / grouped GEMMs:

```cpp
using GroupedGemm = typename mutlass::gemm::device::GemmGrouped<...>;

GroupedGemm::Arguments args;
args.problem_size = { /* per-group sizes */ };
args.ptr_A = { /* per-group A pointers */ };
// ...
```

Useful for MoE (mixture-of-experts) and multi-head attention batched GEMMs.

## Profiling Tool

```bash
# Auto-tune tile sizes for a specific problem
mutlass-profiler --operation=Gemm \
                 --A=f16:1024:1024 --B=f16:1024:1024 \
                 --accumulator=f32 \
                 --arch=mp31 \
                 --output=results.csv

# Then read results.csv to find the best tile
```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Wrong layout (Row vs Column major) | Match `layout::RowMajor`/`ColMajor` to data |
| M, N, K not multiple of tile | Let MUTLASS handle tail, or pad |
| Forgetting to call `gemm.run` | Some configs need explicit `initialize`/`run` |
| Mixing archs in same binary | Use separate template instantiations |
| Compile time too long | Pre-instantiate the configs you need |

## When to Use MUTLASS vs Hand-Written

| Situation | Use |
|-----------|-----|
| Standard GEMM with Tensor Cores | MUTLASS |
| Convolution | MUTLASS |
| Need fused epilogue | MUTLASS |
| Unusual MMA pattern (e.g. sparse) | Custom (MUTLASS may not support) |
| Very small matrices | Hand-written (MUTLASS overhead dominates) |
| Educational / learning | Hand-written first, then MUTLASS |

## Cross-References

- [[gemm-optimization]] — what MUTLASS implements
- [[tensor-cores]] — the inner primitive
- [[musa-x-libraries]] — muBLAS is built on MUTLASS
- [[flash-attention]] — can be implemented with MUTLASS
- → raw: `performance_tuning_gemm_gemv_optimization.md`
