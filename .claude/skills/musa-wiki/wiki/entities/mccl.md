---
title: "MCCL"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_musa_sdk.md, what_is_musa.md]
tags: [musa, mccl, communication, allreduce, multi-gpu, nccl-equivalent]
---

# MCCL

MCCL (MUSA Communications Collectives Library) is Moore Threads' analog of NVIDIA's NCCL. It provides **multi-GPU collective communication** primitives optimized for topology-aware bandwidth utilization.

## What It Provides

Standard collective operations:

| Operation | Description |
|-----------|-------------|
| `mcclAllReduce` | Element-wise reduction across all GPUs, result on all |
| `mcclReduce` | Reduction to one designated GPU |
| `mcclBroadcast` | One GPU sends to all others |
| `mcclAllGather` | Each GPU gathers data from all others |
| `mcclReduceScatter` | Reduce then scatter chunks |
| `mcclSend` / `mcclRecv` | Point-to-point |

Each operation supports multiple data types (FP32, FP16, BF16, INT8) and reductions (sum, prod, min, max).

## Initialization

```cpp
#include <mccl.h>

mcclComm_t comm;
int nGPUs = 4;
int devList[] = {0, 1, 2, 3};
mcclCommInitAll(&comm, nGPUs, devList);   // or single: mcclCommInitRank
```

Each rank (GPU) gets its own `mcclComm_t`. In multi-process setups, use `mcclCommInitRank` with a unique ID shared via filesystem or MPI.

## All-Reduce Example

```cpp
mcclComm_t myComm = comms[myRank];
musaStream_t stream;
musaStreamCreate(&stream);

// Each GPU has d_inout with N floats
mcclAllReduce(d_inout, d_inout, N, mcclFloat, mcclSum, myComm, stream);

musaStreamSynchronize(stream);
```

After this, every GPU's `d_inout` has the sum of all GPUs' inputs.

## Unique ID for Multi-Process

```cpp
// Process 0 (root):
mcclUniqueId id;
mcclGetUniqueId(&id);
// Broadcast `id` to all other processes via MPI, TCP, file, etc.

// Each process:
mcclCommInitRank(&comm, nRanks, id, myRank);
```

## Ring and Tree Algorithms

MCCL uses **ring** and **tree** topologies internally, auto-selected based on GPU topology:

- **Ring**: Each GPU sends/receives chunks in a circle. Optimal bandwidth utilization for small to medium messages.
- **Tree**: Hierarchical reduction. Lower latency for very small messages, better for large GPU counts.

MCCL probes the interconnect (NVLink-equivalent, PCIe, etc.) and picks the best algorithm automatically.

## Streams and Concurrency

```cpp
mcclAllReduce(d1, d1, N, mcclFloat, mcclSum, comm, stream1);
mcclAllReduce(d2, d2, M, mcclFloat, mcclSum, comm, stream2);
// Two collectives on different streams can overlap
```

> Same communicator, different streams → may serialize. For full overlap, create separate communicators.

## Synchronization

MCCL operations are **async** w.r.t. the host — they return immediately and execute on the specified stream. To wait for completion:

```cpp
musaStreamSynchronize(stream);
// or use events
```

Each collective is **collectively ordered** — all ranks must call the operation in the same order. If rank A calls `AllReduce` then `Broadcast`, all ranks must do the same.

## Common Patterns

### DDP (Distributed Data Parallel) Gradient Sync

```cpp
// Each GPU computes gradients locally
backwardPass();
// All-reduce gradients across GPUs
for (auto& param : params) {
    mcclAllReduce(param.grad(), param.grad(), param.count(),
                  mcclFloat, mcclSum, comm, stream);
}
// Scale by 1/nGPUs
scaleKernel<<<...>>>(params, 1.0f / nGPUs);
// Optimizer step
optimizerStep();
```

### Pipeline Parallelism

```cpp
// Stage 0: forward on GPU 0
forward0<<<..., stream0>>>(d0_in, d0_out);
mcclSend(d0_out, size, mcclFloat, 1, comm, stream0);

// Stage 1: receive and forward on GPU 1
mcclRecv(d1_in, size, mcclFloat, 0, comm, stream1);
forward1<<<..., stream1>>>(d1_in, d1_out);
mcclSend(d1_out, size, mcclFloat, 2, comm, stream1);
```

## Performance Tuning

| Concern | Mitigation |
|---------|-----------|
| Small message latency | Use `mcclGroupStart/End` to batch multiple collectives |
| Topology mismatch | Use `MCCL_NET_GDR_DRAM` env var to tune transport |
| CPU-side bottleneck | Use `mcclCommRegister` to pin memory |
| Imbalanced ranks | Ensure all ranks call same operations |

## Grouping Calls

```cpp
mcclGroupStart();
for (auto& layer : layers) {
    mcclAllReduce(layer.grad, layer.grad, layer.size, ...);
}
mcclGroupEnd();    // all collectives launched together
```

For small gradients, this is much faster than issuing many separate AllReduce calls.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Different ranks call different ops | Each rank must call the same op in the same order |
| Forgetting to sync stream | Next kernel may read stale data |
| Single communicator for everything | Serialize; create separate comms for parallelism |
| Large message on default stream | Blocks other ops; use dedicated stream |

## Cross-References

- [[musa-sdk-stack]] — library's place in the stack
- [[stream-and-event-model]] — async coordination
- → raw: `what_is_musa_musa_sdk.md`
