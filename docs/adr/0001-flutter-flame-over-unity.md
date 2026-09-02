# ADR-0001 — Flutter + Flame over Unity, Godot, React Native and native

**Status:** proposed · **Date:** 2026-09-02

## Context

GROW is three products at once: a premium mobile UI application, a continuously
animated 2D world, and a client for two of the most restricted native APIs on
either platform (`FamilyControls` on iOS, `UsageStatsManager` on Android). Most
engines are strong at one of these and weak at the others.

## Decision

Flutter with Impeller, Flame for the world layer, Rive for character animation,
and native plugins written with Pigeon.

## Rationale

The deciding factor is not rendering — several options render 2D well enough. It
is that **the platform integration is the product's differentiator, and it is
ordinary work in Flutter and extraordinary work in a game engine.** Adding a
SwiftUI `DeviceActivityMonitor` app extension to a Flutter project is a standard
Xcode target; in Unity or Godot it is a fight with the export pipeline.

Second: the brief demands modern, accessible, premium mobile UI. Game engines
rebuild that from nothing, without platform text rendering, dynamic type, or
screen reader support.

Third: keeping the simulation and the renderer in one AOT-compiled language with
one set of numeric semantics avoids the divergence risk that killed the native
option and the thread-boundary problem that killed React Native.

## Consequences

**Positive** — one codebase; hot reload for the hundreds of feel iterations that
determine whether the game is good; small binaries; excellent accessibility
primitives; straightforward native extension work.

**Negative** — canvas accessibility needs explicit work ([09 §7](../09-ui-and-navigation.md#7-accessibility));
Flame's API churn must be contained; no SIMD for geometry maths.

**Mitigated** — all simulation lives in `grow_sim`, a pure Dart package with no
Flutter and no Flame dependency, so the game engine choice is reversible at the
rendering layer only.
