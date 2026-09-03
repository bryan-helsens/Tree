# ADR-0005 — JSON is the pre-release save format; Drift is the release format

**Status:** Accepted (Week 7)
**Supersedes nothing. Constrains:** [docs/10 — Save & Persistence](../10-persistence.md)

## Context

docs/10 §1 specifies **Drift (SQLite) with a normalised schema**, and gives
good reasons: partial writes, cheap queries for the field guide and statistics,
real migrations, and a shape cloud sync can be added to without a rewrite.

`grow_data` ships something else: the whole `GameState` encoded as one JSON
document through `SaveCodec`, behind a `SaveRepository` interface. That was a
Week 6 slice decision and it was not flagged as a decision at the time, which
is the actual problem this ADR exists to fix.

The choice was put explicitly as: implement Drift now, or formally define the
JSON format as versioned and temporary with a concrete migration boundary.

## Decision

**Option B. The JSON document is the pre-release save format. Drift is the
release format. The boundary is the first build handed to anyone outside the
team.**

Not "we'll migrate it later". The boundary is a named event, and the promise is
enforced by a test rather than by memory.

### What is true now

1. `SaveFormat.version` is the version this build writes. `SaveCodec` reads it
   through `SaveFormat.migrate`, which brings an older document forward and
   **refuses a newer one** rather than half-reading it.
2. `SaveFormat.migrations` is the registry of `n → n+1` steps. It is empty at
   version 1, correctly — there is nothing older. The machinery exists now so
   that the first migration is written calmly rather than under pressure.
3. `SaveFormat.released` is **the migration boundary, as data**. It lists every
   version that has been inside a build given to anyone outside the team —
   TestFlight and internal tracks count.
4. `save_format_test.dart` fails the build if any released version lacks an
   unbroken chain of steps to the current version. While `released` is empty
   the format is private and may change freely: dev saves may be reset, because
   everyone holding one can be told.

**Adding to `released` is the act of shipping, and belongs in the same commit
as the release.** From that moment the format is frozen except through
migrations, and the tripwire test in `save_format_test.dart` fails until this
ADR is updated with a dated Drift plan.

### Why not implement Drift now

Not because the design is wrong — it is not — but because the cost lands at the
wrong time and buys nothing yet:

- Drift means a dependency, `build_runner` codegen, and ~15 table definitions
  over a domain that has changed materially every week of this phase. The
  schema would be rewritten several times before anyone reads from it.
- The three things the normalised schema buys — partial writes, field-guide
  queries, sync-readiness — have **no consumer in the slice**. There is one
  tree, no field guide, and no account system.
- The atomicity guarantee the game actually depends on is already stronger with
  one document than with fifteen tables. A focus session's reward and its
  `claimed` phase are fields of the same object, so exactly-once needs no
  transaction at all (docs/22 §8). Under Drift this becomes a transaction that
  has to be correct.

### Why not leave it implicit

Because the cost of the JSON format is not paid by us; it is paid by the first
player whose save cannot be read. That cost is zero today and grows with the
install base, and the only moment at which it is cheap to act is before the
first release. Hence the boundary, and hence the test.

## The cutover, concretely

`SaveRepository` is the seam and does not change. Neither does any caller.

1. Add `DriftSaveRepository implements SaveRepository`, with the docs/10 schema.
2. On first launch after the update, if a JSON save exists and the Drift
   database is empty: decode it with `SaveCodec`, write it through the Drift
   repository in one transaction, and keep the JSON file as a backup for one
   release cycle. `GuardedSaveRepository` already knows how to fall back.
3. `SaveCodec` becomes an **import path only** — it stops being written to.
4. From then on, schema changes are Drift `MigrationStrategy` steps, and
   `SaveFormat.migrations` covers only the JSON-era versions still in the wild.

That import is ~50 lines and is possible precisely because the JSON document is
a whole `GameState`: there is nothing to reconcile, only to write.

### What has to be true before the first release

- [ ] `DriftSaveRepository` exists and passes the `SaveRepository` contract
      tests, including the atomicity and corrupt-load cases.
- [ ] The JSON → Drift import is implemented and tested from a real v1 document.
- [ ] `docs/10` describes what is implemented rather than what is intended.
- [ ] The version being shipped is added to `SaveFormat.released` in the
      release commit.

If a build goes out before those are done, the JSON version ships and the
migration debt becomes real. That is a decision someone can make deliberately —
it is not one that can now be made by forgetting.

## Consequences

- The slice keeps a save layer that is small, readable, and has no codegen.
- The Drift work is deferred but **dated**: it is due before the first external
  build, not "later".
- One test guards the boundary, and it fails loudly rather than silently.
- If the project never ships externally, the debt is never paid, which is the
  correct outcome for a format nobody outside the team ever held.
