---
title: "Cluster 内存"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [programming_model_advanced_memory.md, programming_model_thread_hierarchy.md]
tags: [musa, cluster, distributed-shared-memory, thread-block-cluster]
---

# Cluster 内存 (Cluster Memory)

A **Thread Block Cluster** is a group of thread blocks (typically 2–16) that are co-scheduled on adjacent SMs and given a way to access each other's **shared memory**. This extends the block-level collaboration model across block boundaries without falling back to global memory.

## The Hierarchy Extension

```
Grid
└── Cluster  (co-scheduled, distributed shared mem)
    ├── Block 0  → shared mem SM0
    ├── Block 1  → shared mem SM1
    └── Block N  → shared mem SMN
```

Without clusters, blocks can only communicate via [[atomic-functions]] on global memory (slow, no sync guarantee). With clusters, a block can directly read/write a peer block's shared memory using **distributed shared memory** addresses.

## Declaring a Cluster

```cpp
__global__ void __cluster_dims__(2, 1, 1) kernel(float* data) {
    // This kernel runs in clusters of 2x1x1 = 2 blocks each.
    // Blocks within a cluster are co-scheduled and share DSMEM.
    ...
}
```

`__cluster_dims__(X, Y, Z)` must be a compile-time constant. Total blocks per cluster ≤ hardware limit (typically 8 or 16 — query via `musaDevAttrClusterLaunch`).

## Cluster Built-ins

```cpp
// Index of this block within its cluster
uint3 clusterIdx = blockIdx.cluster_dim();

// Rank of this block within the cluster (linearized)
unsigned clusterRank = blockIdx.cluster_rank;

// Total blocks in the cluster
unsigned clusterSize = blockDim.cluster_size;
```

## Distributed Shared Memory (DSMEM)

A pointer into another block's shared memory is constructed via `musaClusterMapSharedRank`:

```cpp
__global__ void __cluster_dims__(2,1,1) k(float* out) {
    __shared__ float local_tile[256];
    local_tile[threadIdx.x] = compute(...);
    __syncthreads();                          // local barrier — within this block

    // Get pointer to peer block's shared memory (block 1 from block 0's POV)
    float* peer_tile = (float*)musaClusterMapSharedRank(local_tile, 1);

    // Now read peer's data
    float v = peer_tile[threadIdx.x];

    // Cluster-wide barrier — all blocks in cluster must reach
    musaClusterSync();

    out[blockIdx.x * 256 + threadIdx.x] = v;
}
```

## Cluster Sync Primitives

| Function | Scope |
|----------|-------|
| `musaClusterSync()` | All threads in cluster |
| `musaClusterBarrierArrive()` | Arrival side of barrier (decouple arrival/wait) |
| `musaClusterBarrierWait()` | Wait side |
| `cluster_group cg = cluster_group::this_cluster(); cg.sync()` | Group API |

`musaClusterSync()` is the workhorse — use it unless you have a measured reason to decouple arrival and wait.

## When Clusters Help

| Use case | Why cluster |
|----------|-------------|
| Halo exchange (stencil) between block tiles | Avoid global memory round-trip for neighbor data |
| Cooperative GEMM tile assembly | Multiple blocks contribute to a single output tile |
| Multi-block reduction intermediate stage | Skip the global atomic step |
| Sliding-window convolutions | Reuse incoming strip across adjacent blocks |

## Constraints

- All blocks in a cluster must launch together (same kernel, same grid).
- Cannot exceed cluster size limit (query `musaDevAttrClusterLaunch`).
- Co-scheduling requires adjacent SMs — cluster size affects launch success rate. If the GPU cannot fit the cluster, the launch fails.
- Cluster barriers are **not** cross-grid synchronization; each cluster is independent.

## Relationship to Existing Primitives

| Primitive | Scope | Memory |
|-----------|-------|--------|
| `__syncwarp` | Warp | registers/shuffle |
| `__syncthreads` | Block | shared memory |
| `musaClusterSync` | Cluster | distributed shared mem |
| atomic on global | Grid | global memory (slow) |

Clusters fill the **middle gap** between block-scoped and grid-scoped communication.

## Cross-References

- [[thread-hierarchy]] — block is the unit clusters operate on
- [[memory-hierarchy]] — shared memory, now distributed
- [[synchronization-primitives]] — full sync hierarchy
- [[advanced-memory]] — other advanced memory features
- → raw: `programming_model_advanced_memory.md`
