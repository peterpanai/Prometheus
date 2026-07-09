---
title: "Driver API"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [api_guides_driver_api_guide.md, api_guides.md]
tags: [musa, driver-api, mudrv, low-level, jit, green-context]
---

# Driver API

The Driver API is the **low-level** MUSA host API: explicit context management, JIT module loading, fine-grained control. Header: `<mu.h>`. Link: `-lmudrv`. All symbols are prefixed `mu*` (not `musa*`).

## When to Use Driver API

| Need | Use Driver |
|------|------------|
| JIT-compile MUSA source at runtime | ✅ `muModuleLoadData` |
| Load PTX/binary modules dynamically | ✅ |
| Green Context (MP partitioning) | ✅ (only API exposing this) |
| Multi-process service integration | ✅ |
| Low-level performance counters | ✅ |
| Anything else | Runtime API is simpler |

For typical applications, **Runtime API is preferred**. Driver API is for tooling, JIT engines, and advanced resource management.

## What It Provides

| Capability | Key APIs |
|------------|----------|
| Device enumeration | `muDeviceGet`, `muDeviceGetAttribute`, `muDeviceGetName` |
| Context | `muCtxCreate`, `muCtxSetCurrent`, `muCtxDestroy`, `muDevicePrimaryCtxRetain` |
| Module loading | `muModuleLoad`, `muModuleLoadData`, `muModuleLoadFatBinary` |
| Function lookup | `muModuleGetFunction` |
| Kernel launch | `muLaunchKernel` |
| Memory | `muMemAlloc`, `muMemFree`, `muMemcpyHtoD`, `muMemcpyDtoH`, `muMemcpyDtoDAsync` |
| Stream/event | `muStreamCreate`, `muEventRecord`, `muStreamWaitEvent` |
| Green Context | `muGreenCtxCreate`, `muStreamCreateWithGreenCtx` |
| Module linking | `muModuleLinkData`, `muModuleLoadDataEx` |

## Lifecycle

```cpp
// 1. Initialize (only once per process)
muInit(0);

// 2. Get device
MUdevice dev;
muDeviceGet(&dev, 0);

// 3. Create context
MUcontext ctx;
muCtxCreate(&ctx, 0, dev);
muCtxSetCurrent(ctx);

// 4. Load module (compiled ahead-of-time or JIT)
MUpmodule mod;
muModuleLoad(&mod, "kernel.afatbin");   // or muModuleLoadData for in-memory

// 5. Get function
MUfunction fn;
muModuleGetFunction(&fn, mod, "myKernel");

// 6. Configure and launch
void* args[] = { &d_data, &n };
muLaunchKernel(fn,
                gridX, gridY, gridZ,
                blockX, blockY, blockZ,
                sharedMem, stream,
                args);

// 7. Synchronize
muStreamSynchronize(stream);

// 8. Cleanup
muModuleUnload(mod);
muCtxDestroy(ctx);
```

## Parameter Passing — The Tedious Part

Driver API passes kernel arguments as a `void**` array, but each argument's **size and offset** must be set explicitly via `muParamSet*`:

```cpp
int n = 1024;
float* d_data; muMemAlloc(&d_data, n * sizeof(float));

// Method 1: void** array (simpler, common)
void* args[] = { &d_data, &n };
muLaunchKernel(fn, gx,gy,gz, bx,by,bz, 0, stream, args);

// Method 2: muParamSet* (more verbose, sometimes required)
size_t offset = 0;
muParamSetv(fn, offset, &d_data, sizeof(d_data));   offset += sizeof(d_data);
muParamSetv(fn, offset, &n, sizeof(n));             offset += sizeof(n);
muParamSetSize(fn, offset);

muLaunchKernel(fn, gx,gy,gz, bx,by,bz, 0, stream, NULL);
```

Method 1 is preferred where supported; Method 2 gives explicit control for unusual types.

## JIT Compilation

```cpp
const char* ptx_src = "/* PTX or MUSA IR string */";
MUmodule mod;
MUjit_option opts[] = { MU_JIT_OPT_MAX_REG_COUNT };
void* opt_vals[] = { (void*)64 };   // limit to 64 regs/thread
muModuleLoadDataEx(&mod, ptx_src, 1, opts, opt_vals);
```

Options include:
- `MU_JIT_OPT_MAX_REG_COUNT` — cap register usage
- `MU_JIT_OPT_THREADS_PER_BLOCK` — hint for compile-time optimization
- `MU_JIT_OPT_INFO_LOG_BUFFER` — capture compilation log
- `MU_JIT_OPT_ERROR_LOG_BUFFER` — capture compilation errors

## Memory Management

```cpp
// Allocate
MUdeviceptr d;
muMemAlloc(&d, 1024 * sizeof(float));

// Host → Device
float h[1024];
muMemcpyHtoD(d, h, 1024 * sizeof(float));

// Device → Device
muMemcpyDtoD(d2, d, 1024 * sizeof(float));

// Async (with stream)
muMemcpyHtoDAsync(d, h, sz, stream);

// Free
muMemFree(d);
```

> **Important**: `MUdeviceptr` is **not** a CPU pointer. Cast it to `float*` for kernel-side use only — never dereference it on the host.

## Mixed Runtime + Driver API

To make Driver API allocations visible to Runtime API kernels, use the **primary context** (not `muCtxCreate`):

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

## Green Context

Driver API is the only way to create Green Contexts:

```cpp
MUdevResource res = {};
res.smCount = 16;
res.partitionType = MU_PARTITION_TYPE_SM;

MUcontext greenCtx;
muGreenCtxCreate(&greenCtx, dev, &res, MU_GREEN_CTX_CREATE_SCHEDULING_FLAG);

// Streams bound to this GC execute only on its MPs
musaStream_t gcStream;
musaStreamCreateWithGreenCtx(&gcStream, greenCtx);
```

See [[green-context]].

## Module Format

Driver API loads MUSA modules in **fatbin** format — a container holding multiple compiled variants (PTX, SASS for different archs). The compiler (`mcc`) produces these:

```bash
mcc -fatbin -arch=mp31 -o kernel.fatbin kernel.cu
```

At runtime, the driver picks the best variant for the current device.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| `MUdeviceptr` treated as CPU pointer | Only cast to `T*` for kernel arg passing |
| Context not set before Driver API call | `muCtxSetCurrent` first |
| Module unload before kernel finishes | `muStreamSynchronize` before unload |
| Mixing `muCtxCreate` with Runtime API | Use `muDevicePrimaryCtxRetain` instead |
| Forgetting `muInit(0)` at startup | Required before any other Driver API call |
| Argument alignment issues | Use `muParamSetv` with explicit offsets |

## When to Stay with Runtime API

If you don't need JIT, Green Contexts, or low-level control — Runtime API is simpler, safer, and equally fast. Driver API's power comes at the cost of verbosity and footguns.

## Cross-References

- [[runtime-api]] — the high-level alternative
- [[primary-context]] — bridging Runtime and Driver APIs
- [[green-context]] — Driver-API-only feature
- [[musadrv-driver]] — the library entity
- → raw: `api_guides_driver_api_guide.md`
