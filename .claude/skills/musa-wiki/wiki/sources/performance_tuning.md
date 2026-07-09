---
title: "性能优化 — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources:
  - performance_tuning.md
  - performance_tuning_quickstart_optimization.md
  - performance_tuning_performance_bottleneck.md
  - performance_tuning_perf_tools.md
  - performance_tuning_compute_optimization.md
  - performance_tuning_memory_optimization.md
  - performance_tuning_reduction_optimization.md
  - performance_tuning_gemm_gemv_optimization.md
  - performance_tuning_flash_attention_optimization.md
tags: [musa, performance, optimization, profiling, roofline, occupancy, gemm, flash-attention]
---

# 性能优化 (Performance Tuning)

The performance tuning chapter is the largest in the MUSA programming guide. It covers the **profiling methodology**, **bottleneck classification**, **optimization techniques** (compute, memory, reduction), and **workload-specific playbooks** (GEMM/GEMV, FlashAttention).

The unifying mental model is the **Roofline model**: plot achievable FLOP/s vs. arithmetic intensity (FLOP/Byte). The ridge point separates memory-bound (left) from compute-bound (right) kernels. Different bottlenecks need different fixes.

## Source Pages

| Raw File | Title | Covers |
|----------|-------|--------|
| `performance_tuning.md` | 性能优化 | Chapter index |
| `performance_tuning_quickstart_optimization.md` | 快速开始 | Roofline, decision tree, occupancy checklist, compile flags |
| `performance_tuning_performance_bottleneck.md` | 性能瓶颈分析 | 4 bottleneck types, MP eff vs mem throughput matrix, sync analysis |
| `performance_tuning_perf_tools.md` | 性能分析工具 | `mcu`, `msys`, muPTI Profiler API, metric meanings |
| `performance_tuning_compute_optimization.md` | 计算优化 | Occupancy dialectics, ILP, warp divergence, warp specialization, Tensor Cores |
| `performance_tuning_memory_optimization.md` | 内存优化 | Coalescing, vectorized loads, bank conflicts, AoS vs SoA, shared mem tiling |
| `performance_tuning_reduction_optimization.md` | 归约算法优化 | Two-stage reduction, warp shuffle, vectorized load, single-kernel reduction |
| `performance_tuning_gemm_gemv_optimization.md` | GEMM/GEMV 优化 | Tiling, register tiles, double buffering, Tensor Cores, MUTLASS |
| `performance_tuning_flash_attention_optimization.md` | FlashAttention 优化 | Tiling, online softmax, recomputation, double buffering, TME |

---

## A. Profiling Methodology

### A.1 Roofline Model

**Arithmetic Intensity** = FLOP / Byte. The Roofline plots achievable FLOP/s vs. intensity; the ridge point separates memory-bound (left) from compute-bound (right).

- Memory-bound (left of ridge): increase arithmetic intensity via shared memory, data reuse, coalesced access.
- Compute-bound (right of ridge): reduce FLOPs, use lower precision (FP16, INT8), or Tensor Cores.

Diagnostic shortcut: compare your kernel to `mublasSgemm` (reference compute-bound kernel).

Compile command for profiling:
```bash
mcc --offload-arch=mp_31 -O2 app.mu -lmusart -L/usr/local/musa/lib -o app
```
`-O2` is officially recommended. `mp_31` = MTT S5000 target.

### A.2 Bottleneck Classification

| Bottleneck | Diagnostic signature | Fix |
|------------|----------------------|-----|
| **Compute** | MP eff > 80%, mem throughput < 50% peak, high arithmetic intensity | Tensor Cores, algorithmic improvements |
| **Memory** | Mem throughput near peak, MP eff ≤ 60%, L2 miss rate high, intensity ≤ 10 FLOP/Byte | Coalesce access, shared memory caching |
| **Latency** | Low warps/MP, achieved occupancy < 30%, high branch divergence | Increase parallelism, reduce divergence |
| **Sync** | Low stream utilization, frequent `__syncthreads()`, GPU-CPU stalls | Async ops, reduce syncs |

**Decision tree** (key heuristic):

| MP efficiency | Mem throughput | Diagnosis |
|---------------|----------------|-----------|
| > 80% | > 80% | Compute-bound |
| > 80% | < 80% | Latency-bound |
| < 80% | > 80% | Memory-bound |
| < 80% | < 80% | Occupancy insufficient |

### A.3 Profiling Tools

**`mcu` (Moore Compute Utility)** — kernel-level profiler (analog of `ncu`):
```bash
mcu -o report ./application                                   # basic
mcu -k vectorAdd -o report ./application                      # filter by kernel
mcu --metrics sm_efficiency,gld_throughput,gst_throughput -o report ./app
mcu --metrics sm__achieved_occupancy.pct ./app                # occupancy
mcu --metrics sm__average_warp_execution_efficiency ./app     # divergence
mcu --metrics shared_mem_efficiency -o report ./app           # bank conflicts
```

| Metric | Meaning |
|--------|---------|
| `kernel_runtime` | Kernel execution time |
| `gld_throughput` / `gst_throughput` | Global mem load/store bandwidth |
| `sm_efficiency` | % time MPs have at least one active warp |
| `sm__throughput.avg.pct_of_peak_sustained` | MP throughput vs. peak |
| `sm__achieved_occupancy.pct` | Achieved occupancy |
| `sm__average_warp_execution_efficiency` | Active lanes per warp (< 80% suggests divergence) |
| `shared_mem_efficiency` | Shared mem bank conflict rate |
| `warp_execution_efficiency` | Warp divergence measure |

**`msys` (Moore Perf System)** — system-level timeline:
```bash
msys -t musa --gpu-metrics-set=0 -o timeline ./application
msys -t musa --kernel-exec -o kernel_report ./application
msys-ui report.msys-rep   # GUI viewer
```

**`mu-info`** — device property dump.

**muPTI Profiler API** — programmatic profiling via `<mupti.h>`. Lifecycle: `muptiProfilerInitialize` → `BeginSession` → `SetConfig` → `EnableProfiling` → run → `DisableProfiling` → `EndSession` → `DeInitialize`.

### A.4 Occupancy APIs

```cpp
int minGridSize, blockSize;
musaOccupancyMaxPotentialBlockSize(&minGridSize, &blockSize, myKernel, 0, 0);

int numBlocks;
musaOccupancyMaxActiveBlocksPerMultiprocessor(&numBlocks, kernel, 256, 0);
```

Peak bandwidth formula: `peakGBs = (memClockKHz/1000) * (memBusWidth/8) * 2` (DDR factor).

---

## B. Compute Optimization

### B.1 Four Core Principles

1. **Dialectical view of occupancy** — high occupancy ≠ high performance.
2. **Maximize ILP** — hide latency, keep compute units busy.
3. **Eliminate warp divergence** — uniform control flow within a warp.
4. **Warp specialization** — pipeline parallelism via producer/consumer warps.

### B.2 Occupancy — Dialectical View

Occupancy = active warps per MP / max warps per MP. Limited by **registers per thread** and **shared memory per block**.

| App type | Strategy | Reason |
|----------|----------|--------|
| Memory-bound | High occupancy | Convert latency-bound to bandwidth-bound via high memory concurrency |
| Compute-bound | Low occupancy OK | Sufficient ILP keeps units busy; pushing occupancy reduces per-thread resources |

Example: matmul with `tile[8][8]` (high occ) underperforms `tile[32][32]` (low occ, high compute/memory ratio).

Target: **> 50%** baseline. Block size: **128, 256, 512, 1024** (multiples of warp size); sweet spot **256–1024**; cap shared memory per block at **~48 KB**.

### B.3 Warp Divergence Elimination

A warp shares one PC; divergent branches serialize. Elimination techniques:
- **Ternary expression** over `if-else` — compiler emits predicated instruction.
- **Restructure index test** to `tid < N` instead of `tid % N == 0`.
- **Align loop boundaries** to warp size.

```cpp
// ❌ divergent: tid % (2*stride) == 0
for (int stride = 1; stride < 8; stride *= 2) {
    if (tid % (2 * stride) == 0) smem[tid] += smem[tid + stride];
    __syncthreads();
}
// ✅ uniform within warp: tid < stride
for (int stride = 4; stride > 0; stride /= 2) {
    if (tid < stride) smem[tid] += smem[tid + stride];
    __syncthreads();
}
```

### B.4 Instruction-Level Parallelism (ILP)

GPU pipeline: `取指 → 译码 → 发射 → 执行 → 写回`. Main hazard: **RAW** from long-latency loads.

Strategies:
- **Interleave independent instructions** between dependent ones (multiple loads before first use).
- **Loop unrolling** (`#pragma unroll`) — fully unroll GEMM inner loop to expose independent FMAs.
- **Software pipelining / double buffering**: prefetch next tile while computing current.
- **Vectorized loads** (`float4`, 16B per instruction).
- **Register reuse**: keep data in registers across iterations.

Tradeoff: unrolling increases register pressure (may lower occupancy) and code size (potential ICache miss).

### B.5 Warp Specialization (线程束专用化)

Assigns warps to roles (producer for data movement, consumer for compute). Hardware support on S5000:

| Feature | Purpose | S5000 |
|---------|---------|-------|
| **TME (Tensor Memory Engine)** | Async data movement | Yes |
| **Async Barrier** | Flexible sync (acquire/release/wait) | Yes |
| **Register reconfiguration** | Dynamic register allocation | Future |

Pattern: producer `barrier_acquire()` → `tme_async_copy()` → `barrier_release()`; consumer `barrier_wait()` → compute → `barrier_release()`.

### B.6 Tensor Cores (wmma)

`#include <musa_tensor.h>`. Fragments: `matrix_a`, `matrix_b`, `accumulator`. APIs: `load_matrix_sync`, `store_matrix_sync`, `mma_sync`, `fill_fragment`. Common tile: 16×16×16, half inputs, float accumulator.

### B.7 Matmul Optimization Progression (case study)

| Version | Occupancy | ILP | Relative |
|---------|-----------|-----|----------|
| Naive (no shared mem) | 100% | 1× | 1.0× |
| Shared-mem tiling 32×32 | 50% | 1× | 3.5× |
| + `#pragma unroll` 4 accumulators | 50% | 4× | 8.2× |

---

## C. Memory Optimization

### C.1 Three Core Principles

1. Maximize global mem bandwidth (coalesce + vectorize)
2. Minimize global mem accesses (shared mem cache, register reuse)
3. Avoid shared-mem bank conflicts (padding or swizzle)

### C.2 Coalesced Access

S5000 mechanism: 32-thread warp → merge unit groups 4 or 8 threads → aggregate into **128B transactions** (L2 cache line size).

| Access pattern | Transactions | Bandwidth util |
|----------------|--------------|----------------|
| 32 contiguous addresses | 1 | 100% |
| Stride 2 | 2 | 50% |
| Stride 4 | 4 | 25% |
| Random | 32 | ~3% |

### C.3 Vectorized Loads

S5000 supports up to **1024-bit** per instruction; **128-bit `float4` is recommended**.

| Type | Bits/instr | Use |
|------|-----------|-----|
| `float` | 32 | Basic |
| `float2` | 64 | Small vectors |
| `float4` | 128 | **Recommended** |
| `int4` | 128 | INT8 quantization |

```cpp
float4 v = ((float4*)in)[idx];   // one instruction loads 4 floats
v.x *= 2.0f; v.y *= 2.0f; v.z *= 2.0f; v.w *= 2.0f;
((float4*)out)[idx] = v;
```

### C.4 Bank Conflicts

Shared memory: **32 banks**, **4 bytes wide**. Same-bank-different-address → serialization. Same-bank-same-address → broadcast (free).

```cpp
// ❌ 32-way conflict: all threads read column 0 → all bank 0
__shared__ float matrix[32][32];
float v = matrix[threadIdx.x][0];

// ✅ padding: 32×33 breaks alignment
__shared__ float matrix[32][33];
float v = matrix[threadIdx.x][0];
```

Padding cost: 32×32→32×33 wastes 128B (3.1%).

**Swizzle (hardware)**: S5000 supports address-hash remap. No manual padding needed when compiler detects the pattern.

### C.5 AoS vs SoA

| Layout | Bandwidth util | Use when |
|--------|----------------|----------|
| **AoS** | Often low — loading whole struct when only one field needed | All fields used together |
| **SoA** | High — only load needed component | Selective access, vectorization |

### C.6 Shared Memory Tiling

Standard matmul tile pattern (16×16):
```cpp
__shared__ float tileA[16][16], tileB[16][16];
for (int t = 0; t < (N + 15) / 16; t++) {
    tileA[ty][tx] = A[row * N + t*16 + tx];     // coalesced
    tileB[ty][tx] = B[(t*16 + ty) * N + col];
    __syncthreads();
    for (int k = 0; k < 16; k++)
        sum += tileA[ty][k] * tileB[k][tx];
    __syncthreads();
}
```

### C.7 Case Study: Vector Add

- Slow version: scalar, 25% bandwidth.
- Fast version: `float4` + bounds check, **100% bandwidth, 3.8× speedup**.

---

## D. Reduction Optimization

### D.1 Two-Stage Reduction (基础实现)

**Phase 1**: each block reduces its slice into `out_partial[bid]`.
**Phase 2**: launch with one block to reduce partials into final.

```cpp
template<int THREAD_PER_BLOCK>
__global__ void ReduceLarge(float* in, float* out_partial, int num_ele) {
    __shared__ float sdata[THREAD_PER_BLOCK];
    unsigned int tid = threadIdx.x, bid = blockIdx.x;
    sdata[tid] = in[bid * THREAD_PER_BLOCK + tid];
    __syncthreads();
    for (int s = THREAD_PER_BLOCK / 2; s >= 2; s >>= 1) {
        if (tid < s) sdata[tid] += sdata[tid + s];
        __syncthreads();
    }
    if (tid == 0) out_partial[bid] = sdata[0] + sdata[1];  // handle final 2
}
```

### D.2 Warp Shuffle Reduction

`__shfl_down_sync(0xffffffff, val, offset)` exchanges register values directly — no shared memory, no `__syncthreads()` within a warp. 5 shuffles (offset 16, 8, 4, 2, 1) reduce 32 lanes.

```cpp
template<int blockSize>
__device__ __forceinline__ void WarpReduce(float& rv1) {
    if constexpr (blockSize >= 32) rv1 += __shfl_down_sync(0xffffffff, rv1, 16);
    if constexpr (blockSize >= 16) rv1 += __shfl_down_sync(0xffffffff, rv1, 8);
    if constexpr (blockSize >= 8)  rv1 += __shfl_down_sync(0xffffffff, rv1, 4);
    if constexpr (blockSize >= 4)  rv1 += __shfl_down_sync(0xffffffff, rv1, 2);
    if constexpr (blockSize >= 2)  rv1 += __shfl_down_sync(0xffffffff, rv1, 1);
}
```

### D.3 Vectorized Load (VL=4)

Each thread accumulates 4 elements via `float4` grid-stride loop, then participates in block reduction. Reduces block count, fewer global-mem instructions, better bandwidth.

### D.4 Single-Kernel Reduction

Uses `__threadfence()` + global semaphore + `atomicAdd` to detect "last block", which performs the final cross-block reduction itself. Eliminates one kernel-launch overhead and one global-mem round trip.

```cpp
__global__ void ReduceInOne(float* in, float* out_partial, float* out,
                            int num_ele, uint32_t* semaphores) {
    // ... block-level reduction ...
    if (tid == 0) out_partial[bid] = sdata[0] + sdata[1];
    __threadfence();  // make writes visible to other blocks
    __syncthreads();
    if (tid == 0) {
        uint32_t prev = atomicAdd(&semaphores[bid], 1);
        is_last_block_done_shared = (prev == block_num - 1);
    }
    __syncthreads();
    if (is_last_block_done_shared) {
        // re-reduce out_partial[] and write out[0]
    }
}
```

### D.5 Strategy Selection

| Data size | Strategy |
|-----------|----------|
| < 4096 | Single block, single kernel |
| 4096–65536 | Two-stage + warp shuffle |
| > 65536 | Two-stage + vectorized load |
| > 10⁷ | Multi-kernel + semaphore (avoid single-block bottleneck) |

### D.6 Performance Data (vs naive serial)

| Implementation | 1024 | 40960 | 10⁷ |
|----------------|------|-------|-----|
| Naive serial | 1.0× | 1.0× | 1.0× |
| Two-stage base | 3.5× | 8.2× | 15.3× |
| + Warp shuffle | 4.2× | 10.5× | 18.7× |
| + Vector load | 4.5× | 12.3× | 22.1× |
| Single-kernel | 5.1× | 9.8× | — |

---

## E. GEMM / GEMV Optimization

### E.1 Roofline Positioning

- **GEMV** (y = A·x): arithmetic intensity ≈ 0.5 FLOP/Byte → **memory-bandwidth-bound**. Optimize coalesced loads, vectorized (float4) transactions, shared-mem caching of x.
- **GEMM** (C = A×B): arithmetic intensity ≫ 1 → **compute-bound**. Optimize tiling, register tiles, double buffering, Tensor Cores.

### E.2 GEMM Optimization Ladder

| Stage | Technique | Effect |
|-------|-----------|--------|
| 1. Naive | One thread per output, all global mem | Baseline |
| 2. Shared-mem tiling | Cooperative load of A/B sub-tiles | ~16× fewer global loads |
| 3. Register tile | Each thread computes 8×8 or 16×16 sub-tile | Higher compute/memory ratio |
| 4. Loop unroll | `#pragma unroll` K-dim inner loop | More ILP |
| 5. Double buffering | K_BLOCK_MAX-stage pipeline, overlap gmem loads | Hides gmem→smem latency |
| 6. Tensor Core MMA | `mma.sync` / MUTLASS `gemm()` | Order-of-magnitude FLOPS/s |

### E.3 Tile Sizes

| Parameter | Typical | Constraint |
|-----------|---------|------------|
| TILE_M | 64–256 | shared mem capacity |
| TILE_N | 64–256 | shared mem capacity |
| TILE_K | 8–32 | shared mem capacity |
| THREAD_M | 8–16 | register count |
| THREAD_N | 8–16 | register count |

For Tensor Core GEMM: all tile dims must be multiples of 16; addresses 16-byte aligned. Typical start: `128 × 64 × 32`.

### E.4 GEMV Pattern (vectorized + shared-mem x cache)

```cpp
__device__ float warpReduceSum(float v) {
    for (int o = 16; o > 0; o >>= 1)
        v += __shfl_down_sync(0xffffffff, v, o);
    return v;
}

__global__ void gemv(float* A, float* x, float* y, int m, int k) {
    constexpr int TILE_V = 256;
    __shared__ float x_shared[TILE_V];
    int warp_id = threadIdx.x / 32, lane = threadIdx.x % 32;
    int warps = blockDim.x / 32, row = blockIdx.x * warps + warp_id;
    if (row >= m) return;

    float partial = 0.0f;
    int num_tiles = (k + TILE_V - 1) / TILE_V;
    for (int t = 0; t < num_tiles; t++) {
        int xi = t * TILE_V + threadIdx.x;
        if (threadIdx.x < TILE_V) x_shared[threadIdx.x] = (xi < k) ? x[xi] : 0.0f;
        __syncthreads();
        int base = row * k + t * TILE_V;
        for (int j = lane * 4; j < TILE_V; j += 32 * 4) {
            float4 a = *reinterpret_cast<float4*>(&A[base + j]);
            float4 b = *reinterpret_cast<float4*>(&x_shared[j]);
            partial += a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
        }
        __syncthreads();
    }
    partial = warpReduceSum(partial);
    if (lane == 0) y[row] = partial;
}
```

### E.5 MUTLASS

MUTLASS is MUSA's header-only GEMM library (analog of CUTLASS). Provides two-stage mainloop with double buffering via `for_each(make_int_sequence<K_BLOCK_MAX>{})` and `MUTLASS_PRAGMA_NO_UNROLL`. Building blocks: `tCrA`, `tCsA`, `tAgA` (gmem/smem/rmem tiles), `tiled_mma`, `gmem_tiled_copy_a/b`, `tApA`/`tBpA` (predicates), `mute::transform`, `mute::gemm`.

**Recommendation**: use MUTLASS for production Tensor Core GEMM rather than hand-rolled MMA.

---

## F. FlashAttention Optimization

### F.1 What & Why

FlashAttention is an IO-aware attention algorithm that achieves the same result as standard attention while avoiding the O(N²) memory footprint of the full attention matrix. Core strategy: tile Q/K/V into blocks that fit in on-chip SRAM, fuse matmul + online softmax + output accumulation inside each block, and recompute attention scores in the backward pass instead of materializing them.

### F.2 Key Concepts

| Concept | Meaning |
|---------|---------|
| **Tiling (分块)** | Decompose Q/K/V along sequence dim into blocks (Br × d for K/V, Bc × d for Q) fitting in shared mem |
| **Online softmax (在线 Softmax)** | Single-pass streaming softmax with running max `m_j` and running denominator `ℓ_j`; eliminates global dependency |
| **Recomputation (重计算)** | Backward pass recomputes S/P from Q/K/V in SRAM rather than storing N×N matrix |
| **Safe softmax** | Subtract running max before exponentiating to prevent overflow |
| **Rescaling trick** | When `m_i → m_new`, scale previous O and ℓ by `exp(m - m_new)` for numerical consistency |

### F.3 Optimization Techniques

| Technique | What it does | When to apply |
|-----------|--------------|---------------|
| Block tiling (Bc, Br) | Splits S, P, O tiles to fit SRAM | Always; foundation |
| Online softmax | Fuses max + sum + divide into one streaming pass | Always; replaces 3-pass softmax |
| Recomputation | Recompute S/P in backward | Backward when memory-bound |
| Double buffering | Two shared-mem buffers alternate load/compute | Main K/V loop |
| Software pipelining | Issue load for next K/V block while computing current | Large N |
| TME (Tensor Memory Engine) | Async gmem→smem via hardware DMA | When available (S5000+) |
| Pre-compute QK | Compute first QK while loading K0,V0 | First iteration of main loop |
| Register accumulator for O | Keep Bc×d output in registers across all K/V tiles | Always |
| Reduce Br to lower register pressure | Trade SRAM occupancy for fewer registers | When compiler reports spills |
| FP32 accumulator | Use float32 for O and ℓ accumulation | Recommended |

### F.4 Tile Size Recommendations (MP31 / S5000, d=128, FP16)

| Head dim d | Bc (Q block) | Br (K/V block) | SRAM |
|------------|--------------|----------------|------|
| 64 | 512 | 256 | ~128KB |
| 128 | 256 | 128 | ~128KB |
| 256 | 128 | 64 | ~128KB |

Rule of thumb: keep shared-memory use under ~90% to leave headroom for double buffers and online-softmax state.

### F.5 Memory Reduction

| Sequence length N | Standard Attention | FlashAttention | Reduction |
|-------------------|--------------------|----------------|-----------|
| 512 | 4MB | 0.5MB | 8× |
| 2048 | 68MB | 2MB | 34× |
| 4096 | 268MB | 4MB | 67× |
| 16384 | 4.3GB | 16MB | 268× |

### F.6 Core Code Pattern

```cpp
template<int Bc, int Br, int d>
__global__ void flashAttention(half* Q, half* K, half* V, half* O, int N) {
    __shared__ float Q_shared[Bc][d], K_shared[Br][d], V_shared[Br][d];
    float m_i = -INFINITY, ell_i = 0.0f;
    float O_accum[Bc][d] = {0};

    loadQBlock(Q, blockIdx.x, blockIdx.y, Q_shared);
    __syncthreads();

    for (int j = 0; j < (N + Br - 1) / Br; j++) {
        loadKVBlock(K, V, j, K_shared, V_shared);   // async / TME
        __syncthreads();

        float S[Bc][Br];
        computeS(Q_shared, K_shared, S);

        // Online softmax update
        float m_new = m_i;
        for (int i = 0; i < Bc; i++)
            for (int jj = 0; jj < Br; jj++)
                m_new = fmaxf(m_new, S[i][jj]);

        float scale = __expf(m_i - m_new);
        ell_i *= scale;
        float P[Bc][Br];
        for (int i = 0; i < Bc; i++)
            for (int jj = 0; jj < Br; jj++) {
                P[i][jj] = __expf(S[i][jj] - m_new);
                ell_i += P[i][jj];
            }

        updateO(O_accum, P, V_shared, scale);
        m_i = m_new;
        __syncthreads();
    }

    for (int i = 0; i < Bc; i++)
        for (int j = 0; j < d; j++)
            O_accum[i][j] /= ell_i;
    storeOBlock(O, blockIdx.x, blockIdx.y, O_accum);
}
```

---

## Cross-References

- **Concept pages**: [[roofline-model]], [[occupancy]], [[warp-divergence]], [[coalesced-access]], [[bank-conflicts]], [[tensor-cores]], [[warp-shuffle]], [[reduction-patterns]], [[double-buffering]], [[online-softmax]]
- **Workload playbooks**: [[gemm-optimization]], [[gemv-optimization]], [[flash-attention]], [[reduction-optimization]]
- **Source chapters**: [[programming-model]] (the abstractions being optimized), [[musa-cpp-syntax]] (the intrinsics used)
- **Entity pages**: [[mcu-profiler]], [[msys-profiler]], [[mupti]], [[mcc-compiler]] (compile flags), [[mutlass]], [[mublas]]
