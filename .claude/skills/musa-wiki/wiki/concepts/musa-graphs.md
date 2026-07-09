---
title: "MUSA Graphs"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [features_musa_graphs.md, features.md]
tags: [musa, graphs, dag, stream-capture, performance]
---

# MUSA Graphs

A MUSA Graph is a **DAG of GPU work** (kernel launches, memcpys, events) submitted as a single unit. Re-launching a graph skips kernel-by-kernel host/device round-trips, dramatically reducing launch overhead for workloads that repeat the same sequence many times.

## When Graphs Win

| Workload | Graph benefit |
|----------|---------------|
| Training step (forward+backward+step) × 1000 epochs | Launch overhead collapses; ~10-30% wall-clock improvement |
| Inference batch loop | Same kernels every iter — perfect graph candidate |
| Multi-kernel pipeline with fixed topology | No need to re-issue stream of commands |
| Adaptive / data-dependent branching | ❌ Bad fit — graphs are static DAGs |

## Graph Construction — Two Paths

### Explicit API

Build node-by-node. Verbose but precise.

```cpp
musaGraph_t graph;
musaGraphCreate(&graph, 0);

musaGraphNode_t a, b, c;
musaKernelNodeParams kp = {};
kp.func = (void*)myKernel;
kp.gridDim = grid; kp.blockDim = block;
kp.kernelParams = (void**)args;

musaGraphAddKernelNode(&a, graph, NULL, 0, &kp);          // root
musaGraphAddKernelNode(&b, graph, &a, 1, &kp2);           // depends on a
musaGraphAddKernelNode(&c, graph, &b, 1, &kp3);           // depends on b
```

### Stream Capture (Preferred)

Record a stream's operations into a graph by wrapping them in `BeginCapture`/`EndCapture`.

```cpp
musaStreamBeginCapture(stream, musaStreamCaptureModeGlobal);

kernel1<<<grid, block, 0, stream>>>(d_a);
musaMemcpyAsync(d_b, d_a, sz, musaMemcpyDeviceToDevice, stream);
kernel2<<<grid, block, 0, stream>>>(d_b);
musaStreamWaitEvent(stream, some_event, 0);                // captured as dependency edge

musaGraph_t graph;
musaStreamEndCapture(stream, &graph);
```

> During capture, work is **recorded, not executed**. The stream is "offline".

## Instantiate and Launch

```cpp
musaGraphExec_t exec;
musaGraphInstantiate(&exec, graph, NULL, NULL, 0);

// Launch as a unit — replaces the whole captured sequence
for (int i = 0; i < iterations; i++) {
    musaGraphLaunch(exec, stream);
}
musaStreamSynchronize(stream);

musaGraphExecDestroy(exec);
musaGraphDestroy(graph);
```

A `musaGraphExec_t` is a **device-side instantiation** — it has all kernel params, copies, and dependencies resolved into a runnable form. Launching it is a single API call.

## Updating Parameters

For workloads where only kernel arguments change between iterations (e.g., pointers, scalar loop counters), update the graph in-place instead of rebuilding:

```cpp
musaKernelNodeParams kp;
musaGraphExecGetNodeParams(exec, kernelNode, &kp);
// ... modify kp.kernelParams ...
musaGraphExecUpdate(exec, kernelNode, &kp);                // returns musaSuccess or error
```

If the **topology** changes (added/removed edges), the update may fail — must re-instantiate.

## Dependencies

Edges in the DAG express ordering. By default each new node depends on the previously-added node, but you can specify parents explicitly:

```cpp
musaGraphNode_t parents[] = {a, b};
musaGraphAddKernelNode(&c, graph, parents, 2, &kp);        // c depends on both a and b
```

Nodes with **no shared ancestor** can execute concurrently (similar to multi-stream concurrency).

## Events as Edges

`musaStreamWaitEvent` calls during capture become **dependency edges** in the graph. This is how you express cross-graph synchronization.

## Constraints

| Constraint | Consequence |
|------------|-------------|
| Cannot allocate memory inside a captured graph (musaMalloc) | Allocate buffers beforehand |
| Cannot call `musaStreamSynchronize` inside capture | Sync is implicit at graph end |
| Stream capture mode affects host visibility | `musaStreamCaptureModeRelaxed` allows other streams to run; `Global` blocks them |
| Topology change after instantiate → update may fail | Re-instantiate |
| Memory must remain valid across launches | Use pinned or managed memory for graph-resident buffers |

## Stream Capture Modes

| Mode | Behavior |
|------|----------|
| `musaStreamCaptureModeGlobal` | Most restrictive — syncs with all other streams on device |
| `musaStreamCaptureModeThreadLocal` | Syncs only with streams in this thread |
| `musaStreamCaptureModeRelaxed` | Least restrictive — allows concurrent work; must use events for explicit deps |

Default to `Global` unless you have a measured reason.

## Debugging Capture

```cpp
musaStreamIsCapturing(stream, &captureStatus);             // check if in capture
musaStreamGetCaptureInfo(stream, &captureStatus, &id, ...); // get capture id / topology
```

If a capture fails (e.g., you accidentally called `musaMalloc`), the error is reported on the next stream API call — check with `musaGetLastError`.

## Conditional Nodes

Some MUSA versions support `musaGraphAddConditionalNode` which adds runtime branching. Useful when a small flag decides whether to run a subgraph. Not all topology updates work with conditionals — verify on your target device.

## Performance Notes

| Concern | Mitigation |
|---------|-----------|
| Capture overhead is non-trivial | Capture once, launch many times |
| Graph re-instantiation is expensive | Use `musaGraphExecUpdate` for param-only changes |
| Memory pressure if many graphs coexist | Destroy unused `musaGraphExec_t` |
| Captured stream blocks other work | Use `Relaxed` mode + events |

## Cross-References

- [[stream-and-event-model]] — stream capture is built on streams
- [[green-context]] — graphs compose with green contexts
- [[runtime-api]] — graph API surface
- → raw: `features_musa_graphs.md`
