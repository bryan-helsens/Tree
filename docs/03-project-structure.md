# 03 — Project Structure

A Dart **pub workspace** monorepo. Single `flutter pub get`, shared lockfile,
fast cross-package refactors, and enforced module boundaries.

```
grow/
├─ pubspec.yaml                       # workspace root, resolution: workspace
├─ dependencies.yaml                  # single source of truth for versions
├─ analysis_options.yaml              # strict-casts/inference/raw-types, custom lints
│
├─ apps/
│  └─ grow_app/
│     ├─ lib/
│     │  ├─ main.dart                 # thin: runApp(bootstrap())
│     │  ├─ bootstrap.dart            # DI graph, error zone, logging, flags
│     │  ├─ app.dart                  # root widget, router, theme
│     │  ├─ routing/
│     │  │  ├─ router.dart            # go_router shell + routes
│     │  │  └─ transitions.dart
│     │  ├─ design_system/
│     │  │  ├─ tokens/                # colour, spacing, radius, motion, elevation
│     │  │  ├─ typography.dart
│     │  │  ├─ components/            # GrowButton, StatBar, Sheet, Chip, Pill…
│     │  │  ├─ motion/                # named curves + durations, reduced-motion aware
│     │  │  └─ theme.dart             # season-aware palette resolution
│     │  ├─ features/
│     │  │  ├─ onboarding/            # first-run, seed planting, permission story
│     │  │  ├─ forest/                # world screen + HUD overlay
│     │  │  │  ├─ view/
│     │  │  │  ├─ controller/
│     │  │  │  └─ widgets/
│     │  │  ├─ tree_detail/           # bottom sheet, actions, risk preview
│     │  │  ├─ focus/                 # picker, running session, completion
│     │  │  ├─ satchel/               # inventory
│     │  │  ├─ field_guide/           # species + animal discovery collection
│     │  │  ├─ progression/           # level, challenges, streak
│     │  │  ├─ welcome_back/          # offline summary sequence
│     │  │  └─ settings/              # audio, motion, notifications, privacy, data
│     │  └─ di/
│     │     └─ providers.dart         # Riverpod root overrides
│     ├─ android/
│     │  └─ app/src/main/kotlin/…     # MainActivity only; logic lives in plugins
│     ├─ ios/
│     │  ├─ Runner/
│     │  ├─ GrowDeviceActivityMonitor/     # app extension target
│     │  └─ GrowDeviceActivityReport/      # app extension target (SwiftUI)
│     ├─ assets/
│     │  ├─ content/                  # species.json, animals.json, biomes.json
│     │  ├─ shaders/                  # *.frag (GLSL → SkSL at build)
│     │  ├─ rive/                     # animals.riv, ui_fx.riv
│     │  ├─ atlas/                    # leaf/particle/ground atlases + .json
│     │  └─ audio/
│     └─ test/  integration_test/
│
├─ packages/
│  ├─ grow_domain/          # entities, value objects. depends on: nothing
│  ├─ grow_sim/             # simulator. depends on: grow_domain
│  ├─ grow_content/         # data + loader. depends on: grow_domain
│  ├─ grow_data/            # drift, repos. depends on: grow_domain
│  ├─ grow_render/          # flame world. depends on: grow_domain, flame, rive
│  ├─ grow_focus/           # session orchestration. depends on: grow_domain, plugin iface
│  ├─ grow_notifications/   # scheduling policy + platform adapter
│  ├─ grow_audio/           # mixer, ducking, category management
│  └─ grow_telemetry/       # local-only ring buffer; opt-in export. no SDK.
│
├─ plugins/
│  ├─ grow_screen_time/
│  │  ├─ grow_screen_time_platform_interface/
│  │  ├─ grow_screen_time_android/    # Kotlin: UsageStatsManager
│  │  └─ grow_screen_time_ios/        # Swift: FamilyControls, ManagedSettings
│  └─ grow_time_authority/            # monotonic clock + bootId
│
├─ tools/
│  ├─ balance_sim/          # Dart CLI: N-day headless runs → CSV → tuning
│  ├─ content_lint/         # validates content JSON against schema, checks art refs
│  ├─ tree_lab/             # standalone Flutter app: live sliders for every tree param
│  └─ arch_check/           # fails CI if a package imports something it may not
│
└─ docs/
```

## Dependency rules (enforced in CI by `tools/arch_check`)

| Package | May depend on |
|---|---|
| `grow_domain` | *(nothing)* |
| `grow_sim` | `grow_domain` |
| `grow_content` | `grow_domain` |
| `grow_data` | `grow_domain`, `drift` |
| `grow_render` | `grow_domain`, `flutter`, `flame`, `rive` |
| `grow_focus` | `grow_domain`, `grow_screen_time_platform_interface` |
| `grow_app` | everything |
| anything | **never** `grow_app` |

Additional banned imports, checked by lint:

- `dart:io` inside `grow_sim`, `grow_domain`, `grow_content`
- `DateTime.now()` anywhere except `grow_time_authority` and `ClockGuard`
- `math.Random()` without a seed, anywhere
- `package:flutter` inside `grow_domain`, `grow_sim`, `grow_content`

## Naming and file-size conventions

- One public class per file; file name is `snake_case` of the class.
- Hard limit **400 lines** per file, **60 lines** per method; CI warns at 80%.
- Widget files hold widgets only. Any computation moves to a controller or a
  pure function in the same feature folder.
- Feature folders are self-contained: a feature may not import another feature's
  `widgets/` or `controller/`. Shared UI is promoted to `design_system/`.

## `tools/tree_lab` deserves special mention

A standalone Flutter app that renders one procedural tree with a live slider for
every parameter in the species schema plus every visual uniform (wind amplitude,
gust frequency, leaf density, droop, pallor, scorch, branch angle variance,
taper, phototropism). It exports a species JSON directly.

This exists because the difference between "procedural tree" and "beautiful
procedural tree" is a few hundred iterations on twenty numbers, and doing that
inside the full game is far too slow a loop. It is a Phase 1 deliverable, not a
nice-to-have.
