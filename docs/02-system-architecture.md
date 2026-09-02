# 02 — System Architecture

## 1. Layer model

```
┌──────────────────────────────────────────────────────────────────────┐
│  PRESENTATION                                                        │
│  grow_app/features/*        Flutter widgets, routing, design system   │
│  grow_render               Flame world, procedural trees, shaders     │
└───────────────▲──────────────────────────────────────┬───────────────┘
                │ WorldSnapshot (immutable, per frame) │ Intent
┌───────────────┴──────────────────────────────────────▼───────────────┐
│  APPLICATION                                                         │
│  Riverpod controllers · use cases · FocusSessionOrchestrator          │
│  RewardService · ChallengeService · NotificationScheduler             │
└───────────────▲──────────────────────────────────────┬───────────────┘
                │ GameState                            │ commands
┌───────────────┴──────────────────────────────────────▼───────────────┐
│  DOMAIN                                                              │
│  grow_domain   entities, value objects, invariants (pure Dart)        │
│  grow_sim      deterministic simulator (pure Dart, no I/O, no clock)  │
│  grow_content  species / animal / biome definitions (data)            │
└───────────────▲──────────────────────────────────────┬───────────────┘
                │                                      │
┌───────────────┴──────────────────────────────────────▼───────────────┐
│  INFRASTRUCTURE                                                      │
│  grow_data (Drift)  ·  plugins/grow_screen_time  ·  grow_time_authority│
│  notifications  ·  audio  ·  local analytics                          │
└──────────────────────────────────────────────────────────────────────┘
```

**The critical rule: dependencies point inward only.** `grow_sim` cannot import
Flutter, cannot read a clock, cannot touch a database, and cannot generate an
unseeded random number. Everything it needs arrives as arguments. This is what
makes a 30-day simulation testable in 40 milliseconds in a CI job with no device.

## 2. The core loop, precisely

```
App resume
   │
   ├─ TimeAuthority.now()  →  (wallClockMs, monotonicMs, bootId)
   ├─ ClockGuard.trustedElapsed(lastSave, now)     ── see 05 §8
   │
   ├─ SaveRepository.load()  →  GameState (immutable)
   │
   ├─ compute in Isolate:
   │     SimulationResult r = Simulator.run(
   │         state:    gameState,
   │         content:  contentBundle,
   │         from:     state.simTime,
   │         to:       state.simTime + trustedElapsed,
   │         weather:  WeatherOracle.forWindow(...)   ── deterministic from seed
   │     )
   │
   ├─ r.state       → new GameState
   ├─ r.journal     → list of things that happened (growth, rain, visits, …)
   │
   ├─ WelcomeBackScreen renders r.journal as a sequence   (if elapsed > 20 min)
   ├─ SaveRepository.persist(r.state)
   └─ World.hydrate(r.state) → renders
```

While the app is open, the same `Simulator.run` is called on a 1 Hz ticker with
`to = from + 60s`. **There is exactly one simulation code path.** Online ticking
and 3-day catch-up are the same function with different bounds. This eliminates
the entire class of bug where the offline result disagrees with the online one.

## 3. Data flow and threading

| Thread | Responsibility |
|---|---|
| Platform/UI isolate | Flutter widgets, Flame render loop, input |
| `sim` isolate (long-lived) | `Simulator.run` for catch-up windows > 5 min |
| `db` isolate (Drift's own) | All SQLite I/O |

`GameState` is deeply immutable (`freezed` + `fast_immutable_collections`), so
passing it across isolate boundaries is cheap and safe.

The render layer consumes a **`WorldSnapshot`** — a flattened, render-oriented
projection of `GameState` (positions, growth values, health uniforms, active
animals, weather, light). The Flame world never reads domain entities directly
and never writes to them. Player input produces `Intent` objects that go to
application-layer controllers.

```
GameState ──project──▶ WorldSnapshot ──▶ Flame components ──▶ frame
    ▲                                          │
    └────── controllers ◀────── Intent ◀───────┘
```

This one-way discipline is what allows the world to be re-rendered from a save
file at any time, and what will allow a replay/debug tool later.

## 4. Module responsibilities

### `grow_domain` (pure Dart, zero dependencies)
Entities (`Tree`, `Plot`, `Player`, `Inventory`, `FocusSession`), value objects
(`Vitals`, `Percent`, `SimTime`, `SpeciesId`), and invariants. No behaviour that
requires the outside world.

### `grow_sim` (pure Dart)
`Simulator`, `VitalsModel`, `GrowthModel`, `HealthModel`, `EventRoller`,
`WeatherOracle`, `DormancyModel`. Deterministic, seeded, side-effect free.
Ports it declares but does not implement: none — it takes plain values.

### `grow_content` (pure Dart + assets)
JSON species/animal/biome definitions, a schema validator that runs at build
time, and typed frozen classes. **No game logic.** Adding a species is adding a
JSON object and an art entry; it never touches `grow_sim`.

### `grow_data`
Drift database, DAOs, `SaveRepository`, migrations, integrity (HMAC + high-water
mark), backup rotation, and the sync-readiness columns.

### `grow_render`
Flame `World`, layered scene graph, `ProceduralTreeComponent`, `WindField`,
`ParticleSystems`, `RiveCreatureComponent`, shaders, `QualityTier`. Depends on
`grow_domain` for types but never on `grow_data` or `grow_app`.

### `grow_focus`
Platform-agnostic focus session state machine and reward computation. Talks to
`grow_screen_time` through an interface it owns, so the whole feature is
testable with a fake integrity provider.

### `plugins/grow_screen_time`
Federated plugin. `..._platform_interface` defines the contract, `..._android`
and `..._ios` implement it. **The contract is deliberately the intersection of
what both platforms can honestly do**, plus explicit capability flags for what
they cannot — see [07](07-screen-time-integration.md).

### `plugins/grow_time_authority`
Returns `(wallClockMs, monotonicMs, bootId)`. Android:
`SystemClock.elapsedRealtimeNanos()` + a boot id derived from
`wallClock - elapsedRealtime` bucketed to the second. iOS:
`clock_gettime(CLOCK_MONOTONIC)` (which on Darwin advances during sleep) plus
`kern.boottime`.

## 5. Cross-cutting concerns

**Error handling.** Three tiers: `Result<T, GrowError>` for expected failures
(insufficient resources, permission denied); exceptions for programmer errors;
a top-level `runZonedGuarded` that persists a crash breadcrumb and shows a
recovery screen rather than a white screen. A corrupt save falls back to the
newest of three rotating backups before ever showing "start over."

**Logging.** A `Logger` port with a no-op release implementation for verbose
levels. **Nothing about screen time is ever logged, at any level, in any build.**
Enforced by a lint rule and a test that greps the plugin sources.

**Feature flags.** A local `FeatureFlags` object read from a bundled JSON with a
debug override screen. `iosGroundedMode` ships **off**; it turns on when the
Family Controls entitlement is granted, via an app update, not a remote kill
switch (no server in MVP).

**Time.** No code outside `grow_time_authority` and `ClockGuard` may call
`DateTime.now()`. A lint rule forbids it. This is what makes the simulation
testable and the anti-cheat coherent.

## 6. Why not an ECS

Flame offers a component tree, not a true ECS, and that is the right level here.
The world holds tens, not thousands, of entities. A full ECS would add
indirection for a performance problem we do not have; the actual hot loop is
tree tessellation and leaf instancing, which is solved by caching geometry, not
by cache-friendly component storage.
