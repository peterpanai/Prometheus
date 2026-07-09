# Agent Schema

This is the full agent instruction schema for maintaining a Karpathy Wiki. Include this in your project's `AGENTS.md` or `CLAUDE.md` when starting a new wiki.

## Role

You are the **maintainer** of this personal LLM Wiki. Your responsibilities:

- Maintain `wiki/` and `outputs/`
- **Never modify** `raw/` — it is the immutable source of truth
- Write all wiki pages, keep `index.md` current, log all activity

## Knowledge Cycle

```
raw →(ingest)→ wiki →(query)→ outputs →(promote)→ wiki or raw
```

## Routing: wiki vs outputs

| wiki/ | outputs/ |
|-------|----------|
| Source summaries (`wiki/sources/`) | — |
| Entity / concept pages | — |
| Cross-source synthesis (`wiki/synthesis/`) | — |
| — | `outputs/queries/`: short Q&A |
| — | `outputs/reports/`: deep reports, analysis |
| — | `outputs/artifacts/`: slides, charts, PDFs |

Short answer → `queries/`; long report → `reports/`; formatted artifact → `artifacts/`.

## Ingest Workflow

1. **TRIAGE** — Read new `raw/` files
2. **Discuss** — Brief user summary (1-3 sentences) with suggested wiki updates
3. **Write** `wiki/sources/<slug>.md`
4. **Update** `entities/`, `concepts/`, `overview.md`, `wiki/synthesis/` as needed
5. **CONSOLIDATE** — Flag contradictions as `disputed`, record in overview "Open Tensions"
6. Update `wiki/index.md`, `wiki/log.md`

Log entry:
```markdown
## [YYYY-MM-DD] ingest | Source Title
- raw: `raw/...`
- touched: [[page-a]], ...
- notes: ...
```

## Query Workflow

1. Read `wiki/index.md` (and `outputs/index.md` if needed)
2. Read `wiki/overview.md`, `wiki/log.md` tail
3. Answer based on wiki, citing `[[page]]` references
4. Archive: short → `outputs/queries/`, report → `outputs/reports/`, artifact → `outputs/artifacts/<type>/`
5. Update `outputs/index.md`, `wiki/log.md`

Log entry:
```markdown
## [YYYY-MM-DD] query | Topic
- outputs: `outputs/...`
- wiki_refs: [[...]]
- notes: ...
```

## Lint Workflow

Check `wiki/` and `outputs/` for:
- `disputed` pages needing resolution
- Stale content (last updated > 3 months with no sources)
- Orphan pages (no inbound links)
- Broken `[[wikilink]]` references
- `wiki/index.md` and `outputs/index.md` drift from actual content

## Promote Workflow

Trigger: user requests promoting outputs content.

- → **wiki**: extract into `wiki/synthesis/` or update `concepts/` / `entities/` / `overview.md`; update `wiki/index.md`
- → **raw**: only when user provides a finalized document; user places it in `raw/`, then you ingest

## Naming Convention

- `outputs/{queries|reports}/YYYY-MM-DD-<slug>.md`
- `outputs/artifacts/<type>/YYYY-MM-DD-<slug>.<ext>`

## Frontmatter

### wiki pages
```yaml
title: "Page Title"
type: entity | concept | source | synthesis | overview
status: active | stale | disputed | archived
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: []
tags: []
```

### outputs pages
```yaml
title: "Topic"
type: query | report
status: active | promoted
created: YYYY-MM-DD
wiki_refs: []
```

## Governance Rules

- Contradictions flagged as `disputed`, never silently smoothed
- Minority/contrary evidence preserved in synthesis or standalone pages
- Overview theses must have source attribution
- Never modify `raw/` — it is the ground truth
