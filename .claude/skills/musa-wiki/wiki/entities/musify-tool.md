---
title: "musify 转换工具"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_musa_sdk.md, getting_started_first_kernel.md, toolkits_musify.md]
tags: [musa, musify, cuda-porting, source-conversion, migration]
---

# musify 转换工具 (musify Conversion Tool)

`musify` is a source-to-source conversion tool that rewrites CUDA C++ source as MUSA C++ source. It performs the mechanical name substitutions (`cuda*` → `musa*`, `cu*` → `mu*`) that would otherwise be tedious to do by hand.

## What It Does

| Pattern | CUDA | MUSA |
|---------|------|------|
| Header | `<cuda_runtime.h>` | `<musa_runtime.h>` |
| Header | `<cublas_v2.h>` | `<mublas_v2.h>` |
| Header | `<cudnn.h>` | `<mudnn.h>` |
| Prefix | `cuda*` | `musa*` |
| Prefix | `cuBLAS` / `cuFFT` / etc. | `muBLAS` / `muFFT` / etc. |
| Macro | `__CUDA_API__` | `__MUSA_API__` |
| Macro | `CUDA_VERSION` | `MUSA_VERSION` |
| Type | `cudaError_t` | `musaError_t` |
| Type | `cudaStream_t` | `musaStream_t` |
| Type | `cudaDeviceProp` | `musaDeviceProp` |
| Constant | `cudaSuccess` | `musaSuccess` |
| Function | `cudaMalloc` | `musaMalloc` |
| Function | `cudaMemcpy` | `musaMemcpy` |
| Function | `cublasCreate` | `mublasCreate` |

## Basic Usage

```bash
musify kernel.cu > kernel.mu
```

Or in place:

```bash
musify -i kernel.cu
# produces kernel.mu, original kernel.cu preserved
```

Recursive over a directory:

```bash
musify -r src/ -o musa_src/
```

## What musify Cannot Do

`musify` does **mechanical substitution only**. It does not handle:

| Pattern | Manual fix needed |
|---------|-------------------|
| Warp size assumptions (`warpSize == 32`) | Add runtime check or conditional code for MP21/MP22 (warp=128) |
| PTX inline assembly (`asm("...")`) | Rewrite as MUSA intrinsics |
| CUDA-specific pragmas (`#pragma unroll`) | Usually portable, but verify |
| Thrust → muThrust API differences | Mostly direct, but check types |
| cuDNN descriptors → muDNN descriptors | Similar API but descriptor setup differs |
| cuTensor / cuQuantum | No direct MUSA equivalent — port to alternative |
| Driver API (`cuCtxCreate` etc.) | Manual: `muCtxCreate`, parameter differences |
| `nvcc` flags (`-arch=sm_80`) | Manual: `-arch=mp31` |
| Library names (`-lcudart`) | Manual: `-lmusart` |

After running musify, expect to fix the above by hand.

## Workflow: Porting a CUDA Project

1. **Run musify** on each `.cu` file → produces `.mu` files.
2. **Inspect diffs** — manual review of changes catches incorrect substitutions.
3. **Update build system**:
   - Replace `nvcc` with `mcc`.
   - Replace `-lcudart`, `-lcublas`, etc. with `-lmusart`, `-lmublas`.
   - Replace `-arch=sm_X` with `-arch=mpX` (mp21, mp22, or mp31).
4. **Compile and fix errors** — focus on:
   - API differences (descriptor setup, parameter order)
   - PTX assembly (rewrite as intrinsics)
   - Warp size assumptions
5. **Test for correctness** — verify outputs match.
6. **Profile and tune** — see [[optimization-playbook]].

## Handling Warp Size Differences

CUDA assumes `warpSize == 32`. On MTT M1000/S4000 (MP21/MP22), warpSize is 128. Code that hardcodes 32 breaks:

```cpp
// ❌ CUDA original
v += __shfl_down_sync(0xffffffff, v, 16);
v += __shfl_down_sync(0xffffffff, v, 8);
v += __shfl_down_sync(0xffffffff, v, 4);
v += __shfl_down_sync(0xffffffff, v, 2);
v += __shfl_down_sync(0xffffffff, v, 1);

// ✅ Portable MUSA — loop using warpSize
for (int offset = warpSize / 2; offset > 0; offset >>= 1) {
    v += __shfl_down_sync(0xffffffff, v, offset);
}
```

Or compile two versions and select at runtime:

```cpp
if (warpSize == 32) {
    reduce32Kernel<<<grid, block>>>(d);
} else {
    reduce128Kernel<<<grid, block>>>(d);
}
```

## Manual API Mapping

For APIs that don't have direct MUSA equivalents, see [[cuda-to-musa-mapping]].

## Compile After musify

```bash
mcc kernel.mu -lmusart -o kernel
# or for a project:
mcc -arch=mp31 -I./include src/*.mu -lmusart -lmublas -lmudnn -o app
```

## Limitations and Pitfalls

| Pitfall | Fix |
|---------|-----|
| Substitutions inside comments/strings | Review output manually |
| Type-mismatched overloads | Verify each `cuda*` → `musa*` is type-correct |
| Conditional compilation (`#ifdef CUDA`) | Update your `#ifdef`s or add `#define MUSA` |
| CUDA-specific libraries (cuQuantum, cuTensor) | Find alternative or implement manually |
| Inline PTX | Rewrite as MUSA intrinsics |

## When musify Isn't Enough

For projects with extensive PTX, heavy use of CUDA-specific features (cooperative groups, dynamic parallelism nuances, etc.), or unusual APIs, manual porting is required. Use musify to do the bulk mechanical work, then finish by hand.

## Cross-References

- [[cuda-to-musa-mapping]] — comprehensive name/concept mapping
- [[mcc-compiler]] — compiles the converted source
- [[musa-sdk-stack]] — target software stack
- → raw: `what_is_musa_musa_sdk.md`
