---
title: "muDNN"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [what_is_musa_musa_sdk.md, what_is_musa.md]
tags: [musa, mudnn, deep-learning, conv, attention, library]
---

# muDNN

`muDNN` is the MUSA Deep Neural Network library — Moore Threads' analog of NVIDIA's cuDNN. It provides optimized primitives for common deep learning operations: convolutions, pooling, normalization, activation, and attention.

## What It Provides

| Category | Primitives |
|----------|-----------|
| **Convolution** | `ConvolutionForward`, `ConvolutionBackwardData`, `ConvolutionBackwardFilter` |
| **Pooling** | Max, Average (forward + backward) |
| **Activation** | ReLU, Sigmoid, Tanh, ELU, GELU |
| **Normalization** | BatchNorm, LayerNorm, GroupNorm, InstanceNorm |
| **Softmax** | Forward + backward |
| **Dropout** | Forward + backward |
| **Matrix multiply** | `MatMul` (cross-precision) |
| **Attention** | ScaledDotProductAttention (includes FlashAttention path) |
| **RNN** | LSTM, GRU (limited) |

## API Style

Handle-based, descriptor-heavy (mirrors cuDNN):

```cpp
#include <mudnn.h>

mudnnHandle_t handle;
mudnnCreate(&handle);
mudnnSetStream(handle, stream);

// Tensor descriptors
mudnnTensorDescriptor_t x_desc, y_desc;
mudnnCreateTensorDescriptor(&x_desc);
mudnnSetTensor4dDescriptor(x_desc, MUDNN_FORMAT_NCHW, MUDNN_DATA_FLOAT, N, C, H, W);

// ... set up conv descriptor, filter descriptor, algorithm ...

// Execute
mudnnConvolutionForward(
    handle,
    &alpha, x_desc, d_x,
    filter_desc, d_w,
    conv_desc,
    algo, workspace, ws_size,
    &beta, y_desc, d_y
);

mudnnDestroyTensorDescriptor(x_desc);
mudnnDestroy(handle);
```

## Algorithm Selection

Many operations (especially convolution) have multiple algorithms with different performance characteristics:

```cpp
mudnnConvolutionFwdAlgo_t algo;
int returnedAlgoCount;
mudnnConvolutionFwdAlgoPerf_t perfResults[10];
mudnnGetConvolutionForwardAlgorithmList(
    handle, x_desc, filter_desc, conv_desc, y_desc,
    10, &returnedAlgoCount, perfResults
);
// Pick the best (e.g., by memory footprint or speed)
algo = perfResults[0].algo;
```

For production: benchmark each algorithm at startup, cache the best for each shape.

## Workspace Management

Some algorithms need scratch memory:

```cpp
size_t ws_size;
mudnnGetConvolutionForwardWorkspaceSize(
    handle, x_desc, filter_desc, conv_desc, y_desc, algo, &ws_size
);

void* workspace;
mudaMalloc(&workspace, ws_size);

mudnnConvolutionForward(handle, &alpha, x_desc, d_x, ..., workspace, ws_size, &beta, y_desc, d_y);

mudaFree(workspace);
```

Pool workspace memory across calls — allocation is expensive.

## Attention (FlashAttention Path)

```cpp
mudnnScaledDotProductAttention(
    handle,
    &alpha, q_desc, d_q,
    k_desc, d_k,
    v_desc, d_v,
    mask_desc, d_mask,    // optional
    scale,
    &beta, out_desc, d_out
);
```

Internally selects FlashAttention when applicable — see [[flash-attention]].

## Cross-Precision MatMul

```cpp
mudnnMatMul(
    handle,
    &alpha,
    a_desc, d_a,    // can be FP16/BF16
    b_desc, d_b,    // can be FP16/BF16
    &beta,
    c_desc, d_c     // can be FP16/FP32
);
```

Supports mixed-precision compute (FP16 inputs, FP32 accumulator).

## Heuristics vs Explicit Configuration

muDNN often provides a "heuristics" mode that picks reasonable defaults:

```cpp
mudnnConvolutionFwdAlgoPerf_t perf;
mudnnGetConvolutionForwardAlgorithm(
    handle, x_desc, filter_desc, conv_desc, y_desc,
    MUDNN_CONVOLUTION_FWD_SPECIFY_WORKSPACE_LIMIT,
    ws_limit, &perf
);
algo = perf.algo;
```

For consistent performance, prefer **explicit algorithm selection + caching** over heuristics.

## Integration with Frameworks

PyTorch-MUSA and TensorFlow-MUSA backends use muDNN as the underlying primitive library. Framework users typically don't call muDNN directly — but if you're building a custom kernel or framework, muDNN is the lowest-level primitive library for DL ops.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Tensor descriptor mismatch | Verify dims/format match the actual data |
| Wrong data type | Check `MUDNN_DATA_FLOAT` vs `MUDNN_DATA_HALF` |
| Insufficient workspace | Query workspace size, allocate enough |
| Algorithm not supported for shape | Fall back to a different algo |
| Stream not set on handle | Operations serialize on default stream |

## Cross-References

- [[musa-sdk-stack]] — library's place in the stack
- [[musa-x-libraries]] — sibling math libraries
- [[mutlass]] — lower-level GEMM template library
- [[flash-attention]] — what muDNN attention uses internally
- → raw: `what_is_musa_musa_sdk.md`
