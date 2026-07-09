---
title: "Green Context"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [features_green_context.md, features.md]
tags: [musa, green-context, mp-partition, driver-api, multi-tenancy]
---

# Green Context

A **Green Context** is a Driver-API construct that partitions a physical GPU's MPs (multiprocessors) into isolated execution regions. Each Green Context gets its own stream queue and executes only on its assigned MPs, enabling true multi-tenant isolation on a single GPU.

## Why Green Contexts Exist

Without Green Contexts, multiple workloads sharing a GPU contend via time-slicing — the runtime migrates work between MPs and one workload can starve another. Green Contexts give each workload a **fixed MP slice**, so:

- Latency for workload A does not depend on workload B's intensity.
- Cache state stays local to the partition (less thrash).
- Multi-process serving (e.g. MaaS) can give each tenant a predictable compute slice.

## Conceptual Model

```
GPU (128 MPs)
├── Green Context A  ──►  MPs 0..15    (16 MPs)  ──► streamA
├── Green Context B  ──►  MPs 16..63   (48 MPs)  ──► streamB
└── Green Context C  ──►  MPs 64..127  (64 MPs)  ──► streamC
```

Each Green Context has its own:
- Stream pool (created with `musaStreamCreateWithGreenCtx`)
- Events (created with `musaEventCreateWithGreenCtx`)
- MP range (defined by `MUdevResource`)

## Driver API Only

Green Contexts are **Driver API** constructs. They are not exposed via the Runtime API. You can mix them with Runtime API calls by passing the GC's underlying `MUcontext` to runtime calls — but the lifecycle is managed through Driver API.

## Creating a Green Context

```cpp
MUcontext greenCtx;
MUdevResource res = {};

// Reserve a specific MP range
res.smCount = 16;                            // how many MPs
res.minorSMCount = 0;                        // optional lower bound
res.partitionType = MU_PARTITION_TYPE_SM;    // SM-based partitioning

muGreenCtxCreate(&greenCtx, dev, &res, MU_GREEN_CTX_CREATE_SCHEDULING_FLAG);

// Use it as a regular context
muCtxSetCurrent(greenCtx);

// Streams bound to this GC will only run on its MPs
musaStream_t s;
musaStreamCreateWithGreenCtx(&s, greenCtx);
```

## Stream and Event Binding

```cpp
musaStream_t gcStream;
musaStreamCreateWithGreenCtx(&gcStream, greenCtx);

musaEvent_t gcEvent;
musaEventCreateWithGreenCtx(&gcEvent, greenCtx);

// All work in gcStream executes only on greenCtx's MPs
kernel<<<grid, block, 0, gcStream>>>(d);
musaEventRecord(gcEvent, gcStream);
```

Streams created normally (without `WithGreenCtx`) **do not** honor the partition — they use the primary context's MP pool.

## Sizing Guidance

| Workload | Recommended MPs | Why |
|----------|-----------------|-----|
| LLM inference (1 user) | 8–16 | Most inference is memory-bound; few MPs suffice |
| LLM inference (batched) | 32–64 | Compute-bound at higher batch |
| Training (small model) | 32–48 | Backward pass scales with MP count |
| Training (large model) | 64+ | Tensor Core utilization needs parallelism |
| Auxiliary (logging, eval) | 2–4 | Just enough for throughput |

> **Caveat**: This is empirical guidance, not specification. Always profile with `mcu`/`msys` and adjust based on your model and batch size.

## MP Count Discovery

```cpp
int totalSMs;
muDeviceGetAttribute(&totalSMs, MU_DEVICE_ATTRIBUTE_MULTIPROCESSOR_COUNT, dev);

// Free MPs available for partitioning
MUdevResource avail;
muDeviceGetGreenCtxAllocableRegions(&avail, sizeof(avail), dev);
// avail.smCount is the upper bound you can request
```

## Partitioning Strategies

### Static (Manual)

```cpp
// Hardcode the partition based on workload knowledge
MUdevResource r1 = {.smCount=16};
MUdevResource r2 = {.smCount=48};
muGreenCtxCreate(&gc1, dev, &r1, 0);
muGreenCtxCreate(&gc2, dev, &r2, 0);
```

### Dynamic (Scheduler)

For MaaS / multi-tenant serving, a scheduler creates/destroys Green Contexts on demand:

```cpp
// Tenant arrives → create GC with N MPs
muGreenCtxCreate(&tenantGC, dev, &tenantRes, 0);
// ... serve tenant ...
muGreenCtxDestroy(tenantGC);
```

> Dynamic create/destroy is more expensive than reuse — pool Green Contexts when possible.

## Constraints

| Constraint | Consequence |
|------------|-------------|
| Driver API only | Runtime-only consumers can't use GCs directly |
| Total reserved MPs ≤ device total | Over-reservation fails with `MU_ERROR_INVALID_VALUE` |
| Cross-GC sync requires host-side coordination | No native cross-GC barrier; use events + host wait |
| Memory allocations are device-global | GC doesn't partition VRAM; only compute |
| Capture/stream behavior is per-GC | A graph captured in GC1 won't run on GC2's MPs |

## Performance Notes

| Concern | Mitigation |
|---------|-----------|
| Too-small partition → low occupancy | Use ≥4 MPs per GC for any non-trivial kernel |
| Imbalanced partition → idle MPs | Monitor `mcu` SM utilization, rebalance |
| Cross-GC contention on memory bus | Both GCs share DRAM bandwidth — model this |
| Context switch overhead | Keep GCs long-lived; avoid churning |

## Comparison with MPS / MIG

| Feature | Green Context | NVIDIA MIG | NVIDIA MPS |
|---------|--------------|------------|------------|
| Compute isolation | Soft (MP slice) | Hard (HW partition) | Soft (client priority) |
| Memory isolation | None | Hard (per-instance) | None |
| Reconfigurable at runtime | Yes | No (requires reset) | Yes |
| API | Driver API | Driver API | Daemon |

Green Context is MUSA's analog to a lighter-weight MIG/MPS — flexible but not hardware-isolated.

## Cross-References

- [[driver-api]] — Green Contexts are Driver-API constructs
- [[primary-context]] — relationship to primary context
- [[stream-and-event-model]] — GC-bound streams
- [[musa-graphs]] — graphs can run on GC streams
- → raw: `features_green_context.md`
