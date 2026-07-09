---
title: "MUSA Wiki Log"
type: overview
status: active
created: 2026-07-07
updated: 2026-07-10
---

# MUSA Wiki Log

Chronological append-only record of wiki operations. Parseable: `grep "^## \[" log.md | tail -10` gives recent entries.

## [2026-07-07] ingest | MUSA SDK Programming Guide (full)
- raw: `raw/sources/` (32 files, 281 KB total)
- source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide
- fetched: 2026-07-07 via curl + pandoc + custom Docusaurus HTML cleaner
- touched: all wiki pages (initial build)
- notes: Initial construction of the MUSA wiki. Fetched all 32 pages of the official programming guide, converted to clean markdown, and ingested into the three-layer raw/wiki/outputs architecture. Built 7 source-summary pages (one per chapter), 30 concept pages, 12 entity pages, 2 synthesis pages, plus overview/index/log.

### Pages Created

**Sources (7):**
- `sources/what_is_musa.md`
- `sources/getting_started.md`
- `sources/programming_model.md`
- `sources/musa_cpp_syntax.md`
- `sources/features.md`
- `sources/api_guides.md`
- `sources/performance_tuning.md`

**Concepts (30):**
- Foundations: `simt-execution-model`, `thread-hierarchy`, `thread-indexing`, `memory-hierarchy`, `kernel-launch-syntax`, `advanced-memory`
- Sync & Comm: `synchronization-primitives`, `warp-functions`, `warp-shuffle`, `atomic-functions`, `stream-and-event-model`, `cluster-memory`
- Memory Opt: `coalesced-access`, `bank-conflicts`, `l2-cache-management`
- Compute Opt: `roofline-model`, `occupancy`, `warp-divergence`, `tensor-cores`
- Workload Patterns: `reduction-patterns`, `gemm-optimization`, `gemv-optimization`, `flash-attention`, `online-softmax`, `double-buffering`
- API Surface: `runtime-api`, `driver-api`, `primary-context`, `musa-graphs`, `green-context`

**Entities (12):**
- Hardware: `mtt-s5000`
- Stack: `musa-sdk-stack`, `mcc-compiler`, `musart-runtime`, `musadrv-driver`
- Libraries: `musa-x-libraries`, `mudnn`, `mccl`, `mutlass`
- Tools: `moore-perf`, `mupti`, `musify-tool`

**Synthesis (2):**
- `cuda-to-musa-mapping`
- `optimization-playbook`

**Index/Overview:**
- `overview.md`, `index.md`, `log.md`

### Ingestion Process

1. **Discovery**: Reverse-engineered Docusaurus SPA structure. Sidebar JSON endpoints returned SPA fallback; extracted internal links from article HTML via regex.
2. **Fetch**: `curl --compressed` for each of 32 pages.
3. **Conversion**: `pandoc` HTML→markdown + custom Python cleaner (`/tmp/clean_musa3.py`) handling Docusaurus code blocks, breadcrumbs, hash-links, base64 SVG icons.
4. **Triage**: Read raw files; identified 7-chapter structure.
5. **Source summaries**: Used 4 parallel subagents to summarize large chapters (MUSA Graphs/Green Context, Runtime/Driver API guides, 6 performance tuning pages, FlashAttention & GEMM/GEMV).
6. **Concept extraction**: Derived 30 concept pages from source summaries.
7. **Entity extraction**: Derived 12 entity pages for tools, libraries, hardware.
8. **Synthesis**: Built 2 cross-cutting pages (CUDA→MUSA mapping, optimization playbook).
9. **Index/overview/log**: Wrote catalog, thesis, and chronological log.

### Open Issues

See `overview.md` "Open Tensions" section. Five items flagged as needing verification:
- Warp size rationale (MP21/MP22 vs MP31)
- Green Context isolation strength vs MIG/MPS
- FlashAttention version in muDNN
- L2 persistence scope across multiple streams
- Cluster max size per architecture

### Tooling Notes

- Raw files have header comments with source URL and "do not edit" notice.
- All wiki pages use frontmatter with `name`, `description`, `type`, `status`, `created`, `updated`, `sources`, `tags`.
- Cross-references use `[[wikilink]]` syntax (Obsidian-compatible).
- Raw → wiki → outputs flow per karpathy-wiki methodology.

## [2026-07-10] ingest | Programming Guide Root Page
- raw: `raw/sources/programming_guide.md` (633 bytes)
- source: https://docs.mthreads.com/musa-sdk/musa-sdk-doc-online/programming_guide/
- fetched: 2026-07-10 via curl + pandoc + Python Docusaurus cleaner
- touched: [[overview]], `raw/sources/_MANIFEST.md`, [[index]]
- notes: Ingested the programming guide root/landing page (not previously mirrored - the 32-file initial build on 2026-07-07 covered sub-pages only). New information captured: (1) SDK version is explicitly **5.2.0**, upgrading the wiki's "v5.x" references to a specific version in [[overview]] thesis; (2) official recommended learning path "入门 -> 编程模型 -> 语法 -> API -> 硬件架构 -> 性能优化" added to [[overview]] as a new "Official Learning Path" section. All 7 chapter links from the root page were already covered by the existing 32 raw files - no new sub-pages discovered. No contradictions with existing wiki content.

## [2026-07-10] ingest | MUSA SDK Toolkits Chapter
- raw: `raw/sources/toolkits.md`, `raw/sources/toolkits_mcc_compiler.md`, `raw/sources/toolkits_mtrtc_runtime_compilation.md`, `raw/sources/toolkits_musa_runtime.md`, `raw/sources/toolkits_musify.md`, `raw/sources/toolkits_mupti.md`, `raw/sources/toolkits_moore_perf.md`, `raw/sources/toolkits_musa_mapping.md`
- touched: [[sources/toolkits]], [[mtrtc]], [[musa-mapping]]
- notes: Ingested the toolkit chapter and added a source summary for MUSA toolkits, plus entity pages for MTRTC and MUSA Mapping. Captured compiler, runtime compilation, runtime/eager library, CUDA migration, profiling, and compile-time compatibility tooling in the wiki.

## Maintenance Commands

| Command | Action |
|---------|--------|
| `grep "^## \[" log.md \| tail -10` | Recent log entries |
| `grep "^- \[\[" index.md` | All wiki pages |
| `find raw/sources -name "*.md" \| wc -l` | Raw file count |
| `find wiki -name "*.md" \| wc -l` | Wiki page count |
