---
title: "流与事件模型"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [programming_model_execution_model.md, api_guides_runtime_api_guide.md, features_musa_graphs.md]
tags: [musa, stream, event, async, synchronization]
---

# 流与事件模型 (Stream and Event Model)

Streams are virtual queues of GPU work; events are markers placed in streams. Together they enable **asynchronous host/device execution** and **fine-grained dependency control** — the foundation of overlap and concurrency in MUSA.

## Core Concept

```
Host thread              GPU stream
-----------              -----------
musaMemcpyAsync ────►   [H2D copy]
kernel<<<...,s>>>  ────►  [kernel A]
kernel<<<...,s>>>  ────►  [kernel B]   (serial within stream)
musaMemcpyAsync ────►   [D2H copy]
                           ↑ all in-order within stream s
```

- Work in the **same stream** executes **in order**, but the host returns immediately.
- Work in **different streams** can execute **concurrently** (subject to hardware resources).
- The host can keep doing CPU work while the GPU drains its queue.

## Default Stream

```cpp
kernel<<<grid, block>>>(args);              // stream 0 (default)
musaMemcpy(d, h, sz, musaMemcpyHostToDevice); // sync, default stream
```

- The default stream is **synchronizing** with respect to all other streams on the same device.
- For overlap, **always create explicit streams**.

## Stream Lifecycle

```cpp
musaStream_t s;
musaStreamCreate(&s);                        // create

kernel<<<grid, block, 0, s>>>(d_data);       // enqueue kernel
musaMemcpyAsync(d, h, sz, musaMemcpyH2D, s); // enqueue copy

musaStreamSynchronize(s);                    // block host until empty
musaStreamDestroy(s);                        // free
```

## Stream Priority

```cpp
int least, greatest;
musaDeviceGetStreamPriorityRange(&least, &greatest);
musaStreamCreateWithPriority(&high, 0, greatest);  // high-prio stream
musaStreamCreateWithPriority(&low, 0, least);      // low-prio stream
```

Useful when a small kernel must pre-empt a long-running one (e.g. latency-sensitive inference alongside training).

## Events — Markers, Not Work

Events are placed **in a stream** and used for two purposes: **timing** and **cross-stream dependency**.

```cpp
musaEvent_t start, stop;
musaEventCreate(&start);
musaEventCreate(&stop);

musaEventRecord(start, s);                   // record start into s
kernel<<<grid, block, 0, s>>>(d);
musaEventRecord(stop, s);                    // record stop into s
musaEventSynchronize(stop);                  // wait for stop

float ms;
musaEventElapsedTime(&ms, start, stop);      // GPU-side timing
```

> **Why not host-side `clock()`?** Kernels are async — host `clock()` measures enqueue time, not execution time.

## Cross-Stream Dependency

```cpp
musaEventRecord(done_a, streamA);
musaStreamWaitEvent(streamB, done_a, 0);     // B waits for event from A
// kernels in B can now safely read what A produced
```

This is the **only** way to express a dependency between two streams.

## Wait Variants

| API | Meaning |
|-----|---------|
| `musaStreamSynchronize(s)` | Host waits for all work in `s` |
| `musaEventSynchronize(e)` | Host waits for event `e` |
| `musaDeviceSynchronize()` | Host waits for all work on current device |
| `musaStreamWaitEvent(s, e, 0)` | Stream `s` (GPU-side) waits for `e` |
| `musaStreamQuery(s)` | Returns `musaSuccess` if `s` is idle (non-blocking poll) |
| `musaEventQuery(e)` | Non-blocking check if event has been recorded |

## Concurrency — When Do Streams Actually Overlap?

Three conditions must hold for two streams to run concurrently:

1. They are different streams.
2. The device has free execution resources (SMs, copy engines).
3. There is no implicit or explicit dependency between them.

Common pitfalls that break concurrency:
- Using the default stream anywhere in the chain.
- `musaMemcpy` (sync) instead of `musaMemcpyAsync`.
- Forgetting `musaStreamWaitEvent` between dependent kernels.
- Allocating memory mid-stream (causes implicit sync).

## Classic Overlap Patterns

### H2D / Kernel / D2H Triple Pipeline

```cpp
for (int i = 0; i < N; i++) {
    musaMemcpyAsync(d_in[i], h_in[i], sz, musaMemcpyH2D, streams[i % nStreams]);
    kernel<<<grid, block, 0, streams[i % nStreams]>>>(d_in[i], d_out[i]);
    musaMemcpyAsync(h_out[i], d_out[i], sz, musaMemcpyD2H, streams[i % nStreams]);
}
```

With `nStreams ≥ 2`, copy and compute overlap; total throughput approaches `max(H2D, kernel, D2H)` instead of `sum`.

### Producer / Consumer via Events

```cpp
musaEventRecord(produced, prodStream);
musaStreamWaitEvent(consStream, produced, 0);
kernel<<<grid, block, 0, consStream>>>(d_buf);
```

## Stream Capture → MUSA Graphs

A stream can be "captured" to record its work as a graph instead of executing it:

```cpp
musaStreamBeginCapture(s, musaStreamCaptureModeGlobal);
kernel<<<grid, block, 0, s>>>(d);
musaMemcpyAsync(d2, d, sz, musaMemcpyDeviceToDevice, s);
kernel<<<grid2, block2, 0, s>>>(d2);
musaStreamEndCapture(s, &graph);
```

See [[musa-graphs]].

## Callbacks

```cpp
musaStreamAddCallback(s, my_callback, userData, 0);
```

`my_callback` runs on a **runtime-managed host thread** when the stream reaches the callback point. Useful for host-side signaling, but **blocks the stream** until it returns — keep it short.

## Cross-References

- [[kernel-launch-syntax]] — the `stream` slot in `<<<>>>`
- [[synchronization-primitives]] — `__syncthreads()` is device-side, this is host-side
- [[musa-graphs]] — stream capture is the gateway to graphs
- [[runtime-api]] — stream/event API surface
- → raw: `programming_model_execution_model.md`
