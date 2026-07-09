---
title: "mudrv 驱动库"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [api_guides_driver_api_guide.md, what_is_musa_musa_sdk.md]
tags: [musa, mudrv, driver, library, jit, green-context]
---

# mudrv 驱动库 (mudrv Driver Library)

`mudrv` is the MUSA Driver API library — the low-level host-side API for explicit context management, JIT compilation, and advanced features like Green Contexts. Linked via `-lmudrv`, header `<mu.h>`. All symbols prefixed `mu*` (not `musa*`).

## What's In It

| Category | Key APIs |
|----------|----------|
| **Init** | `muInit` (call once per process) |
| **Device** | `muDeviceGet`, `muDeviceGetAttribute`, `muDeviceGetName`, `muDeviceGetCount` |
| **Context** | `muCtxCreate`, `muCtxDestroy`, `muCtxSetCurrent`, `muCtxGetCurrent`, `muCtxPushCurrent`, `muCtxPopCurrent`, `muDevicePrimaryCtxRetain`, `muDevicePrimaryCtxRelease`, `muDevicePrimaryCtxReset` |
| **Module** | `muModuleLoad`, `muModuleLoadData`, `muModuleLoadDataEx`, `muModuleLoadFatBinary`, `muModuleUnload`, `muModuleGetFunction`, `muModuleGetGlobal` |
| **JIT** | Options via `MUjit_option`: `MU_JIT_OPT_MAX_REG_COUNT`, `MU_JIT_OPT_THREADS_PER_BLOCK`, etc. |
| **Memory** | `muMemAlloc`, `muMemFree`, `muMemAllocHost`, `muMemFreeHost`, `muMemAllocManaged`, `muMemcpyHtoD`, `muMemcpyDtoH`, `muMemcpyDtoD`, `muMemcpyHtoDAsync`, `muMemcpyDtoHAsync`, `muMemcpyPeer`, `muMemsetD8`, `muMemsetD32` |
| **Stream/Event** | `muStreamCreate`, `muStreamDestroy`, `muStreamSynchronize`, `muStreamWaitEvent`, `muEventCreate`, `muEventRecord`, `muEventSynchronize`, `muEventQuery` |
| **Launch** | `muLaunchKernel`, `muLaunchKernelEx`, `muLaunchHostFunc` |
| **Green Context** | `muGreenCtxCreate`, `muGreenCtxDestroy`, `muStreamCreateWithGreenCtx`, `muEventCreateWithGreenCtx` |
| **Profiling** | `muProfilerStart`, `muProfilerStop`, MUcontext event counters |

## Linking

```bash
mcc myapp.mu -lmudrv -o myapp           # via mcc (also pulls musart)
g++ myapp.cc -lmudrv -o myapp           # direct g++
```

For applications using **only** Driver API (no `<<<>>>` syntax), `-lmudrv` alone suffices. Most code mixes both.

## Initialization

```cpp
// MUST be called before any other Driver API
muInit(0);
```

`muInit` is process-wide and idempotent — calling it multiple times is safe.

## Context Stack

Driver API maintains a **stack** of contexts per host thread:

```cpp
muCtxPushCurrent(ctxA);     // push A
work();                      // uses A
muCtxPopCurrent(&ctxOld);   // pop A → ctxOld == A
```

Or set current explicitly:

```cpp
muCtxSetCurrent(ctxB);      // set current to B (replaces top of stack)
```

`muCtxGetCurrent` returns the current context without modifying the stack.

## Module Loading

### From File

```cpp
MUmodule mod;
muModuleLoad(&mod, "kernel.fatbin");
MUfunction fn;
muModuleGetFunction(&fn, mod, "myKernel");
```

### From In-Memory Data (JIT)

```cpp
const void* ptx_data = /* PTX or fatbin bytes */;
MUmodule mod;
muModuleLoadData(&mod, ptx_data);

// With JIT options:
MUjit_option opts[] = { MU_JIT_OPT_MAX_REG_COUNT, MU_JIT_OPT_LOG_LEVEL };
void* vals[] = { (void*)64, (void*)3 };
muModuleLoadDataEx(&mod, ptx_data, 2, opts, vals);
```

### From Linked Objects

```cpp
// Link multiple pre-compiled objects at runtime
MUlinkState linkState;
muModuleLinkData(&linkState, MU_LINK_LOG_LEVEL, 3);
muModuleLinkAddData(linkState, MU_INPUT_OBJECT, obj1, ...);
muModuleLinkAddData(linkState, MU_INPUT_OBJECT, obj2, ...);
MUmodule mod;
muModuleLinkComplete(linkState, &mod, nullptr, 0);
```

## Kernel Launch

```cpp
void* args[] = { &d_data, &n };
muLaunchKernel(fn,
                gx, gy, gz,        // grid
                bx, by, bz,        // block
                sharedMem,         // bytes
                stream,            // MUstream
                args);             // void**
```

Or with extended config:

```cpp
MUlaunchConfig cfg = {};
cfg.gridDimX = gx; cfg.gridDimY = gy; cfg.gridDimZ = gz;
cfg.blockDimX = bx; cfg.blockDimY = by; cfg.blockDimZ = bz;
cfg.sharedMemBytes = 0;
cfg.stream = stream;
muLaunchKernelEx(cfg, fn, args);
```

## Green Context

```cpp
MUdevResource res = {};
res.smCount = 16;
res.partitionType = MU_PARTITION_TYPE_SM;

MUcontext greenCtx;
muGreenCtxCreate(&greenCtx, dev, &res, MU_GREEN_CTX_CREATE_SCHEDULING_FLAG);

musaStream_t gcStream;
musaStreamCreateWithGreenCtx(&gcStream, greenCtx);
```

See [[green-context]].

## Memory Management

```cpp
MUdeviceptr d;
muMemAlloc(&d, N * sizeof(float));

float h[N];
muMemcpyHtoD(d, h, N * sizeof(float));

// ...
muMemFree(d);
```

> `MUdeviceptr` is **not** a CPU pointer. Cast to `float*` only for kernel argument passing.

## Interop with Runtime API

To make Driver API allocations visible to Runtime API kernels, use the **primary context**:

```cpp
MUcontext primCtx;
muDevicePrimaryCtxRetain(&primCtx, dev);
muCtxSetCurrent(primCtx);

MUdeviceptr d;
muMemAlloc(&d, 1024);

// Now Runtime API can use this memory
kernel<<<grid, block>>>((float*)d);
```

See [[primary-context]].

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgetting `muInit(0)` | All Driver API calls fail |
| Using `muCtxCreate` then mixing with Runtime | Use `muDevicePrimaryCtxRetain` instead |
| Module unload before kernels finish | `muStreamSynchronize` first |
| Wrong argument size in `muParamSetv` | Use `sizeof` on the actual variable |
| Treating `MUdeviceptr` as host pointer | Only cast for kernel arg passing |
| Driver version < Runtime version | Update driver |

## Cross-References

- [[driver-api]] — concept page with usage
- [[runtime-api]] — the high-level alternative
- [[musart-runtime]] — companion library
- [[primary-context]] — bridging musart/mudrv
- [[green-context]] — mudrv-exclusive feature
- [[musa-sdk-stack]] — library's place in the stack
- → raw: `api_guides_driver_api_guide.md`
