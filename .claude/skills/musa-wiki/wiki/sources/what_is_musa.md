---
title: "什么是 MUSA — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa.md, what_is_musa_gpu_parallel_basics.md, what_is_musa_musa_sdk.md]
tags: [musa, overview, simt, gpu-architecture, software-stack]
---

# 什么是 MUSA (What is MUSA)

**MUSA** (Meta-computing Unified System Architecture, 元计算统一系统架构) is Moore Threads' GPU parallel computing platform and programming language. The term "元计算" (meta-computing) covers AI compute, graphics, and physics simulation. MUSA includes the MUSA Instruction Set Architecture (ISA) and the parallel compute engines inside the GPU.

This chapter is the entry point to the MUSA programming guide. It covers three things:

1. **What MUSA is** — the platform, language, and software stack.
2. **GPU parallel computing basics** — CPU vs GPU, SIMT, thread hierarchy, memory hierarchy, kernel functions.
3. **The MUSA SDK software stack** — compiler, runtime, libraries, tools.

## Key Takeaways

- MUSA is a **CUDA-like platform** from Moore Threads. The API naming mirrors CUDA almost 1:1 (`musaMalloc`, `musaMemcpy`, `musaFree`, `musaStream_t`, `__global__`, `__shared__`, `<<<>>>`), so existing CUDA knowledge transfers directly.
- **Heterogeneous model**: CPU = Host (sequential logic, memory management, kernel launch), GPU = Device (massive parallel compute). They have separate memory spaces connected via PCIe.
- **SIMT execution**: a warp executes one instruction across all its threads; divergent branches are serialized. Warp size is **architecture-dependent**: 32 threads on MP31 (MTT S5000), 128 threads on MP21/MP22 (MTT M1000/S4000).
- **Three-level thread hierarchy**: Grid → Block → Thread. Blocks can sync internally (`__syncthreads()`); cross-block sync is forbidden to preserve portability.
- **Memory hierarchy**: registers (1 cycle, per-thread) > shared memory (1-2 cycles, per-block) > L1/L2 cache > constant memory (cached read-only) > global memory (100+ cycles, all threads). Plus host memory variants: pageable, pinned, mapped-pinned, write-combined.
- **Automatic scalability**: blocks are independent scheduling units, so the same compiled program runs on any number of multiprocessors (MPs) without code changes.

## Source Pages

| Raw File | Title | Covers |
|----------|-------|--------|
| `raw/sources/what_is_musa.md` | 什么是 MUSA | One-paragraph definition of MUSA as a platform/language/stack |
| `raw/sources/what_is_musa_gpu_parallel_basics.md` | GPU 并行计算 | CPU vs GPU, SIMT, Grid/Block/Thread, memory hierarchy, kernel basics, SAXPY example |
| `raw/sources/what_is_musa_musa_sdk.md` | MUSA 软件栈 | SDK architecture: Toolkits, MCCL, muDNN, compiler tools, OpenLibs, profiling tools, compatibility guarantees |

## MUSA SDK Software Stack

The SDK sits on top of the MT Linux Driver and bundles:

| Module | Components | Purpose |
|--------|------------|---------|
| **MUSA Toolkits** | `mcc` (compiler), MUSA Runtime, `musify` (CUDA→MUSA converter), MUSA-X Library (muBLAS, muBLASLt, muFFT, muSPARSE, muSOLVER, muPP, muRAND) | Core compile + runtime + math libs |
| **MCCL** | Multi-card communication library | Single-node multi-card and multi-node scenarios |
| **muDNN** | Deep learning acceleration library | Primitives for DL training/inference |
| **Compiler tools** | Triton-MUSA, TileLang-MUSA | Alternative compiler backends |
| **MUSA OpenLibs** | MATE (inference operators), MUTLASS (header-only GEMM library) | Higher-level accelerated libraries |
| **Tools** | Moore Perf, muPTI (Profiling and Tracing Infrastructure) | Performance analysis |

### Compatibility Guarantee (since v5.1)

Starting with MUSA 5.1, the SDK and Driver are independently upgradeable:

- **Forward compat**: Apps built with a newer SDK run on a 5.2.x Driver, except for driver-dependent features.
- **Backward compat**: Apps built with 5.2.x SDK run on a newer Driver.

## Hardware Reference Points

| Metric | CPU (Intel Xeon 8280) | GPU (MTT S5000) |
|--------|----------------------|-----------------|
| Cores | 28 | 4,096 |
| Clock | 2.7 GHz | 1.8 GHz |
| Memory bandwidth | 140 GB/s | 448 GB/s |
| Concurrent threads | ~1,792 | ~196,608 |
| FP32 throughput | 4.8 TFLOPS | 14.7 TFLOPS |

## Canonical First Kernel

```cpp
#include <musa_runtime.h>

__global__ void vectorAdd(const float *A, const float *B, float *C, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) C[i] = A[i] + B[i];
}

int main() {
    int n = 50000;
    size_t sz = n * sizeof(float);
    float *h_A = (float*)malloc(sz), *h_B = (float*)malloc(sz), *h_C = (float*)malloc(sz);
    /* ... init h_A, h_B ... */
    float *d_A, *d_B, *d_C;
    musaMalloc(&d_A, sz); musaMalloc(&d_B, sz); musaMalloc(&d_C, sz);
    musaMemcpy(d_A, h_A, sz, musaMemcpyHostToDevice);
    musaMemcpy(d_B, h_B, sz, musaMemcpyHostToDevice);
    int blockSize = 256, gridSize = (n + blockSize - 1) / blockSize;
    vectorAdd<<<gridSize, blockSize>>>(d_A, d_B, d_C, n);
    musaDeviceSynchronize();
    musaMemcpy(h_C, d_C, sz, musaMemcpyDeviceToHost);
    musaFree(d_A); musaFree(d_B); musaFree(d_C);
    free(h_A); free(h_B); free(h_C);
    return 0;
}
```

Compile: `mcc vectorAdd.mu -lmusart -o vectorAdd`.

## Cross-References

- **Programming model details**: [[programming-model]] — host/device, thread hierarchy, memory hierarchy, execution model
- **MUSA C++ syntax**: [[musa-cpp-syntax]] — `__global__`, `<<<>>>`, built-in variables
- **Software stack entities**: [[musa-sdk-stack]], [[mcc-compiler]], [[musify-tool]], [[musa-x-libraries]], [[mudnn]], [[mccl]], [[moore-perf]], [[mupti]]
- **SIMT and warp**: [[simt-execution-model]], [[warp-functions]], [[thread-hierarchy]]
- **Memory**: [[memory-hierarchy]], [[l2-cache-management]], [[advanced-memory]]
