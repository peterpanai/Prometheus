# Methodology: LLM Wiki Pattern

> Source: [Karpathy LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
> Author: Andrej Karpathy · 2026-04-04

## The Core Idea

Most people's experience with LLMs and documents looks like RAG: you upload a collection of files, the LLM retrieves relevant chunks at query time, and generates an answer. This works, but the LLM is rediscovering knowledge from scratch on every question. There's no accumulation. Ask a subtle question that requires synthesizing five documents, and the LLM has to find and piece together the relevant fragments every time. Nothing is built up.

The LLM Wiki pattern is different. Instead of retrieving from raw documents at query time, the LLM **incrementally builds and maintains a persistent wiki** — a structured, interlinked collection of markdown files that sits between you and the raw sources. When you add a new source, the LLM:

- Reads and extracts key information
- Integrates it into the existing wiki — updating entity pages, revising topic summaries
- Notes where new data contradicts old claims
- Strengthens or challenges the evolving synthesis

The knowledge is compiled once and then _kept current_, not re-derived on every query.

## Key Difference from RAG

| RAG | LLM Wiki |
|-----|----------|
| Retrieve chunks at query time | Pre-compile knowledge into wiki |
| No accumulation between queries | Persistent, compounding artifact |
| Cross-references discovered per-query | Cross-references maintained long-term |
| Contradictions found ad-hoc | Contradictions flagged during ingest |
| Knowledge scattered across documents | Knowledge organized in interlinked pages |

## Architecture: Three Layers

1. **Raw Sources** — curated source documents. Immutable. LLM reads but never modifies. Source of truth.

2. **The Wiki** — LLM-generated markdown files. Summaries, entity pages, concept pages, comparisons, overview, synthesis. LLM owns this layer entirely.

3. **The Schema** — a document (CLAUDE.md or AGENTS.md) that tells the LLM how the wiki is structured, conventions, and workflows. Makes the LLM a disciplined wiki maintainer rather than a generic chatbot.

## Three Operations

### Ingest
User drops a new source into raw and tells the LLM to process it. The LLM: reads source → discusses key takeaways with user → writes summary → updates index → updates relevant entity/concept pages → appends log entry. One source may touch 10-15 wiki pages.

### Query
User asks questions against the wiki. The LLM: searches relevant pages → reads them → synthesizes answer with citations. Good answers get filed back into the wiki as new pages — explorations compound like ingested sources.

### Lint
Periodic health-check: contradictions between pages, stale claims, orphan pages, missing cross-references, index drift. The LLM suggests new questions to investigate and new sources to look for.

## Indexing: Two Special Files

- **index.md** (content-oriented): catalog of everything — each page with link, one-line summary, category. LLM reads index first on every query. Works at moderate scale (~100 sources, ~hundreds of pages).
- **log.md** (chronological): append-only record. Consistent prefix format allows grep: `grep "^## \[" log.md | tail -5`.

## Why It Works

The tedious part of maintaining a knowledge base is bookkeeping: updating cross-references, keeping summaries current, noting contradictions, maintaining consistency across dozens of pages. Humans abandon wikis because the maintenance burden grows faster than the value. LLMs don't get bored, don't forget cross-references, and can touch many files in one pass. Maintenance cost is near zero.

The human's job: curate sources, direct analysis, ask good questions, think about meaning.  
The LLM's job: everything else.

## Memex Spirit

Related to Vannevar Bush's Memex (1945) — a personal, curated knowledge store with associative trails between documents. Bush's vision was closer to this than to what the web became: private, actively curated, with connections between documents as valuable as the documents themselves. The part Bush couldn't solve was who does the maintenance. The LLM handles that.

## Example Domains

- **Personal**: goals, health, psychology, self-improvement — structured self-knowledge over time
- **Research**: deep topic exploration over weeks/months with evolving thesis
- **Reading a book**: companion wiki with characters, themes, plot threads (think fan wikis)
- **Business/team**: internal wiki fed by Slack, meetings, project docs, customer calls
- **Competitive analysis, due diligence, trip planning, course notes, hobby deep-dives**

## Tips

- **Obsidian Web Clipper**: browser extension for clipping articles to markdown
- **Download images locally**: set Obsidian attachment folder to `raw/assets/`
- **Obsidian graph view**: best way to see wiki shape — hubs, orphans, connections
- **Marp**: markdown-based slide decks from wiki content
- **Dataview**: Obsidian plugin for querying page frontmatter
- **Git**: version history, branching, collaboration for free
