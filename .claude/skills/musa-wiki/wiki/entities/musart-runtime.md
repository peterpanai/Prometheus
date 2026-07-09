---
title: "musart 运行时库"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [api_guides_runtime_api_guide.md, what_is_musa_musa_sdk.md, toolkits_musa_runtime.md]
tags: [musa, musart, runtime, library, host-api]
---

# musart 运行时库 (musart Runtime Library)

`musart` is the MUSA Runtime API library — the high-level host-side API for device management, memory allocation, and kernel launch. Linked via `-lmusart`, header `<musa_runtime.h>`. All symbols prefixed `musa*`.

## What's In It

| Category | Key APIs |
|----------|----------|
| **Device** | `musaGetDeviceCount`, `musaSetDevice`, `musaGetDevice`, `musaGetDeviceProperties`, `musaDeviceGetAttribute`, `musaDeviceSynchronize`, `musaDeviceReset` |
| **Memory** | `musaMalloc`, `musaFree`, `musaMallocHost`, `musaFreeHost`, `musaMallocManaged`, `musaMallocAsync`, `musaFreeAsync` |
| **Copy** | `musaMemcpy`, `musaMemcpyAsync`, `musaMemcpy2D`, `musaMemcpyToSymbol`, `musaMemcpyFromSymbol`, `musaMemcpyPeer` |
| **Stream/Event** | `musaStreamCreate`, `musaStreamDestroy`, `musaStreamSynchronize`, `musaStreamQuery`, `musaEventCreate`, `musaEventRecord`, `musaEventSynchronize`, `musaEventElapsedTime`, `musaStreamWaitEvent` |
| **Error** | `musaGetLastError`, `musaGetErrorString`, `musaGetErrorName` |
| **Occupancy** | `musaOccupancyMaxActiveBlocksPerMultiprocessor`, `musaOccupancyMaxPotentialBlockSize` |
| **Module/Func** | (limited; for runtime module loading use Driver API) |
| **Memory Advise** | `musaMemAdvise`, `musaMemPrefetchAsync`, `musaMemRangeGetAttribute` |
| **Stream Attr** | `musaStreamGetAttribute`, `musaStreamSetAttribute` |
| **Graph** | `musaGraphCreate`, `musaGraphAddKernelNode`, `musaGraphInstantiate`, `musaGraphLaunch` |
| **Groups** | `musaStreamBeginCapture`, `musaStreamEndCapture`, `musaGraphExecUpdate` |

## Linking

```bash
mcc myapp.mu -lmusart -o myapp
```

`mcc` links `musart` automatically when you use MUSA C++ features. For pure C++ host code calling Runtime API:

```bash
g++ myapp.cc -lmusart -o myapp
```

## Initialization

`musart` initializes lazily on first API call. There's no explicit `musaInit` — the first call to `musaGetDeviceCount` (or similar) triggers initialization.

## Thread Safety

- Each host thread has its own "current device" state.
- `musaSetDevice` is thread-local.
- Streams and events can be shared across threads, but **concurrent API calls** to the same stream are not safe — use `musaStreamAddCallback` or external synchronization.

## Error Model

Most Runtime API functions return `musaError_t`:

```cpp
musaError_t err = musaMalloc(&d, 1024);
if (err != musaSuccess) { /* handle */ }
```

Kernel launches (`<<<>>>`) don't return an error code — use `musaGetLastError()` immediately after.

Common errors:

| Error | Meaning |
|-------|---------|
| `musaSuccess` | No error |
| `mudaErrorInvalidValue` | Bad argument |
| `mudaErrorOutOfMemory` | Allocation failed |
| `mudaErrorInvalidDevicePointer` | Pointer not from musart |
| `mudaErrorInvalidConfiguration` | Block/grid too large, etc. |
| `mudaErrorLaunchFailure` | Kernel crashed (often OOB access) |
| `mudaErrorLaunchTimeout` | Watchdog killed kernel (display GPU) |
| `mudaErrorInsufficientDriver` | Runtime version > driver version |

## Device Properties

```cpp
musaDeviceProp prop;
musaGetDeviceProperties(&prop, device);

printf("Name: %s\n", prop.name);
printf("SMs: %d\n", prop.multiProcessorCount);
printf("Max threads/SM: %d\n", prop.maxThreadsPerMultiProcessor);
printf("Shared mem/SM: %zu\n", prop.sharedMemPerMultiprocessor);
printf("Warp size: %d\n", prop.warpSize);
printf("Compute capability: %d.%d\n", prop.major, prop.minor);
```

Query specific attributes without the full struct:

```cpp
int value;
musaDeviceGetAttribute(&value, musaDevAttrMultiprocessorCount, device);
musaDeviceGetAttribute(&value, musaDevAttrMaxThreadsPerMultiProcessor, device);
musaDeviceGetAttribute(&value, musaDevAttrL2CacheSize, device);
musaDeviceGetAttribute(&value, musaDevAttrMaxSharedMemoryPerMultiprocessor, device);
musaDeviceGetAttribute(&value, musaDevAttrGlobalMemoryBusWidth, device);
musaDeviceGetAttribute(&value, musaDevAttrMemoryClockRate, device);
```

## Streams in musart

```cpp
musaStream_t s;
musaStreamCreate(&s);
// or with priority:
musaStreamCreateWithPriority(&s, 0, priority);
// or with flags:
musaStreamCreateWithFlags(&s, musaStreamNonBlocking);

kernel<<<grid, block, 0, s>>>(args);
musaStreamSynchronize(s);
musaStreamDestroy(s);
```

## Memory Allocation Patterns

```cpp
// Standard
musaMalloc(&d, sz);

// Pinned (host)
musaMallocHost(&h, sz);
musaMallocHost(&h, sz, musaHostAllocMapped);          // mapped
musaMallocHost(&h, sz, musaHostAllocWriteCombined);   // write-combined

// Unified memory
musaMallocManaged(&d, sz);

// Stream-ordered async
musaMallocAsync(&d, sz, stream);
musaFreeAsync(d, stream);

// Pools
mudaMemPool_t pool;
mudaDeviceGetDefaultMemPool(&pool, device);
mudaMemPoolSetAttribute(pool, musaMemPoolAttrReleaseThreshold, &(size_t){UINT64_MAX});
```

## Cross-References

- [[runtime-api]] — concept page with usage
- [[driver-api]] — the low-level alternative
- [[musadrv-driver]] — companion library
- [[primary-context]] — what musart uses implicitly
- [[musa-sdk-stack]] — library's place in the stack
- → raw: `api_guides_runtime_api_guide.md`
