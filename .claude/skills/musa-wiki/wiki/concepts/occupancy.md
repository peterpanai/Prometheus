---
title: "占用率"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_compute_optimization.md, performance_tuning_quickstart_optimization.md]
tags: [musa, occupancy, active-warps, latency-hiding]
---

# 占用率 (Occupancy)

Occupancy is the ratio of **active warps per SM** to the **maximum warps per SM** the hardware supports. It is a measure of how much parallelism the scheduler has to hide latency — not a measure of performance directly, but a precondition for it.

## Definition

```
Occupancy = active_warps_per_SM / max_warps_per_SM
```

For MTT S5000 (MP31): max 64 warps × 32 lanes = 2048 threads per SM.
For MTT M1000/S4000 (MP21/MP22): max 16 warps × 128 lanes = 2048 threads per SM.

> Both architectures cap at 2048 threads/SM but with different warp sizes — query `musaDevAttrMaxThreadsPerMultiProcessor` and `warpSize` at runtime.

## Three Limits

A block is **limited** by whichever of the following is hit first:

| Resource | Limit |
|----------|-------|
| Threads per block | ≤ 1024 |
| Blocks per SM | ≤ 32 (typical) |
| Shared memory per SM | 48–96 KB |
| Registers per thread | ≤ 255 (compiler-controlled) |
| Registers per SM | ~64K |

The achieved occupancy is determined by the **most constraining** resource.

## Calculating Achievable Occupancy

```cpp
int device; musaGetDevice(&device);

int maxThreadsPerSM, maxBlocksPerSM, sharedMemPerSM, regsPerSM, regsPerBlock;
musaDeviceGetAttribute(&maxThreadsPerSM, musaDevAttrMaxThreadsPerMultiProcessor, device);
musaDeviceGetAttribute(&maxBlocksPerSM, musaDevAttrMaxBlocksPerMultiProcessor, device);
musaDeviceGetAttribute(&sharedMemPerSM, musaDevAttrMaxSharedMemoryPerMultiprocessor, device);
musaDeviceGetAttribute(&regsPerSM, musaDevAttrMaxRegistersPerMultiprocessor, device);

// For a kernel with B=256 threads/block, S=4096 bytes shared/block, R=32 regs/thread:
int B = 256, S = 4096, R = 32;

int blocksByThreads = maxThreadsPerSM / B;
int blocksByShared   = sharedMemPerSM / S;
int blocksByRegs     = regsPerSM / (R * B);
int blocksPerSM = min(min(blocksByThreads, blocksByShared),
                      min(blocksByRegs, maxBlocksPerSM));

int activeWarps = blocksPerSM * (B / warpSize);
int maxWarps = maxThreadsPerSM / warpSize;
float occupancy = (float)activeWarps / maxWarps;
```

MUSA also exposes this directly via the **occupancy calculator** API:

```cpp
int numBlocks;
musaOccupancyMaxActiveBlocksPerMultiprocessor(&numBlocks, myKernel, blockSize, dynShmem);
float occupancy;
musaOccupancyMaxActiveBlocksPerMultiprocessorWithFlags(&numBlocks, myKernel, blockSize, dynShmem, 0);
musaOccupancyMaxPotentialBlockSize(&gridSize, &blockSize, myKernel, 0, 0, 0);
```

## Register Pressure

The compiler chooses register count per thread. Use `--ptxas-options=-v` (or MUSA equivalent) to see:

```
ptxas info : Compiling entry function 'myKernel' for 'sm_80'
ptxas info : Function properties for myKernel
        0 bytes stack frame, 0 bytes spill stores, 0 bytes spill loads
ptxas info : Used 32 registers, 256 bytes cmem[0]
```

| Register count | Max threads/SM (assuming 64K regs) | Notes |
|----------------|------------------------------------|-------|
| 32 | 2048 (full) | Ideal |
| 64 | 1024 (half) | Common |
| 128 | 512 (quarter) | Heavy kernels |
| 255 (max) | 256 | Usually spills — bad |

If `--ptxas-options=-v` shows spills, the compiler ran out of registers and started using local memory (100× slower). Reduce register pressure by:
- Breaking large functions into smaller ones
- Avoiding large per-thread arrays
- Using `__launch_bounds__(maxThreadsPerBlock, minBlocksPerSM)` to hint the compiler

```cpp
__global__ void __launch_bounds__(256, 4) myKernel(...) {
    // Compiler targets 256 threads/block, at least 4 blocks/SM
    // → caps register usage at ~64
}
```

## Shared Memory Pressure

```cpp
__shared__ float tile[48 * 1024 / sizeof(float)];   // 48 KB — uses entire SM carve-out
// Only 1 block can run on this SM
```

Trade-off: more shared mem per block → fewer concurrent blocks → lower occupancy. But sometimes **low occupancy + more shared mem per block** wins (e.g. GEMM tiles).

## The Occupancy Dialectic

**High occupancy is not always faster**:

| Scenario | Effect |
|----------|--------|
| Memory-bound kernel | High occupancy helps hide DRAM latency |
| Compute-bound kernel with high ILP | Lower occupancy may be fine — ILP hides latency instead |
| Heavy register pressure forcing spills | Spills cost more than low occupancy |

Target:
- Memory-bound: **≥ 50% occupancy** (rule of thumb).
- Compute-bound: enough warps to hide arithmetic pipeline depth (often 25-50% suffices).
- Always benchmark rather than chase 100%.

## How to Increase Occupancy

| Lever | Action |
|-------|--------|
| Block size | Match to a divisor of `maxThreadsPerSM / warpSize` (e.g. 128, 256) |
| Register count | `__launch_bounds__`, reduce per-thread arrays |
| Shared memory | Reduce static allocation, use dynamic shared mem |
| Block count | Grid-stride loops to keep blocks filled |

## When to NOT Maximize Occupancy

- **GEMM with Tensor Cores**: tile size determines warps; occupancy is whatever the tile allows.
- **Persistent kernels**: deliberately launch fewer blocks than SMs, each block does many tiles.
- **Warp-specialized kernels**: producer/consumer warps may have different resource profiles.

## Cross-References

- [[roofline-model]] — occupancy is second-order; roofline determines bottleneck
- [[warp-divergence]] — divergence reduces effective occupancy
- [[memory-hierarchy]] — register and shared memory limits
- [[gemm-optimization]] — when low occupancy + tile size wins
- → raw: `performance_tuning_compute_optimization.md`
