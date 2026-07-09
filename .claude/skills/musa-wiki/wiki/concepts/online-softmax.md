---
title: "在线 Softmax"
type: concept
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [performance_tuning_flash_attention_optimization.md]
tags: [musa, softmax, online-algorithm, numerical-stability, flash-attention]
---

# 在线 Softmax (Online Softmax)

Online softmax computes softmax **incrementally** as new blocks of data arrive, without needing the full row in memory at once. It is the mathematical core of [[flash-attention]] and any tiled softmax implementation.

## The Problem

Standard softmax for a row `x` of length N:

```
m = max(x)
s = sum(exp(x - m))
y[i] = exp(x[i] - m) / s
```

This requires two passes over `x`: one to compute `m`, another to compute `s` and `y`. For large N (e.g. attention with N=4096), materializing the full row is expensive.

## The Online Trick

Process `x` in blocks. Maintain running statistics `(m, l)` and rescale the running output as new blocks arrive.

```
# Initialize
m = -inf
l = 0
y = [0, 0, ..., 0]    # running unnormalized output

# For each block x_b of size B:
m_new = max(m, max(x_b))
# Rescale: existing y was normalized to old max m; rescale to m_new
y = y * exp(m - m_new)
l = l * exp(m - m_new)
# Add new block's contributions
p = exp(x_b - m_new)       # block's exp values
l += sum(p)
y[block_indices] = p       # OR accumulate into output: O += p × V_b
m = m_new

# Final
y /= l
```

This is **mathematically exact** — the result is identical to computing softmax over the full row at once.

## Why It Works

The standard softmax:

```
y[i] = exp(x[i] - m) / sum_j exp(x[j] - m)
     = exp(x[i] - m) / l
```

When we update `m` to `m_new > m`, every `exp(x[j] - m)` term becomes `exp(x[j] - m_new) * exp(m - m_new)`. The sum rescales by the same factor, so the **ratio** (i.e. the softmax output) is unchanged. We just need to track `m` and `l` correctly.

## Code Sketch

```cpp
struct OnlineSoftmaxState {
    float m;     // running max
    float l;     // running sum (rescaled)
};

void update(OnlineSoftmaxState& s, float* x_b, int B) {
    // 1. Compute block max
    float m_block = x_b[0];
    for (int i = 1; i < B; i++) m_block = fmaxf(m_block, x_b[i]);

    // 2. Update global max and rescale
    float m_new = fmaxf(s.m, m_block);
    float scale = expf(s.m - m_new);   // 1.0 if s.m == m_new (first block)
    s.l *= scale;

    // 3. Add new block's contributions
    for (int i = 0; i < B; i++) {
        x_b[i] = expf(x_b[i] - m_new);   // in-place: x_b is now p
        s.l += x_b[i];
    }

    // 4. Update state
    s.m = m_new;
    // Note: caller must rescale any accumulated output (O) by `scale` too
}
```

## In FlashAttention

In FlashAttention, the "output" `O = P × V` accumulates alongside the softmax state:

```cpp
// Per Q row block:
m = -inf; l = 0; O = 0;

for each K, V block:
    S = Q_block × K_block^T        // [Br, Bc]
    m_new = max(m, rowmax(S))
    scale = exp(m - m_new)
    l = l * scale
    O = O * scale                  // rescale running output
    P = exp(S - m_new)             // [Br, Bc]
    l = l + rowsum(P)
    O = O + P × V_block            // accumulate
    m = m_new

O = O / l                          // final normalization
```

The key invariant: after processing block `i`, `O` holds `sum_{j<=i} softmax(Q×K^T)[j] × V[j]`, **unnormalized** (the `1/l` factor is applied at the end).

## Numerical Stability

The `m - m_new` rescale is what makes this numerically stable:

- If `m_new >> m`: `scale ≈ 0`, so old contributions vanish (but they were tiny anyway — the new max dominates).
- If `m_new ≈ m`: `scale ≈ 1`, no change.
- The `exp(x - m_new)` computation never overflows because we subtract the running max.

This is the **same numerical trick** as standard softmax (`exp(x - max(x))`) — extended to the online setting.

## Memory Savings

| Version | Per-row storage |
|---------|-----------------|
| Naive softmax | Full row in HBM |
| Online softmax | `m`, `l`, output accumulator |

For attention with N=4096, d=128:
- Naive: 4096 × 4096 = 16M floats per attention matrix in HBM.
- Online: just the running stats + output (O(1) per row).

## Generalization: Two-Pass → One-Pass

| Algorithm | Passes | Memory |
|-----------|--------|--------|
| Naive 2-pass | 2 | O(N) |
| Online 1-pass | 1 | O(1) per row |

The "online" formulation is sometimes called the **1-pass softmax** — it lets you compute softmax in a single sweep through the data.

## Beyond Softmax: LogSumExp

The same trick applies to **log-sum-exp**:

```
lse(x) = log(sum(exp(x)))

# Online:
m = -inf
lse = -inf
for block x_b:
    m_new = max(m, max(x_b))
    lse = log(exp(lse + m - m_new) + sum(exp(x_b - m_new))) + m_new
    m = m_new
```

Used in gradient computations and many ML frameworks.

## Cross-References

- [[flash-attention]] — the canonical application
- [[reduction-patterns]] — max and sum reductions across blocks
- → raw: `performance_tuning_flash_attention_optimization.md`
