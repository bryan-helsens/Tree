import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

/// How a modelled player behaves. The harness drives these through the real
/// action and economy APIs — never by poking vitals directly — so what it
/// measures is what a player would actually experience.
class Archetype {
  const Archetype({
    required this.name,
    required this.description,
    required this.sessionsPerDay,
    required this.sessionMinutes,
    required this.activeDayOfWeek,
    required this.caresForTrees,
    this.overwaters = false,
    this.absentFromDay,
    this.absentUntilDay,
  });

  final String name;
  final String description;
  final int sessionsPerDay;
  final int sessionMinutes;

  /// Which weekdays this player opens the app at all. Empty means every day.
  final Set<int> activeDayOfWeek;

  final bool caresForTrees;

  /// Tops the tree up at every opportunity, ignoring the ideal band.
  final bool overwaters;

  final int? absentFromDay;
  final int? absentUntilDay;

  bool isActiveOn(int day) {
    if (absentFromDay != null &&
        absentUntilDay != null &&
        day >= absentFromDay! &&
        day < absentUntilDay!) {
      return false;
    }
    if (activeDayOfWeek.isEmpty) return true;
    return activeDayOfWeek.contains(day % 7);
  }
}

const archetypes = <Archetype>[
  Archetype(
    name: 'daily_two_sessions',
    description: 'Opens twice a day, one focus session each, tends carefully',
    sessionsPerDay: 2,
    sessionMinutes: 30,
    activeDayOfWeek: {},
    caresForTrees: true,
  ),
  Archetype(
    name: 'weekend_only',
    description: 'Plays Saturday and Sunday only',
    sessionsPerDay: 2,
    sessionMinutes: 45,
    activeDayOfWeek: {5, 6},
    caresForTrees: true,
  ),
  Archetype(
    name: 'once_a_week',
    description: 'One session a week, tends what needs it',
    sessionsPerDay: 1,
    sessionMinutes: 30,
    activeDayOfWeek: {3},
    caresForTrees: true,
  ),
  Archetype(
    name: 'absentee_14_day',
    description: 'Plays for three days, disappears for a fortnight, returns',
    sessionsPerDay: 2,
    sessionMinutes: 30,
    activeDayOfWeek: {},
    caresForTrees: true,
    absentFromDay: 3,
    absentUntilDay: 17,
  ),
  Archetype(
    name: 'overwaterer',
    description: 'Waters every time they open the app, band be damned',
    sessionsPerDay: 2,
    sessionMinutes: 30,
    activeDayOfWeek: {},
    caresForTrees: true,
    overwaters: true,
  ),
];

/// One day of a modelled player's behaviour and the state it produced.
class DayRecord {
  const DayRecord({
    required this.day,
    required this.level,
    required this.xp,
    required this.water,
    required this.nutrients,
    required this.dew,
    required this.health,
    required this.moisture,
    required this.nutrition,
    required this.absoluteGrowth,
    required this.stage,
    required this.state,
    required this.sessions,
    required this.actionsTaken,
    required this.blockedActions,
    required this.afflictions,
  });

  final int day;
  final int level;
  final int xp;
  final int water;
  final int nutrients;
  final int dew;
  final double health;
  final double moisture;
  final double nutrition;
  final double absoluteGrowth;
  final String stage;
  final String state;
  final int sessions;
  final int actionsTaken;

  /// Times the player wanted to act and could not afford it. A player should
  /// never be blocked for long (Design Charter C5).
  final int blockedActions;
  final int afflictions;

  static const String csvHeader =
      'archetype,day,level,xp,water,nutrients,dew,health,moisture,nutrition,'
      'growth,stage,state,sessions,actions,blocked,afflictions';

  String toCsv(String archetype) => [
    archetype,
    day,
    level,
    xp,
    water,
    nutrients,
    dew,
    health.toStringAsFixed(2),
    moisture.toStringAsFixed(2),
    nutrition.toStringAsFixed(2),
    absoluteGrowth.toStringAsFixed(2),
    stage,
    state,
    sessions,
    actionsTaken,
    blockedActions,
    afflictions,
  ].join(',');
}

class RunSummary {
  RunSummary(this.archetype, this.days);

  final Archetype archetype;
  final List<DayRecord> days;

  DayRecord get last => days.last;
  int get deaths => days.where((d) => d.state == 'snag').length;
  bool get everDied => days.any((d) => d.state == 'snag');
  double get minHealth =>
      days.map((d) => d.health).reduce((a, b) => a < b ? a : b);
  int get totalBlocked => days.fold(0, (a, d) => a + d.blockedActions);
  bool get everReachedCritical => days.any((d) => d.state == 'critical');
}

/// Runs one archetype for [days] simulated days through the real APIs.
RunSummary runArchetype(
  Archetype archetype, {
  required ContentBundle content,
  int days = 30,
  int seed = 20260902,
}) {
  final simulator = Simulator(content: content);
  final actions = Actions(content);
  // Sessions go through the real state machine, so thirty days of modelled
  // play exercises fatigue, streaks, the daily cap and acknowledgement
  // exactly as a device would.
  final focus = FocusMachine(content: content);

  var state = GameState.newGame(
    worldSeed: Seed(seed),
    starterSpecies: const SpeciesId('quercus_robur'),
  );

  final records = <DayRecord>[];

  for (var day = 0; day < days; day++) {
    var sessionsToday = 0;
    var actionsToday = 0;
    var blockedToday = 0;

    if (archetype.isActiveOn(day)) {
      // The player opens the app a few times across the waking day.
      for (var opening = 0; opening < archetype.sessionsPerDay; opening++) {
        final hour = 9 + opening * 7;
        final at = SimTime(day * SimTime.dayMs + hour * SimTime.hourMs);
        state = simulator.run(state: state, to: at).state;
        state = state.touched(state.simTime);

        // Care first. A careful player tops a tree up until the action
        // preview says the next one would overshoot the band — which is
        // exactly what the tree panel teaches, since the ideal range is drawn
        // on the bar and every button previews its result. An overwaterer
        // ignores that warning and keeps going.
        if (archetype.caresForTrees) {
          for (final id in state.livingTrees.map((t) => t.id).toList()) {
            for (var pour = 0; pour < 6; pour++) {
              final tree = state.treeById(id)!;
              final species = content[tree.species];
              final preview = actions.previewWater(tree);
              final wants = archetype.overwaters
                  ? tree.water.value < 92
                  : preview.to <= species.water.max;
              if (!wants) break;
              final r = actions.water(state, id);
              if (r.ok) {
                state = r.state!;
                actionsToday++;
              } else {
                blockedToday++;
                break;
              }
            }

            final tree = state.treeById(id)!;
            final species = content[tree.species];
            if (!species.nutrition.contains(tree.nutrition.value) &&
                tree.nutrition.value < species.nutrition.min) {
              final r = actions.feed(state, id);
              if (r.ok) {
                state = r.state!;
                actionsToday++;
              } else {
                blockedToday++;
              }
            }
          }
        }

        // Then a focus session, driven through the real state machine so the
        // harness measures the shipped path: fatigue, streaks, the daily soft
        // cap and the acknowledgement that gates the next session.
        final started = focus.start(
          state,
          planned: Duration(minutes: archetype.sessionMinutes),
          id: 'd$day-s$opening',
          wallMs: 0,
        );
        if (started.ok) {
          state = started.state!;
          state = simulator
              .run(
                state: state,
                to:
                    state.simTime +
                    Duration(minutes: archetype.sessionMinutes + 1),
              )
              .state;
          final claimed = focus.claim(focus.evaluate(state));
          if (claimed.ok) {
            state = focus.dismiss(claimed.state!).state ?? claimed.state!;
            sessionsToday++;
          }
          state = state.touched(state.simTime);
        }
      }
    }

    // Advance to the end of the day.
    state = simulator
        .run(state: state, to: SimTime((day + 1) * SimTime.dayMs))
        .state;

    final tree = state.trees.first;
    records.add(
      DayRecord(
        day: day,
        level: state.progression.level,
        xp: state.progression.xp,
        water: state.inventory.water,
        nutrients: state.inventory.nutrients,
        dew: state.inventory.dew,
        health: tree.health.value,
        moisture: tree.water.value,
        nutrition: tree.nutrition.value,
        absoluteGrowth: tree.stage.index * 100.0 + tree.growth.value,
        stage: tree.stage.name,
        state: tree.state.name,
        sessions: sessionsToday,
        actionsTaken: actionsToday,
        blockedActions: blockedToday,
        afflictions: tree.afflictions.length,
      ),
    );
  }

  return RunSummary(archetype, records);
}
