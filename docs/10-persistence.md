# 10 — Save & Persistence

> **Status (Week 7) — decided, see [ADR-0005](adr/0005-json-save-format.md).**
>
> This document describes the **release** persistence design. It is not what is
> implemented. `grow_data` persists the whole `GameState` as one JSON document
> through `SaveCodec`, behind a `SaveRepository` interface.
>
> That is now a recorded decision rather than a drift: **JSON is the pre-release
> format, Drift is the release format, and the boundary is the first build
> handed to anyone outside the team.** `SaveFormat.released` holds that boundary
> as data, and `save_format_test.dart` fails the build if a released version
> ever loses its migration path. ADR-0005 has the cutover plan and the checklist
> that must be green before a first release.
>
> Everything below stands as the target. Read it as specification, not as
> description.

## 1. Choice: Drift (SQLite), not a JSON blob

A single serialised save document is simpler for two weeks and a liability for two
years. Normalised SQLite gives us partial writes, cheap queries for the field
guide and statistics, real migrations, and — decisively — **a schema that cloud
sync can be added to without a rewrite.**

Cost: schema ceremony and generated code. Accepted.

## 2. Schema

```
player          (id, level, xp, world_seed, created_at, sim_time, content_version)
plots           (id, biome_id, slot_count, unlocked_slots)
plot_slots      (id, plot_id, index, soil_type, ground_cover)
trees           (id, species_id, seed, slot_id, health, water, nutrition,
                 growth, stage, state, planted_at, last_tended_at,
                 critical_hours, critical_sightings, times_watered, times_fed,
                 is_flowering, mutation_id)
tree_traits     (tree_id, trait_id, discovered_at)
afflictions     (id, tree_id, kind, severity, started_at)
inventory       (resource_key, amount, cap)
seeds           (species_id, count)
items           (item_id, count)
codex_species   (species_id, discovered_at, times_grown, best_stage)
codex_animals   (animal_id, first_seen_at, times_seen)
focus_sessions  (id, planned_ms, actual_ms, started_at, mode, integrity,
                 gp, water, nutrients, xp, seed_id, boot_id, start_monotonic_ms)
daily_stats     (day_index, sessions, minutes, gp, notifications_sent)
screen_time_day (day_index, screen_on_minutes, under_goal)     -- 14-day rolling
challenges      (id, kind, template_id, progress, target, claimed, expires_at)
streak          (current, longest, shields, last_day_index, second_wind_until)
settings        (key, value)
meta            (key, value)   -- schema_version, sim_time_high, hmac, boot_id
```

**Every table carries three sync-readiness columns from day one:**

```
updated_at  INTEGER NOT NULL      -- ms, from TimeAuthority
rev         INTEGER NOT NULL      -- per-row revision counter
deleted     INTEGER NOT NULL      -- tombstone flag, never a hard DELETE
```

They cost almost nothing now and are the difference between "add cloud sync in a
sprint" and "add cloud sync in a quarter." Last-writer-wins per row with a
Lamport-style `rev` handles every conflict this game can actually produce.

## 3. What is *not* in the save

Species stats, animal definitions, biome parameters, balance constants. The save
stores `species_id`; the numbers live in bundled content JSON
([04 §6](04-data-models.md#6-why-content-and-save-are-separate)). Rebalancing an
Oak in v1.3 updates every existing Oak with no migration.

`player.content_version` records which content build a save was written against,
so the loader can substitute a stand-in if a species is ever removed rather than
crashing.

## 4. Write policy

Single-writer `SaveRepository` with a serialised write queue. Every write is one
transaction. Saves are triggered on:

- any player action (water, feed, plant, claim) — immediately,
- focus session start and end — immediately, with the monotonic anchor,
- `AppLifecycleState.paused` / `inactive` — **the critical one**,
- a 60-second dirty-check while in the foreground,
- before scheduling notifications (so the projection matches what was saved).

`paused` is the important hook: Android can kill a backgrounded process without
further warning, and the simulation only needs the last-saved timestamp to be
correct to recover perfectly.

## 5. Integrity

- `meta.hmac` = HMAC-SHA256 over a canonical serialisation of the mutable tables,
  keyed from platform secure storage (Keychain / Android Keystore).
- `meta.sim_time_high` mirrors the highest `sim_time` ever reached, stored
  **outside the database** — iOS Keychain (survives app deletion), Android
  `EncryptedSharedPreferences` with `android:allowBackup` exclusion.
- On load: if `sim_time < sim_time_high`, the save is behind the watermark. The
  game **does not accuse anyone and does not wipe anything**; it advances
  `sim_time` to the watermark without granting rewards for the skipped interval.
  A restored backup therefore works, it just does not print money.
- A failed HMAC is treated as corruption, not cheating → backup recovery (§6).

Per [05 §8](05-simulation.md#8-clock-integrity) and the brief: no server, no
attestation, no fingerprinting. This stops accidents and casual exploits and
nothing more, on purpose.

## 6. Corruption recovery

Three rotating backups (`grow.db.bak.0/1/2`), rotated on successful launch after
a clean load. On a corrupt or failed-integrity open:

1. try the newest backup, then the next, then the next;
2. if all fail, extract whatever is readable via a salvage query (trees and codex
   above all — a player's discovered species list is the most emotionally costly
   thing to lose) into a fresh database;
3. only then, a fresh save, with an in-app explanation and an offer of a small
   compensation grant.

The player is never shown a raw error and never silently reset.

## 7. Migrations

Drift `MigrationStrategy` with one numbered step per schema version and a
matching `test/migration/vN_to_vN1_test.dart` that opens a **committed fixture
database** from the previous version and asserts the result. Schema snapshots are
checked into `test/fixtures/schema/`.

Rule: **a migration PR without a fixture test does not merge.** Silent save
corruption on update is the single worst failure mode a game like this has,
because the loss is irreplaceable and the review will say so.

## 8. Cloud sync readiness (post-MVP, explicitly out of MVP scope)

Nothing is built now. What is *reserved* now:

- the three sync columns on every table,
- a stable `world_seed` as the account-independent save identity,
- deterministic simulation, so a device can replay to a common `sim_time` rather
  than merging divergent vitals,
- no wall-clock dependence in game logic, so two devices in different timezones
  agree.

The eventual design is: sync the **event journal plus periodic state snapshots**,
resolve by `(rev, updated_at)` per row, and treat `sim_time` as the merge clock.
The determinism guarantee in [05 §1](05-simulation.md#1-time-model) is what makes
that tractable.
