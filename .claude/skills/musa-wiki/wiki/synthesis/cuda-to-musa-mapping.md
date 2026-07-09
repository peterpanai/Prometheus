---
title: "CUDA → MUSA 映射"
type: synthesis
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_musa_sdk.md, api_guides_runtime_api_guide.md, api_guides_driver_api_guide.md, musa_cpp_syntax.md]
tags: [musa, cuda, mapping, porting, synthesis]
---

# CUDA → MUSA 映射 (CUDA to MUSA Mapping)

MUSA is API-compatible with CUDA at the source level for the vast majority of operations. This page is the comprehensive mapping — use it as a lookup when porting CUDA code or reading MUSA code with a CUDA background.

## Naming Convention

| Layer | CUDA | MUSA |
|-------|------|------|
| Runtime API prefix | `cuda*` | `musa*` |
| Driver API prefix | `cu*` | `mu*` |
| Library prefix | `cu*` (cuBLAS, cuFFT, cuDNN) | `mu*` (muBLAS, muFFT, muDNN) |
| Compiler | `nvcc` | `mcc` |
| Source extension | `.cu` | `.mu` (or `.cu`, mcc accepts both) |
| Header path | `<cuda_*.h>` | `<musa_*.h>` |
| Link flag | `-lcudart` | `-lmusart` |
| Driver link | `-lcudart` | `-lmudrv` |

## Header Mapping

| CUDA Header | MUSA Header |
|-------------|-------------|
| `<cuda_runtime.h>` | `<musa_runtime.h>` |
| `<cuda_runtime_api.h>` | `<musa_runtime_api.h>` |
| `<cuda.h>` (Driver) | `<mu.h>` |
| `<cublas_v2.h>` | `<mublas_v2.h>` |
| `<cufft.h>` | `<mufft.h>` |
| `<curand.h>` | `<murand.h>` |
| `<cusparse.h>` | `<musparse.h>` |
| `<cusolver_common.h>` | `<musolver_common.h>` |
| `<cudnn.h>` | `<mudnn.h>` |
| `<nccl.h>` | `<mccl.h>` |
| `<cutlass/cutlass.h>` | `<mutlass/...>` |
| `<cooperative_groups.h>` | `<musa_cooperative_groups.h>` (if available) |
| `<mma.h>` (wmma) | `<musa_wmma.h>` |

## Type Mapping

| CUDA Type | MUSA Type |
|-----------|-----------|
| `cudaError_t` | `musaError_t` |
| `cudaStream_t` | `musaStream_t` |
| `cudaEvent_t` | `musaEvent_t` |
| `cudaDeviceProp` | `musaDeviceProp` |
| `cudaMemcpyKind` | `musaMemcpyKind` |
| `cudaHostAlloc_t` | `musaHostAlloc_t` |
| `cudaMemPool_t` | `musaMemPool_t` |
| `cudaGraph_t` | `musaGraph_t` |
| `cudaGraphExec_t` | `musaGraphExec_t` |
| `cudaUUID_t` | `musaUUID_t` |
| `CUcontext` (Driver) | `MUcontext` |
| `CUmodule` | `MUmodule` |
| `CUfunction` | `MUfunction` |
| `CUdeviceptr` | `MUdeviceptr` |
| `CUstream` | `MUstream` |
| `CUevent` | `MUevent` |
| `CUresult` (Driver) | `MUresult` |

## Constant / Enum Mapping

| CUDA | MUSA |
|------|------|
| `cudaSuccess` | `musaSuccess` |
| `cudaMemcpyHostToDevice` | `musaMemcpyHostToDevice` |
| `cudaMemcpyDeviceToHost` | `musaMemcpyDeviceToHost` |
| `cudaMemcpyDeviceToDevice` | `musaMemcpyDeviceToDevice` |
| `cudaHostAllocMapped` | `musaHostAllocMapped` |
| `cudaHostAllocWriteCombined` | `musaHostAllocWriteCombined` |
| `cudaStreamNonBlocking` | `musaStreamNonBlocking` |
| `cudaDeviceSynchronize` | `musaDeviceSynchronize` |
| `cudaDevAttrMultiprocessorCount` | `musaDevAttrMultiprocessorCount` |
| `CUDA_ERROR_INVALID_VALUE` | `MU_ERROR_INVALID_VALUE` |

## Function Mapping (Runtime API)

| CUDA | MUSA |
|------|------|
| `cudaMalloc` | `musaMalloc` |
| `cudaFree` | `musaFree` |
| `cudaMallocHost` | `musaMallocHost` |
| `cudaFreeHost` | `musaFreeHost` |
| `cudaMallocManaged` | `musaMallocManaged` |
| `cudaMallocAsync` | `musaMallocAsync` |
| `cudaFreeAsync` | `musaFreeAsync` |
| `cudaMemcpy` | `musaMemcpy` |
| `cudaMemcpyAsync` | `musaMemcpyAsync` |
| `cudaMemset` | `musaMemset` |
| `cudaMemcpyToSymbol` | `musaMemcpyToSymbol` |
| `cudaMemcpyFromSymbol` | `musaMemcpyFromSymbol` |
| `cudaGetDeviceCount` | `musaGetDeviceCount` |
| `cudaSetDevice` | `musaSetDevice` |
| `cudaGetDevice` | `musaGetDevice` |
| `cudaGetDeviceProperties` | `musaGetDeviceProperties` |
| `cudaDeviceGetAttribute` | `musaDeviceGetAttribute` |
| `cudaDeviceSynchronize` | `musaDeviceSynchronize` |
| `cudaDeviceReset` | `musaDeviceReset` |
| `cudaGetLastError` | `musaGetLastError` |
| `cudaGetErrorString` | `musaGetErrorString` |
| `cudaStreamCreate` | `musaStreamCreate` |
| `cudaStreamDestroy` | `musaStreamDestroy` |
| `cudaStreamSynchronize` | `musaStreamSynchronize` |
| `cudaStreamWaitEvent` | `musaStreamWaitEvent` |
| `cudaEventCreate` | `musaEventCreate` |
| `cudaEventRecord` | `musaEventRecord` |
| `cudaEventSynchronize` | `musaEventSynchronize` |
| `cudaEventElapsedTime` | `musaEventElapsedTime` |
| `cudaOccupancyMaxActiveBlocksPerMultiprocessor` | `musaOccupancyMaxActiveBlocksPerMultiprocessor` |
| `cudaGraphCreate` | `musaGraphCreate` |
| `cudaGraphInstantiate` | `musaGraphInstantiate` |
| `cudaGraphLaunch` | `musaGraphLaunch` |
| `cudaStreamBeginCapture` | `musaStreamBeginCapture` |
| `cudaStreamEndCapture` | `musaStreamEndCapture` |

## Function Mapping (Driver API)

| CUDA | MUSA |
|------|------|
| `cuInit` | `muInit` |
| `cuDeviceGet` | `muDeviceGet` |
| `cuDeviceGetAttribute` | `muDeviceGetAttribute` |
| `cuCtxCreate` | `muCtxCreate` |
| `muCtxDestroy` | `muCtxDestroy` |
| `cuCtxSetCurrent` | `muCtxSetCurrent` |
| `cuDevicePrimaryCtxRetain` | `muDevicePrimaryCtxRetain` |
| `cuModuleLoad` | `muModuleLoad` |
| `cuModuleLoadData` | `muModuleLoadData` |
| `cuModuleUnload` | `muModuleUnload` |
| `cuModuleGetFunction` | `muModuleGetFunction` |
| `cuMemAlloc` | `muMemAlloc` |
| `cuMemFree` | `muMemFree` |
| `cuMemcpyHtoD` | `muMemcpyHtoD` |
| `cuMemcpyDtoH` | `muMemcpyDtoH` |
| `cuLaunchKernel` | `muLaunchKernel` |
| `cuStreamCreate` | `muStreamCreate` |
| `cuEventRecord` | `muEventRecord` |

## Architecture / Compute Capability

| CUDA | MUSA |
|------|------|
| `sm_50` (Maxwell) | — |
| `sm_60` (Pascal) | — |
| `sm_70` (Volta) | `mp21` (MTT S4000) |
| `sm_75` (Turing) | `mp22` (MTT M1000) |
| `sm_80` (Ampere) | `mp31` (MTT S5000) |
| `sm_90` (Hopper) | — |

```bash
# CUDA
nvcc -arch=sm_80 kernel.cu -o kernel

# MUSA
mcc -arch=mp31 kernel.mu -o kernel
```

## Intrinsic Mapping

| CUDA Intrinsic | MUSA Intrinsic |
|----------------|----------------|
| `__syncthreads()` | `__syncthreads()` |
| `__syncwarp()` | `__syncwarp()` |
| `__shfl_sync` | `__shfl_sync` |
| `__shfl_up_sync` | `__shfl_up_sync` |
| `__shfl_down_sync` | `__shfl_down_sync` |
| `__shfl_xor_sync` | `__shfl_xor_sync` |
| `__ballot_sync` | `__ballot_sync` |
| `__all_sync` | `__all_sync` |
| `__any_sync` | `__any_sync` |
| `__activemask` | `__activemask` |
| `__threadfence` | `__threadfence` |
| `__threadfence_block` | `__threadfence_block` |
| `__threadfence_system` | `__threadfence_system` |
| `atomicAdd` | `atomicAdd` |
| `atomicCAS` | `atomicCAS` |
| `__ldg` (read-only cache) | `__ldg` |
| `__nanosleep` | `__nanosleep` |

Most device-side intrinsics share the same name. The `<<<>>>` syntax is identical.

## Qualifiers

| CUDA | MUSA |
|------|------|
| `__global__` | `__global__` |
| `__device__` | `__device__` |
| `__host__` | `__host__` |
| `__shared__` | `__shared__` |
| `__constant__` | `__constant__` |
| `__managed__` | `__managed__` |
| `__restrict__` | `__restrict__` |
| `__align__(N)` | `__align__(N)` |
| `__launch_bounds__(...)` | `__launch_bounds__(...)` |

## Built-in Variables

| CUDA | MUSA |
|------|------|
| `threadIdx` | `threadIdx` |
| `blockIdx` | `blockIdx` |
| `blockDim` | `blockDim` |
| `gridDim` | `gridDim` |
| `warpSize` | `warpSize` |

## What Doesn't Map Directly

| CUDA Feature | MUSA Status | Workaround |
|--------------|-------------|------------|
| `__nanosleep` | ✅ Available | Direct |
| Cooperative groups | Partial | Use `musa_cooperative_groups.h` if available |
| Dynamic parallelism (kernel-launches-kernel) | Partial | Verify on target arch |
| `cudaMemcpyToSymbolAsync` | ✅ | Direct |
| CUDA Async Memory Pools (`cudaMemPool_t`) | ✅ | Direct |
| Programmatic dependent launch | Limited | Use streams + events |
| `cuStreamWriteValue32` / `cuStreamWaitValue32` | Limited | Check Driver API version |
| Inline PTX (`asm("...")`) | ❌ Different ISA | Rewrite as MUSA intrinsics |
| Tensor Memory Access (TMA, Hopper) | Different on MP31 | See MUSA-specific docs |
| Distributed Shared Memory (DSMEM) | ✅ via clusters | See [[cluster-memory]] |
| Warp specialization (`__pipeline_*`) | ✅ | Use MUSA equivalents |
| `cudaFuncSetAttribute` for shared mem carveout | ✅ | Direct |

## Warp Size Trap

CUDA assumes `warpSize == 32` everywhere. MUSA has **two** warp sizes:

- MP31 (S5000): 32 (matches CUDA)
- MP21/MP22 (M1000/S4000): 128 (does NOT match CUDA)

Code that hardcodes `32` will break on MP21/MP22. Always use the `warpSize` built-in:

```cpp
// ❌ Hardcoded
v += __shfl_down_sync(0xffffffff, v, 16);
// ... assumes 32 lanes

// ✅ Portable
for (int o = warpSize/2; o > 0; o >>= 1)
    v += __shfl_down_sync(0xffffffff, v, o);
```

## Tooling Mapping

| CUDA Tool | MUSA Equivalent |
|-----------|-----------------|
| `nvcc` | `mcc` |
| `nvprof` / `nsys compute` | `mcu` |
| `nsys profile` | `msys profile` |
| `Nsight Compute GUI` | `Moore Perf GUI` |
| `nvcc --ptxas-options=-v` | `mcc --ptxas-options=-v` |
| `cudnn` library | `mudnn` library |
| `nccl` library | `mccl` library |
| `cutlass` library | `mutlass` library |
| `cupti` (profiling API) | `mupti` |
| `nvcc -arch=sm_80` | `mcc -arch=mp31` |
| `cuda-gdb` | `musa-gdb` (if available) |

## Cross-References

- [[musify-tool]] — automated conversion tool
- [[mcc-compiler]] — target compiler
- [[musa-sdk-stack]] — target software stack
- [[mtt-s5000]] — target hardware
- → raw: `what_is_musa_musa_sdk.md`
