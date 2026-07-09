---
title: "Bank 冲突"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_memory_optimization.md, programming_model_memory_hierarchy.md]
tags: [musa, shared-memory, bank-conflict, memory-bank]
---

# Bank 冲突 (Bank Conflicts)

Shared memory is divided into **banks** that can be accessed in parallel. When multiple threads in a warp access the **same bank** in the same transaction, the accesses are serialized — a **bank conflict**. Bank conflicts are the shared-memory analog of uncoalesced global memory access.

## Bank Layout

- **32 banks** (on MP31 / MTT S5000; same as CUDA).
- Each bank is **4 bytes wide**.
- Successive 4-byte words are striped across banks:

```
Address:   0    4    8    12   16   ... 124
Bank:      0    1    2    3    4    ... 31
Address:   128  132  136  140  144  ... 252
Bank:      0    1    2    3    4    ... 31
```

> On MP21/MP22 (warpSize = 128), the bank count may be larger. Always query via `musaDeviceGetAttribute(musaDevAttrSharedMemoryBanks, ...)`.

## Three Cases

| Pattern | Effect | Cost |
|---------|--------|------|
| Different banks | All parallel | 1 transaction |
| Same bank, same address | **Broadcast** (free) | 1 transaction |
| Same bank, different addresses | **Conflict** — serialized | N transactions |

### Broadcast (free)

```cpp
__shared__ float s[32];
float v = s[0];          // All threads read s[0] → bank 0 broadcasts to all
```

### 2-way Conflict

```cpp
__shared__ float s[32];
// Thread 0 reads s[0] (bank 0), thread 16 reads s[1] (bank 0)... wait, no.
// Pattern: thread i reads s[i % 16] — two threads per bank
```

### 32-way Conflict (Worst)

```cpp
__shared__ float m[32][32];
float v = m[threadIdx.x][0];     // All threads hit column 0 → all bank 0
// 32-way conflict → 32× slower
```

## Diagnosing with Padding

The classic fix is to **pad** the array so the conflicting column moves to a different bank:

```cpp
// ❌ 32-way conflict
__shared__ float m[32][32];
v = m[threadIdx.x][0];

// ✅ Padding breaks the alignment
__shared__ float m[32][33];      // 33 columns — bank for column 0 varies by row
v = m[threadIdx.x][0];
// Row 0, col 0 → bank 0
// Row 1, col 0 → bank 33 % 32 = 1
// Row 2, col 0 → bank 66 % 32 = 2
// ...
```

The cost: 1 wasted float per row (32 × 4 = 128 bytes total). Usually worth it.

## Common Conflict Patterns

### Transpose

```cpp
// Reading row-wise, writing column-wise
__shared__ float tile[32][32];

// Read: coalesced in shared mem (no conflict)
float v = tile[row][threadIdx.x];

// Write: column access — all threads write to same column → conflict!
tile[threadIdx.x][col] = v;
```

Fix: pad to `[32][33]`.

### Histogram-style Update

```cpp
__shared__ int hist[256];
// If multiple threads increment the same bin, atomicAdd serializes anyway — but
// even different bins can conflict if they fall on the same bank (bin%32 == same).
atomicAdd(&hist[bin], 1);
```

Fix: privatize histograms per warp (each warp has its own `hist[256]`), then merge.

### Stencil Access

```cpp
__shared__ float tile[32][32];
// Each thread reads its own cell + 4 neighbors
float c = tile[y][x];
float u = tile[y-1][x];   // bank conflict? depends on y pattern
float d = tile[y+1][x];
float l = tile[y][x-1];
float r = tile[y][x+1];
```

If thread `i` corresponds to `(y, x) = (i/32, i%32)`, the up/down reads hit `(y-1, x)` and `(y+1, x)`. For each column x, threads in different rows access the same bank → conflict.

Fix: pad to `[33][32]` (rows are the slow index).

## Multiple Conflicts per Warp

If thread 0 hits bank 0 and thread 1 also hits bank 0, that's a 2-way conflict. If thread 2 hits bank 5 and thread 3 also hits bank 5, that's another 2-way conflict **on a different bank** — they happen in parallel. So a warp can have multiple independent conflicts, each serialized within itself.

## Diagonal Padding Trick

For square tiles, padding by 1 sometimes shifts only some rows off-bank. A more general fix is to pad by a value that's coprime with the bank count:

```cpp
__shared__ float m[32][32 + 1];    // pad by 1
__shared__ float m[32][32 + 5];    // pad by 5 — also coprime, sometimes better
```

But pad-by-1 is the standard, well-understood choice.

## 64-bit Access Special Case

```cpp
__shared__ double d[32];
double v = d[threadIdx.x];     // 8 bytes per thread → uses 2 banks each
// Threads 0..15 each touch banks (2i, 2i+1) — broadcast pattern, no conflict for full warp
```

64-bit accesses are split into two 32-bit accesses, each on adjacent banks. Conflicts can still occur if 64-bit accesses have stride patterns.

## How to Detect

- **`mcu`**: shared memory bank conflict counters (per warp).
- Manual inspection: any access of form `s[constant][threadIdx.x]` or `s[threadIdx.x * stride]` is suspicious.

## Cross-References

- [[memory-hierarchy]] — shared memory bank structure
- [[coalesced-access]] — global memory analog
- [[reduction-patterns]] — common shared-memory user; patterns avoid conflicts
- → raw: `performance_tuning_memory_optimization.md`
