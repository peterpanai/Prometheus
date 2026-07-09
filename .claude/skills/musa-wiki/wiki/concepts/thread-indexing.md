---
title: "线程索引"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [programming_model_thread_indexing.md, programming_model_thread_hierarchy.md]
tags: [musa, indexing, thread-id, grid-stride-loop, coordinates]
---

# 线程索引 (Thread Indexing)

Every MUSA kernel starts with the same boilerplate: compute the thread's global index, then check bounds. Getting this right is the foundation of every kernel — and there are subtle traps around 2D/3D layouts, overflow, and grid-stride loops.

## Built-in Variables

| Variable | Type | Meaning |
|----------|------|---------|
| `threadIdx` | `dim3` | Thread index within block (x, y, z) |
| `blockIdx` | `dim3` | Block index within grid (x, y, z) |
| `blockDim` | `dim3` | Block dimensions (threads per block) |
| `gridDim` | `dim3` | Grid dimensions (blocks per grid) |
| `warpSize` | `int` | Warp size (32 on S5000, 128 on M1000/S4000) |

These are valid inside `__global__` and `__device__` functions only.

## 1D Indexing

```cpp
int idx = blockIdx.x * blockDim.x + threadIdx.x;
if (idx < n) {
    out[idx] = in[idx] * 2.0f;
}
```

Always check `idx < n` — the grid may have more threads than work (rounding up to block size).

## 2D Indexing (Row-Major)

```cpp
int x = blockIdx.x * blockDim.x + threadIdx.x;
int y = blockIdx.y * blockDim.y + threadIdx.y;
if (x < width && y < height) {
    int idx = y * width + x;          // row-major
    out[idx] = in[idx] * 2.0f;
}
```

Typical block size for image processing: `dim3(16, 16)` = 256 threads.

## 3D Indexing (Row-Major Depth-Last)

```cpp
int x = blockIdx.x * blockDim.x + threadIdx.x;
int y = blockIdx.y * blockDim.y + threadIdx.y;
int z = blockIdx.z * blockDim.z + threadIdx.z;
if (x < W && y < H && z < D) {
    int idx = (z * H + y) * W + x;
    out[idx] = in[idx] * 2.0f;
}
```

## Grid-Stride Loop (Many Elements Per Thread)

When `n` is much larger than `gridDim.x * blockDim.x`, use a grid-stride loop so each thread processes multiple elements:

```cpp
int tid = blockIdx.x * blockDim.x + threadIdx.x;
int stride = blockDim.x * gridDim.x;
for (int i = tid; i < n; i += stride) {
    out[i] = in[i] * 2.0f;
}
```

Benefits:
- Works for any `n` without recalculating grid size.
- Each thread does multiple iterations → better instruction-level parallelism.
- Cache-friendly: threads stay stride-aligned across iterations.

## Choosing Block and Grid Size

```cpp
int blockSize = 256;                            // typical
int gridSize = (n + blockSize - 1) / blockSize; // ceil div
kernel<<<gridSize, blockSize>>>(d, n);
```

For grid-stride loop, cap gridSize at a multiple of SM count:

```cpp
int numSMs;
musaDeviceGetAttribute(&numSMs, musaDevAttrMultiprocessorCount, device);
int gridSize = min((n + blockSize - 1) / blockSize, numSMs * 8);
// 8 blocks per SM gives enough work to fill the pipeline
```

## Overflow — Use 64-bit

`int` overflows around `2.1 × 10^9`. For arrays larger than that (e.g. >8 GB of floats):

```cpp
// ❌ Overflow for n > 2^31
int idx = blockIdx.x * blockDim.x + threadIdx.x;

// ✅ Use long long
long long idx = (long long)blockIdx.x * blockDim.x + threadIdx.x;
```

Or use `size_t` for full pointer-width safety.

## 2D Indexing Pitfall: Column vs Row

```cpp
// ❌ Wrong — indexing column-major but data is row-major
int idx = x * height + y;     // stride = height

// ✅ Correct — row-major
int idx = y * width + x;      // stride = width
```

If the data is column-major (e.g. Fortran-style), use the column-major form — but make sure **all kernels agree** on the layout.

## Multi-Dimensional Indexing for Higher Rank

For a 4D tensor `T[A][B][C][D]` accessed at `(a, b, c, d)`:

```cpp
int idx = ((a * B + b) * C + c) * D + d;
```

Generalize: each dimension multiplies the product of all lower dimensions.

## Sub-Block Tiling

When threads cooperate on a 2D tile but each thread processes multiple elements:

```cpp
// Each thread handles a TILE_X × TILE_Y region
const int TILE_X = 4, TILE_Y = 4;
int baseX = blockIdx.x * blockDim.x * TILE_X + threadIdx.x * TILE_X;
int baseY = blockIdx.y * blockDim.y * TILE_Y + threadIdx.y * TILE_Y;
for (int dy = 0; dy < TILE_Y; dy++) {
    for (int dx = 0; dx < TILE_X; dx++) {
        int x = baseX + dx, y = baseY + dy;
        if (x < W && y < H) out[y * W + x] = compute(in, x, y);
    }
}
```

## Linearized Block Index

Sometimes you need a flat block ID (e.g. for shared output buffer indexing):

```cpp
int blockId = blockIdx.x
            + blockIdx.y * gridDim.x
            + blockIdx.z * gridDim.x * gridDim.y;
```

## Indexing Cheatsheet

```
1D:        idx = blockIdx.x * blockDim.x + threadIdx.x

2D row:    x = blockIdx.x * blockDim.x + threadIdx.x
           y = blockIdx.y * blockDim.y + threadIdx.y
           idx = y * width + x

3D row:    idx = (z * height + y) * width + x

Grid-stride:
           tid = blockIdx.x * blockDim.x + threadIdx.x
           for (i = tid; i < n; i += blockDim.x * gridDim.x)

Linear block ID:
           blockId = blockIdx.x + blockIdx.y * gridDim.x
                            + blockIdx.z * gridDim.x * gridDim.y
```

## Cross-References

- [[thread-hierarchy]] — what grid/block mean
- [[kernel-launch-syntax]] — passing `dim3` to `<<<>>>`
- [[coalesced-access]] — indexing affects memory access patterns
- → raw: `programming_model_thread_indexing.md`
