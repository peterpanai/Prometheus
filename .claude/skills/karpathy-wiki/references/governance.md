# Governance: Companion Memory

> Source: Stefan Miteski, [Memory as Metabolism: A Design for Companion Knowledge Systems](https://doi.org/10.5281/zenodo.19559895) (2026)

## Design Principle

Personal LLM memory is a **companion system** with two complementary duties:

| Duty | Description |
|------|-------------|
| **Mirror** | Reflect the user's working vocabulary, cognitive load structure, and contextual continuity |
| **Compensate** | Actively resist knowledge calcification, suppressed contradictions, and Kuhnian paradigm rigidity |

A companion memory that only mirrors reinforces blind spots. One that only compensates feels adversarial. The system must do both.

## Five Metabolic Operations

| Operation | In Karpathy Wiki |
|-----------|-----------------|
| **TRIAGE** | Ingest: initial classification of new sources |
| **DECAY** | Lint: mark stale pages, archive low-value content |
| **CONTEXTUALIZE** | Entity/concept pages: situate facts in user's context |
| **CONSOLIDATE** | Synthesize into overview/synthesis, preserving disputes |
| **AUDIT** | Lint: full wiki health check |

Just as biological metabolism involves both building up (anabolism) and breaking down (catabolism), a healthy wiki needs both ingestion and decay.

## Practical Constraints

- Contradictions must be flagged as `disputed`, never silently smoothed over
- Minority or contrary evidence should be preserved in synthesis pages or standalone
- Overview core theses must have source attribution or be explicitly marked as user hypothesis
- The `overview.md` "Open Tensions" table is the visible register of unresolved contradictions

## Anti-Patterns

- Silently removing contradictory claims to make the wiki "clean"
- Rewriting overview theses without source evidence
- Archiving disputed pages without linking to the dispute
- Allowing synthesis to drift into ungrounded speculation

## See Also

- [methodology.md](methodology.md) — the LLM Wiki pattern this governance model was designed for
