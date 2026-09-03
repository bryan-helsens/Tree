import '../values/sim_time.dart';

/// Where a focus session is in its life.
///
/// The separation that matters is [completed] from [claimed]. Reaching the end
/// of a session is a *fact about time*; committing its reward is a *change to
/// the game*. Keeping them apart is what makes the reward survivable across a
/// crash: a process that dies between the two leaves a completed, unclaimed
/// session that the next launch finishes exactly once.
enum FocusPhase {
  /// Underway. The only phase that permits ending early.
  running,

  /// The planned duration elapsed. Reward computed but not yet committed.
  completed,

  /// The player stopped early. Rewarded pro rata — there is no fail state
  /// (Design Charter C2) — but the reward is still pending.
  abandoned,

  /// Reward committed to the game. Terminal: a claimed session can never
  /// reward again, which is the whole idempotency guarantee.
  claimed;

  bool get isFinished => this != FocusPhase.running;
  bool get awaitsReward =>
      this == FocusPhase.completed || this == FocusPhase.abandoned;
}

/// What a completed session paid out. Recorded on the session itself so the
/// completion screen reads the committed truth rather than recomputing it.
class SessionOutcome {
  const SessionOutcome({
    required this.actual,
    required this.integrity,
    required this.growthPoints,
    required this.water,
    required this.nutrients,
    required this.xp,
    required this.growthInjection,
    required this.deepFocusBonus,
    required this.levelsGained,
  });

  final Duration actual;
  final double integrity;
  final int growthPoints;
  final int water;
  final int nutrients;
  final int xp;
  final double growthInjection;
  final bool deepFocusBonus;
  final int levelsGained;

  Map<String, Object?> toJson() => {
    'actualMs': actual.inMilliseconds,
    'integrity': integrity,
    'growthPoints': growthPoints,
    'water': water,
    'nutrients': nutrients,
    'xp': xp,
    'growthInjection': growthInjection,
    'deepFocusBonus': deepFocusBonus,
    'levelsGained': levelsGained,
  };

  factory SessionOutcome.fromJson(Map<String, Object?> j) => SessionOutcome(
    actual: Duration(milliseconds: (j['actualMs']! as num).toInt()),
    integrity: (j['integrity']! as num).toDouble(),
    growthPoints: (j['growthPoints']! as num).toInt(),
    water: (j['water']! as num).toInt(),
    nutrients: (j['nutrients']! as num).toInt(),
    xp: (j['xp']! as num).toInt(),
    growthInjection: (j['growthInjection']! as num).toDouble(),
    deepFocusBonus: j['deepFocusBonus']! as bool,
    levelsGained: (j['levelsGained']! as num).toInt(),
  );
}

/// One focus session.
///
/// Its progress is measured in **simulated** time, not wall time. `simTime`
/// only ever advances by an elapsed interval the clock guard has already
/// vetted, and never decreases — so a session cannot be shortened by moving
/// the clock, and needs no timer of its own. There is nothing to keep running
/// while the app is backgrounded.
class FocusSession {
  const FocusSession({
    required this.id,
    required this.planned,
    required this.startedAt,
    required this.startedAtWallMs,
    required this.phase,
    this.finishedAt,
    this.outcome,
  });

  /// Stable for the life of the session. The idempotency key: a claimed id is
  /// never claimed again.
  final String id;

  final Duration planned;

  /// Simulated instant the session began.
  final SimTime startedAt;

  /// Wall clock at the start, kept only so the platform can later be asked
  /// what the screen was doing during this window. Never used for progress.
  final int startedAtWallMs;

  final FocusPhase phase;

  /// When it stopped being [FocusPhase.running].
  final SimTime? finishedAt;

  final SessionOutcome? outcome;

  Duration elapsedAt(SimTime now) {
    final end = finishedAt ?? now;
    final ms = end.ms - startedAt.ms;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  /// 0..1 through the planned duration.
  double progressAt(SimTime now) {
    if (planned.inMilliseconds <= 0) return 1;
    return (elapsedAt(now).inMilliseconds / planned.inMilliseconds)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  Duration remainingAt(SimTime now) {
    final left = planned - elapsedAt(now);
    return left.isNegative ? Duration.zero : left;
  }

  bool hasElapsedAt(SimTime now) => elapsedAt(now) >= planned;

  FocusSession copyWith({
    FocusPhase? phase,
    SimTime? finishedAt,
    SessionOutcome? outcome,
  }) => FocusSession(
    id: id,
    planned: planned,
    startedAt: startedAt,
    startedAtWallMs: startedAtWallMs,
    phase: phase ?? this.phase,
    finishedAt: finishedAt ?? this.finishedAt,
    outcome: outcome ?? this.outcome,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'plannedMs': planned.inMilliseconds,
    'startedAtMs': startedAt.ms,
    'startedAtWallMs': startedAtWallMs,
    'phase': phase.name,
    'finishedAtMs': finishedAt?.ms,
    'outcome': outcome?.toJson(),
  };

  factory FocusSession.fromJson(Map<String, Object?> j) => FocusSession(
    id: j['id']! as String,
    planned: Duration(milliseconds: (j['plannedMs']! as num).toInt()),
    startedAt: SimTime((j['startedAtMs']! as num).toInt()),
    startedAtWallMs: (j['startedAtWallMs']! as num).toInt(),
    phase: FocusPhase.values.firstWhere(
      (p) => p.name == j['phase'],
      orElse: () => throw ArgumentError('unknown phase "${j['phase']}"'),
    ),
    finishedAt: j['finishedAtMs'] == null
        ? null
        : SimTime((j['finishedAtMs']! as num).toInt()),
    outcome: j['outcome'] == null
        ? null
        : SessionOutcome.fromJson(j['outcome']! as Map<String, Object?>),
  );

  @override
  String toString() =>
      'FocusSession($id, ${planned.inMinutes}min, ${phase.name})';
}
