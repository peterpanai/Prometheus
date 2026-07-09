---
title: "MUSA Wiki Index"
type: overview
status: active
created: 2026-07-07
updated: 2026-07-10
---

# MUSA Wiki Index

Content-oriented catalog of the MUSA wiki. Read this first on every query.

## Quick Navigation

- **Official learning path** (per `raw/sources/programming_guide.md`): 入门 → 编程模型 → 语法 → API → 硬件架构 → 性能优化. See [[overview#official-learning-path]].
- **New to MUSA?** Start with [[overview]] → [[thread-hierarchy]] → [[memory-hierarchy]] → [[kernel-launch-syntax]]
- **Porting from CUDA?** [[cuda-to-musa-mapping]] → [[musify-tool]] / [[musa-mapping]] → [[mtt-s5000]]
- **Optimizing?** [[optimization-playbook]] → [[roofline-model]] → workload-specific page
- **Reference?** Jump to the page you need below.

## Sources (Chapter Summaries)

One-page digest of each chapter of the MUSA programming guide.

- [[sources/what_is_musa]] — What MUSA is, GPU basics, SDK software stack
- [[sources/getting_started]] — First kernel, compile command, troubleshooting
- [[sources/programming_model]] — Host/Device, threads, memory, execution, L2, advanced
- [[sources/musa_cpp_syntax]] — Qualifiers, built-ins, atomics, warp functions
- [[sources/api_guides]] — Runtime API vs Driver API, lifecycle, pitfalls
- [[sources/features]] — MUSA Graphs and Green Context
- [[sources/performance_tuning]] — Profiling, compute/memory/reduction/GEMM/FlashAttention optimization
- [[sources/toolkits]] — Compiler, runtime, CUDA migration, profiling, and compat tools

## Concepts

### Foundations

- [[simt-execution-model]] — SIMT vs SIMD, warp execution, divergence
- [[thread-hierarchy]] — Grid/Block/Thread, indexing, limits
- [[thread-indexing]] — 1D/2D/3D index formulas, grid-stride loops
- [[memory-hierarchy]] — Registers, shared, L1/L2, global, constant, host memory
- [[kernel-launch-syntax]] — The `<<<>>>` syntax and configuration
- [[advanced-memory]] — Pinned, mapped, unified, stream-ordered allocation

### Synchronization & Communication

- [[synchronization-primitives]] — `__syncthreads`, `__syncwarp`, fences, atomics scope
- [[warp-functions]] — `__syncwarp`, vote, ballot, shuffle
- [[warp-shuffle]] — Register-to-register exchange patterns
- [[atomic-functions]] — atomicAdd, atomicCAS, scope variants
- [[stream-and-event-model]] — Host-side async coordination
- [[cluster-memory]] — Distributed shared memory across blocks

### Memory Optimization

- [[coalesced-access]] — The most important global-mem optimization
- [[bank-conflicts]] — Shared-mem access serialization
- [[l2-cache-management]] — Persistence policy windows

### Compute Optimization

- [[roofline-model]] — Visual bottleneck analysis
- [[occupancy]] — Active warps per SM, register/shared limits
- [[warp-divergence]] — Branch divergence cost and mitigation
- [[tensor-cores]] — MMA hardware units, wmma API

### Workload Patterns

- [[reduction-patterns]] — Sum/max/min, two-stage and single-kernel
- [[gemm-optimization]] — The optimization ladder (naive → MUTLASS)
- [[gemv-optimization]] — Matrix-vector special case
- [[flash-attention]] — Tiled attention with online softmax
- [[online-softmax]] — The math trick behind FlashAttention
- [[double-buffering]] — Overlap memory and compute

### API Surface

- [[runtime-api]] — High-level host API (`musa*`)
- [[driver-api]] — Low-level host API (`mu*`), JIT, Green Context
- [[primary-context]] — Bridging Runtime and Driver APIs
- [[musa-graphs]] — DAG-based work submission
- [[green-context]] — MP partitioning for multi-tenancy

## Entities

### Hardware

- [[mtt-s5000]] — MP31 flagship GPU (data center)

### Software Stack

- [[musa-sdk-stack]] — Overview of the full SDK
- [[mcc-compiler]] — MUSA C++ compiler (analog of nvcc)
- [[musart-runtime]] — Runtime API library (-lmusart)
- [[musadrv-driver]] — Driver API library (-lmudrv)
- [[mtrtc]] — runtime JIT compilation library
- [[musa-mapping]] — compile-time CUDA compatibility layer

### Libraries

- [[musa-x-libraries]] — muBLAS, muFFT, muRAND, muSPARSE, muSOLVER, muThrust
- [[mudnn]] — Deep learning primitives (analog of cuDNN)
- [[mccl]] — Multi-GPU collectives (analog of NCCL)
- [[mutlass]] — GEMM/conv template library (analog of cuTLASS)

### Tools

- [[moore-perf]] — mcu, msys, Moore Perf GUI
- [[mupti]] — Profiling Tools Interface (programmatic)
- [[musify-tool]] — CUDA→MUSA source converter
- [[mtrtc]] — runtime compilation / JIT device code
- [[musa-mapping]] — compile-time CUDA compatibility layer

## Synthesis

- [[cuda-to-musa-mapping]] — Comprehensive name/concept/API mapping
- [[optimization-playbook]] — Decision tree for slow kernels

## Statistics

- Sources: 8 chapter summary pages (mirroring 41 raw files)
- Concepts: 30 pages
- Entities: 14 pages
- Synthesis: 2 pages
- **Total**: 54 wiki pages

## Maintenance

- To find recent changes: see [[log]]
- To check health: run `lint` (skills command)
- To add a new page: see `../SCHEMA.md` for naming and frontmatter conventions
- Raw source files: see `../raw/sources/_MANIFEST.md`
