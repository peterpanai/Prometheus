---
title: "MUSA Wiki Outputs Index"
type: overview
status: active
created: 2026-07-07
updated: 2026-07-07
---

# MUSA Wiki Outputs Index

Catalog of generated outputs (queries, reports, artifacts). Outputs are derived from the wiki and may be promoted back into `wiki/synthesis/` or `raw/` if they prove durable.

## Structure

```
outputs/
├── index.md         # this file
├── queries/         # short Q&A, exploratory notes (date-prefixed)
├── reports/         # deep research, analysis (date-prefixed)
└── artifacts/       # slides, charts, PDFs, canvas
```

## Status

No outputs generated yet. The wiki was just constructed (see `../wiki/log.md`).

## How to Use

### Query

When you ask a question that warrants archiving (e.g. "how does warp divergence affect occupancy on S5000?"), the answer will be saved as `queries/YYYY-MM-DD-<slug>.md` with frontmatter:

```yaml
title: "Topic"
type: query
status: active | promoted
created: YYYY-MM-DD
wiki_refs: [[page1]], [[page2]]
```

### Report

Deeper analysis or research that synthesizes multiple wiki pages becomes `reports/YYYY-MM-DD-<slug>.md`. Example use cases:
- "Compare S5000 vs H100 for inference workloads"
- "When to use MUTLASS vs hand-written GEMM"
- "MUSA optimization checklist for LLM training"

### Artifacts

Visual outputs (charts, diagrams, slides) go in `artifacts/`. Subdirectories by type if needed.

## Promotion

When an output proves durable (cited multiple times, becomes reference material), it can be promoted:

- **To wiki/synthesis/**: cross-cutting analysis
- **To wiki/concepts/** or **wiki/entities/**: new topic discovered
- **To raw/**: only when user provides a finalized document to treat as a new source

See `../SCHEMA.md` for the promote workflow.

## Quick Commands

| User says | Agent does |
|-----------|------------|
| `查 / query ...` | Query → `queries/YYYY-MM-DD-<slug>.md` |
| `report ...` | Deep analysis → `reports/YYYY-MM-DD-<slug>.md` |
| `升格 outputs/...` | Promote to wiki or raw |
