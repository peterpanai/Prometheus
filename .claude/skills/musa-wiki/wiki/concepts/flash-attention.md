---
title: "FlashAttention"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_flash_attention_optimization.md]
tags: [musa, flash-attention, transformer, online-softmax, tiling]
---

# FlashAttention

FlashAttention is an **exact** (no approximation) algorithm for computing attention that minimizes HBM (DRAM) traffic. It is the dominant optimization for transformer training/inference and typically delivers 2-4× speedup over the naive `Q × K^T → softmax → × V` formulation.

## Why Naive Attention is Slow

Standard attention for sequence length N, head dim d:

```
S = Q × K^T        # [N, N] matrix — written to HBM
P = softmax(S)     # [N, N] matrix — read S, written to HBM
O = P × V          # [N, d] — read P, written to HBM
```

For N=4096, d=128: S and P are each 4096×4096×4B = 64 MB. **Materializing them in HBM costs 128 MB of traffic per attention layer.** The actual compute is small (2N²d ≈ 4 GFLOPS) — this is firmly memory-bound.

## FlashAttention's Insight

Two techniques collapse HBM traffic:

1. **Tiling**: load Q, K, V in blocks; compute partial attention for each block; never materialize the full N×N matrix.
2. **Online softmax**: incrementally compute softmax as new blocks arrive, without needing the full row.

```
for each block of Q (size Br × d):
    init O[Br × d] = 0, m[Br] = -inf, l[Br] = 0
    for each block of K/V (size Bc × d):
        S = Q_block × K_block^T           # [Br, Bc] in shared mem
        m_new = max(m, rowmax(S))
        P = exp(S - m_new)                # in shared mem
        l = exp(m - m_new) * l + rowsum(P)
        O = exp(m - m_new) * O + P × V_block
        m = m_new
    O /= l                                # final normalization
```

The full N×N matrix **never exists in HBM** — only the small [Br, Bc] tile in shared memory.

## Memory Traffic Comparison

For N=4096, d=128, FP16:

| Version | HBM reads/writes | Notes |
|---------|------------------|-------|
| Naive | ~256 MB | Q, K, V read + S, P, O written/read |
| FlashAttention | ~3 MB | Q, K, V read once; O written once |

~80× less HBM traffic → ~2-4× wall-clock speedup depending on hardware.

## Tiling Choice

| Tile | Typical size | Notes |
|------|--------------|-------|
| `Br` (Q block rows) | 64 or 128 | Larger = more reuse, more shared mem |
| `Bc` (K/V block cols) | 64 or 128 | Limited by shared mem capacity |
| Shared mem per block | ~32-96 KB | Two Q tiles + K + V + accumulator |

For S5000 with 96 KB shared mem: `Br=128, Bc=128` fits with FP16. For S4000 with 48 KB, drop to `Br=64, Bc=64`.

## Online Softmax Math

The trick: track the running max `m` and sum `l` for each row, and rescale the running output `O` when a new block updates the max.

```
Given: m_old, l_old, O_old, and new block S
m_new = max(m_old, rowmax(S))
P = exp(S - m_new)                          # numerically stable
l_new = exp(m_old - m_new) * l_old + rowsum(P)
O_new = exp(m_old - m_new) * O_old + P × V_block
```

The `exp(m_old - m_new)` factor rescales the existing accumulator to the new max. This is mathematically exact — no precision lost vs. computing softmax over the full row.

## Recomputation (Backward Pass)

In training, the backward pass needs the attention weights `P = softmax(QK^T)`. Naive implementations store P (huge) for backward. FlashAttention **recomputes** P from Q, K on the fly:

- Forward: stores Q, K, V, O, and the per-block `m, l` statistics.
- Backward: re-runs the tiled attention to get P, then computes gradients.

Trade-off: 0.5× extra FLOPS in backward, but **no 64 MB P matrix** to write/read. Net win.

## Implementation Sketch

```cpp
__global__ void flashAttention(
    const __half* Q, const __half* K, const __half* V,
    __half* O, int N, int d
) {
    const int Br = 64, Bc = 64;
    __shared__ __half Qs[Br][d];
    __shared__ __half Ks[Bc][d];
    __shared__ __half Vs[Bc][d];
    __shared__ float S[Br][Bc];              // FP32 accumulator for softmax

    int q_block = blockIdx.x;

    // Load Q tile
    loadQ(Qs, Q + q_block * Br * d, d);
    __syncthreads();

    float O_acc[Br][d] = {0};                // per-thread registers
    float m[Br] = {-INFINITY};
    float l[Br] = {0};

    for (int k_block = 0; k_block < N; k_block += Bc) {
        loadK(Ks, K + k_block * Bc * d, d);
        loadV(Vs, V + k_block * Bc * d, d);
        __syncthreads();

        // Compute S = Qs × Ks^T (use Tensor Cores if available)
        matmul(S, Qs, Ks);

        // Online softmax update
        for (int i = 0; i < Br; i++) {
            float m_new = m[i];
            for (int j = 0; j < Bc; j++) m_new = fmaxf(m_new, S[i][j]);
            float scale = expf(m[i] - m_new);
            for (int j = 0; j < Bc; j++) S[i][j] = expf(S[i][j] - m_new);
            l[i] = l[i] * scale + rowsum(S[i]);
            for (int k = 0; k < d; k++) O_acc[i][k] *= scale;
            m[i] = m_new;
        }

        // O += S × Vs (Tensor Cores)
        accumulateO(O_acc, S, Vs);
        __syncthreads();
    }

    // Normalize and write back
    for (int i = 0; i < Br; i++)
        for (int k = 0; k < d; k++)
            O[(q_block * Br + i) * d + k] = O_acc[i][k] / l[i];
}
```

## Variants

| Variant | Use case |
|---------|----------|
| FlashAttention v1 | Original (Dao et al.) |
| FlashAttention v2 | Better parallelism along sequence dim, less non-matmul FLOPS |
| FlashAttention v3 | Async copy + Tensor Core overlap, FP8 support |
| Flash Decoding | Inference-specific: splits long K/V across blocks |

MUSA's FlashAttention implementations track these — check MUSA-X for the latest available.

## Cross-References

- [[online-softmax]] — the core math trick
- [[gemm-optimization]] — inner kernel
- [[tensor-cores]] — used in matmul
- [[roofline-model]] — why minimizing traffic matters
- [[reduction-patterns]] — max/sum across blocks
- → raw: `performance_tuning_flash_attention_optimization.md`
