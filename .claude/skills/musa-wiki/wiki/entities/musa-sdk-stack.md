---
title: "MUSA SDK 软件栈"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_musa_sdk.md, what_is_musa.md]
tags: [musa, sdk, stack, overview, component]
---

# MUSA SDK 软件栈 (MUSA SDK Software Stack)

The MUSA SDK is the complete software stack for developing GPU-accelerated applications on Moore Threads GPUs. It mirrors the structure of NVIDIA's CUDA Toolkit — most CUDA code can be ported with minimal changes (see [[cuda-to-musa-mapping]]).

## Stack Layers

```
┌─────────────────────────────────────────────────────────┐
│  Application                                            │
├─────────────────────────────────────────────────────────┤
│  MUSA-X Libraries    │  muDNN    │  MCCL  │  MATE      │
│  (muBLAS, muFFT, ...) │  (DL)    │  (comm)│  (auto-tune)│
├─────────────────────────────────────────────────────────┤
│  MUSA C++ Language  │  Runtime API  │  Driver API      │
│  (compiler, syntax) │  (musart)     │  (mudrv)         │
├─────────────────────────────────────────────────────────┤
│  MUSA Driver (kernel-mode)                              │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
                   Moore Threads GPU Hardware
```

## Components

### Compiler Toolchain

- **mcc**: MUSA C++ compiler. Accepts `.cu`/`.mu` source with `__global__`, `<<<>>>` syntax. Produces fatbins containing PTX-like IR and SASS for target architectures. See [[mcc-compiler]].
- **musify**: Tool that converts CUDA source to MUSA source (mostly mechanical: `cuda*` → `musa*`). See [[musify-tool]].
- **MUSA Mapping**: compile-time CUDA compatibility plugin for `mcc` that rewrites CUDA-style source without changing the original files. See [[musa-mapping]].

### Runtime Libraries

- **musart** (`-lmusart`): High-level Runtime API. Device management, memory allocation, kernel launch via `<<<>>>`. Header: `<musa_runtime.h>`. See [[musart-runtime]], [[runtime-api]].
- **mudrv** (`-lmudrv`): Low-level Driver API. Explicit context, JIT module loading, Green Contexts. Header: `<mu.h>`. See [[musadrv-driver]], [[driver-api]].

### Math Libraries (MUSA-X)

Drop-in replacements for cuBLAS, cuFFT, etc. Prefixed `mu*` instead of `cu*`.

- **muBLAS**: Dense linear algebra (GEMM, GEMV, etc.)
- **muFFT: Fast Fourier Transform**
- **muRAND: Random number generation**
- **muSPARSE: Sparse matrix operations**
- **muSOLVER: Direct solvers (LU, Cholesky, etc.)**

See [[musa-x-libraries]].

### Domain Libraries

- **muDNN**: Deep learning primitives (conv, pooling, normalization). MUSA's analog of cuDNN. See [[mudnn]].
- **MCCL**: Multi-GPU collective communication (all-reduce, broadcast). MUSA's analog of NCCL. See [[mccl]].
- **MUTLASS**: Template library for GEMM/conv at the Tensor Core level. Analog of cuTLASS. See [[mutlass]].
- **MATE**: Auto-tuning framework for kernel parameters. (MUSA Auto-Tuning Engine.)

### Tooling

- **mcu**: Compute profiler — kernel timing, occupancy, memory metrics. See [[moore-perf]].
- **msys**: System profiler — multi-kernel timeline, stream/event visualization.
- **muPTI**: Profiling Tools Interface — low-level callbacks for instrumentation. See [[mupti]].
- **Moore Perf**: Unified performance analysis GUI.

### High-Level Frameworks

- **Triton-MUSA**: Triton language backend targeting MUSA.
- **TileLang-MUSA**: Tile-based DSL for writing portable kernels.
- **PyTorch/TensorFlow MUSA backends**: Framework-level integration.

## Compatibility Guarantee

Since MUSA SDK v5.1, the runtime guarantees backward compatibility — code compiled against an older SDK continues to work on newer drivers. This matches the CUDA minor-version compatibility promise.

Implication: **pin your SDK version** at the oldest driver you want to support. Newer drivers can run older-compiled binaries; older drivers cannot run newer-compiled binaries (without recompilation).

## Hardware Generations

| Codename | Architecture | Example GPU | Warp Size |
|----------|--------------|-------------|-----------|
| MP21 | MUSA 2.x | MTT S4000 | 128 |
| MP22 | MUSA 2.x | MTT M1000 | 128 |
| MP31 | MUSA 3.x | MTT S5000 | 32 |

Compile with `-arch=mp21`, `-arch=mp22`, or `-arch=mp31` (or `mp31` for fatbins supporting multiple).

## Version Discovery

```cpp
int version;
musaDriverGetVersion(&version);     // driver version
musaRuntimeGetVersion(&version);    // runtime version (must be ≤ driver)
```

If runtime > driver, your code will fail with `musaErrorInsufficientDriver`.

## Cross-References

- [[mcc-compiler]] — the compiler
- [[musart-runtime]] / [[musadrv-driver]] — runtime/driver libraries
- [[musa-x-libraries]] — math library family
- [[mudnn]] / [[mccl]] / [[mutlass]] — domain libraries
- [[moore-perf]] / [[mupti]] — profiling tools
- [[musify-tool]] — CUDA porting
- [[cuda-to-musa-mapping]] — naming and concept mapping
- → raw: `what_is_musa_musa_sdk.md`
