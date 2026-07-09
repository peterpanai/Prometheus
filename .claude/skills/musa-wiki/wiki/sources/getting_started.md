---
title: "快速开始 — 章节摘要"
type: source
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [getting_started_first_kernel.md]
tags: [musa, getting-started, tutorial, vector-add]
---

# 快速开始 (Getting Started — First Kernel)

A 15-minute walkthrough from environment verification to a complete vector-add kernel: write, compile, run, debug. This is the canonical "hello world" of MUSA.

## Key Takeaways

- **Toolchain path**: write `.mu` source → compile with `mcc` → link against `libmusart` → run binary.
- **Environment check**: `mthreads-gmi` (driver/GPU info) and `musa_version_query` (Toolkit version).
- **Compile command**: `mcc vectorAdd.mu -lmusart -L/usr/local/musa/lib -o vectorAdd`.
- **Standard GPU program flow**: host alloc → device alloc → H2D copy → kernel launch → device sync → D2H copy → free.
- **Common pitfalls**: missing `musaDeviceSynchronize()` before reading results, missing `-lmusart` link, environment variables not set, device memory leaks.

## Source Page

| Raw File | Title | Covers |
|----------|-------|--------|
| `raw/sources/getting_started_first_kernel.md` | 编写你的第一个内核 | Prerequisites, env check, project setup, full vectorAdd code, compile/run, troubleshooting (5 Q&A), next steps |

## Prerequisites

- C/C++ basics
- Ubuntu 22.04 (kernel 5.15.x)
- MTT M1000/S4000/S5000 series GPU
- MUSA SDK 5.2.0 (driver + Toolkit + env vars)

## Environment Setup

```bash
# Verify driver
mthreads-gmi

# Verify Toolkit
musa_version_query

# If commands not found:
export PATH=$MUSA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$MUSA_HOME/lib:$LD_LIBRARY_PATH
```

## The 7-Step GPU Program Flow

1. Host allocates + initializes input data
2. Host allocates device memory (`musaMalloc`)
3. H2D copy (`musaMemcpy` with `musaMemcpyHostToDevice`)
4. Launch kernel (`<<<gridSize, blockSize>>>`)
5. Device computes (parallel)
6. D2H copy results back (`musaMemcpyDeviceToHost`)
7. Free everything (`musaFree`, `free`)

## Compile & Run

```bash
mcc vectorAdd.mu -lmusart -L/usr/local/musa/lib -o vectorAdd
./vectorAdd
# Expected: 内核启动：196 个块，每块 256 线程
#           测试通过
#           完成
```

For a 50,000-element vector add with blockSize=256, gridSize = ceil(50000/256) = 196.

## Troubleshooting Cheatsheet

| Problem | Likely Cause | Fix |
|---------|--------------|-----|
| `command not found: mthreads-gmi` | PATH not set | `export PATH=$MUSA_HOME/bin:$PATH` |
| `invalid device ordinal` | Driver not loaded | `lsmod \| grep musa`; `sudo modprobe musa` |
| Results are 0 / wrong | Kernel didn't finish before D2H copy | Add `musaDeviceSynchronize()` before `musaMemcpy` D2H |
| Memory leak | Forgot to free | Free both host (`free`) and device (`musaFree`) memory |
| `cannot find -lmusart` | Library path missing | `export LD_LIBRARY_PATH=/usr/local/musa/lib:$LD_LIBRARY_PATH`; pass `-L/usr/local/musa/lib` to mcc |

## Cross-References

- **Foundations**: [[what-is-musa]] — what MUSA is, why this works
- **Programming model**: [[programming-model]] — what `<<<gridSize, blockSize>>>` actually does
- **MUSA C++ syntax**: [[musa-cpp-syntax]] — `__global__`, built-in variables
- **mcc compiler**: [[mcc-compiler]] — compile flags, `.mu` vs `.cpp`
- **Runtime API**: [[api-guides]] — the `musaMalloc`/`musaMemcpy`/`musaFree` family
