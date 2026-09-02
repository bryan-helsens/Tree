# 01 — Technology Stack

## Recommendation

**Flutter 3.x (Impeller) + Flame for the world layer + Rive for character
animation + native platform plugins written with Pigeon.**

| Concern | Choice |
|---|---|
| App shell, UI, navigation | Flutter / Material-free custom design system |
| Renderer | Impeller (Metal on iOS, Vulkan on Android) |
| World / game loop | `flame` — component tree, camera, game loop inside a `GameWidget` |
| Trees, grass, weather | **Procedural**, custom `Component` + `FragmentProgram` shaders |
| Animals | **Rive** state machines (`rive` Flutter runtime) |
| State management | Riverpod (code-generated providers) |
| Persistence | Drift (SQLite) |
| Platform channels | Pigeon (type-safe generated bindings) |
| Android screen time | Kotlin, `UsageStatsManager` |
| iOS screen time | Swift, `FamilyControls` + `DeviceActivityMonitor` extension |
| Notifications | `flutter_local_notifications` + `timezone` |
| Audio | `just_audio` (music/ambient) + `soLoud` or `audioplayers` pool (SFX) |
| Testing | `flutter_test`, `golden_toolkit`, `fast_immutable_collections`, custom sim harness |

Language: **Dart with sound null safety** throughout, `strict-casts`,
`strict-inference` and `strict-raw-types` enabled; Kotlin and Swift only inside
the plugin packages.

## Why, against each alternative

The decision was driven by an unusual requirement combination: this product is
**60% premium mobile UI application, 40% animated 2D world, and 100% dependent
on two of the most restricted native APIs on either platform.** Most engines
optimise for one of those three and are poor at the others.

### Unity — rejected

- **Fatal:** the app's value depends on `FamilyControls`, a `DeviceActivityMonitor`
  app extension, `ManagedSettings`, and `UsageStatsManager`. In Unity every one
  of those is a hand-written native plugin plus an Xcode post-processor to inject
  an app extension target. This is the single most integration-heavy part of the
  project and Unity makes it the hardest.
- App size: an empty 2D Unity project ships around 25–35 MB compressed; GROW's
  actual content is small, so the engine would dominate the download for a game
  whose audience is being told it's a calm, lightweight thing.
- UI: the brief demands "modern mobile UI" and "premium." UI Toolkit is workable
  but every sheet, list, transition and accessibility affordance would be
  rebuilt from scratch, without platform text rendering, dynamic type, or screen
  reader support.
- Cold start and battery are materially worse, which matters for an app opened
  in short bursts.
- Genuine strength — tooling, animation, particles — is real but is aimed at a
  larger and more action-oriented game than this one.

### Godot — rejected

- Better than Unity on size (~15 MB) and licensing, and its 2D pipeline is
  excellent.
- **Fatal:** iOS app extensions and Swift-only frameworks are the weakest part of
  Godot's mobile story. Adding a `DeviceActivityReportExtension` (SwiftUI-only,
  separate target, separate entitlement) to a Godot export is fighting the export
  template. Community iOS plugins are thin and slow-moving.
- Same UI/accessibility problem as Unity.

### React Native — rejected, but it was the runner-up

- `react-native-skia` + `reanimated` is a genuinely strong 2D pipeline and RN's
  native module story is good; the iOS extension work would be comparable to
  Flutter's.
- Rejected for three reasons:
  1. The tree simulator and the tree renderer share a lot of geometry maths. In
     Dart both run in the same AOT-compiled language with the same numeric
     semantics. In RN the simulation would sit in JS (or be duplicated into a
     worklet) with a JS/UI-thread boundary running through the most
     performance-sensitive part of the app.
  2. Per-frame procedural geometry with hundreds of branch segments crosses the
     JS↔native boundary badly unless everything is pushed into worklets, at
     which point you are writing a restricted dialect of JS anyway.
  3. Long-term maintenance surface: RN + Skia + Reanimated + Gesture Handler is
     four fast-moving independent version trains. Flutter + Flame is two.

### Native (SwiftUI + Jetpack Compose) — rejected

- Unambiguously the best result if cost were no object: best performance, best
  platform integration, best accessibility, smallest binaries.
- **Fatal:** the simulation is the product. Two independent implementations of
  the same deterministic float maths will diverge, and the divergence will
  manifest as "my tree grew differently on my iPad." Keeping them bit-compatible
  costs more than the UI savings.
- Roughly 1.8× the engineering cost for a project whose scope is already large.

### Flutter *without* Flame — considered

Viable. Flame is not doing anything magical; it supplies a game loop, a component
tree with a transform hierarchy, a camera, and a spatial query structure. Writing
those is maybe two weeks of work. We take Flame to save that time and get a
maintained camera/viewport implementation, but the architecture deliberately
keeps Flame at arm's length: **all simulation lives in `grow_sim`, a pure Dart
package with no Flutter and no Flame dependency**, so replacing or dropping Flame
later is a rendering-layer change only.

## Why Flutter specifically wins here

1. **One renderer, both platforms.** Impeller compiles shaders ahead of time, so
   the shader-compilation jank that historically hurt Skia-based animation is
   gone. A wind-driven procedural forest is exactly the "continuously animating,
   custom-painted" case Impeller was built for.
2. **Custom painting is a first-class citizen, not an escape hatch.** The tree
   renderer is a `CustomPainter`/Flame component drawing into the same canvas as
   the UI, so world and interface share one frame budget with no compositing
   seam, and a bottom sheet can sit over a live animated world at 60fps.
3. **GLSL fragment shaders** via `FragmentProgram` give us soil wetness, god rays,
   fog, water and seasonal colour grading without a second rendering stack.
4. **The platform work is normal work.** Adding an iOS app extension to a Flutter
   project is a standard Xcode target; the Flutter side never needs to know. The
   Kotlin `UsageStatsManager` code is ordinary Android code behind a Pigeon
   interface.
5. **Hot reload while tuning feel.** The single biggest determinant of whether
   this game is any good is hundreds of small iterations on wind amplitude, leaf
   density, easing curves and colour. Sub-second iteration is a design tool.
6. **App size** lands around 10–16 MB, and startup is fast enough that "open,
   glance, close" feels good.

## Known weaknesses of this choice, accepted

- **Text rendering and accessibility on a canvas world** need explicit work; a
  `Semantics` tree parallel to the Flame component tree is required
  ([09 §7](09-ui-and-navigation.md#7-accessibility)).
- **Flame's release cadence** occasionally breaks APIs. Mitigation: pin exact
  versions, keep the Flame surface area small and wrapped.
- **No mature 3D path.** Irrelevant — GROW is a 2.5D layered 2D world by design.
- **Dart has no SIMD for our geometry work.** Measured budget in
  [08 §7](08-animation.md#7-performance-budget) shows headroom, but the tree
  tessellation is the thing to profile first.

## Version policy

Pin exact versions in `pubspec.yaml` (no `^`). A single `dependencies.yaml` at
the workspace root is the source of truth, consumed by all packages via
`pub workspaces`. Upgrades are a deliberate, tested PR — never incidental.
