---
name: musa-wiki
description: Query and maintain the MUSA SDK knowledge wiki - a structured knowledge base for Moore Threads' MUSA GPU compute platform (MUSA is to Moore Threads what CUDA is to NVIDIA). Covers MUSA C++ syntax, runtime/driver APIs, MUSA Graphs, Green Context, cluster memory, performance tuning (compute/memory/reduction/GEMM/FlashAttention), and the MT GPU hardware line (MTT S5000/S4000/M1000, MP21/MP22/MP31). Use when the user asks about MUSA, Moore Threads GPUs, the mcc/musart/muDNN/MCCL/MUTLASS/moore-perf toolchain, porting CUDA to MUSA, or wants to ingest new MUSA docs / query the wiki / lint its health / promote outputs / check status. Triggers on MUSA SDK questions, MTT GPU queries, MUSA optimization, CUDA->MUSA porting, and the wiki maintenance operations (ingest/query/lint/promote/status).
license: MIT
metadata:
  author: github.com/panmcai
  version: "1.0.0"
---

# MUSA Wiki

A persistent, structured knowledge base for the **MUSA SDK** (Meta-computing Unified System Architecture) - Moore Threads' GPU parallel computing platform and programming language. Built and maintained using the [Karpathy Wiki](../karpathy-wiki/SKILL.md) pattern with MUSA-specific governance (see [references/governance.md](references/governance.md)).

The wiki was distilled from the official MUSA programming guide at `docs.mthreads.com` into 51 interlinked pages: 7 chapter summaries, 30 concept pages, 12 entity pages, 2 cross-cutting synthesis pages.

## Subject Domain

In scope:
- MUSA programming model (SIMT, Grid/Block/Thread, memory hierarchy)
- MUSA C++ syntax (`__global__`, `__shared__`, `<<<>>>`, built-in variables)
- Runtime API and Driver API
- Advanced features (MUSA Graphs, Green Context, Cluster memory, L2 persistence)
- Performance tuning (compute, memory, reduction, GEMM, FlashAttention)
- MUSA SDK toolchain (mcc, musify, MUSA-X libs, muDNN, MCCL, Moore Perf, muPTI)
- MT GPU hardware (MTT S5000/S4000/M1000, MP31/MP21/MP22 architectures)

Out of scope: Moore Threads driver installation, non-MUSA SDK products, unrelated GPU platforms.

## Three-Layer Architecture

| Layer | Path | Role | Rules |
|-------|------|------|-------|
| Raw Sources | `raw/sources/` | Immutable mirror of docs.mthreads.com (32 files) | **Never modify.** Single source of truth. |
| Wiki | `wiki/` | Structured knowledge core (51 pages) | LLM writes and maintains all pages, `index.md`, `log.md` |
| Outputs | `outputs/` | Queries, reports, artifacts | LLM generates; can be promoted back to wiki |

**Knowledge cycle**: `raw` ->(ingest)-> `wiki` ->(query)-> `outputs` ->(promote)-> `wiki` or `raw`

## Quick Navigation

- **New to MUSA?** `wiki/overview.md` -> [[thread-hierarchy]] -> [[memory-hierarchy]] -> [[kernel-launch-syntax]]
- **Porting from CUDA?** [[cuda-to-musa-mapping]] -> [[musify-tool]] -> [[mtt-s5000]]
- **Optimizing?** [[optimization-playbook]] -> [[roofline-model]] -> workload-specific page
- **Reference?** Read `wiki/index.md` first - it's the content catalog.

## Quick Commands

| User says | Agent does |
|-----------|------------|
| `摄入 <path>` / `ingest <path>` | Ingest new raw file(s) |
| `查 ...` / `query ...` | Answer from wiki, archive to `outputs/queries/` or `outputs/reports/` |
| `lint` | Health-check wiki + outputs |
| `升格 outputs/...` / `promote outputs/...` | Promote to wiki or raw |
| `状态` / `status` | Show index + log tail + open disputes |

## Hardware Footgun

MUSA has architecture-dependent behavior. **Always use the `warpSize` built-in**, never the literal `32`:

| GPU | Arch | Warp Size |
|-----|------|-----------|
| MTT S5000 | MP31 | 32 |
| MTT M1000 | MP22 | 128 |
| MTT S4000 | MP21 | 128 |

See [references/governance.md](references/governance.md) for the full MUSA-specific governance rules.

## Operations

See [SCHEMA.md](SCHEMA.md) for the full operating manual: ingest/query/lint/promote workflows, frontmatter conventions, naming conventions, citation conventions, log entry formats.

## References

- [SCHEMA.md](SCHEMA.md) - full agent operating manual (MUSA-specific)
- [references/governance.md](references/governance.md) - MUSA-specific companion memory governance
- [../karpathy-wiki/SKILL.md](../karpathy-wiki/SKILL.md) - the generic Karpathy Wiki pattern this wiki follows
- [../karpathy-wiki/references/methodology.md](../karpathy-wiki/references/methodology.md) - LLM Wiki methodology
- [../karpathy-wiki/references/governance.md](../karpathy-wiki/references/governance.md) - generic companion memory model
