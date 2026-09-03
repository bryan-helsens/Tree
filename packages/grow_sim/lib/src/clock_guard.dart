import 'dart:math' as math;

import 'package:grow_domain/grow_domain.dart';

/// Decides how much elapsed time the game is willing to credit.
///
/// Pure. It reads no clock; it is handed two readings and the save's memory of
/// the last one. That is what makes every branch below testable without
/// waiting, rebooting, or changing a device's date.
///
/// See docs/05-simulation.md §8 and docs/22 §11.
class ClockGuard {
  const ClockGuard({
    this.maxResumeMs = 36 * 60 * 60 * 1000,
    this.forwardJumpToleranceMs = 5 * 60 * 1000,
  });

  /// The most time a single resume may credit when the monotonic clock cannot
  /// corroborate it — after a reboot, or on a first run.
  final int maxResumeMs;

  /// How far the wall clock may run ahead of the monotonic clock within one
  /// boot before the interval is treated as a jump.
  final int forwardJumpToleranceMs;

  TrustedElapsed elapsed(ClockMeta last, ClockReading now) {
    // A save with no clock memory yet: nothing to compare against, so credit
    // nothing and start the record here.
    if (last.isFresh) return const TrustedElapsed.zero();

    final wall = now.wallMs - last.lastWallMs;

    // Backwards. Zero progress, never negative progress — a rewound clock
    // must not undo a tree's day.
    if (wall < 0) {
      return const TrustedElapsed.zero(anomaly: ClockAnomaly.rewind);
    }

    if (now.bootId != last.bootId) {
      // Rebooted: the monotonic clock restarted, so it can say nothing about
      // this interval. Take the wall clock, capped.
      return TrustedElapsed(
        math.min(wall, maxResumeMs),
        anomaly: ClockAnomaly.reboot,
      );
    }

    final monotonic = now.monotonicMs - last.lastMonotonicMs;

    // Within one boot both clocks should agree. Where they disagree, the
    // smaller is the honest one: the monotonic clock cannot be set forward,
    // and the wall clock cannot be set backward without being caught above.
    final credited = math.min(wall, monotonic);
    final jumped = (wall - monotonic).abs() > forwardJumpToleranceMs;

    return TrustedElapsed(
      math.max(0, credited),
      anomaly: jumped ? ClockAnomaly.forwardJump : ClockAnomaly.none,
    );
  }

  /// Where the simulation should advance to, given a reading.
  ///
  /// Also enforces the high-water mark: a restored older save cannot re-earn
  /// time the game has already lived through. The game does not accuse anyone
  /// of anything — it simply declines to pay twice.
  ({SimTime target, ClockMeta meta}) advance(
    GameState state,
    ClockReading now,
  ) {
    final credit = elapsed(state.clock, now);
    var targetMs = state.simTime.ms + credit.ms;

    if (targetMs < state.clock.simTimeHighMs) {
      targetMs = state.clock.simTimeHighMs;
    }

    return (
      target: SimTime(targetMs).floorToStep,
      meta: state.clock.copyWith(
        lastWallMs: now.wallMs,
        lastMonotonicMs: now.monotonicMs,
        bootId: now.bootId,
        simTimeHighMs: math.max(state.clock.simTimeHighMs, targetMs),
        anomalies:
            state.clock.anomalies +
            (credit.anomaly == ClockAnomaly.none ? 0 : 1),
      ),
    );
  }

  /// The first reading of a run, which only records where the clocks are.
  ClockMeta anchor(GameState state, ClockReading now) => state.clock.copyWith(
    lastWallMs: now.wallMs,
    lastMonotonicMs: now.monotonicMs,
    bootId: now.bootId,
    simTimeHighMs: math.max(state.clock.simTimeHighMs, state.simTime.ms),
  );
}
