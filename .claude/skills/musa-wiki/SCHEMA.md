# MUSA Wiki - Agent Schema

This file is the operating manual for the **musa-wiki** knowledge base. It is the MUSA-specific companion to the generic [karpathy-wiki](../karpathy-wiki/SKILL.md) methodology. Any agent maintaining this wiki must follow these rules.

[SKILL.md](SKILL.md) is the skill entry point (frontmatter, quick commands, scope summary). This file is the full operating manual. [references/governance.md](references/governance.md) extends the generic companion-memory model with MUSA-specific governance.

## Role

You are the **maintainer** of the MUSA wiki. Your responsibilities:

- Maintain `wiki/` and `outputs/`.
- **Never modify** `raw/` - it is the immutable source of truth (mirror of docs.mthreads.com).
- Write all wiki pages, keep `index.md` current, log all activity in `log.md`.
- Cite sources with `[[wikilink]]` and raw file paths.

## Subject Domain

This wiki covers the **MUSA SDK** (Meta-computing Unified System Architecture) - Moore Threads' GPU parallel computing platform and programming language, analogous to NVIDIA CUDA. Scope:

- MUSA programming model (SIMT, Grid/Block/Thread, memory hierarchy)
- MUSA C++ syntax (`__global__`, `__shared__`, `<<<>>>`, built-in variables)
- Runtime API and Driver API
- Advanced features (MUSA Graphs, Green Context, Cluster memory, L2 persistence)
- Performance tuning (compute, memory, reduction, GEMM, FlashAttention)
- MUSA SDK toolchain (mcc, musify, MUSA-X libs, muDNN, MCCL, Moore Perf, muPTI)
- MT GPU hardware (MTT S5000/S4000/M1000, MP31/MP21/MP22 architectures)

Out of scope: Moore Threads driver installation, non-MUSA SDK products, unrelated GPU platforms.

## Knowledge Cycle

```
raw ->(ingest)-> wiki ->(query)-> outputs ->(promote)-> wiki or raw
```

## Directory Layout

```
musa-wiki/
├── SKILL.md                     # Skill entry point (frontmatter, quick commands, scope)
├── SCHEMA.md                    # This file - full operating manual
├── references/
│   └── governance.md            # MUSA-specific companion-memory governance
├── raw/
│   ├── sources/                 # Immutable mirror of docs.mthreads.com pages
│   │   ├── _MANIFEST.md         # Catalog of all raw files
│   │   └── *.md                 # One per fetched page (32 files)
├── wiki/
│   ├── index.md                 # Content catalog - READ FIRST on every query
│   ├── log.md                   # Chronological append-only log
│   ├── overview.md              # Global thesis, structure, open tensions
│   ├── sources/                 # Per-chapter source summaries
│   ├── concepts/                # Cross-cutting technical concepts
│   ├── entities/                # Tools, libraries, APIs, hardware
│   └── synthesis/               # Cross-source analysis
└── outputs/
    ├── index.md
    ├── queries/                 # Short Q&A
    ├── reports/                 # Deep reports
    └── artifacts/               # Slides, charts, diagrams
```

## Naming Conventions

- Raw files: `<chapter>_<page>.md` mirroring the URL slug (e.g., `programming_model_thread_hierarchy.md`).
- Wiki source pages: `<chapter>.md` (one per chapter, 7 total).
- Concept/entity pages: `<slug>.md` with kebab-case (e.g., `simt-execution-model.md`, `mcc-compiler.md`).
- Output pages: `outputs/{queries|reports}/YYYY-MM-DD-<slug>.md`.

## Frontmatter

### wiki/ pages

```yaml
---
title: "Page Title"
type: entity | concept | source | synthesis | overview
status: active | stale | disputed | archived
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [raw-filename, ...]
tags: [musa, gpu, ...]
---
```

### outputs/ pages

```yaml
---
title: "Topic"
type: query | report
status: active | promoted
created: YYYY-MM-DD
wiki_refs: [page-slug, ...]
---
```

## Ingest Workflow

When new material is added to `raw/` (e.g., a new doc page fetched from docs.mthreads.com):

1. **TRIAGE** - Read the new raw file(s).
2. **Discuss** - Brief user summary (1-3 sentences) with suggested wiki updates.
3. **Update** the corresponding `wiki/sources/<chapter>.md` page (or create a new chapter page if it's a new top-level section).
4. **Update** `wiki/concepts/` and `wiki/entities/` pages as needed - create new pages for newly-introduced concepts, update existing ones.
5. **CONSOLIDATE** - Flag contradictions with existing wiki content as `disputed`; record in `wiki/overview.md` "Open Tensions".
6. **Update** `wiki/index.md` and append to `wiki/log.md`.

Log entry format:
```markdown
## [YYYY-MM-DD] ingest | Source Title
- raw: `raw/sources/<file>.md`
- touched: [[page-a]], [[page-b]], ...
- notes: ...
```

## Query Workflow

When the user asks a question about MUSA:

1. Read `wiki/index.md` to find relevant pages.
2. Read `wiki/overview.md` and the tail of `wiki/log.md` for recent context.
3. Read the relevant `wiki/concepts/`, `wiki/entities/`, and/or `wiki/sources/` pages.
4. If the wiki lacks the answer, consult the raw files in `raw/sources/` directly.
5. Answer with `[[wikilink]]` citations to wiki pages and `raw/sources/<file>.md` citations for direct source references.
6. Archive the answer:
   - Short Q&A -> `outputs/queries/YYYY-MM-DD-<slug>.md`
   - Deep report -> `outputs/reports/YYYY-MM-DD-<slug>.md`
7. Update `outputs/index.md` and append to `wiki/log.md`.

Log entry format:
```markdown
## [YYYY-MM-DD] query | Topic
- outputs: `outputs/queries/YYYY-MM-DD-<slug>.md`
- wiki_refs: [[page-a]], [[page-b]]
- notes: ...
```

## Lint Workflow

Periodically check `wiki/` and `outputs/` for:
- `disputed` pages needing resolution
- Stale content (updated > 6 months ago, source URL changed)
- Orphan pages (no inbound links)
- Broken `[[wikilink]]` references
- `wiki/index.md` drift from actual content
- Raw files not yet summarized in `wiki/sources/`

## Promote Workflow

When the user requests promoting outputs content into long-term knowledge:

- -> **wiki**: extract into `wiki/synthesis/` or update `concepts/` / `entities/` / `overview.md`; update `wiki/index.md`.
- -> **raw**: only when the user provides a finalized external document to treat as a new source; user places it in `raw/sources/`, then you ingest.

## Governance Rules

See [references/governance.md](references/governance.md) for the full MUSA-specific companion-memory model. Summary:

- **Contradictions flagged as `disputed`, never silently smoothed.** If two raw sources disagree, record both claims and mark the wiki page `disputed`. Link back to the corresponding Open Tension in `overview.md`.
- **Source attribution required.** Every factual claim in `wiki/` must trace back to a `raw/sources/<file>.md` reference. Overview theses with no source attribution must be marked as user hypothesis.
- **Never modify `raw/`.** It is the ground truth.
- **Preserve minority/contrary evidence** in `wiki/synthesis/` or standalone pages - do not delete technically-valid alternative approaches.
- **Hardware specificity.** MUSA has architecture-dependent behavior (warp size 32 on MP31/S5000 vs 128 on MP21/MP22/M1000/S4000). Always note which architecture a claim applies to. Use the `warpSize` built-in, never the literal `32`.
- **CUDA analogy flagged, not assumed.** Say "MUSA equivalent of X" or "differs from CUDA in Y", not "same as X". Cross-reference [[cuda-to-musa-mapping]].
- **Open Tensions stay open.** The 5 items in `overview.md` "Open Tensions" are not silently resolved; new evidence updates a tension rather than deleting it.

## Citation Conventions

- Wiki page reference: `[[page-slug]]` (e.g., `[[simt-execution-model]]`).
- Raw source reference: `` `raw/sources/<file>.md` `` or inline `-> raw: what_is_musa_musa_sdk.md`.
- External URL: full URL, e.g., `https://docs.mthreads.com/musa-sdk/...`.
- Section within a page: `[[page-slug#section]]`.

## Quick Commands

| User says | Agent does |
|-----------|------------|
| `摄入 <path>` or `ingest <path>` | Ingest new raw file(s) |
| `查 ...` or `query ...` | Answer from wiki, archive to outputs/ |
| `lint` | Health-check wiki + outputs |
| `升格 outputs/...` or `promote outputs/...` | Promote to wiki or raw |
| `状态` or `status` | Show index + log tail + open disputes |
