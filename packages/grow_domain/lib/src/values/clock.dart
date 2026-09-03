/// A reading of the device's clocks.
///
/// Three numbers, because no one of them is trustworthy alone: the wall clock
/// can be moved by the user, the monotonic clock resets on reboot, and the
/// boot id is what tells you which of those just happened.
class ClockReading {
  const ClockReading({
    required this.wallMs,
    required this.monotonicMs,
    required this.bootId,
  });

  /// Milliseconds since the Unix epoch. User-settable.
  final int wallMs;

  /// Milliseconds since boot, including sleep. Not user-settable, but reset
  /// by a restart.
  final int monotonicMs;

  /// Identifies the boot session, so a reset monotonic clock is detectable
  /// rather than looking like time travel.
  final String bootId;
}

enum ClockAnomaly {
  none,

  /// The wall clock moved backwards. Progress is zero, never negative.
  rewind,

  /// The device rebooted, so the monotonic cross-check is unavailable for
  /// this interval and the wall clock is all we have.
  reboot,

  /// The wall clock ran far ahead of the monotonic clock within one boot.
  forwardJump,
}

/// How much elapsed time the game is willing to credit.
class TrustedElapsed {
  const TrustedElapsed(this.ms, {this.anomaly = ClockAnomaly.none});
  const TrustedElapsed.zero({this.anomaly = ClockAnomaly.none}) : ms = 0;

  final int ms;
  final ClockAnomaly anomaly;

  Duration get duration => Duration(milliseconds: ms);
  bool get isZero => ms <= 0;

  @override
  String toString() => 'TrustedElapsed(${ms}ms, ${anomaly.name})';
}

/// What the save remembers about clocks, so the next launch can reason about
/// the gap.
class ClockMeta {
  const ClockMeta({
    required this.lastWallMs,
    required this.lastMonotonicMs,
    required this.bootId,
    required this.simTimeHighMs,
    this.anomalies = 0,
  });

  const ClockMeta.initial()
    : lastWallMs = 0,
      lastMonotonicMs = 0,
      bootId = '',
      simTimeHighMs = 0,
      anomalies = 0;

  final int lastWallMs;
  final int lastMonotonicMs;
  final String bootId;

  /// The furthest the simulation has ever reached. Restoring an older save
  /// cannot re-earn time that has already been consumed.
  final int simTimeHighMs;

  /// How often something odd was seen. Diagnostic only — the game never
  /// accuses anyone.
  final int anomalies;

  bool get isFresh => bootId.isEmpty;

  ClockMeta copyWith({
    int? lastWallMs,
    int? lastMonotonicMs,
    String? bootId,
    int? simTimeHighMs,
    int? anomalies,
  }) => ClockMeta(
    lastWallMs: lastWallMs ?? this.lastWallMs,
    lastMonotonicMs: lastMonotonicMs ?? this.lastMonotonicMs,
    bootId: bootId ?? this.bootId,
    simTimeHighMs: simTimeHighMs ?? this.simTimeHighMs,
    anomalies: anomalies ?? this.anomalies,
  );

  Map<String, Object?> toJson() => {
    'lastWallMs': lastWallMs,
    'lastMonotonicMs': lastMonotonicMs,
    'bootId': bootId,
    'simTimeHighMs': simTimeHighMs,
    'anomalies': anomalies,
  };

  factory ClockMeta.fromJson(Map<String, Object?> j) => ClockMeta(
    lastWallMs: (j['lastWallMs']! as num).toInt(),
    lastMonotonicMs: (j['lastMonotonicMs']! as num).toInt(),
    bootId: j['bootId']! as String,
    simTimeHighMs: (j['simTimeHighMs']! as num).toInt(),
    anomalies: (j['anomalies'] as num?)?.toInt() ?? 0,
  );
}
