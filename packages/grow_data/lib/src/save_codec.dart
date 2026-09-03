import 'dart:convert';

import 'package:grow_domain/grow_domain.dart';

import 'save_format.dart';

/// Turns a save into a document and back.
///
/// The whole `GameState` is one value, so a save is one write. That is what
/// makes a focus session's reward and its claim atomic without a transaction
/// manager: they are fields of the same object.
///
/// The document carries a schema version and is brought forward through
/// [SaveFormat.migrate] before it is read. A save from a *future* version is
/// refused rather than half-read.
class SaveCodec {
  const SaveCodec();

  static int get schemaVersion => SaveFormat.version;

  String encode(GameState state) => jsonEncode(toJson(state));

  GameState decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);

  Map<String, Object?> toJson(GameState s) => {
    'schemaVersion': schemaVersion,
    'worldSeed': s.worldSeed.raw,
    'simTimeMs': s.simTime.ms,
    'lastInteractionAtMs': s.lastInteractionAt.ms,
    'biome': s.biome.raw,
    'trees': [for (final t in s.trees) _tree(t)],
    'inventory': _inventory(s.inventory),
    'progression': _progression(s.progression),
    'clock': s.clock.toJson(),
    'session': s.session?.toJson(),
  };

  GameState fromJson(Map<String, Object?> raw) {
    // Older documents are brought forward here, so everything below may assume
    // the current shape. Refusal for a newer version happens inside migrate.
    final j = SaveFormat.migrate(raw);
    return GameState(
      worldSeed: Seed((j['worldSeed']! as num).toInt()),
      simTime: SimTime((j['simTimeMs']! as num).toInt()),
      lastInteractionAt: SimTime((j['lastInteractionAtMs']! as num).toInt()),
      biome: BiomeId(j['biome']! as String),
      trees: [
        for (final t in j['trees']! as List<Object?>)
          _treeFrom(t! as Map<String, Object?>),
      ],
      inventory: _inventoryFrom(j['inventory']! as Map<String, Object?>),
      progression: _progressionFrom(j['progression']! as Map<String, Object?>),
      clock: ClockMeta.fromJson(j['clock']! as Map<String, Object?>),
      session: j['session'] == null
          ? null
          : FocusSession.fromJson(j['session']! as Map<String, Object?>),
    );
  }

  // ── trees ─────────────────────────────────────────────────────────────

  Map<String, Object?> _tree(Tree t) => {
    'id': t.id.raw,
    'species': t.species.raw,
    'seed': t.seed.raw,
    'slot': t.slot,
    'health': t.health.value,
    'water': t.water.value,
    'nutrition': t.nutrition.value,
    'growth': t.growth.value,
    'stage': t.stage.name,
    'state': t.state.name,
    'plantedAtMs': t.plantedAt.ms,
    'lastTendedAtMs': t.lastTendedAt.ms,
    'criticalHours': t.criticalHours,
    'criticalSightings': t.criticalSightings,
    'careNotificationSent': t.careNotificationSent,
    'timesWatered': t.timesWatered,
    'timesFed': t.timesFed,
    'isFlowering': t.isFlowering,
    'diedAtMs': t.diedAt?.ms,
    'discoveredTraits': [for (final x in t.discoveredTraits) x.raw],
    'afflictions': [
      for (final a in t.afflictions)
        {
          'kind': a.kind.name,
          'severity': a.severity,
          'startedAtMs': a.startedAtMs,
        },
    ],
  };

  Tree _treeFrom(Map<String, Object?> j) {
    double d(String k) => (j[k]! as num).toDouble();
    return Tree(
      id: TreeId(j['id']! as String),
      species: SpeciesId(j['species']! as String),
      seed: Seed((j['seed']! as num).toInt()),
      slot: (j['slot']! as num).toInt(),
      health: Vital(d('health')),
      water: Vital(d('water')),
      nutrition: Vital(d('nutrition')),
      growth: Vital(d('growth')),
      stage: _byName(GrowthStage.values, j['stage']! as String),
      state: _byName(HealthState.values, j['state']! as String),
      plantedAt: SimTime((j['plantedAtMs']! as num).toInt()),
      lastTendedAt: SimTime((j['lastTendedAtMs']! as num).toInt()),
      criticalHours: d('criticalHours'),
      criticalSightings: (j['criticalSightings']! as num).toInt(),
      careNotificationSent: j['careNotificationSent']! as bool,
      timesWatered: (j['timesWatered']! as num).toInt(),
      timesFed: (j['timesFed']! as num).toInt(),
      isFlowering: j['isFlowering']! as bool,
      diedAt: j['diedAtMs'] == null
          ? null
          : SimTime((j['diedAtMs']! as num).toInt()),
      discoveredTraits: {
        for (final x in j['discoveredTraits']! as List<Object?>)
          TraitId(x! as String),
      },
      afflictions: [
        for (final a in j['afflictions']! as List<Object?>)
          _affliction(a! as Map<String, Object?>),
      ],
    );
  }

  Affliction _affliction(Map<String, Object?> j) => Affliction(
    kind: _byName(AfflictionKind.values, j['kind']! as String),
    severity: (j['severity']! as num).toDouble(),
    startedAtMs: (j['startedAtMs']! as num).toInt(),
  );

  // ── player ────────────────────────────────────────────────────────────

  Map<String, Object?> _inventory(Inventory i) => {
    'water': i.water,
    'waterCap': i.waterCap,
    'nutrients': i.nutrients,
    'nutrientCap': i.nutrientCap,
    'dew': i.dew,
    'seeds': {for (final e in i.seeds.entries) e.key.raw: e.value},
  };

  Inventory _inventoryFrom(Map<String, Object?> j) => Inventory(
    water: (j['water']! as num).toInt(),
    waterCap: (j['waterCap']! as num).toInt(),
    nutrients: (j['nutrients']! as num).toInt(),
    nutrientCap: (j['nutrientCap']! as num).toInt(),
    dew: (j['dew']! as num).toInt(),
    seeds: {
      for (final e in (j['seeds']! as Map<String, Object?>).entries)
        SpeciesId(e.key): (e.value! as num).toInt(),
    },
  );

  Map<String, Object?> _progression(Progression p) => {
    'level': p.level,
    'xp': p.xp,
    'focusStreakDays': p.focusStreakDays,
    'longestStreak': p.longestStreak,
    'streakShields': p.streakShields,
    'lastStreakDayIndex': p.lastStreakDayIndex,
    'today': p.today.toJson(),
  };

  Progression _progressionFrom(Map<String, Object?> j) => Progression(
    level: (j['level']! as num).toInt(),
    xp: (j['xp']! as num).toInt(),
    focusStreakDays: (j['focusStreakDays']! as num).toInt(),
    longestStreak: (j['longestStreak']! as num).toInt(),
    streakShields: (j['streakShields']! as num).toInt(),
    lastStreakDayIndex: (j['lastStreakDayIndex']! as num).toInt(),
    today: DailyStats.fromJson(j['today']! as Map<String, Object?>),
  );

  static T _byName<T extends Enum>(List<T> values, String name) =>
      values.firstWhere(
        (v) => v.name == name,
        orElse: () => throw ArgumentError('unknown value "$name"'),
      );
}
