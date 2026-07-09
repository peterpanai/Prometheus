---
title: "Primary Context"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [api_guides_driver_api_guide.md, api_guides_runtime_api_guide.md]
tags: [musa, primary-context, context, driver-api, runtime-api]
---

# Primary Context

The **Primary Context** is the per-device context that the Runtime API implicitly uses. Understanding it is essential when **mixing Runtime API and Driver API** code in the same application — without coordination, you can end up with two contexts on the same device, each holding their own state and interfering with each other.

## What is a Context?

A **context** is the MUSA equivalent of a process — it holds:
- Device memory allocations
- Streams and events
- Module loads (Driver API)
- The current device's state (stack size, shared mem config, L2 carve-out)

A device can have **multiple contexts** active simultaneously (multi-process isolation), but each Runtime API call implicitly targets the **primary context** for the current device.

## Primary Context Lifecycle

```cpp
// Runtime API implicitly retains the primary context on first use
musaMalloc(&d, 1024);              // triggers muDevicePrimaryCtxRetain if not yet active

// Driver API can explicitly retain it
MUcontext primCtx;
muDevicePrimaryCtxRetain(&primCtx, device);
// ... use primCtx ...
muDevicePrimaryCtxRelease(device);  // decrement refcount
```

The primary context has a **refcount**. It is created on first retain, destroyed when refcount reaches 0.

## Mixing Runtime and Driver APIs

The common pitfall:

```cpp
// Driver API creates a NEW context (NOT the primary one)
MUcontext myCtx;
muCtxCreate(&myCtx, 0, device);
muCtxSetCurrent(myCtx);

// Driver API allocation
MUdeviceptr d;
muMemAlloc(&d, 1024);

// Now switch to Runtime API
musaSetDevice(device);
float* d_runtime = (float*)d;
kernel<<<grid, block>>>(d_runtime);    // ❌ d is in myCtx, not primary!
                                        // Runtime API can't see it
```

The fix: tell Driver API to use the **primary context** instead of creating a new one:

```cpp
MUcontext primCtx;
muDevicePrimaryCtxRetain(&primCtx, device);
muCtxSetCurrent(primCtx);              // use primary, not a new context

// Now allocations are visible to Runtime API
MUdeviceptr d;
muMemAlloc(&d, 1024);
kernel<<<grid, block>>>((float*)d);    // ✅ works
```

## Primary Context Management APIs

| API | Effect |
|-----|--------|
| `muDevicePrimaryCtxRetain(&ctx, dev)` | Increment refcount, return context |
| `muDevicePrimaryCtxRelease(dev)` | Decrement refcount; destroy at 0 |
| `muDevicePrimaryCtxReset(dev)` | Force-reset (frees all state) |
| `muDevicePrimaryCtxSetFlags(dev, flags)` | Set context flags (e.g. scheduling mode) |
| `muDevicePrimaryCtxGetState(dev, &flags, &active)` | Query current state |

## Flags

| Flag | Meaning |
|------|---------|
| `MU_CTX_SCHED_AUTO` | Runtime decides (spin/yield/block) |
| `MU_CTX_SCHED_SPIN` | Busy-wait (low latency, high CPU) |
| `MU_CTX_SCHED_YIELD` | Yield CPU while waiting |
| `MU_CTX_SCHED_BLOCKING_SYNC` | Block on sync (low CPU, high latency) |
| `MU_CTX_MAP_HOST` | Allow mapped pinned memory |

Set once at context creation; cannot be changed afterward.

## Default Behavior

- **Runtime API** auto-creates and retains the primary context on first device use.
- The primary context is **per-process** per device — not shared across processes.
- When the process exits, all primary contexts are released.
- For multi-threaded code, use `musaSetDevice` per thread to set the active device — primary context is shared.

## Green Contexts vs Primary Context

Green Contexts (see [[green-context]]) are **not** primary contexts — they are explicit partitions of the device. A Green Context has its own streams but the same memory space as the primary context. Streams created without `WithGreenCtx` use the primary context.

## Cross-Process Context Sharing

Multiple processes can share a GPU by each creating their own context. The driver schedules them with time-slicing. For true isolation (no time-slicing), use **Green Contexts** or external partitioning (MIG-like).

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Driver API creates new context, allocations invisible to Runtime | Use `muDevicePrimaryCtxRetain` instead of `muCtxCreate` |
| Forgetting to release primary context | Refcount never reaches 0; memory leaks |
| Calling `muDevicePrimaryCtxReset` while contexts are active | Returns error; release first |
| Mixing contexts across threads | Each thread has its own "current context" stack — set explicitly |

## Cross-References

- [[runtime-api]] — implicit primary context user
- [[driver-api]] — explicit context management
- [[green-context]] — partition alternative to primary
- → raw: `api_guides_driver_api_guide.md`
