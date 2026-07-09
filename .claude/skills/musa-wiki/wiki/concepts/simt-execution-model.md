---
title: "SIMT 执行模型"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_gpu_parallel_basics.md, programming_model_execution_model.md, programming_model_thread_hierarchy.md]
tags: [musa, simt, warp, execution-model, gpu-architecture]
---

# SIMT 执行模型 (SIMT Execution Model)

**SIMT** (Single Instruction, Multiple Threads) is the execution model used by MT GPUs. A group of threads (a **warp**) executes one instruction at a time across all its threads. Each thread has its own register state and can branch independently — when threads diverge, the warp serializes the branches.

## SIMT vs SIMD

| Aspect | SIMD | SIMT |
|--------|------|------|
| Control flow | All lanes must follow same path | Each thread can branch independently |
| Programming model | Explicit vector instructions | Scalar code, hardware handles parallelism |
| Branch handling | Must execute all branches | Hardware serializes divergent branches |
| Flexibility | Low — for regular data | High — for irregular tasks |

## Warp Size — Architecture-Dependent

| GPU | Architecture | Warp size |
|-----|--------------|-----------|
| MTT S5000 | MP31 | **32 threads** |
| MTT M1000, S4000 | MP21/MP22 | **128 threads** |

Use the `warpSize` built-in variable to query at runtime. Always pick block sizes that are multiples of `warpSize`.

## Warp Execution

```
┌─────────────────────────────────────┐
│ 1. Fetch (取指)                      │
│ 2. Decode (译码)                     │
│ 3. Execute (执行) - all threads     │
│ 4. Write-back (写回)                 │
└─────────────────────────────────────┘
```

A block of 256 threads on S5000 = 8 warps. The MP scheduler picks a ready warp to execute each cycle.

## Branch Divergence

When threads in a warp take different branches, the hardware **serializes** each path:

```cpp
// ❌ Divergent: both branches execute serially across the warp
if (threadIdx.x % 2 == 0) {
    data[idx] = data[idx] * 2.0f;   // path A: half the threads
} else {
    data[idx] = 0.0f;                // path B: other half
}
// Total time = path A time + path B time

// ✅ Branchless: all threads execute one instruction
float sign = (threadIdx.x % 2 == 0) ? 1.0f : 0.0f;
result = value * sign;
```

See [[warp-divergence]] for elimination techniques.

## Latency Hiding

GPU memory access latency is 100+ cycles; ALU ops are 1-4 cycles. To hide memory latency, the MP **switches to another ready warp** when the current one stalls:

```
Warp 0: [ALU] [ALU] [wait mem] [ALU] [ALU]
Warp 1: [ALU] [ALU] [ALU]        [ALU] [ALU]
Warp 2: [ALU] [ALU] [ALU]        [ALU] [wait mem]
Warp 3: [ALU] [wait mem] [ALU]   [ALU] [ALU]
```

This is why **occupancy** (active warps / max warps per MP) matters — see [[occupancy]].

## Synchronization Primitives

| Primitive | Scope | Purpose |
|-----------|-------|---------|
| `__syncthreads()` | Block | Barrier + memory fence |
| `__syncwarp(mask)` | Warp | Warp barrier |
| `__threadfence()` | System | Memory fence across device |
| `__threadfence_block()` | Block | Block-scoped fence |

See [[synchronization-primitives]].

## Warp-Level Primitives

- **Vote**: `__all_sync`, `__any_sync`, `__ballot_sync`, `__activemask`
- **Shuffle**: `__shfl_sync`, `__shfl_up_sync`, `__shfl_down_sync`, `__shfl_xor_sync`

See [[warp-functions]].

## Cross-References

- [[thread-hierarchy]] — how warps fit into blocks/grids
- [[warp-functions]] — vote + shuffle intrinsics
- [[warp-divergence]] — elimination techniques
- [[occupancy]] — why many active warps matter
- → raw: `programming_model_execution_model.md`
