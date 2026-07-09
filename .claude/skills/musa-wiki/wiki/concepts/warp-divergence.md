---
title: "Warp 分支发散"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [programming_model_execution_model.md, performance_tuning_compute_optimization.md]
tags: [musa, warp-divergence, branch, simt, control-flow]
---

# Warp 分支发散 (Warp Divergence)

In SIMT execution, all lanes in a warp execute the **same instruction** at the same time. When threads in the same warp take **different branches** of an `if/else`, the warp must serialize both paths — this is **warp divergence**, and it wastes cycles.

## How Divergence Works

```cpp
if (threadIdx.x < 16) {
    a();    // Path A — executed by lanes 0..15
} else {
    b();    // Path B — executed by lanes 16..31
}
```

Execution on hardware:

1. Lanes 0..15 are active; `a()` runs (lanes 16..31 are masked off).
2. Lanes 0..15 reach end of `if` block; they wait.
3. Lanes 16..31 become active; `b()` runs (lanes 0..15 masked off).
4. Both groups reconverge at the post-`if` instruction.

Total cycles = `cycles(a) + cycles(b)`, even though only half the lanes were doing useful work each time. **Worst case: 2× slowdown.**

## Three-Way and N-Way Divergence

```cpp
if (x % 3 == 0) pathA();
else if (x % 3 == 1) pathB();
else pathC();
```

Three divergent paths → up to 3× slowdown. Each branch is serialized.

## Reconvergence

Hardware reconverges warps at the **immediate post-dominator** of the branch — the point where all paths must pass through. The compiler determines this; usually it's right after the `if/else` block.

```cpp
if (cond) { f(); } else { g(); }
// Reconvergence happens here ↓
h();   // all lanes execute together again
```

To help the compiler, keep divergent code short and let it reconverge naturally — don't artificially extend divergent regions.

## Cost of Divergence

| Situation | Cost |
|-----------|------|
| `if (cond) return;` early exit | One path empty → only ~2× for the diverged lanes |
| `if/else` with both paths heavy | Up to 2× |
| Switch with N branches | Up to N× |
| Loop bound differs per lane (`for i in 0..N`) | Loop exits serialized — N × max_iter cycles |

## Loop Divergence — Subtle

```cpp
for (int i = 0; i < local_N; i++) {
    work(i);
}
```

If `local_N` varies per lane, lanes with smaller N finish early but the warp **stays in the loop** until the max-N lane completes. Result: idle lanes for many iterations.

Fix: bound the loop uniformly and skip work via `if`:

```cpp
for (int i = 0; i < MAX_N; i++) {
    if (i < local_N) work(i);
}
// Same total work, but warp reconverges each iteration
```

This is *not* always better — depends on how `work` is structured. Profile both.

## Patterns That Avoid Divergence

### 1. Predication (for short bodies)

```cpp
// Instead of branching, compute both and select
float a = f(x);
float b = g(x);
float result = (cond) ? a : b;
```

For very short bodies this avoids the divergence cost. The compiler does this automatically for short branches.

### 2. Data Reorganization

```cpp
// ❌ All threads in warp test different condition
if (data[threadIdx.x] > threshold) { ... }

// ✅ Sort/partition data so each warp sees uniform condition
// (preprocessing on host, or kernel-side sort)
```

### 3. Warp-Bound Work Partition

```cpp
// Process elements where each warp handles a contiguous chunk
int warpStart = (blockIdx.x * blockDim.x + threadIdx.x) / warpSize * warpSize;
// All lanes in warp process warpStart..warpStart+warpSize — uniform branches
```

### 4. Predicated Store

```cpp
// Instead of "if (cond) out[idx] = val", use:
if (idx < n) out[idx] = val;        // boundary check, divergence only at boundary
```

Boundary-checking `if (idx < n)` diverges only at the last warp — negligible cost.

## When Divergence is Fine

| Case | Why it's fine |
|------|---------------|
| Last warp of kernel with `if (idx < n)` | Only one warp diverges; rest of grid is uniform |
| `if (cond) return;` early exit | After return, lanes are masked off — no wasted work for them |
| `if (lane == 0) doSomething();` | Only one lane does work; common for warp leaders |

## Detecting Divergence

- **`mcu`**: reports warp execution efficiency. Low efficiency = divergence or low occupancy.
- Code review: any `if/else`, `switch`, or `for` with branch conditions depending on `threadIdx` or per-thread data is suspect.

## Reconvergence Control

Some MUSA versions support reconvergence control via `#pragma musa_reconvergence` or compiler flags — explicit hints about where to reconverge. Use only if `mcu` shows divergence as the bottleneck; the default heuristic is usually right.

## Cross-References

- [[simt-execution-model]] — why warps exist and how they execute
- [[warp-functions]] — `__ballot_sync` and `__shfl_*` are how diverged lanes communicate
- [[occupancy]] — divergence reduces effective occupancy
- → raw: `programming_model_execution_model.md`
