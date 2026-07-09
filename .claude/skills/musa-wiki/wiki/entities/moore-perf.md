---
title: "Moore Perf / mcu / msys"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_perf_tools.md, performance_tuning_quickstart_optimization.md, toolkits_moore_perf.md]
tags: [musa, mcu, msys, moore-perf, profiling, tools]
---

# Moore Perf / mcu / msys

MUSA's profiling toolset: **mcu** (compute profiler), **msys** (system profiler), and **Moore Perf** (unified GUI). Together they provide kernel-level timing, hardware counter collection, and timeline visualization.

## mcu — Compute Profiler

Analogous to NVIDIA `nvprof`/`nsys compute`. Reports per-kernel metrics:

- Execution time (duration, average, min, max)
- Occupancy (achieved vs theoretical)
- Memory throughput (DRAM, L2, shared)
- Compute throughput (FP32, FP16 TC, INT8)
- Warp execution efficiency (divergence)
- Bank conflicts
- Roofline position

### Basic Usage

```bash
# Profile an entire run
mcu ./my_app

# Profile specific kernels (regex match)
mcu --kernel "regex:.*gemm.*" ./my_app

# Get detailed per-kernel report
mcu --detailed ./my_app

# Generate roofline plot data
mcu --roofline --csv ./my_app > roofline.csv
```

### Key Metrics

| Metric | What it tells you |
|--------|-------------------|
| `kernel_duration` | Total wall-clock time |
| `achieved_occupancy` | How many warps were active (0-1) |
| `dram_read_bytes` / `dram_write_bytes` | Actual DRAM traffic |
| `l2_hit_rate` | L2 cache effectiveness |
| `shared_mem_bank_conflicts` | Shared mem inefficiency |
| `warp_execution_efficiency` | Divergence measure |
| `sm_efficiency` | % of time SMs were active |
| `tc_utilization` | Tensor Core utilization (0-1) |

### Output Format

`mcu` produces tabular output by default. Use `--csv` for machine-parseable:

```csv
kernel,duration_ms,occupancy,dram_gb_s,fp32_tflops,tc_pct
gemm_kernel,2.34,0.78,850.2,18.5,72.0
reduce_kernel,0.45,0.92,650.0,2.1,0.0
```

## msys — System Profiler

Analogous to NVIDIA `nsys`. Captures a **timeline** of all GPU and related CPU activity:

- Kernel launches (with stream, grid, block info)
- Memory copies (H2D, D2H, D2D)
- Stream/event operations
- Driver/Runtime API calls
- CPU-side function calls (with `--cpu-profiling`)

### Basic Usage

```bash
# Capture timeline
msys profile -o timeline.msys-rep ./my_app

# View in GUI
moore-perf-gui timeline.msys-rep

# Generate text report
msys stats timeline.msys-rep
```

### Timeline Visualization

The GUI shows a Gantt-chart-style view:

```
Stream 0: [H2D 1ms][kernel A 5ms][kernel B 3ms][D2H 1ms]
Stream 1:          [H2D 0.8ms][kernel C 8ms]
                       ↑ overlaps with A — good!
```

Useful for:
- Identifying gaps where the GPU is idle
- Verifying stream overlap actually happens
- Debugging sync issues (kernels running serially when they should overlap)

### Common Stats

```
=== Statistics ===
Total duration:          1234.5 ms
Kernel time:              856.2 ms (69.4%)
Memory copies:            210.0 ms (17.0%)
Idle gaps:                168.3 ms (13.6%)

Top kernels by total time:
  1. gemm_kernel         450.2 ms (52.6% of kernel)
  2. conv_kernel         285.4 ms (33.3%)
  3. reduce_kernel        78.6 ms (9.2%)
```

## Moore Perf GUI

Unified front-end that loads both mcu and msys reports. Provides:
- Timeline view
- Kernel statistics table
- Roofline plot
- Memory chart
- Counter chart over time

```bash
moore-perf-gui report.msys-rep
```

## Profiling Workflow

The recommended optimization loop:

1. **Run `msys profile`** to get a timeline. Look for:
   - Long idle gaps (sync issues, allocation overhead)
   - Serial kernels that should overlap (use streams)
   - Kernels taking unexpectedly long

2. **For each slow kernel, run `mcu --detailed`**:
   - Check `achieved_occupancy` — is it ≥ 50%?
   - Check `warp_execution_efficiency` — divergence?
   - Check `dram_gb_s` vs peak bandwidth — memory-bound?
   - Check `tc_utilization` — using Tensor Cores?

3. **Plot roofline**: `mcu --roofline --csv` → import to spreadsheet.
   - Find each kernel's `(AI, achieved_FLOPS/s)` point.
   - Compare to the roofline — gap = optimization headroom.

4. **Iterate**: fix the most-impactful issue, re-measure.

## Hardware Counters

`mcu` can collect raw hardware counters:

```bash
mcu --events sm_inst_executed,shared_ld_bank_conflict --kernel "gemm" ./my_app
```

Useful counters:

| Counter | What |
|---------|------|
| `sm_inst_executed.sum` | Total instructions executed |
| `shared_ld_bank_conflict` / `shared_st_bank_conflict` | Bank conflicts |
| `l2_subp0_read_sector_hit_rate.pct` | L2 hit rate |
| `smsp__warp_issue_stalled_long_scoreboard_per_warp_active` | Memory stall cycles |
| `smsp__warp_issue_stalled_short_scoreboard_per_warp_active` | Pipeline stalls |

## Programmatic Profiling

For in-app profiling, use **muPTI** (Profiling Tools Interface) — see [[mupti]]. It allows subscribing to events at runtime, useful for tools like profilers or auto-tuners.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Profiling overhead skews results | Profile briefly, then validate without profiling |
| Averaging kernels with very different inputs | Group by similar size/shape |
| Focusing on absolute time | Focus on hardware utilization (occupancy, BW, FLOPS) |
| Ignoring memory copies | They often dominate end-to-end time |

## Cross-References

- [[mupti]] — programmatic profiling API
- [[roofline-model]] — mcu's roofline output
- [[occupancy]] — what mcu's occupancy metric means
- [[musa-sdk-stack]] — tooling layer
- → raw: `performance_tuning_perf_tools.md`
