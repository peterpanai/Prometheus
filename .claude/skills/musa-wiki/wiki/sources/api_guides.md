---
title: "API 指南 — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources:
  - api_guides.md
  - api_guides_runtime_api_guide.md
  - api_guides_driver_api_guide.md
tags: [musa, runtime-api, driver-api, musart, musadrv, context, stream, event]
---

# API 指南 (API Guides)

MUSA exposes two API layers, mirroring CUDA's split:

1. **Runtime API** (`musa*` prefix, header `<musa_runtime.h>`) — high-level, implicit context, `<<<>>>` launch syntax. Recommended for applications and prototyping.
2. **Driver API** (`mu*` prefix, header `<mu.h>`) — low-level, explicit context/module/function handles, parameter-by-parameter kernel launch. Recommended for frameworks, libraries, multi-GPU/multi-process work.

Both share the same underlying device, memory, stream, and event concepts — they differ in how much the API manages for you.

## Source Pages

| Raw File | Title | Covers |
|----------|-------|--------|
| `api_guides.md` | APIs | Chapter index |
| `api_guides_runtime_api_guide.md` | MUSA Runtime API 开发者指南 | Device mgmt, memory mgmt, kernel launch, streams, events, error handling, lifecycle |
| `api_guides_driver_api_guide.md` | MUSA Driver API 开发者指南 | Init, context, module, function, memory, streams, events, multi-GPU, error handling |

## Runtime vs Driver — When to Pick Which

| Aspect | Runtime API | Driver API |
|--------|-------------|------------|
| Init | Automatic (first call) | Manual `muInit(0)` |
| Context | Implicit primary context | Explicit `muCtxCreate()` |
| Module loading | Auto from PTX/binary | Manual `muModuleLoad()` |
| Kernel launch | `kernel<<<grid, block>>>(args)` | `muLaunchKernel(fn, grid, block, ...)` with `muParamSet*` |
| Complexity | Low | High |
| Flexibility | Limited | Full control |
| Use case | Apps, prototypes | Frameworks, libraries, multi-tenant, JIT-loaded PTX |

You can mix them via the **primary context** bridge: the Runtime's implicit per-device context is the same context the Driver exposes via `muDevicePrimaryCtxGetState` / `muDevicePrimaryCtxRelease`.

## Runtime API

### Key Concepts

- **Device (`musaDevice`)**: single MTT GPU, indexed 0..N-1.
- **Primary context**: one per device, auto-created by Runtime.
- **Stream (`musaStream_t`)**: execution queue. Same-stream ops are ordered; cross-stream ops may overlap. Legacy stream = `0`/`NULL`; per-thread stream = `(musaStream_t)-1`.
- **Event (`musaEvent_t`)**: marker recorded into a stream — for cross-stream sync and GPU timing.
- **Memory kinds**: device (`musaMalloc`), host pinned (`musaMallocHost`), write-combined (`musaHostAlloc` flag), managed/unified (`musaMallocManaged`), array (`musaMallocArray`), pitched 2D/3D (`musaMallocPitch`, `musaMalloc3D`).
- **Memcpy kinds**: `musaMemcpyHostToDevice`, `musaMemcpyDeviceToHost`, `musaMemcpyDeviceToDevice`, `musaMemcpyHostToHost`; async `musaMemcpyAsync`; P2P `musaMemcpyPeer` / `musaMemcpyPeerAsync`.

### Key APIs by Category

| Category | Functions |
|----------|-----------|
| Device mgmt | `musaGetDeviceCount`, `musaGetDeviceProperties`, `musaSetDevice`, `musaGetDevice`, `musaDeviceReset`, `musaDeviceSynchronize`, `musaDeviceCanAccessPeer`, `musaDeviceGetPCIBusId`, `musaDeviceGetUuid`, `musaDeviceGetStreamPriorityRange` |
| Memory (device) | `musaMalloc`, `musaMallocPitch`, `musaMalloc3D`, `musaMallocArray`, `musaFree`, `musaMemset`, `musaMemset2D` |
| Memory (host/managed) | `musaMallocHost`, `musaHostAlloc`, `musaHostRegister`, `musaMallocManaged`, `musaMemPrefetchAsync`, `musaMemAdvise`, `musaFreeHost` |
| Memory copy | `musaMemcpy`, `musaMemcpyAsync`, `musaMemcpy2D`, `musaMemcpy3D`, `musaMemcpyPeer`, `musaMemcpyPeerAsync` |
| Pointer query | `musaPointerGetAttribute`, `musaPointerGetMemoryType`, `musaPointerGetDevice` |
| Streams | `musaStreamCreate`, `musaStreamCreateWithPriority(flags, prio)`, `musaStreamDestroy`, `musaStreamSynchronize`, `musaStreamQuery`, `musaStreamAddCallback` |
| Events | `musaEventCreate`, `musaEventCreateWithFlags` (flags: `musaEventDisableTiming`, `musaEventBlockingSync`, `musaEventInterprocess`), `musaEventRecord`, `musaEventRecordWithFlags`, `musaEventSynchronize`, `musaEventQuery`, `musaEventElapsedTime`, `musaEventDestroy`, `musaIpcGetEventHandle`, `musaIpcOpenEventHandle` |
| Kernel launch | `kernel<<<grid, block, shmem, stream>>>(args)`; up to 3D `dim3`; dynamic shared mem via `extern __shared__` |
| Error handling | `musaGetLastError` (consumes!), `musaGetErrorString`, `musaGetErrorName` |

### Lifecycle Pattern

```cpp
#include <musa_runtime.h>

__global__ void vectorAdd(const float* a, const float* b, float* c, int n) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

int main() {
    int n = 1 << 20;
    size_t bytes = n * sizeof(float);
    float *h_a = (float*)malloc(bytes), *h_b = (float*)malloc(bytes), *h_c = (float*)malloc(bytes);
    /* init h_a, h_b ... */
    float *d_a, *d_b, *d_c;
    musaMalloc(&d_a, bytes); musaMalloc(&d_b, bytes); musaMalloc(&d_c, bytes);
    musaStream_t stream; musaStreamCreate(&stream);
    musaMemcpyAsync(d_a, h_a, bytes, musaMemcpyHostToDevice, stream);
    musaMemcpyAsync(d_b, h_b, bytes, musaMemcpyHostToDevice, stream);
    int block = 256, grid = (n + block - 1) / block;
    vectorAdd<<<grid, block, 0, stream>>>(d_a, d_b, d_c, n);
    if (musaGetLastError() != musaSuccess) return -1;  // check launch IMMEDIATELY
    musaMemcpyAsync(h_c, d_c, bytes, musaMemcpyDeviceToHost, stream);
    musaStreamSynchronize(stream);
    musaStreamDestroy(stream);
    musaFree(d_a); musaFree(d_b); musaFree(d_c);
    free(h_a); free(h_b); free(h_c);
    return 0;
}
```

### Critical Pitfalls

- **`musaGetLastError` is destructive** — it resets the error flag. Call it exactly once after the suspect operation.
- **Kernel launch via `<<<>>>` does not return a value.** Invalid launches are reported only on the next Runtime call (typically `musaGetLastError`). Always check immediately after launch.
- **Stream priority**: lower integer = higher priority. Query valid range with `musaDeviceGetStreamPriorityRange`.
- **Pitched allocations** (`musaMallocPitch`) choose their own alignment — do not assume `widthInBytes` equals the returned pitch.
- **Unified-memory prefetch** is async and stream-bound; attach kind is `musaMemAttachGlobal` vs `musaMemAttachSingle`.

## Driver API

### Key Concepts

- **`MUdevice`**: opaque integer handle to a GPU (from `muDeviceGet(&dev, index)`).
- **`MUcontext`**: isolated execution scope bound to one device. Created by `muCtxCreate`, made current with `muCtxSetCurrent`. Only one context current per thread.
- **Primary context**: the Runtime's implicit per-device context, visible to Driver via `muDevicePrimaryCtxGetState` / `muDevicePrimaryCtxRelease`.
- **`MUmodule`**: loaded code image (PTX, fatbinary, or in-memory blob).
- **`MUfunction`**: kernel handle pulled from a module via `muModuleGetFunction(&fn, mod, "name")`.
- **`MUdeviceptr`**: opaque device-memory handle (pointer-sized integer, NOT a real CPU pointer — do not dereference).
- **`MUstream` / `MUevent`**: lower-level handle types, same role as Runtime equivalents.

### Key APIs by Category

| Category | Functions |
|----------|-----------|
| Init & context | `muInit(flags)`, `muDeviceGet`, `muCtxCreate(&ctx, flags, dev)`, `muCtxSetCurrent`, `muCtxGetCurrent`, `muCtxGetDevice`, `muCtxDestroy`, `muDevicePrimaryCtxGetState`, `muDevicePrimaryCtxRelease` |
| Module / kernel | `muModuleLoad(&mod, "kernel.ptx")`, `muModuleLoadData(&mod, bytes)`, `muModuleUnload`, `muModuleGetFunction(&fn, mod, "name")`, `muFuncGetParamSize`, `muParamSeti`, `muParamSetd`, `muParamSetSize`, `muLaunchKernel(fn, gx,gy,gz, bx,by,bz, shmem, stream)`, `muLaunchKernelByPtr` |
| Device mgmt | `muGetDeviceCount`, `muDeviceGet`, `muDeviceGetAttribute(&val, MU_DEVICE_ATTRIBUTE_*, dev)`, `muDeviceGetName`, `muDeviceGetUuid`. Attributes: `MAX_THREADS_PER_BLOCK`, `MAX_SHARED_MEMORY_PER_BLOCK`, `MULTIPROCESSOR_COUNT`, `COMPUTE_CAPABILITY_MAJOR/MINOR` |
| Memory (device) | `muMemAlloc(&dptr, sz)`, `muMemAllocPitch(&dptr, &pitch, w, h, 4)`, `muMemFree` |
| Memory (host) | `muMemAllocHost`, `muMemHostAlloc` (flags: `MU_MEMHOSTALLOC_WRITECOMBINED`), `muMemHostRegister` (flags: `MU_MEMHOSTREGISTER_DEVICEMAP`), `muMemHostGetDevicePointer`, `muMemFreeHost`, `muMemHostUnregister` |
| Memory (managed) | `muMemAllocManaged(..., MU_MEM_ATTACH_GLOBAL)`, `muMemAdvise(..., MU_MEM_ADVISE_SET_PREFERRED_LOCATION, dev)`, `muMemPrefetchAsync(..., dev, stream)` |
| Memory copy | `muMemcpyHtoD`, `muMemcpyDtoH`, `muMemcpyDtoD`, `muMemcpy2D`, `muMemcpyAsync` |
| Streams | `muStreamCreate`, `muStreamCreateWithPriority(flags, prio)` (flags: `MU_STREAM_NON_BLOCKING`), `muStreamDestroy`, `muStreamSynchronize`, `muStreamQuery` |
| Events | `muEventCreate`, `muEventCreateWithFlags(..., MU_EVENT_DISABLE_TIMING)`, `muEventRecord`, `muEventSynchronize`, `muEventQuery`, `muEventElapsedTime`, `muEventDestroy` |
| Error handling | `muGetLastError`, `muGetErrorString(&str, err)`, `muGetErrorName(&name, err)` |

### Lifecycle Pattern (Multi-GPU)

```cpp
#include <mu.h>

#define NUM_DEVICES 2

int main() {
    MUdevice  devs[NUM_DEVICES];
    MUcontext ctxs[NUM_DEVICES];
    MUstream  stream;
    MUmodule  module;
    MUfunction kernel;

    muInit(0);                              // explicit init

    int n = 0; muGetDeviceCount(&n);
    for (int i = 0; i < NUM_DEVICES && i < n; i++) {
        muDeviceGet(&devs[i], i);
        muCtxCreate(&ctxs[i], 0, devs[i]);  // one context per device
    }

    muCtxSetCurrent(ctxs[0]);
    muModuleLoad(&module, "kernel.ptx");
    muModuleGetFunction(&kernel, module, "vectorAdd");

    MUdeviceptr d_a, d_b, d_c;
    muMemAlloc(&d_a, 1024 * sizeof(float));
    muMemAlloc(&d_b, 1024 * sizeof(float));
    muMemAlloc(&d_c, 1024 * sizeof(float));

    muStreamCreate(&stream);
    int paramSize; muFuncGetParamSize(kernel, &paramSize);
    // muParamSet* pushed against offsets, then:
    muLaunchKernel(kernel, 4, 1, 1, 256, 1, 1, 0, stream);
    muStreamSynchronize(stream);

    muMemFree(d_a); muMemFree(d_b); muMemFree(d_c);
    muModuleUnload(module);
    muStreamDestroy(stream);
    for (int i = 0; i < NUM_DEVICES && i < n; i++) muCtxDestroy(ctxs[i]);
    return 0;
}
```

### Critical Pitfalls

- **`muInit` is required** (though often implicit). Call it explicitly for clarity.
- **Only one context current per thread.** Switch with `muCtxSetCurrent` before device operations.
- **`MUdeviceptr` is not a CPU pointer** — never dereference it. Convert host buffers with `muMemHostGetDevicePointer` after registering them.
- **Parameter passing**: `muParamSeti` / `muParamSetd` accumulate against offsets; commit total size with `muParamSetSize`. Or use `muLaunchKernelByPtr` for a simpler grid/block/shmem/stream-only path.
- **`muMemAllocPitch`'s last argument** is the requested alignment in bytes.
- **`muGetLastError` consumes the error**, just like the Runtime.

## Error Codes (shared)

| Code | Name | Meaning |
|------|------|---------|
| 0 | `musaSuccess` / `muSuccess` | OK |
| 1 | `musaErrorInvalidValue` | Invalid parameter |
| 2 | `musaErrorMemoryAllocation` / `musaErrorOutOfMemory` | OOM |
| 3 | `musaErrorInitializationError` / `musaErrorNotInitialized` | Init failed |
| 100 | `musaErrorInvalidDevice` | Bad device index |
| 101 | `musaErrorInvalidContext` | (Driver) Bad context |
| 300 | `musaErrorInvalidKernel` | Kernel load/launch issue |
| 400 | `musaErrorLaunchFailure` | Kernel crashed |
| 408 | `musaErrorLaunchTimeout` | Kernel hit TDR |

## Cross-References

- **Concept pages**: [[runtime-api]], [[driver-api]], [[stream-and-event-model]], [[primary-context]], [[kernel-launch-syntax]]
- **Source chapters**: [[musa-cpp-syntax]] (the language layer above these APIs), [[programming-model]] (the abstractions these APIs expose)
- **Entity pages**: [[musart-runtime]], [[musadrv-driver]], [[mcc-compiler]] (produces the PTX/modules Driver loads)
- **Advanced**: [[green-context]] (Driver-only feature), [[musa-graphs]] (uses streams as capture/launch substrate)
