---
title: "L2 缓存管理"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [programming_model_l2_cache_management.md]
tags: [musa, l2-cache, persistence, access-policy, locality]
---

# L2 缓存管理 (L2 Cache Management)

L2 is the **last-level cache** between SMs and DRAM. By default it is a hardware-managed, demand-allocated cache with **streaming** policy — useful data is evicted as fast as it is brought in. MUSA exposes APIs to override this: pinning specific address ranges in L2 so repeated accesses hit the cache instead of DRAM.

## When L2 Persistence Helps

| Workload | Helps? | Why |
|----------|--------|-----|
| Repeated reads of same buffer across many kernels | ✅ | Persistent hit replaces 100+ cycle DRAM access |
| Streaming read-once | ❌ | No reuse — persistence wastes capacity |
| Small hot working set (< L2 size) | ✅ | Pinning guarantees no eviction |
| Working set > L2 size | ⚠️ Partial | Only the pinned portion benefits; choose carefully |

## Access Policy Model

Three properties, set per-allocation:

| Property | Meaning |
|----------|---------|
| `musaAccessPropertyPersisting` | Hits stay in L2 (resist eviction) |
| `mudaAccessPropertyStreaming` | Hits evict ASAP (default behavior) |
| `musaAccessPropertyNormal` | Reset to default demand-allocated caching |

A `hitRatio` (0.0–1.0) controls **what fraction** of accesses are subject to the policy — useful when the working set exceeds L2 capacity but you want partial persistence.

## Sizing the Persistent Region

```cpp
int device;
musaGetDevice(&device);

size_t l2Total, l2Persistent;
musaDeviceGetAttribute(&l2Total, musaDevAttrL2CacheSize, device);

// Maximum cache lines that can be reserved for persistence
musaDeviceGetAttribute((int*)&l2Persistent,
                       musaDevAttrMaxPersistingL2CacheSize, device);

// Set the persistent carve-out (must be ≤ l2Persistent)
musaDeviceSetLimit(musaLimitPersistingL2CacheSize, l2Persistent);
```

## Pinning an Address Range

```cpp
musaStreamAttrValue attr;
attr.accessPolicyWindow.base_ptr = d_data;
attr.accessPolicyWindow.num_bytes = N * sizeof(float);
attr.accessPolicyWindow.hitRatio  = 1.0f;                          // 100%
attr.accessPolicyWindow.hitProp   = musaAccessPropertyPersisting;
attr.accessPolicyWindow.missProp  = musaAccessPropertyStreaming;

musaStreamSetAttribute(stream, musaStreamAttributeAccessPolicyWindow, &attr);
```

After this, all accesses (in `stream`) to `d_data[0..N)` are subject to the policy.

## Lifecycle

```cpp
// 1. Set limit
musaDeviceSetLimit(musaLimitPersistingL2CacheSize, max_persist_size);

// 2. Mark window per stream
musaStreamSetAttribute(s, musaStreamAttributeAccessPolicyWindow, &attr);

// 3. Run kernels that reuse d_data — they hit L2
for (int i = 0; i < iterations; i++)
    reuseKernel<<<grid, block, 0, s>>>(d_data, i);

// 4. Reset window (otherwise it persists until stream destroyed)
attr.accessPolicyWindow.num_bytes = 0;
musaStreamSetAttribute(s, musaStreamAttributeAccessPolicyWindow, &attr);

// 5. Reset limit (frees the carve-out)
musaDeviceSetLimit(musaLimitPersistingL2CacheSize, 0);
```

## HitRatio Tuning

When the working set is larger than the persistent carve-out, `hitRatio < 1.0` distributes persistence across the whole buffer:

- `hitRatio = 0.5` on a 64 MB buffer with 32 MB carve-out → each cache line has 50% chance of being persisted, covering effectively the whole buffer over many accesses.
- `hitRatio = 1.0` would persist only the first 32 MB and leave the rest cold.

Choose ratio ≈ `carve_out_size / working_set_size` for best coverage.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Forget to reset window — next allocation silently inherits the policy | Always set `num_bytes = 0` at end |
| `num_bytes` exceeds L2 carve-out | Reduce to ≤ `musaLimitPersistingL2CacheSize` |
| Pinning a buffer that is also being written by D2H copies | The copy invalidates the cache lines anyway — no benefit |
| Pinning global memory accessed by multiple streams | Each stream needs its own policy window; effects compound |

## Hardware Variations

MP21/MP22 (MTT M1000/S4000) and MP31 (MTT S5000) have different L2 sizes. Always query via `musaDevAttrL2CacheSize` rather than hard-coding.

## Cross-References

- [[memory-hierarchy]] — L2's place in the hierarchy
- [[advanced-memory]] — other memory control surfaces
- [[stream-and-event-model]] — policies are stream-scoped
- → raw: `programming_model_l2_cache_management.md`
