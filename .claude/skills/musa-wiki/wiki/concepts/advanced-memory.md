---
title: "高级内存"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [programming_model_advanced_memory.md, programming_model_memory_hierarchy.md]
tags: [musa, advanced-memory, unified-memory, pinned, mapped, managed-memory]
---

# 高级内存 (Advanced Memory)

Beyond the basic global/shared/register hierarchy, MUSA exposes several advanced memory features for specific use cases: pinned memory, mapped memory, unified memory, and cluster distributed memory.

## Pinned Memory

Pinned (page-locked) host memory cannot be swapped out by the OS. This enables:
- **Async H2D/D2H copies** via DMA (no CPU involvement).
- **Overlap** of copy and compute.

```cpp
float* h_pinned;
musaMallocHost(&h_pinned, N * sizeof(float));     // allocate pinned

musaStream_t s; musaStreamCreate(&s);
musaMemcpyAsync(d, h_pinned, sz, musaMemcpyHostToDevice, s);
kernel<<<grid, block, 0, s>>>(d);
musaMemcpyAsync(h_pinned, d, sz, musaMemcpyDeviceToHost, s);
musaStreamSynchronize(s);

musaFreeHost(h_pinned);                            // free pinned
```

### Cost of Pinned Memory

| Aspect | Cost |
|--------|------|
| Allocation | Slower than `malloc` (OS call to lock pages) |
| Physical RAM | Reduces OS page pool — don't pin gigabytes |
| Portability | Cannot be used by other processes via fork() |

> **Best practice**: allocate pinned buffers once at startup, reuse them for the lifetime of the program.

## Mapped Pinned Memory (Zero-Copy)

```cpp
float* h_mapped;
musaMallocHost(&h_mapped, N * sizeof(float), musaHostAllocMapped);

float* d_mapped;
musaHostGetDevicePointer(&d_mapped, h_mapped, 0);

// GPU accesses host memory directly via d_mapped — no explicit copy
kernel<<<grid, block>>>(d_mapped);
musaDeviceSynchronize();
// h_mapped now reflects GPU writes
```

### When Zero-Copy Helps

| Use case | Helps? |
|----------|--------|
| Sparse / infrequent small accesses | ✅ — avoids full H2D copy |
| Read-only data with `musaMemAdvise` hints | ✅ |
| Frequent updates by host, then small GPU reads | ✅ |
| Large dataset that doesn't fit in VRAM | ✅ |
| Large dataset that GPU reads many times | ❌ — pay PCIe latency every access |

## Write-Combined Memory

```cpp
musaMallocHost(&h_wc, sz, musaHostAllocWriteCombined);
```

Optimized for **write bandwidth** (CPU→GPU). Reads from CPU are very slow (uncached) — only use when host writes, device reads.

## Unified Memory (Managed)

```cpp
float* d;
musaMallocManaged(&d, N * sizeof(float));

// Initialize on host
for (int i = 0; i < N; i++) d[i] = i;

// Use on device — driver migrates pages on demand
kernel<<<grid, block>>>(d);
musaDeviceSynchronize();

// Use on host again — driver migrates back
printf("%f\n", d[0]);
```

### Benefits

- Single pointer — no explicit H2D/D2H copies.
- Lazy migration — only touched pages move.
- Simplifies code for prototyping.

### Pitfalls

| Pitfall | Consequence |
|---------|-------------|
| Thrashing under alternating host/device access | Page-fault overhead dominates |
| No control over placement | May end up in system RAM instead of VRAM |
| Concurrent host+device access (without prefetch) | Undefined behavior |

### Performance Hints

```cpp
// Prefetch to device before kernel launch
musaMemPrefetchAsync(d, N * sizeof(float), device, stream);

// Advise on usage pattern
musaMemAdvise(d, N * sizeof(float), musaMemAdviseSetPreferredLocation, device);
musaMemAdvise(d, N * sizeof(float), musaMemAdviseSetReadMostly, device);
```

| Advice | Effect |
|--------|--------|
| `SetPreferredLocation` | Pages prefer to live on specified device |
| `SetReadMostly` | Read-only — driver replicates to avoid migration |
| `SetAccessedBy` | Listed devices can read without migration |

## Memory Advise (For Unified Memory)

```cpp
// Hint that this buffer will be read by GPU 1
musaMemAdvise(d, sz, musaMemAdviseSetAccessedBy, 1);
```

The driver uses these hints to optimize page placement — they are not enforced.

## Asynchronous Memory Prefetch

```cpp
musaMemPrefetchAsync(d, sz, device, stream);
// Pages start migrating in background; don't read until stream syncs
musaStreamSynchronize(stream);
// Now d is resident on device — kernel will hit no faults
```

## Stream-Ordered Memory Allocation

Allocate memory **asynchronously**, ordered with stream work:

```cpp
float* d = (float*)musaMallocAsync(sz, stream);
kernel<<<grid, block, 0, stream>>>(d);
musaFreeAsync(d, stream);
```

The allocation/deallocation is queued in the stream — no host sync needed. Useful for transient buffers in graph capture.

## Memory Pools

```cpp
musaMemPool_t pool;
musaDeviceGetDefaultMemPool(&pool, device);
musaMemPoolSetAttribute(pool, musaMemPoolAttrReleaseThreshold, &(size_t){UINT64_MAX});

// Now async-free'd memory stays in the pool instead of returning to OS
float* d = (float*)musaMallocAsync(sz, stream);
// ... use ...
musaFreeAsync(d, stream);
// Next musaMallocAsync may reuse the same memory instantly
```

Reduces allocation overhead for hot loops.

## Cluster Memory

See [[cluster-memory]] for distributed shared memory across blocks in a cluster.

## Cross-References

- [[memory-hierarchy]] — the basic hierarchy this builds on
- [[stream-and-event-model]] — async copies
- [[cluster-memory]] — distributed shared memory
- [[l2-cache-management]] — persistence policy
- → raw: `programming_model_advanced_memory.md`
