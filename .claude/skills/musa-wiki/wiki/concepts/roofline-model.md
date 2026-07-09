---
title: "Roofline 模型"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_performance_bottleneck.md, performance_tuning_quickstart_optimization.md]
tags: [musa, roofline, performance, analysis, arithmetic-intensity]
---

# Roofline 模型 (Roofline Model)

The Roofline model is a **visual performance analysis** that shows whether a kernel is bound by compute, memory bandwidth, or neither. It plots achievable FLOPS/s against the kernel's **arithmetic intensity** (FLOPS per byte of memory traffic), bounded by the hardware's peak compute and peak bandwidth.

## Core Formula

```
Achievable FLOPS/s = min(Peak Compute, Arithmetic Intensity × Peak Bandwidth)
```

- **Arithmetic Intensity (AI)**: FLOPs / Bytes — how much compute per byte of memory accessed.
- **Peak Compute**: hardware FLOPS/s ceiling (FP32, FP16, Tensor Core, etc.).
- **Peak Bandwidth**: hardware memory bandwidth ceiling (DRAM, L2, shared).

## Visualizing the Roof

```
FLOPS/s
   ↑
   │            ┌──────────── Peak Compute (e.g. 30 TFLOPS FP16)
   │           /
   │          /
   │         /  ← Memory-bound region (slope = Peak BW)
   │        /
   │       /
   │      /
   │     /
   └─────┴────────────────────────→ Arithmetic Intensity (FLOPs/Byte)
        Ridge point
```

The "ridge point" is where the two ceilings cross: `AI_ridge = PeakCompute / PeakBandwidth`.

- If kernel's AI < `AI_ridge`: **memory-bound**.
- If kernel's AI > `AI_ridge`: **compute-bound**.

## Computing Arithmetic Intensity

For a kernel:

```
AI = total_FLOPs / total_bytes_moved
```

Count both numerator and denominator carefully:

| Pattern | FLOPs | Bytes (per element) |
|---------|-------|---------------------|
| `y[i] = a*x[i] + y[i]` (axpy) | 2 | 12 (3 reads/writes × 4B) |
| `y[i] += x[i]` (reduce) | 1 | 4 read + 4 write = 8 |
| `c[i] = a*b + c[i]` fused | 2 | 12 |
| GEMM `C[M,N] = A[M,K]*B[K,N]` | 2MNK | 4(MK+KN+MN) |

GEMM's AI ≈ `K / 2` (for large M, N) — grows with K, eventually compute-bound.

## Reading a Roofline Plot

Plot your kernel as a dot at `(AI, achieved_FLOPS/s)`. The dot's position tells you:

1. **Where it sits vs. the roof**: gap = headroom for optimization.
2. **Whether it's left or right of the ridge point**: memory- or compute-bound.
3. **Distance from ridge point**: how much you'd need to change AI to flip bottlenecks.

```
                    ●  ← left of ridge, low on slope = memory-bound, optimize traffic
                          ●  ← at ridge, near peak = well-optimized
                                      ●  ← right of ridge, below ceiling = compute-bound, optimize math
```

## Hardware Numbers (Indicative)

| GPU | Peak FP16 TC | Peak FP32 | Peak DRAM BW |
|-----|-------------|-----------|--------------|
| MTT S5000 (MP31) | ~160 TFLOPS | ~40 TFLOPS | ~1.2 TB/s |
| MTT M1000 (MP21) | ~10 TFLOPS | ~3 TFLOPS | ~256 GB/s |

> These are indicative — always query via `musaDeviceGetAttribute` and benchmark with `mcu`.

Ridge point (S5000 FP16 TC): `160 / 1.2 ≈ 133 FLOPs/Byte`. Anything with AI < 133 is memory-bound on Tensor Cores.

## Implications for Optimization

| Bottleneck | Optimize |
|------------|----------|
| Memory-bound (left of ridge) | Reduce traffic: tiling, data reuse, vectorized loads, shared mem, fewer passes |
| Compute-bound (right of ridge, below ceiling) | Use Tensor Cores, reduce wasted compute, increase ILP |
| At ridge, below peak | Latency hiding: more parallelism, occupancy |

## Common Pitfalls

| Mistake | Consequence |
|---------|-------------|
| Using DRAM BW when L2 hits dominate | Overestimates traffic — measure actual DRAM reads |
| Counting only reads, ignoring writes | Underestimates traffic by ~2x |
| Counting FLOPs without considering Tensor Core rates | Wrong ceiling |
| Comparing to peak compute that includes Tensor Cores when kernel uses FP32 | Wrong ceiling — pick the right one |
| Measuring on idle GPU vs. shared GPU | Bandwidth contention skews numbers |

## Tooling

- **`mcu`**: MUSA profiler. Reports achieved FLOPS/s, DRAM bytes, duration. AI = FLOPS/bytes derived.
- **`msys`**: System-level profiling, useful for multi-kernel roofline.
- **`muPTI`**: Low-level tracing, gives per-kernel counters.

## Cross-References

- [[occupancy]] — second-order concern once roofline gap is identified
- [[coalesced-access]] — reduces effective memory traffic
- [[gemm-optimization]] — canonical compute-bound workload
- [[reduction-patterns]] — canonical memory-bound workload
- → raw: `performance_tuning_performance_bottleneck.md`
