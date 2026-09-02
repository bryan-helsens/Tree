import 'dart:math' as math;

/// Forest level and XP.
///
/// `xpToNext(n) = round(90 · n^1.45)` — see docs/06-economy-and-progression.md §6.
/// Levels 1–8 land inside the first week and carry the MVP.
class Progression {
  const Progression({
    required this.level,
    required this.xp,
    required this.focusStreakDays,
    required this.longestStreak,
    required this.streakShields,
    required this.lastStreakDayIndex,
  });

  const Progression.starting()
    : level = 1,
      xp = 0,
      focusStreakDays = 0,
      longestStreak = 0,
      streakShields = 1,
      lastStreakDayIndex = -1;

  final int level;
  final int xp;
  final int focusStreakDays;
  final int longestStreak;

  /// Grace tokens, max 1, regenerating every 10 days. A missed day is absorbed
  /// silently and the player is told afterwards — never warned beforehand.
  final int streakShields;
  final int lastStreakDayIndex;

  static const int maxShields = 1;

  static int xpToNext(int level) => (90 * math.pow(level, 1.45)).round();

  static int cumulativeXpFor(int level) {
    var total = 0;
    for (var n = 1; n < level; n++) {
      total += xpToNext(n);
    }
    return total;
  }

  int get xpForNextLevel => xpToNext(level);
  double get levelProgress => (xp / xpForNextLevel).clamp(0.0, 1.0);

  /// Streak multiplier on focus yields, capped at +50% so it never becomes
  /// coercive.
  double get streakMultiplier => 1.0 + math.min(0.50, 0.05 * focusStreakDays);

  /// Applies XP, cascading through as many level-ups as it earns.
  ({Progression progression, int levelsGained}) addXp(int amount) {
    var lvl = level;
    var pool = xp + amount;
    var gained = 0;
    while (pool >= xpToNext(lvl)) {
      pool -= xpToNext(lvl);
      lvl++;
      gained++;
      if (gained > 100) break; // defensive: never spin on absurd input
    }
    return (progression: copyWith(level: lvl, xp: pool), levelsGained: gained);
  }

  Progression copyWith({
    int? level,
    int? xp,
    int? focusStreakDays,
    int? longestStreak,
    int? streakShields,
    int? lastStreakDayIndex,
  }) => Progression(
    level: level ?? this.level,
    xp: xp ?? this.xp,
    focusStreakDays: focusStreakDays ?? this.focusStreakDays,
    longestStreak: longestStreak ?? this.longestStreak,
    streakShields: streakShields ?? this.streakShields,
    lastStreakDayIndex: lastStreakDayIndex ?? this.lastStreakDayIndex,
  );

  @override
  String toString() => 'L$level ($xp/$xpForNextLevel xp, 🔥$focusStreakDays)';
}
