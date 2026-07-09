---
title: "Kernel 启动语法"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_gpu_parallel_basics.md, musa_cpp_syntax_intro_to_musa_cpp.md, programming_model_host_device_model.md]
tags: [musa, kernel-launch, execution-configuration, dim3]
---

# Kernel 启动语法 (Kernel Launch Syntax)

MUSA extends C++ with the `<<<>>>` triple-chevron syntax for launching kernels from host code. This is the bridge between the programming model (Grid/Block/Thread) and the runtime.

## Syntax

```cpp
kernel<<<gridDim, blockDim, sharedMem, stream>>>(args);
```

| Parameter | Type | Required | Meaning |
|-----------|------|----------|---------|
| `gridDim` | `dim3` or int | Yes | Grid dimensions (number of blocks) |
| `blockDim` | `dim3` or int | Yes | Block dimensions (threads per block) |
| `sharedMem` | `size_t` | No | Dynamic shared memory size in bytes (default 0) |
| `stream` | `musaStream_t` | No | Execution stream (default stream if omitted) |

## 1D, 2D, 3D Configurations

```cpp
// 1D — most common
int blockSize = 256;
int gridSize = (n + blockSize - 1) / blockSize;
kernel<<<gridSize, blockSize>>>(d_data, n);

// 2D — image processing
dim3 blockSize(16, 16);                            // 256 threads
dim3 gridSize((width + 15) / 16, (height + 15) / 16);
imageKernel<<<gridSize, blockSize>>>(d_img, width, height);

// 3D — volume data
dim3 blockSize(8, 8, 8);                           // 512 threads
dim3 gridSize((w+7)/8, (h+7)/8, (d+7)/8);
volKernel<<<gridSize, blockSize>>>(d_vol, w, h, d);

// With stream + dynamic shared memory
kernel<<<gridSize, blockSize, 256*sizeof(float), stream>>>(d_data, n);
```

## Kernel Declaration

```cpp
__global__ void myKernel(float* data, int n) {    // __global__ = host-callable, device-runs
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) data[idx] *= 2.0f;
}
```

- Return type must be `void`.
- `__global__` functions are called from host (or from device via dynamic parallelism).
- Arguments are passed by value; pointers must point to device memory.

## Static vs Dynamic Shared Memory

```cpp
// Static — size known at compile time
__global__ void k1() {
    __shared__ float buf[256];                     // fixed 1024 bytes
    /* ... */
}
k1<<<grid, block>>>(args);                         // no sharedMem arg

// Dynamic — size passed at launch
__global__ void k2() {
    extern __shared__ float buf[];                 // size from launch config
    /* ... */
}
k2<<<grid, block, N * sizeof(float)>>>(args);      // sharedMem arg sets size
```

## Driver API Equivalent

The Driver API uses `muLaunchKernel` instead of `<<<>>>`:

```cpp
muModuleGetFunction(&kernel, module, "myKernel");
muParamSeti(kernel, offset, ...);                  // push params byte-by-byte
muParamSetSize(kernel, totalParamSize);
muLaunchKernel(kernel, gx,gy,gz, bx,by,bz, shmem, stream);
```

See [[driver-api]].

## Error Checking

`<<<>>>` launches are **asynchronous** — the launch returns immediately and errors are reported on the next Runtime call:

```cpp
kernel<<<grid, block>>>(d_data);
musaError_t err = musaGetLastError();              // check launch error IMMEDIATELY
if (err != musaSuccess) { /* handle */ }

musaDeviceSynchronize();                           // wait for kernel to finish
err = musaGetLastError();                          // check runtime error after sync
```

`musaGetLastError()` is **destructive** — it clears the error. Call it once.

## Cross-References

- [[thread-hierarchy]] — what grid/block mean
- [[runtime-api]] — the runtime that implements `<<<>>>`
- [[stream-and-event-model]] — the optional stream parameter
- [[synchronization-primitives]] — `__syncthreads()` inside kernels
- → raw: `musa_cpp_syntax_intro_to_musa_cpp.md`
