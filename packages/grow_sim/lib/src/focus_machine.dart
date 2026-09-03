import 'dart:math' as math;

import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

import 'economy.dart';

/// Why a session transition was refused.
enum FocusRefusal {
  alreadyRunning('A session is already underway.'),
  awaitingAcknowledgement('Your last session is still waiting to be seen.'),
  nothingRunning('No session is running.'),
  nothingToClaim('There is no reward waiting.'),
  tooShort('That session is shorter than the minimum.'),
  tooLong('That session is longer than the maximum.');

  const FocusRefusal(this.message);
  final String message;
}

class FocusTransition {
  const FocusTransition.ok(this.state) : refusal = null, outcome = null;
  const FocusTransition.rewarded(this.state, this.outcome) : refusal = null;
  const FocusTransition.refused(this.refusal) : state = null, outcome = null;

  final GameState? state;
  final FocusRefusal? refusal;

  /// Set only by a claim that actually committed a reward.
  final SessionOutcome? outcome;

  bool get ok => state != null;
}

/// The focus session lifecycle.
///
/// Pure transitions over `GameState`. Every question about backgrounding,
/// process death, reboots and clock movement has the same answer here: the
/// session is a record in the save, its progress is `simTime - startedAt`, and
/// nothing about it runs. There is no timer to lose.
///
/// The transitions, and nothing else:
///
/// ```
///   (none) ─start──▶ running ─elapsed──▶ completed ─claim─▶ claimed ─dismiss─▶ (none)
///                       │                                      ▲
///                       └────────endEarly──▶ abandoned ─claim───┘
/// ```
///
/// See docs/22-focus-session-architecture.md.
class FocusMachine {
  const FocusMachine({
    required this.content,
    this.economy = const FocusEconomy(),
  });

  final ContentBundle content;
  final FocusEconomy economy;

  // ── start ────────────────────────────────────────────────────────────

  FocusTransition start(
    GameState state, {
    required Duration planned,
    required String id,
    required int wallMs,
  }) {
    final active = state.session;
    if (active != null) {
      // A claimed session still on record must be acknowledged before the
      // next one starts. Overwriting it would take away the completion
      // moment — the reward is safe either way, but the moment is the point.
      return FocusTransition.refused(
        active.phase == FocusPhase.claimed
            ? FocusRefusal.awaitingAcknowledgement
            : FocusRefusal.alreadyRunning,
      );
    }
    if (planned.inMinutes < economy.minSessionMinutes) {
      return const FocusTransition.refused(FocusRefusal.tooShort);
    }
    if (planned.inMinutes > economy.maxSessionMinutes) {
      return const FocusTransition.refused(FocusRefusal.tooLong);
    }

    return FocusTransition.ok(
      state.withSession(
        FocusSession(
          id: id,
          planned: planned,
          startedAt: state.simTime,
          startedAtWallMs: wallMs,
          phase: FocusPhase.running,
        ),
      ),
    );
  }

  // ── time passing ─────────────────────────────────────────────────────

  /// Re-evaluates a running session against the clock.
  ///
  /// Called after every simulation advance, including the catch-up on launch.
  /// This is what "completion is determined by" — a comparison, not a callback.
  /// A session that finished while the process was dead completes here, on the
  /// next launch, exactly as if the app had been open.
  GameState evaluate(GameState state) {
    final session = state.session;
    if (session == null || session.phase != FocusPhase.running) return state;
    if (!session.hasElapsedAt(state.simTime)) return state;

    return state.withSession(
      session.copyWith(
        phase: FocusPhase.completed,
        // Credited at its planned end, not at the moment it was noticed.
        finishedAt: SimTime(
          session.startedAt.ms + session.planned.inMilliseconds,
        ),
      ),
    );
  }

  // ── ending early ─────────────────────────────────────────────────────

  /// The player stops before the planned end.
  ///
  /// Not a failure and not a cancellation: the time already spent is real and
  /// is paid for pro rata (Design Charter C2).
  FocusTransition endEarly(GameState state) {
    final session = state.session;
    if (session == null || session.phase != FocusPhase.running) {
      return const FocusTransition.refused(FocusRefusal.nothingRunning);
    }
    return FocusTransition.ok(
      state.withSession(
        session.copyWith(
          phase: FocusPhase.abandoned,
          finishedAt: state.simTime,
        ),
      ),
    );
  }

  // ── the reward ───────────────────────────────────────────────────────

  /// Commits a finished session's reward.
  ///
  /// **Exactly once, by construction.** The reward and the move to
  /// [FocusPhase.claimed] are produced as a single `GameState`. There is no
  /// window in which one has happened and the other has not, so a crash either
  /// loses both — and the session is claimed again on the next launch — or
  /// keeps both, and the claimed phase refuses a second attempt.
  ///
  /// Calling this on an already-claimed session is a no-op, not an error: a
  /// retry after an ambiguous failure must be safe.
  FocusTransition claim(GameState state) {
    final session = state.session;
    if (session == null) {
      return const FocusTransition.refused(FocusRefusal.nothingToClaim);
    }
    if (session.phase == FocusPhase.claimed) {
      // Idempotent. Report the outcome already on record.
      return FocusTransition.rewarded(state, session.outcome!);
    }
    if (!session.phase.awaitsReward) {
      return const FocusTransition.refused(FocusRefusal.nothingToClaim);
    }

    final finished = session.finishedAt ?? state.simTime;
    final actual = session.elapsedAt(finished);
    final day = finished.dayIndex;
    final today = state.progression.today.onDay(day);

    final yield_ = economy.yieldFor(
      minutes: math.max(1, actual.inMinutes),
      sessionIndexToday: today.sessionsCompleted,
      streakDays: state.progression.focusStreakDays,
      gpAlreadyEarnedToday: today.growthPointsEarned,
      deepFocusBonusAlreadyUsed: today.deepFocusUsed,
    );

    // Everything below lands in one state. The order matters: the reward is
    // applied to a world that has already lived through the session.
    final award = applyFocusYield(state, yield_, content: content);
    final rewarded = award.state;
    final levelsGained = rewarded.progression.level - state.progression.level;

    final streak = _advanceStreak(rewarded.progression, day);

    final outcome = SessionOutcome(
      actual: actual,
      integrity: yield_.integrity,
      growthPoints: yield_.growthPoints,
      water: yield_.water,
      nutrients: yield_.totalNutrients,
      xp: yield_.xp,
      // What the tree actually made, not what the table offered: a fully
      // grown tree has nowhere to put it, and the screen must not claim it.
      growthInjection: award.growthApplied,
      deepFocusBonus: yield_.deepFocusBonus,
      levelsGained: levelsGained,
    );

    final next = rewarded
        .copyWith(
          progression: streak.copyWith(
            today: today.copyWith(
              sessionsCompleted: today.sessionsCompleted + 1,
              growthPointsEarned:
                  today.growthPointsEarned + yield_.growthPoints,
              deepFocusUsed: today.deepFocusUsed || yield_.deepFocusBonus,
            ),
          ),
        )
        .withSession(
          session.copyWith(phase: FocusPhase.claimed, outcome: outcome),
        );

    return FocusTransition.rewarded(next, outcome);
  }

  /// Clears a claimed session so another can start.
  FocusTransition dismiss(GameState state) {
    final session = state.session;
    if (session == null) return FocusTransition.ok(state);
    if (session.phase != FocusPhase.claimed) {
      return const FocusTransition.refused(FocusRefusal.nothingToClaim);
    }
    return FocusTransition.ok(state.withSession(null));
  }

  /// A streak day is earned by finishing any qualifying session.
  ///
  /// A missed day is absorbed by the shield silently, and the player is told
  /// afterwards — never warned beforehand. A countdown to losing something is
  /// exactly the anxiety this product exists to reduce.
  Progression _advanceStreak(Progression p, int day) {
    if (p.lastStreakDayIndex == day) return p;

    final gap = day - p.lastStreakDayIndex;
    if (p.lastStreakDayIndex < 0 || gap == 1) {
      final next = p.focusStreakDays + 1;
      return p.copyWith(
        focusStreakDays: next,
        longestStreak: math.max(p.longestStreak, next),
        lastStreakDayIndex: day,
      );
    }
    if (gap == 2 && p.streakShields > 0) {
      // The shield covers exactly one missed day.
      final next = p.focusStreakDays + 1;
      return p.copyWith(
        focusStreakDays: next,
        longestStreak: math.max(p.longestStreak, next),
        streakShields: p.streakShields - 1,
        lastStreakDayIndex: day,
      );
    }
    return p.copyWith(focusStreakDays: 1, lastStreakDayIndex: day);
  }
}
