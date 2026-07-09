---
title: "Runtime API"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [api_guides_runtime_api_guide.md, api_guides.md]
tags: [musa, runtime-api, musart, host-api, high-level]
---

# Runtime API

The Runtime API is the **high-level** MUSA host API: it manages device memory, launches kernels, and handles synchronization with minimal boilerplate. Header: `<musa_runtime.h>`. Link: `-lmusart`. All symbols are prefixed `musa*`.

## What It Provides

| Capability | Key APIs |
|------------|----------|
| Device management | `musaGetDeviceCount`, `musaSetDevice`, `musaGetDeviceProperties` |
| Memory allocation | `musaMalloc`, `mudaFree`, `musaMallocHost`, `mudaMemcpy` |
| Memory copy | `musaMemcpy`, `musaMemcpyAsync` |
| Stream/event | `musaStreamCreate`, `musaEventRecord`, `musaStreamWaitEvent` |
| Kernel launch | `<<<grid, block, shmem, stream>>>` |
| Error handling | `musaGetLastError`, `musaDeviceSynchronize` |
| Synchronization | `musaDeviceSynchronize`, `musaStreamSynchronize`, `musaEventSynchronize` |
| Occupancy | `musaOccupancyMaxActiveBlocksPerMultiprocessor` |
| Symbols | `musaMemcpyToSymbol`, `musaGetSymbolAddress` |

## Hello, MUSA

```cpp
#include <musa_runtime.h>
#include <stdio.h>

__global__ void hello() {
    printf("Hello from thread %d\n", threadIdx.x);
}

int main() {
    hello<<<1, 4>>>();
    musaDeviceSynchronize();
    return 0;
}
```

Compile: `mcc hello.mu -lmusart -o hello`.

## Memory Lifecycle

```cpp
// Allocate
float* d_data;
musaMalloc(&d_data, N * sizeof(float));

// Initialize on host, copy to device
float h_data[N];
for (int i = 0; i < N; i++) h_data[i] = i;
musaMemcpy(d_data, h_data, N * sizeof(float), musaMemcpyHostToDevice);

// Launch kernel
scaleKernel<<<grid, block>>>(d_data, 2.0f, N);

// Copy back
musaMemcpy(h_data, d_data, N * sizeof(float), musaMemcpyDeviceToHost);

// Free
musaFree(d_data);
```

## Error Handling

`musaGetLastError()` is **destructive** — it returns the error and clears it. Always check immediately after a launch:

```cpp
kernel<<<grid, block>>>(args);
musaError_t err = musaGetLastError();      // launch-time errors (e.g. invalid config)
if (err != musaSuccess) {
    fprintf(stderr, "Launch error: %s\n", musaGetErrorString(err));
}

musaDeviceSynchronize();                    // wait for kernel
err = musaGetLastError();                   // runtime errors (e.g. OOB access)
if (err != musaSuccess) {
    fprintf(stderr, "Runtime error: %s\n", musaGetErrorString(err));
}
```

Wrap in a macro for sanity:

```cpp
#define MUSA_CHECK(call) do {                                  \
    auto err = (call);                                          \
    if (err != musaSuccess) {                                   \
        fprintf(stderr, "MUSA error %s:%d: %s\n",              \
                __FILE__, __LINE__, musaGetErrorString(err));  \
        exit(1);                                                \
    }                                                            \
} while (0)

MUSA_CHECK(musaMalloc(&d, 1024));
```

For kernel launches, `MUSA_CHECK(musaGetLastError())` after `<<<>>>`.

## Synchronous vs Asynchronous

| API | Sync? | Notes |
|-----|-------|-------|
| `musaMalloc`, `mudaFree` | Sync | Forces sync on current device |
| `musaMemcpy` (without Async) | Sync | Blocks host until done |
| `musaMemcpyAsync` | Async | Returns immediately; needs stream sync |
| `kernel<<<...>>>` | Async | Returns immediately; queues on stream |
| `musaDeviceSynchronize` | Sync | Waits for all device work |
| `musaStreamSynchronize` | Sync | Waits for one stream |

> **Trap**: `musaMalloc` is synchronous. Doing allocations in a hot loop kills performance. Pre-allocate buffers and reuse them.

## Multi-Device

```cpp
int deviceCount;
musaGetDeviceCount(&deviceCount);

for (int d = 0; d < deviceCount; d++) {
    musaSetDevice(d);
    kernel<<<grid, block>>>(d_data_on_device_d);
}

// P2P copy
musaMemcpyPeer(d_data_d1, d1, d_data_d0, d0, sz);
```

Each device has its own primary context (see [[primary-context]]).

## Unified Memory

```cpp
float* d_data;
musaMallocManaged(&d_data, N * sizeof(float));
// Both host and device can access via the same pointer
for (int i = 0; i < N; i++) d_data[i] = i;   // host write
kernel<<<grid, block>>>(d_data);              // device read
musaDeviceSynchronize();
printf("%f\n", d_data[0]);                     // host read back
```

Convenient but slower than explicit copies — use for prototyping or sparse access patterns.

## Limitations vs Driver API

| Capability | Runtime API | Driver API |
|------------|-------------|------------|
| Kernel launch | `<<<>>>` syntax | `muLaunchKernel` |
| Module loading | Compile-time only | Runtime JIT via `muModuleLoad` |
| Context control | Implicit primary | Explicit |
| Green Context | ❌ | ✅ |
| Stream callback | ✅ | ✅ |
| Low-level perf counters | ❌ | ✅ |

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Forgetting `musaDeviceSynchronize` before reading results | Async kernel hasn't finished |
| Calling `musaGetLastError` twice | Second call returns `musaSuccess` (error cleared) |
| Passing host pointer to kernel | Use `musaMalloc`'d pointer |
| Index `int` overflow for large N | Use `size_t` or `long long` |
| Not setting device in multi-threaded code | `musaSetDevice` is per-thread |

## Cross-References

- [[driver-api]] — the lower-level alternative
- [[primary-context]] — what Runtime API implicitly uses
- [[kernel-launch-syntax]] — the `<<<>>>` syntax
- [[stream-and-event-model]] — async coordination
- [[musart-runtime]] — the library entity
- → raw: `api_guides_runtime_api_guide.md`
