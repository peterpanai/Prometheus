# Governance: MUSA Wiki Companion Memory

> Extends [../../karpathy-wiki/references/governance.md](../../karpathy-wiki/references/governance.md) with MUSA-specific metabolic concerns.
> Source model: Stefan Miteski, [Memory as Metabolism](https://doi.org/10.5281/zenodo.19559895) (2026).

## Design Principle

The MUSA wiki is a **companion system** with two complementary duties:

| Duty | Description |
|------|-------------|
| **Mirror** | Reflect the user's MUSA working context: target GPU (S5000 vs S4000 vs M1000), SDK version, porting vs greenfield, optimization vs correctness focus |
| **Compensate** | Actively resist the three MUSA-specific calcification risks: **CUDA-analogy drift**, **architecture-blind assumptions**, and **undocumented-behavior smoothing** |

A companion memory that only mirrors reinforces blind spots (e.g. silently assuming S5000 is the only target). One that only compensates feels adversarial (e.g. flagging every CUDA analogy as suspicious). The system must do both.

## MUSA-Specific Metabolic Operations

The generic companion memory defines five metabolic operations. Here is how each maps to MUSA wiki maintenance:

| Operation | Generic Meaning | MUSA-Specific Application |
|-----------|-----------------|---------------------------|
| **TRIAGE** | Initial classification of new sources | Detect which MT architecture (MP21/MP22/MP31) and SDK version each raw doc targets; route to the right chapter page |
| **DECAY** | Mark stale pages, archive low-value content | Flag pages when SDK advances (v5.x -> v6.x) or new arch launches; mark `status: stale` when docs.mthreads.com URL changes |
| **CONTEXTUALIZE** | Situate facts in user's context | Every performance/correctness claim notes warp size (32 vs 128) and target arch; never write architecture-blind guidance |
| **CONSOLIDATE** | Synthesize, preserving disputes | The 5 Open Tensions in `overview.md` stay visible; new evidence updates a tension rather than deleting it |
| **AUDIT** | Full wiki health check | Verify hardware-specific claims against the correct arch; check CUDA-analogy pages against [[cuda-to-musa-mapping]] for drift |

Just as biological metabolism requires both anabolism (building up) and catabolism (breaking down), a healthy MUSA wiki needs both ingestion (new docs from docs.mthreads.com) and decay (stale pages when SDK moves on).

## MUSA Governance Rules

1. **Hardware specificity is mandatory.** Every performance or correctness claim must note which MT architecture it applies to. `warpSize` is the most common footgun: 32 on MP31/S5000, 128 on MP21/MP22/S4000/M1000. Pages making warp assumptions must use the `warpSize` built-in, not the literal `32`. See [[warp-functions]], [[simt-execution-model]].

2. **CUDA analogy flagged, not assumed.** MUSA is ~95% CUDA-compatible but the 5% differences bite. Pages must say "MUSA equivalent of X" or "differs from CUDA in Y", not "same as X". [[cuda-to-musa-mapping]] is the canonical diff register - any new analogy page must cross-reference it.

3. **Source attribution to docs.mthreads.com.** Every factual claim in `wiki/` traces to a `raw/sources/<file>.md`. Overview theses without source backing must be marked as user hypothesis. Raw file paths are cited as `` `raw/sources/<file>.md` ``.

4. **Open Tensions stay open.** The 5 items in `wiki/overview.md` "Open Tensions" (see register below) are not to be silently resolved. If new evidence arrives, update the tension; do not delete it. If a wiki page touches one of these topics, the page must link back to the tension.

5. **Version drift tracked.** MUSA SDK is at v5.x with backward-compatibility guarantees since v5.1. When a page references an API, note the introducing version if behavior changed across versions. When SDK advances, audit affected pages and mark `status: stale` where docs have moved on.

6. **Never modify `raw/`.** Raw files are the immutable mirror of docs.mthreads.com. They carry header comments with source URL and "do not edit" notice. If the official docs change, fetch the new version into `raw/sources/` as a new file (or overwrite only with explicit user approval), then re-ingest.

7. **Preserve minority/contrary evidence.** MP21/MP22 (128-lane warps) are not the flagship, but their differences from MP31 must be preserved in pages like [[warp-functions]], [[simt-execution-model]], [[mtt-s5000]]. Do not delete architecture-specific notes because "MP31 is the flagship".

## The Open Tensions Register

`wiki/overview.md` "Open Tensions / Disputed Claims" section is the visible dispute register. Five items currently:

1. **Warp size rationale** - The official docs do not explain *why* MP21/MP22 use 128-lane warps while MP31 reverted to 32. The "128 was an experiment, MP31 converged with CUDA" interpretation is **speculation, not documented**.
2. **Green Context vs MIG isolation strength** - Docs describe Green Context as "MP partition" but don't quantify isolation strictness (cache, memory bandwidth). Whether it matches MIG's hardware isolation or is closer to MPS's soft partitioning is **unclear from docs alone**.
3. **FlashAttention version** - Programming guide references FlashAttention but doesn't specify v1/v2/v3. The muDNN library implements some version - **verify against actual SDK release notes**.
4. **L2 persistence scope across streams** - Docs show stream-scoped policy windows, but behavior when multiple streams access the same buffer with different policies is **underspecified**.
5. **Cluster max size** - Docs say "typically 8 or 16" blocks per cluster, but exact hardware limit per architecture is **not tabulated**. Query via `musaDevAttrClusterLaunch`.

### Handling a disputed claim in a wiki page

When you encounter a claim that contradicts a source or another page:

1. Set `status: disputed` in the page's frontmatter.
2. Add a "Disputed" section in the page body explaining the discrepancy.
3. Link back to the corresponding Open Tension item in `[[overview#open-tensions--disputed-claims]]`.
4. If it's a new kind of tension, add it to the register in `overview.md` and append a log entry.
5. **Do not silently pick one interpretation** to make the page "clean".

## Anti-Patterns

- Writing `warpSize == 32` literally instead of using the built-in (breaks on MP21/MP22)
- Treating Green Context as MIG-equivalent without flagging the isolation-strength ambiguity
- Picking a FlashAttention version (v1/v2/v3) and stating it as fact when muDNN release notes aren't checked
- Deleting MP21/MP22-specific notes because "MP31 is the flagship"
- Smoothing over the L2-persistence-across-streams ambiguity by picking one behavior
- Porting CUDA optimization intuition into [[optimization-playbook]] without noting where MUSA diverges
- Silently removing contradictory claims to make a wiki page "clean"
- Rewriting an overview thesis without source attribution
- Archiving a disputed page without linking to the corresponding Open Tension
- Letting synthesis drift into ungrounded speculation (no raw source backing)

## Citation Conventions

- Wiki page reference: `[[page-slug]]` (e.g., `[[simt-execution-model]]`).
- Raw source reference: `` `raw/sources/<file>.md` `` or inline `-> raw: what_is_musa_musa_sdk.md`.
- External URL: full URL, e.g., `https://docs.mthreads.com/musa-sdk/...`.
- Section within a page: `[[page-slug#section]]`.
- Open Tension reference: `[[overview#open-tensions--disputed-claims]]` or the numbered item.

## See Also

- [../SCHEMA.md](../SCHEMA.md) - full agent operating manual (workflows, frontmatter, naming)
- [../../karpathy-wiki/references/governance.md](../../karpathy-wiki/references/governance.md) - generic companion memory model
- [../../karpathy-wiki/references/methodology.md](../../karpathy-wiki/references/methodology.md) - LLM Wiki pattern (Karpathy)
