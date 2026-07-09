---
title: "高级功能 — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources:
  - features.md
  - features_musa_graphs.md
  - features_green_context.md
tags: [musa, graphs, green-context, dag, mp-partitioning, low-latency]
---

# 高级功能 (Advanced Features)

Two advanced MUSA features for specialized workloads:

1. **MUSA Graphs** — define a workflow once as a DAG, launch it many times with low CPU overhead.
2. **Green Context** — partition a GPU's MPs into reserved subsets for deterministic, latency-bounded execution.

Both are built on top of the standard MUSA runtime/driver stack and compose with streams, events, and kernels.

## Source Pages

| Raw File | Title | Covers |
|----------|-------|--------|
| `features.md` | 功能特性 | Chapter index |
| `features_musa_graphs.md` | MUSA Graphs | Graph model, node types, capture vs explicit build, instantiate, launch, update, memory pool, version gates |
| `features_green_context.md` | Green Context | MP partitioning, MUdevResource, GC-bound streams, GC events, sizing guidance |

---

## MUSA Graphs

### What & Why

MUSA Graphs decouple workflow *definition* from *execution*. Operations (kernel launches, memcpys, event records, etc.) become nodes in a directed acyclic graph; dependency edges constrain execution order. The graph is defined once, instantiated into an executable form, then launched many times with very low CPU overhead.

Use it when:
- Per-launch CPU overhead dominates short kernel runtime (low-latency inference).
- The same workflow runs repeatedly (inference loops, iterative solvers).
- You want global optimization across multiple operations.
- Multi-tenant services need predictable submission.

### Key Concepts

| Concept | Meaning |
|---------|---------|
| **Node (节点)** | A single operation: kernel, memcpy, memset, host call, empty, event-record/wait, external semaphore signal/wait, child graph, mem-alloc/free, conditional |
| **Edge (边)** | Dependency: upstream → downstream. MUSA 5.1.0 supports only default (full) dependency; edge data is reserved |
| **Capture (捕获)** | Stream-based recording: `musaStreamBeginCapture` → submit work → `musaStreamEndCapture` produces a graph |
| **Instantiate (实例化)** | `musaGraphInstantiate` validates + snapshots the graph into a `musaGraphExec_t` |
| **Launch (启动)** | `musaGraphLaunch(exec, stream)` submits the executable to a stream |
| **Auto-free on launch** | Instantiation flag that auto-releases orphan mem-alloc nodes |
| **Empty node** | No-op node used as a join/sync point |

Capture modes: `Global` (default, merges all captured streams in context), `ThreadLocal` (per-thread isolation), `Relaxed` (allows extra ops).

### Key APIs

| API | Purpose |
|-----|---------|
| `musaGraphCreate(graph*, flags)` | Create empty graph |
| `musaGraphAddKernelNode(...)` / `...Memcpy...` / `...Memset...` / `...Host...` / `...Empty...` | Add typed nodes explicitly |
| `musaGraphAddEventRecordNode` / `...EventWait...` | Event nodes (≥ 10000) |
| `musaGraphAddExternalSemaphoresSignalNode` / `...Wait...` | Cross-process sync (≥ 10200) |
| `musaGraphAddMemAllocNode` / `...MemFree...` / `...ChildGraph...` / `...Conditional...` | Advanced (≥ 10400) |
| `musaGraphAddDependencies(graph, from*, to*, n)` | Add edges after node creation |
| `musaStreamBeginCapture(s, mode)` / `musaStreamEndCapture(s, graph*)` | Stream-capture path (≥ 10000) |
| `musaGraphInstantiate(exec*, graph, flags)` | Snapshot to executable |
| `musaGraphInstantiateWithParams(exec*, params)` | Parameterized instantiate (≥ 10400) |
| `musaGraphLaunch(exec, stream)` | Submit |
| `musaGraphExecUpdate(exec, graph, resultInfo*)` | Re-bind exec to a modified graph |
| `musaGraphExecKernelNodeSetParams` / `...Memcpy...` / `...Memset...` | Per-node parameter updates |
| `musaGraphNodeSetEnabled` / `musaGraphNodeGetEnabled` | Toggle nodes |
| `musaGraphGetNodes` / `...RootNodes` / `...Edges` / `musaGraphNodeGetType` / `...GetDependencies` | Introspection |
| `musaGraphDebugDotPrint(graph, path, flags)` | Export to DOT for Graphviz |
| `musaDeviceGetGraphMemAttribute` / `...Set...` / `musaDeviceGraphMemTrim` | Graph memory pool mgmt |
| `musaGraphExecDestroy` / `musaGraphDestroy` | Cleanup |

Instantiate flags: `musaGraphInstantiateFlagAutoFreeOnLaunch`, `...DeviceLaunch`, `...UseNodePriority`.

Update result enum: `TopologyChanged`, `NodeTypeChanged`, `FunctionChanged`, `ParametersChanged`, `AttributesChanged`.

### Constraints

- **Capture cannot**: sync the captured stream, use `musaStreamLegacy` while a non-blocking stream is being captured, call sync APIs like `musaMemcpy`, or merge independent captures via cross-graph event waits.
- **Update cannot change**: graph topology, kernel context, dynamic-parallel flag, memcpy/memset memory kind or transfer type, kernel function pointer in some cases.
- `musaGraph_t` is **not thread-safe**.
- A `musaGraphExec_t` cannot execute concurrently with itself.
- `musaGraphDestroy` does NOT free mem-alloc nodes (unless `AutoFreeOnLaunch` is set).
- All nodes must be on the same device.

### Typical Pattern (Stream Capture)

```cpp
musaStream_t s;  musaStreamCreate(&s);
musaGraph_t g;
musaStreamBeginCapture(s, musaStreamCaptureModeGlobal);
myKernel<<<256, 256, 0, s>>>(d_data, n);
musaMemcpyAsync(d2, d1, sz, musaMemcpyDeviceToDevice, s);
otherKernel<<<128, 256, 0, s>>>(d2, n);
musaStreamEndCapture(s, &g);

musaGraphExec_t e;
musaGraphInstantiate(&e, g, 0);
for (int i = 0; i < 100; ++i) musaGraphLaunch(e, s);   // very low overhead
musaStreamSynchronize(s);

musaGraphExecDestroy(e); musaGraphDestroy(g); musaStreamDestroy(s);
```

---

## Green Context

### What & Why

Green Context (GC, 绿色上下文) is a lightweight execution context that, at creation time, binds work to a **reserved subset of MPs** on the GPU. It exists to give applications precise, deterministic control over MP partitioning — solving the standard MUSA model's inability to control MP allocation, avoid resource contention between concurrent tasks, and bound latency for time-sensitive services.

GC is a **Driver API** feature (not Runtime). Constructed in three stages: query the device's MP pool → split it into disjoint partitions → create a Green Context plus a stream bound to it.

Use it for:
- Multi-tenant GPU sharing
- Latency-critical inference (recommend 8–16 MPs)
- Batch training (32–64 MPs)
- Any SLA-driven workload where predictable resources matter more than raw peak utilization

### Key Concepts

| Concept | Meaning |
|---------|---------|
| **MP (MUSA Processor, 处理器)** | Minimum compute unit, 128 FP32 units — MUSA's SM equivalent |
| **MPX (execution engine)** | 2 MPs sharing 24 KB L1 cache |
| **MPC (cluster)** | 2 MPX sharing 512 KB L2 cache |
| **Green Context (GC)** | Lightweight context bound to a reserved MP subset |
| **MUdevResource** | Resource container; relevant field `.sm.smCount` |
| **MUdevResourceDesc** | Descriptor generated from a resource array, passed to `muGreenCtxCreate` |
| **Resource split** | Partitioning the total MP pool via `muDevSmResourceSplitByCount` |
| **GC-bound stream** | Stream created by `muGreenCtxStreamCreate`; runs only on its GC's MPs |
| **GC events** | Must use `muGreenCtx*Event` family — NOT standard stream event API |

### Key APIs (Driver API, `mu*` prefix)

| API | Purpose |
|-----|---------|
| `muDeviceGetDevResource(dev, &resource, MU_DEV_RESOURCE_TYPE_SM)` | Query total MP pool |
| `muStreamGetDevResource(stream, &resource)` | Query a stream's resource |
| `muDevSmResourceSplitByCount(result*, &actualGroups, &initial, &remaining, minPerGroup, count)` | Split pool — `count=0` for even auto-split, `count>0` to reserve N |
| `muDevResourceGenerateDesc(&desc, &resources, count)` | Wrap resources into a descriptor |
| `muGreenCtxCreate(&gc, desc, dev, flags)` | Create context |
| `muGreenCtxDestroy(gc)` | Destroy (must run AFTER all its streams are destroyed) |
| `muGreenCtxGetDevResource(gc, &resource)` | Introspect via `resource.sm.smCount` |
| `muGreenCtxStreamCreate(&stream, gc, flags, priority)` | Create GC-bound stream |
| `muStreamGetGreenCtx(stream, &gc)` | Retrieve GC behind a stream |
| `muGreenCtxRecordEvent(gc, event)` / `muGreenCtxWaitEvent(gc, event)` | GC-scoped event sync (replaces `muEventRecord`/`muStreamWaitEvent` inside a GC) |

Standard driver memory API (`muMemAlloc`, `muMemFree`) is used; allocations are implicitly associated with the active GC.

### Constraints & Limits

- **Max MPs per GC**: 64; **min MPs per GC**: 2; alignment granularity: 2.
- A GC's resource set is **immutable after creation** — resize requires destroy + recreate.
- GCs are per-device; cross-device reuse is not supported.
- Only **MP** resource type can be split today; Work Queue (WQ) splitting is future work.
- Hardware: full support on S5000+; basic support on earlier chips.
- Software: MUSA SDK 5.1.0+, Linux Driver 5.1.0+, GCC 11.4+, CMake 3.22+.
- **Event API mismatch**: standard stream event calls are NOT valid inside a GC — use `muGreenCtx*Event`.
- Destroy order: stream first, then GC.
- Errors: `MUSA_ERROR_OUT_OF_MEMORY`, `MUSA_ERROR_INVALID_VALUE`, `MUSA_ERROR_INVALID_CONTEXT`, `MUSA_ERROR_INVALID_RESOURCE_CONFIGURATION`, `MUSA_ERROR_INVALID_DEVICE`.

### Sizing Guidance

| Workload | Recommended MPs |
|----------|----------------|
| Latency-sensitive inference | 8–16 |
| Batch training | 32–64 |
| Multi-tenant | Dynamic, based on SLA |

### Typical Pattern

```cpp
MUdevice dev = 0;
MUdevResource mp;
muDeviceGetDevResource(dev, &mp, MU_DEV_RESOURCE_TYPE_SM);

MUdevResource part[1], remaining;
unsigned int actual = 0;
muDevSmResourceSplitByCount(part, &actual, &mp, &remaining, 0, 16);  // reserve 16 MPs

MUdevResourceDesc desc;
muDevResourceGenerateDesc(&desc, &part[0], 1);

MUgreenCtx gc;
muGreenCtxCreate(&gc, desc, dev, 0);

MUstream s;
muGreenCtxStreamCreate(&s, gc, MU_STREAM_DEFAULT, 0);

MUdeviceptr d;
muMemAlloc(&d, N * sizeof(float));
myKernel<<<256, 256, 0, s>>>(d, N);
muStreamSynchronize(s);

muMemFree(d);
muStreamDestroy(s);    // stream first
muGreenCtxDestroy(gc); // then GC
```

## Cross-References

- **Concept pages**: [[musa-graphs]], [[green-context]], [[stream-and-event-model]]
- **Source chapters**: [[programming-model]] (streams/events foundation), [[api-guides]] (Driver API for Green Context)
- **Composes with**: [[l2-cache-management]] (persistent data + graph replay = high-throughput inference), Green Context + MUSA Graphs for deterministic low-latency pipelines
