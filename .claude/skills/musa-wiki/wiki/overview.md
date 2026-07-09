---
title: "MUSA Wiki 概览"
type: overview
status: active
created: 2026-07-07
updated: 2026-07-10
sources: [programming_guide.md, what_is_musa.md, what_is_musa_musa_sdk.md, what_is_musa_gpu_parallel_basics.md]
tags: [musa, overview, thesis, glossary]
---

# MUSA Wiki 概览

This wiki is a persistent, structured knowledge base for the **MUSA SDK** (Moore Threads' GPU compute platform) — MUSA is to Moore Threads what CUDA is to NVIDIA. It was built from the official MUSA programming guide at `docs.mthreads.com`, distilled into concept/entity/synthesis pages with interlinking.

## Official Learning Path

Per the programming guide root page (`raw/sources/programming_guide.md`), the recommended learning order is:

> 入门 -> 编程模型 -> 语法 -> API -> 硬件架构 -> 性能优化

In wiki terms: [[overview]] (入门) -> [[thread-hierarchy]] / [[memory-hierarchy]] (编程模型) -> [[kernel-launch-syntax]] / [[warp-functions]] (语法) -> [[runtime-api]] / [[driver-api]] (API) -> [[mtt-s5000]] (硬件架构) -> [[optimization-playbook]] / [[roofline-model]] (性能优化).

## Thesis

MUSA is a **near-source-compatible** CUDA alternative: ~95% of CUDA code ports with mechanical substitution (`cuda*` → `musa*`, `cu*` → `mu*`), and the programming model (Grid/Block/Thread, SIMT warps, shared memory, Tensor Cores) is structurally identical. The meaningful differences are:

1. **Hardware generations differ** — MP21/MP22 (MTT S4000/M1000) have **128-lane warps**, unlike anything in CUDA. MP31 (MTT S5000) uses 32-lane warps and is the closest CUDA analog.
2. **Tooling is younger** — MUSA SDK 5.2.0 (current as of 2026-07-10 per `raw/sources/programming_guide.md`) with backward-compatibility guarantees since v5.1, but the ecosystem (libraries, frameworks, profilers) is less mature than CUDA's.
3. **Green Context replaces MIG/MPS** — MUSA's MP-partitioning primitive is software-based and runtime-flexible, unlike NVIDIA's hardware MIG.
4. **Cluster memory is a first-class primitive** — distributed shared memory across thread blocks, with `musaClusterSync`.

The optimization playbook ( Roofline, occupancy, coalescing, Tensor Cores ) is **directly transferable** from CUDA. Most CUDA optimization intuition applies.

## What's Here

| Section | Pages | Purpose |
|---------|-------|---------|
| `sources/` | 8 chapter summaries | One-page-per-chapter digest of the official docs |
| `concepts/` | 30 concept pages | Individual MUSA topics with code examples |
| `entities/` | 14 entity pages | Tools, libraries, and hardware |
| `synthesis/` | 2 cross-cutting pages | CUDA→MUSA mapping, optimization playbook |

See `index.md` for the full catalog.

## Key Concepts (Start Here)

If you're new to MUSA:

1. **[[thread-hierarchy]]** — Grid → Block → Thread. The central abstraction.
2. **[[memory-hierarchy]]** — Registers, shared, L1/L2, global. The biggest performance lever.
3. **[[kernel-launch-syntax]]** — The `<<<grid, block>>>` triple-chevron syntax.
4. **[[simt-execution-model]]** — How warps actually execute.
5. **[[roofline-model]]** — The first analysis tool for any slow kernel.

If you're porting from CUDA:

1. **[[cuda-to-musa-mapping]]** — Comprehensive name/concept mapping.
2. **[[musify-tool]]** — Automated source-to-source converter.
3. **[[musa-mapping]]** — Compile-time CUDA compatibility layer for large sourcebases.
4. **[[mtt-s5000]]** — The closest CUDA-equivalent hardware.

If you're optimizing:

1. **[[optimization-playbook]]** — Decision tree for slow kernels.
2. **[[gemm-optimization]]** / **[[flash-attention]]** — Workload-specific patterns.
3. **[[moore-perf]]** — The profiler toolset (mcu / msys).

## Hardware Reference

| GPU | Arch | Warp Size | Position |
|-----|------|-----------|----------|
| MTT S5000 | MP31 | 32 | Data center flagship |
| MTT M1000 | MP22 | 128 | Workstation |
| MTT S4000 | MP21 | 128 | Workstation |

> **warpSize matters**: code assuming `warpSize == 32` will break on MP21/MP22. Always use the `warpSize` built-in. See [[warp-functions]].

## Software Stack

- **Compiler**: `mcc` (analog of `nvcc`) — see [[mcc-compiler]]
- **Runtime**: `-lmusart` (high-level API) — see [[musart-runtime]], [[runtime-api]]
- **Driver**: `-lmudrv` (low-level API, JIT, Green Contexts) — see [[musadrv-driver]], [[driver-api]]
- **Math libraries**: muBLAS, muFFT, muRAND, muSPARSE, muSOLVER, muThrust — see [[musa-x-libraries]]
- **DL library**: muDNN — see [[mudnn]]
- **Multi-GPU**: MCCL — see [[mccl]]
- **GEMM templates**: MUTLASS — see [[mutlass]]
- **Profiler**: mcu, msys, Moore Perf GUI, muPTI — see [[moore-perf]], [[mupti]]
- **Runtime compilation**: MTRTC — see [[mtrtc]]
- **CUDA compatibility**: MUSA Mapping — see [[musa-mapping]]

## Open Tensions / Disputed Claims

> Per the companion-memory model: contradictions and ambiguities in source material are flagged, not smoothed over.

1. **Warp size rationale**: The official docs do not explain *why* MP21/MP22 use 128-lane warps while MP31 reverted to 32. Hypothesis: 128 was an experiment in matching wider SIMD units; MP31's 32 reflects convergence with the CUDA ecosystem for portability. **Status**: speculation, not documented.

2. **Green Context vs MIG isolation strength**: The docs describe Green Context as "MP partition" but don't quantify how strict the isolation is (cache, memory bandwidth). Whether it matches MIG's hardware-level isolation or is closer to MPS's soft partitioning is **unclear from the docs alone**.

3. **FlashAttention version**: The programming guide references FlashAttention but does not specify which version (v1/v2/v3). The muDNN library implements some version — verify against the actual SDK release notes.

4. **L2 persistence scope across streams**: The docs show stream-scoped policy windows, but the behavior when multiple streams access the same buffer with different policies is **underspecified**. Assumed: the most-recently-set policy wins, but this needs verification.

5. **Cluster max size**: Docs say "typically 8 or 16" blocks per cluster, but the exact hardware limit per architecture is not tabulated. Query via `musaDevAttrClusterLaunch`.

If you encounter these in practice, mark them in the relevant page's frontmatter as `status: disputed` and note the discrepancy in the page body.

## Maintenance Notes

- **Raw sources** are in `raw/sources/` — never modify. They are the immutable ground truth.
- **Wiki pages** are derived. Update them when the official docs change.
- **Cross-references** use `[[wikilink]]` syntax. Broken links indicate a page that should exist but doesn't yet.
- **Logs** of all ingest/update operations are in `log.md`.

## See Also

- `index.md` — full content catalog
- `log.md` — chronological record of changes
- `../raw/sources/_MANIFEST.md` — raw source file listing
- `../SCHEMA.md` — wiki maintenance instructions
