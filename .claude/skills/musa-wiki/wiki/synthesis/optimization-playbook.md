---
title: "MUSA 性能优化手册"
type: synthesis
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_quickstart_optimization.md, performance_tuning_performance_bottleneck.md, performance_tuning_compute_optimization.md, performance_tuning_memory_optimization.md, performance_tuning_reduction_optimization.md, performance_tuning_gemm_gemv_optimization.md, performance_tuning_flash_attention_optimization.md]
tags: [musa, optimization, performance, playbook, synthesis, methodology]
---

# MUSA 性能优化手册 (MUSA Performance Optimization Playbook)

A consolidated decision tree and methodology for optimizing MUSA kernels. Use this as a starting checklist when a kernel is slower than expected.

## The Optimization Loop

```
1. Profile end-to-end with msys
   ↓
2. Identify the slowest kernel(s)
   ↓
3. For each slow kernel, profile with mcu --detailed
   ↓
4. Plot on roofline: memory-bound or compute-bound?
   ↓
5. Apply targeted optimizations (see below)
   ↓
6. Re-measure, iterate
```

## Decision Tree

```
Is the kernel slow?
├── Yes — end-to-end msys shows it's a hotspot
│   ├── Run mcu --detailed
│   │   ├── Achieved occupancy < 50%? → See "Low Occupancy"
│   │   ├── Warp efficiency < 80%? → See "Warp Divergence"
│   │   ├── DRAM throughput < 60% peak? → See "Memory-Bound"
│   │   ├── L2 hit rate low? → See "Cache Misuse"
│   │   ├── TC utilization low (GEMM-like)? → See "Not Using Tensor Cores"
│   │   └── None of above → See "Latency Hiding"
│   └── Plot roofline
│       ├── Memory-bound (left of ridge) → See "Memory-Bound"
│       └── Compute-bound (right of ridge) → See "Compute-Bound"
└── No — focus elsewhere
```

## Low Occupancy

**Symptoms**: `achieved_occupancy < 0.5` in mcu.

**Causes & Fixes**:

| Cause | Diagnosis | Fix |
|-------|-----------|-----|
| Too many registers/thread | `--ptxas-options=-v` shows >64 regs | Add `__launch_bounds__(B, minBlocks)`; reduce per-thread arrays |
| Too much shared mem | Shared mem per block > 1/4 of SM | Reduce static shared mem; use dynamic |
| Block size doesn't divide SM | E.g. 1000 threads | Use 128/256/512 (multiples of warpSize) |
| Grid size too small | < # SMs | Use grid-stride loop with more blocks |

See [[occupancy]].

## Warp Divergence

**Symptoms**: `warp_execution_efficiency < 80%`.

**Causes & Fixes**:

| Cause | Fix |
|-------|-----|
| Branch on `threadIdx` or per-thread data | Reorganize data so warps are uniform |
| Variable-length loops | Bound uniformly, gate with `if` |
| Short if/else | Replace with predication |
| Early return | Usually fine — only one warp diverges |

See [[warp-divergence]].

## Memory-Bound

**Symptoms**: Kernel left of ridge point on roofline; DRAM throughput near peak but compute is low.

**Optimization Ladder** (in order of impact):

1. **Coalesce accesses** — see [[coalesced-access]]
   - Verify thread `i` reads `d[i]`, not `d[i*stride]`
   - Use `float4`/`int4` vectorized loads
   - Align data to 128 bytes

2. **Tile in shared memory** — reuse loaded data across threads
   ```cpp
   __shared__ float tile[BM][BK];
   // Load tile cooperatively, __syncthreads, reuse across threads
   ```

3. **Reduce redundant loads** — if the same data is read multiple times, cache it (shared mem or L2 persistence, see [[l2-cache-management]])

4. **Use `__ldg` for read-only** — routes through the read-only cache
   ```cpp
   float v = __ldg(&d[idx]);
   ```

5. **Fuse kernels** — if two kernels both read X, fuse them so X is loaded once
   ```cpp
   // ❌ Two kernels, X loaded twice
   kernel1<<<...>>>(X, Y);
   kernel2<<<...>>>(X, Z);
   // ✅ Fused, X loaded once
   fused<<<...>>>(X, Y, Z);
   ```

6. **SoA over AoS** — improves coalescing when accessing one field
   ```cpp
   // ❌ struct Point { float x, y, z; }; Point* p;
   // ✅ struct { float *x, *y, *z; } p;
   ```

See [[memory-hierarchy]], [[coalesced-access]], [[bank-conflicts]].

## Compute-Bound

**Symptoms**: Kernel right of ridge point; compute throughput near peak but memory is idle.

**Optimization Ladder**:

1. **Use Tensor Cores** for any matrix multiply (see [[tensor-cores]])
   ```cpp
   // Replace scalar FMA loop with mma_sync
   mma_sync(c_frag, a_frag, b_frag, c_frag);
   ```

2. **Use MUTLASS** for production GEMM (see [[mutlass]])
   - Tuned tile shapes, double buffering, fused epilogue

3. **Increase ILP** — multiple independent operations per thread
   ```cpp
   // ❌ Sequential dependencies
   a = b + c;
   d = a + e;
   f = d + g;
   // ✅ Independent (compiler can pipeline)
   x = a + b;
   y = c + d;
   z = e + f;
   ```

4. **Double buffering** — overlap next-tile load with current-tile compute (see [[double-buffering]])

5. **Reduce non-math work** — move conditionals out of inner loops, hoist invariants

6. **Use FP16/BF16** for storage where precision allows (also enables Tensor Cores)

See [[gemm-optimization]].

## Cache Misuse

**Symptoms**: L2 hit rate low; DRAM throughput high.

**Fixes**:

| Issue | Fix |
|-------|-----|
| Working set > L2 size | Tile the kernel to fit |
| Streaming access pattern (no reuse) | Expected — use streaming policy |
| Random access pattern | Sort data to improve locality |
| Want repeated reuse across kernels | L2 persistence (see [[l2-cache-management]]) |

## Not Using Tensor Cores

**Symptoms**: GEMM/conv kernel runs at FP32 throughput, well below TC peak.

**Fixes**:

1. Convert A, B to FP16/BF16
2. Use `mma_sync` for the inner kernel (or MUTLASS)
3. Verify tile shapes are TC-compatible (16×16×16, 32×8×16, etc.)
4. Match data layout to fragment type (row/column major)
5. Handle tail (M, N, K not multiple of tile) separately

See [[tensor-cores]], [[gemm-optimization]].

## Latency Hiding

**Symptoms**: Occupancy OK, no obvious bottleneck, but kernel still slow.

**Fixes**:

| Issue | Fix |
|-------|-----|
| Not enough parallelism per SM | Increase block size or grid-stride |
| Long memory latency | Double buffering, prefetching |
| Instruction dependencies | ILP, multiple independent accumulators |
| Sync overhead | Use `__syncwarp` instead of `__syncthreads` where possible |

## Workload-Specific Patterns

### Reduction

1. Each thread loads multiple elements (grid-stride loop)
2. Per-thread reduction in registers
3. Warp shuffle reduction
4. One atomic per block to global

See [[reduction-patterns]].

### GEMM

1. Shared memory tiling (BM × BN × BK)
2. Register tiling (each thread computes a small output tile)
3. Vectorized loads (`float4`)
4. Tensor Cores (`mma_sync`)
5. Double buffering
6. MUTLASS for production

See [[gemm-optimization]].

### GEMV

1. Row-major: each thread = one row (coalesced A, cached x)
2. Column-major: warp per column, shuffle reduction
3. Vectorized loads
4. muBLAS for production

See [[gemv-optimization]].

### Attention

1. Tiling — never materialize N×N matrix
2. Online softmax — incremental stats
3. Recompute P in backward (no materialization)
4. Tensor Cores for Q×K^T and P×V
5. muDNN's `ScaledDotProductAttention` for production

See [[flash-attention]].

## Profiling Checklist

Before declaring a kernel "optimized":

- [ ] `msys` confirms it's no longer the top hotspot
- [ ] `mcu --detailed` shows ≥ 50% occupancy
- [ ] Warp efficiency ≥ 80%
- [ ] DRAM throughput near peak (if memory-bound)
- [ ] TC utilization near peak (if GEMM-like)
- [ ] Roofline point is near the roof
- [ ] No spills (`--ptxas-options=-v` shows 0 spill stores)
- [ ] No bank conflicts (mcu reports 0)
- [ ] Compared against library equivalent (muBLAS for GEMM, etc.) — within 2× of library

## Common Anti-Patterns

| Anti-pattern | Why it's bad | Fix |
|---------------|--------------|-----|
| `atomicAdd` on global per element | Serializes everything | Block-local reduction, single atomic per block |
| Allocating in hot loop | `musaMalloc` is sync + slow | Pre-allocate, reuse buffers |
| `cudaMemcpy` (sync) inside stream loop | Blocks host, kills overlap | Use `musaMemcpyAsync` |
| Default stream everywhere | No overlap possible | Use explicit streams |
| Hardcoded `warpSize = 32` | Breaks on MP21/MP22 | Use `warpSize` built-in |
| `if (idx < n)` only at end | Tail warp divergence is OK; but `if (idx % 32 < n%32)` is worse | Use `if (idx < n)` |
| Materializing attention matrix | 64 MB per layer | Use FlashAttention |
| Not using `__launch_bounds__` when register-pressure matters | Compiler over-allocates | Add `__launch_bounds__` |

## Cross-References

- [[roofline-model]] — first analysis tool
- [[occupancy]] / [[warp-divergence]] / [[coalesced-access]] / [[bank-conflicts]] — fundamental limits
- [[tensor-cores]] / [[warp-shuffle]] — key primitives
- [[reduction-patterns]] / [[gemm-optimization]] / [[gemv-optimization]] / [[flash-attention]] — workload patterns
- [[moore-perf]] — measurement tools
- [[cuda-to-musa-mapping]] — porting from CUDA
- → raw: `performance_tuning_quickstart_optimization.md` and others
