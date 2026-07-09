---
name: karpathy-wiki
description: Build and maintain personal LLM wikis using the Karpathy Wiki pattern. Three-layer architecture (raw/wiki/outputs) with ingest/query/lint/promote lifecycle. Use when building personal knowledge bases, maintaining structured wikis with AI agents, or implementing companion memory systems. Triggers on requests to create wikis, ingest sources, query knowledge, or lint wiki health.
license: MIT
metadata:
  author: github.com/panmcai
  version: "1.0.0"
---

# Karpathy Wiki

Based on [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) with governance from [Memory as Metabolism](https://doi.org/10.5281/zenodo.19559895).

## Core Idea

Instead of RAG (retrieve-and-forget), the LLM **incrementally builds and maintains a persistent wiki** — a structured, interlinked collection of markdown files. Knowledge is compiled once and kept current, not re-derived on every query. The wiki is a persistent, compounding artifact.

## Three-Layer Architecture

| Layer | Path | Role | Rules |
|-------|------|------|-------|
| Raw Sources | `raw/` | Immutable source material | **Never modify.** LLM reads only. Single source of truth. |
| Wiki | `wiki/` | Structured knowledge core | LLM writes and maintains all pages, `index.md`, `log.md` |
| Outputs | `outputs/` | Queries, reports, artifacts | LLM generates; can be promoted back to wiki |

**Knowledge cycle**: `raw` →(ingest)→ `wiki` →(query)→ `outputs` →(promote)→ `wiki` or `raw`

## Directory Convention

```
wiki/
├── index.md         # Content catalog (LLM-maintained)
├── log.md           # Chronological append-only log
├── overview.md      # Global summary, thesis, open tensions
├── entities/        # People, projects, tools
├── concepts/        # Ideas, patterns, terminology
├── sources/         # Source summaries (link back to raw/)
└── synthesis/       # Cross-source synthesis

outputs/
├── index.md         # Output catalog
├── queries/         # Short Q&A, exploratory notes
├── reports/         # Deep research, analysis
└── artifacts/       # Slides, charts, PDFs, canvas
```

## Page Frontmatter

### wiki/ pages

```yaml
title: "Page Title"
type: entity | concept | source | synthesis | overview
status: active | stale | disputed | archived
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: []
tags: []
```

### outputs/ pages

```yaml
title: "Topic"
type: query | report
status: active | promoted
created: YYYY-MM-DD
wiki_refs: []
```

## Operations

### Ingest (raw → wiki)

Trigger: user drops material into `raw/` and requests processing.

1. **TRIAGE** — Read new files in `raw/`
2. **Discuss** — Summarize key takeaways for user (1-3 sentences)
3. **Write** `wiki/sources/<slug>.md` — source summary page
4. **Update** `entities/`, `concepts/`, `overview.md`, `wiki/synthesis/` as needed
5. **CONSOLIDATE** — Flag contradictions as `disputed`, note in overview "open tensions"
6. **Maintain** `wiki/index.md` and `wiki/log.md`

Log format:
```markdown
## [YYYY-MM-DD] ingest | Source Title
- raw: `raw/...`
- touched: [[page-a]], ...
- notes: ...
```

### Query (wiki → answer → outputs)

Trigger: user asks a question.

1. Read `wiki/index.md` (and `outputs/index.md` if needed)
2. Read `wiki/overview.md` and `wiki/log.md` tail
3. Answer based on wiki, citing pages with `[[wikilink]]`
4. Archive:
   - Short Q&A → `outputs/queries/YYYY-MM-DD-<slug>.md`
   - Deep reports → `outputs/reports/YYYY-MM-DD-<slug>.md`
   - Slides/charts → `outputs/artifacts/<type>/...`
5. Update `outputs/index.md`, `wiki/log.md`

### Lint

Check `wiki/` and `outputs/` for: `disputed` pages, stale content, orphan pages, broken links, index drift.

### Promote

Trigger: user requests promoting outputs content into long-term knowledge.

- → **wiki**: extract into `wiki/synthesis/` or update `concepts/` / `entities/` / `overview.md`
- → **raw**: only when user provides a finalized document to treat as a new source

## Index & Log

- **`index.md`**: content-oriented catalog. LLM reads this first on every query. Works at moderate scale without vector search.
- **`log.md`**: chronological append-only record. Parseable: `grep "^## \[" log.md | tail -5` gives recent entries.

## Governance (Companion Memory)

The wiki is a **companion system** with two duties:
- **Mirror**: reflect the user's working vocabulary, context, load structure
- **Compensate**: resist calcification, suppressed contradictions, Kuhnian rigidity

Rules:
- Contradictions flagged as `disputed`, never silently smoothed
- Minority/contrary evidence preserved in synthesis or standalone pages
- Overview thesis must have source attribution or be marked as user hypothesis

See [references/governance.md](references/governance.md) for the full metabolic model.

## Quick Commands

| User says | Agent does |
|-----------|------------|
| `摄入 path` | Ingest |
| `查 / query ...` | Query → `outputs/queries/` or `reports/` |
| `lint` | Health-check wiki + outputs |
| `升格 outputs/...` | Promote to wiki or raw |
| `状态` | Show index + log tail + open disputes |

## Tool Ecosystem

- **Obsidian**: browse, graph view, wikilink navigation
- **Obsidian Web Clipper**: clip articles → `raw/sources/`
- **Git**: version history, collaboration
- **qmd**: local hybrid search (BM25/vector) for larger wikis

## References

- [references/methodology.md](references/methodology.md) — Karpathy's original LLM Wiki pattern in detail
- [references/governance.md](references/governance.md) — Companion Memory metabolic model
- [references/schema.md](references/schema.md) — Full agent schema for wiki maintenance
