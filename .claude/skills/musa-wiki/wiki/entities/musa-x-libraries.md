---
title: "MUSA-X 数学库"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_musa_sdk.md, what_is_musa.md]
tags: [musa, musa-x, mublas, mufft, murand, musparse, musolver, libraries]
---

# MUSA-X 数学库 (MUSA-X Math Libraries)

MUSA-X is the family of MUSA math libraries — drop-in replacements for NVIDIA's cu* libraries (cuBLAS, cuFFT, etc.). They provide optimized implementations of common numerical primitives, tuned for Moore Threads GPUs. All libraries are prefixed `mu*` and link as `-lmu<name>`.

## Library Inventory

| Library | CUDA equivalent | Purpose | Link flag |
|---------|-----------------|---------|-----------|
| **muBLAS** | cuBLAS | Dense linear algebra (BLAS levels 1-3) | `-lmublas` |
| **muFFT** | cuFFT | Fast Fourier Transform | `-lmufft` |
| **muRAND** | cuRAND | Random number generation | `-lmurand` |
| **muSPARSE** | cuSPARSE | Sparse matrix operations | `-lmusparse` |
| **muSOLVER** | cuSOLVER | Direct solvers (LU, Cholesky, QR) | `-lmusolver` |
| **muThrust** | Thrust | C++ template algorithms (sort, reduce, scan) | `-lmuthrust` |

## muBLAS — Dense Linear Algebra

BLAS levels:

| Level | Operations | Key functions |
|-------|-----------|---------------|
| 1 | Vector-vector | `mublasSaxpy`, `mublasSdot`, `mublasSnrm2` |
| 2 | Matrix-vector | `mublasSgemv`, `mublasSger` |
| 3 | Matrix-matrix | `mublasSgemm`, `mublasStrsm` |

### Example: SGEMM

```cpp
#include <mublas.h>

mublasHandle_t handle;
mublasCreate(&handle);

const float alpha = 1.0f, beta = 0.0f;
mublasSgemm(
    handle,
    MUBLAS_OP_N, MUBLAS_OP_N,    // no transpose for A, B
    M, N, K,                       // dimensions
    &alpha,
    d_A, K,                        // A: MxK, ld=K
    d_B, N,                        // B: KxN, ld=N
    &beta,
    d_C, N                         // C: MxN, ld=N
);

mublasDestroy(handle);
```

Internally uses [[tensor-cores]] when inputs are FP16/BF16 and the matrices are large enough.

## muFFT — Fast Fourier Transform

```cpp
#include <mufft.h>

mufftHandle plan;
mufftPlan1d(&plan, N, MUFFT_C2C, 1);    // 1D complex-to-complex, batch=1

mufftExecC2C(plan, d_in, d_out, MUFFT_FORWARD);

mufftDestroy(plan);
```

Supports 1D, 2D, 3D; complex-to-complex, complex-to-real, real-to-complex.

## muRAND — Random Number Generation

```cpp
#include <murand.h>

murandGenerator_t gen;
murandCreateGenerator(&gen, MURAND_RNG_PSEUDO_PHILOX4_32_10);
murandSetPseudoRandomGeneratorSeed(gen, 42);

murandGenerateUniform(gen, d_out, N);    // U(0,1)
murandGenerateNormal(gen, d_out, N, 0.0f, 1.0f);  // N(0,1)

murandDestroyGenerator(gen);
```

Two flavors:
- **Host API**: generator on host, output on device.
- **Device API**: `__device__` functions for in-kernel RNG.

## muSPARSE — Sparse Matrix Operations

```cpp
#include <musparse.h>

musparseHandle_t handle;
musparseCreate(&handle);

musparseMatDescr_t descr;
musparseCreateMatDescr(&descr);
musparseSetMatType(descr, MUSPARSE_MATRIX_TYPE_GENERAL);
musparseSetMatIndexBase(descr, MUSPARSE_INDEX_BASE_ZERO);

// CSR matrix-vector multiply: y = alpha * A * x + beta * y
musparseScsrmv(handle, MUSPARSE_OPERATION_NON_TRANSPOSE,
               M, N, nnz,
               &alpha,
               descr,
               d_csrVal, d_csrRowPtr, d_csrColInd,
               d_x,
               &beta, d_y);

musparseDestroyMatDescr(descr);
musparseDestroy(handle);
```

CSR, CSC, COO formats supported. Includes SpMV, SpMM, SpGEMM.

## muSOLVER — Direct Solvers

```cpp
#include <musolver.h>

musolverDnHandle_t handle;
musolverDnCreate(&handle);

// LU decomposition with partial pivoting
int* d_pivot;
musaMalloc(&d_pivot, N * sizeof(int));
musolverDnSgetrf(handle, N, N, d_A, N, d_pivot, d_info);

// Solve A * X = B given LU
musolverDnSgetrs(handle, MUSOLVER_OP_N, N, NRHS, d_A, N, d_pivot, d_B, N, d_info);

musaFree(d_pivot);
musolverDnDestroy(handle);
```

## muThrust — C++ Template Algorithms

```cpp
#include <muthrust/device_vector.h>
#include <muthrust/reduce.h>
#include <muthrust/sort.h>

muthrust::device_vector<int> v(N, 1);
int sum = muthrust::reduce(v.begin(), v.end(), 0);
muthrust::sort(v.begin(), v.end());
```

High-level container + algorithm library. Use for prototyping — typically 80-90% of hand-tuned performance with 1/10 the code.

## Library Conventions

All MUSA-X libraries follow these patterns (mirroring NVIDIA's cu* libraries):

1. **Handle-based**: create a handle, pass it to all functions, destroy at end.
2. **Stream-ordered**: `mublasSetStream(handle, stream)` binds operations to a stream.
3. **Pointer mode**: `mublasSetPointerMode(handle, MUBLAS_POINTER_MODE_HOST)` — alpha/beta on host (default) or device.
4. **Synchronous by default**: each call blocks the host until done. Use streams for async.
5. **Column-major** for BLAS (Fortran convention). Row-major data needs transpose flags.

## When to Use Libraries vs Custom Kernels

| Situation | Use |
|-----------|-----|
| Standard GEMM, FFT, RNG | Library — heavily tuned |
| Custom reduction with unusual op | Custom kernel — library may not have your op |
| Mixed-precision GEMM with epilogue | MUTLASS — library has limited flexibility |
| Very small matrices | Custom kernel — library overhead dominates |
| Sparse ops with unusual format | Custom kernel |

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgetting `mublasCreate` | All calls fail with `MUBLAS_STATUS_NOT_INITIALIZED` |
| Wrong leading dimension | Verify ld matches the actual stride |
| Mixing row-major data with column-major API | Use transpose flags or transpose data |
| Synchronous calls in a stream loop | Set stream on handle, use async variants |
| Not destroying handles | Memory leak |

## Cross-References

- [[musa-sdk-stack]] — library family's place in the stack
- [[mudnn]] — deep learning library (separate from MUSA-X)
- [[mccl]] — multi-GPU communication (separate)
- [[mutlass]] — GEMM template library
- [[gemm-optimization]] — what muBLAS does internally
- → raw: `what_is_musa_musa_sdk.md`
