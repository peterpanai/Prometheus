---
title: "mcc 编译器"
type: entity
status: active
created: 2026-07-07
updated: 2026-07-07
sources: [getting_started_first_kernel.md, what_is_musa_musa_sdk.md, toolkits_mcc_compiler.md]
tags: [musa, mcc, compiler, fatbin, ptxas]
---

# mcc 编译器 (mcc Compiler)

`mcc` is the MUSA C++ compiler — Moore Threads' analog of NVIDIA's `nvcc`. It accepts MUSA C++ source (C++ extended with `__global__`, `__device__`, `<<<>>>`, etc.), compiles host and device code separately, and produces a fatbin containing PTX-like IR and architecture-specific SASS.

## Basic Usage

```bash
mcc vectorAdd.mu -lmusart -o vectorAdd
```

This single command:
1. Splits the source into host and device parts.
2. Compiles the device part to PTX-like IR + SASS for the default architecture.
3. Embeds the device fatbin into the host object.
4. Compiles the host part with the system C++ compiler (`g++` or `clang++`).
5. Links with `-lmusart` (and any other libraries you specify).

## Target Architecture

Specify the target GPU architecture with `-arch`:

```bash
mcc -arch=mp31 kernel.mu -lmusart -o kernel          # MTT S5000
mcc -arch=mp22 kernel.mu -lmusart -o kernel          # MTT M1000
mcc -arch=mp21 kernel.mu -lmusart -o kernel          # MTT S4000
```

Generate a fatbin supporting multiple architectures:

```bash
mcc -arch=mp21 -arch=mp22 -arch=mp31 kernel.mu -lmusart -o kernel
```

The runtime picks the best variant for the current device.

## Optimization Flags

| Flag | Effect |
|------|--------|
| `-O0` / `-O1` / `-O2` / `-O3` | Standard optimization levels |
| `--use_fast_math` | Faster but less precise math (implies `--ftz=true --prec-div=false --prec-sqrt=false`) |
| `--ftz` | Flush denormals to zero |
| `--prec-div=false` | Faster division (less precise) |
| `--prec-sqrt=false` | Faster sqrt (less precise) |
| `--fmad=true` | Fuse multiply-add (default on) |
| `--maxrregcount=N` | Cap registers per thread (forces spills if exceeded) |
| `--ptxas-options=-v` | Print register/shared mem usage per kernel |

## Inspecting Compilation

```bash
mcc -arch=mp31 -ptx kernel.mu -o kernel.ptx         # emit PTX-like IR
mcc -arch=mp31 -sass kernel.mu -o kernel.sass       # emit SASS
mcc -arch=mp31 -ptxas-options=-v kernel.mu -c       # print register stats
```

Output of `-ptxas-options=-v`:

```
ptxas info : Compiling entry function 'myKernel' for 'mp31'
ptxas info : Function properties for myKernel
        0 bytes stack frame, 0 bytes spill stores, 0 bytes spill loads
ptxas info : Used 32 registers, 256 bytes cmem[0]
```

If you see `spill stores` / `spill loads` > 0, the compiler ran out of registers and is using local memory — bad for performance. See [[occupancy]].

## Separate Compilation

For projects with multiple translation units:

```bash
# Compile device code to fatbin objects
mcc -arch=mp31 -dc kernel1.mu -o kernel1.o
mcc -arch=mp31 -dc kernel2.mu -o kernel2.o

# Link device objects
mcc -arch=mp31 -dlink kernel1.o kernel2.o -o dlink.o

# Final host link
g++ main.cc kernel1.o kernel2.o dlink.o -lmusart -o app
```

For runtime device linking, use `mcc -rdc=true` to generate relocatable device code.

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Mismatched `-arch` between compile and link | Use same arch for all TUs |
| Forgetting `-lmusart` at link | Add to link command |
| Code uses C++17 features but default is C++14 | Add `-std=c++17` |
| Inlining fails for `__device__` functions in different TUs | Use `__forceinline__` or move to header |
| Default arch doesn't match deployment GPU | Always specify `-arch` explicitly |

## Header Search

`mcc` automatically searches the MUSA SDK include path (`/usr/local/musa/include` by default). For custom headers:

```bash
mcc -I/path/to/headers kernel.mu -lmusart -o kernel
```

## Library Search

```bash
mcc -L/path/to/libs -lmylib kernel.mu -lmusart -o kernel
```

MUSA libraries (`muBLAS`, `muFFT`, etc.) are in the default search path; just link with `-lmublas`, `-lmufft`, etc.

## Cross-References

- [[musa-sdk-stack]] — where mcc fits
- [[kernel-launch-syntax]] — what mcc compiles
- [[musify-tool]] — converting CUDA source for mcc
- [[occupancy]] — register pressure diagnostics
- → raw: `getting_started_first_kernel.md`
