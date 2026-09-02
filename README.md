# GROW

> A living forest that rewards you for putting your phone down.

**Status: Phase 0 — Architecture. No implementation code yet. Awaiting approval.**

GROW is a cozy ecosystem-management game. You raise a forest by managing water,
nutrition, light and health across species with genuinely different needs. The
resources you spend are earned largely by *not* using your phone.

The design goal is not a habit tracker with a plant sticker on top. It is a real
game — strategy, discovery, risk, progression — whose economy happens to be
denominated in attention you chose not to spend elsewhere.

## The one-line design constraint

> A game that rewards you for ignoring your phone must never punish you for
> ignoring the game.

Every mechanic in this repository is checked against that sentence. It is the
reason trees enter **Dormancy** instead of dying during long absences, the reason
focus sessions have no fail state, and the reason there is a hard cap of two
notifications per day.

## Documentation map

| Doc | Contents |
|---|---|
| [00 — Design Charter](docs/00-design-charter.md) | Non-negotiable product rules that code review enforces |
| [01 — Technology Stack](docs/01-technology-stack.md) | Recommendation + honest comparison against Unity, Godot, RN, native |
| [02 — System Architecture](docs/02-system-architecture.md) | Layers, module boundaries, data flow, threading |
| [03 — Project Structure](docs/03-project-structure.md) | Monorepo layout and dependency rules |
| [04 — Data Models](docs/04-data-models.md) | Domain entities, content schema, save schema |
| [05 — Simulation](docs/05-simulation.md) | Every formula, with constants and derivations |
| [06 — Economy & Progression](docs/06-economy-and-progression.md) | Resource maths, focus yields, XP curve, unlock table |
| [07 — Screen Time Integration](docs/07-screen-time-integration.md) | Android and iOS capability matrix, fallbacks, privacy |
| [08 — Animation](docs/08-animation.md) | Procedural trees, wind field, shaders, Rive animals, perf budget |
| [09 — UI & Navigation](docs/09-ui-and-navigation.md) | Screen architecture, state management, design system |
| [10 — Persistence](docs/10-persistence.md) | Drift schema, migrations, integrity, sync-readiness |
| [11 — Notifications](docs/11-notifications.md) | Channels, predictive scheduling, anti-spam budget |
| [12 — MVP Plan](docs/12-mvp-plan.md) | Exact in/out scope and acceptance criteria |
| [13 — Risks](docs/13-risks.md) | Ranked risk register with mitigations and owners |
| [14 — Roadmap](docs/14-roadmap.md) | Phased, milestone-based delivery plan |
| [15 — Testing](docs/15-testing-strategy.md) | Determinism properties, golden tests, balance harness |

## Decision records

- [ADR-0001 — Flutter + Flame over Unity](docs/adr/0001-flutter-flame-over-unity.md)
- [ADR-0002 — Procedural trees over sprite stages](docs/adr/0002-procedural-trees.md)
- [ADR-0003 — Soft enforcement of focus sessions](docs/adr/0003-soft-enforcement.md)
- [ADR-0004 — No per-app screen time data, ever](docs/adr/0004-aggregate-only-screen-time.md)
