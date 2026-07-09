---
title: "Warp Shuffle"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [musa_cpp_syntax_warp_functions.md, performance_tuning_reduction_optimization.md, performance_tuning_compute_optimization.md]
tags: [musa, warp-shuffle, register-exchange, reduction, scan]
---

# Warp Shuffle

Warp shuffle is the **register-to-register exchange** primitive — lanes in a warp can read each other's registers directly, with no shared memory and no `__syncthreads()`. It is the fastest data exchange mechanism for warp-local data.

## The Four Shuffle Operations

```cpp
T __shfl_sync(mask, T var, int srcLane, int width = warpSize);        // copy from srcLane
T __shfl_up_sync(mask, T var, unsigned delta, int width = warpSize);  // from lane - delta
T __shfl_down_sync(mask, T var, unsigned delta, int width = warpSize); // from lane + delta
T __shfl_xor_sync(mask, T var, int laneMask, int width = warpSize);   // from lane ^ laneMask
```

| Operation | Use case |
|-----------|----------|
| `__shfl_sync` | Broadcast (e.g. lane 0 → all) |
| `__shfl_up_sync` | Prefix sum / scan |
| `__shfl_down_sync` | Tree reduction |
| `__shfl_xor_sync` | Butterfly exchange / reduction |

Supported types: `int`, `unsigned int`, `long`, `unsigned long`, `long long`, `unsigned long long`, `float`, `double`.

## Why Shuffle Beats Shared Memory

| Aspect | Shared memory | Shuffle |
|--------|---------------|---------|
| Memory traffic | Yes — load + store | No — register only |
| Latency | 1-2 cycles | ~1 cycle |
| Synchronization | `__syncthreads` or `__syncwarp` | Implicit (mask-based) |
| Capacity | 48-96 KB / block | Limited (warp-local only) |

For warp-local reductions, **always prefer shuffle**.

## The Mask

```cpp
const unsigned full_mask = 0xffffffff;
v = __shfl_down_sync(full_mask, v, 1);
```

The `mask` says which lanes participate. Each calling lane must set its own bit. Use `0xffffffff` for "all lanes in the warp" (typical case).

For partial warps:

```cpp
unsigned mask = (1u << n_active) - 1;       // first n_active lanes
v = __shfl_down_sync(mask, v, 1);
```

## Tree Reduction (Canonical Use)

```cpp
float v = my_value;
v += __shfl_down_sync(0xffffffff, v, 16);
v += __shfl_down_sync(0xffffffff, v, 8);
v += __shfl_down_sync(0xffffffff, v, 4);
v += __shfl_down_sync(0xffffffff, v, 2);
v += __shfl_down_sync(0xffffffff, v, 1);
// Lane 0 now has the sum of all 32 lanes' original v
```

After this, **only lane 0** has the result. To broadcast back:

```cpp
float sum = __shfl_sync(0xffffffff, v, 0);    // broadcast lane 0's v to all
```

On MP21/MP22 (warpSize = 128), add the missing steps:

```cpp
v += __shfl_down_sync(0xffffffff, v, 64);
v += __shfl_down_sync(0xffffffff, v, 32);
v += __shfl_down_sync(0xffffffff, v, 16);
// ... continue with 8, 4, 2, 1
```

## Inclusive Scan (Prefix Sum)

```cpp
float v = my_value;
float t;
t = __shfl_up_sync(0xffffffff, v, 1);   if (lane >= 1)  v += t;
t = __shfl_up_sync(0xffffffff, v, 2);   if (lane >= 2)  v += t;
t = __shfl_up_sync(0xffffffff, v, 4);   if (lane >= 4)  v += t;
t = __shfl_up_sync(0xffffffff, v, 8);   if (lane >= 8)  v += t;
t = __shfl_up_sync(0xffffffff, v, 16);  if (lane >= 16) v += t;
// Lane i now has prefix sum of lanes 0..i
```

## Butterfly Pattern (xor)

```cpp
// Each lane swaps with its neighbor (lane ^ 1)
float neighbor = __shfl_xor_sync(0xffffffff, v, 1);

// Reduction via xor — alternative to down-sync
for (int offset = warpSize/2; offset > 0; offset /= 2) {
    v += __shfl_xor_sync(0xffffffff, v, offset);
}
// All lanes have the sum (not just lane 0)
```

The xor variant produces the **same result on all lanes** — useful when every lane needs the reduced value.

## The `width` Parameter

Segments the warp into sub-groups. Must be a power of 2 and ≤ `warpSize`.

```cpp
// Shuffle within first 16 lanes (and last 16 separately)
v = __shfl_sync(0xffffffff, v, srcLane, 16);
```

- `srcLane` is interpreted **within the segment**.
- Useful for processing multiple smaller tiles per warp.

## Mask Consistency Rules

| Rule | Consequence if violated |
|------|--------------------------|
| Each calling lane sets its own bit in `mask` | Undefined behavior |
| All non-exited lanes in `mask` call same intrinsic with same mask | Undefined behavior |
| `width` is power of 2 and ≤ `warpSize` | Undefined behavior |

## Cross-Warp Reduction

Shuffle works **within a warp only**. For block-wide reduction:

```cpp
// 1. Each warp reduces internally via shuffle (above)
// 2. Lane 0 of each warp writes to shared memory
__shared__ float partials[warpsPerBlock];
if (lane == 0) partials[warpId] = v;
__syncthreads();

// 3. One warp reduces the partials
if (warpId == 0) {
    float p = (lane < warpsPerBlock) ? partials[lane] : 0.0f;
    p += __shfl_down_sync(0xffffffff, p, 16);
    // ... etc
    if (lane == 0) atomicAdd(output, p);     // single global atomic per block
}
```

See [[reduction-patterns]] for the full pattern.

## Cross-References

- [[warp-functions]] — full shuffle/vote API
- [[reduction-patterns]] — canonical use of shuffle
- [[atomic-functions]] — for cross-block reductions
- [[synchronization-primitives]] — when shuffle does NOT need explicit sync
- → raw: `musa_cpp_syntax_warp_functions.md`
