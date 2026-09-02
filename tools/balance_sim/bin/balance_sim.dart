// Headless balance harness.
//
//   dart run tools/balance_sim/bin/balance_sim.dart [--days 30] [--csv out.csv]
//
// Runs every player archetype through the real action and economy APIs and
// checks the ship criteria from docs/06 §9. Exits non-zero on a violation, so
// a balance regression cannot be merged by accident.
import 'dart:io';

import 'package:balance_sim/archetypes.dart';
import 'package:grow_content/grow_content.dart';

void main(List<String> args) {
  final days = _intArg(args, '--days') ?? 30;
  final csvPath = _stringArg(args, '--csv');
  final content = mvpContent();

  final summaries = [
    for (final a in archetypes)
      runArchetype(a, content: content, days: days, seed: 20260902),
  ];

  final rows = <String>[DayRecord.csvHeader];
  for (final s in summaries) {
    for (final d in s.days) {
      rows.add(d.toCsv(s.archetype.name));
    }
  }
  if (csvPath != null) {
    File(csvPath).writeAsStringSync(rows.join('\n'));
    stdout.writeln('wrote ${rows.length - 1} rows to $csvPath');
  }

  stdout.writeln('\nGROW balance report — $days simulated days\n');
  stdout.writeln(
    'archetype             lvl    xp   💧  🌱  health  growth  '
    'min-health  blocked  died',
  );
  stdout.writeln('-' * 92);
  for (final s in summaries) {
    final l = s.last;
    stdout.writeln(
      '${s.archetype.name.padRight(22)}'
      '${l.level.toString().padLeft(3)}'
      '${l.xp.toString().padLeft(6)}'
      '${l.water.toString().padLeft(5)}'
      '${l.nutrients.toString().padLeft(4)}'
      '${l.health.toStringAsFixed(0).padLeft(8)}'
      '${l.absoluteGrowth.toStringAsFixed(0).padLeft(8)}'
      '${s.minHealth.toStringAsFixed(0).padLeft(12)}'
      '${s.totalBlocked.toString().padLeft(9)}'
      '${(s.everDied ? 'YES' : 'no').padLeft(6)}',
    );
  }

  stdout.writeln('\nShip criteria (docs/06 §9):');
  final failures = <String>[];

  void check(String label, bool ok, [String? detail]) {
    stdout.writeln(
      '  ${ok ? 'PASS' : 'FAIL'}  $label${detail == null ? '' : '  — $detail'}',
    );
    if (!ok) failures.add(label);
  }

  final byName = {for (final s in summaries) s.archetype.name: s};

  check('no archetype ever loses a tree', summaries.every((s) => !s.everDied));

  final absentee = byName['absentee_14_day']!;
  check(
    '14-day absentee: zero deaths, recoverable on return',
    !absentee.everDied && absentee.last.health > 60,
    'health on day ${days - 1}: ${absentee.last.health.toStringAsFixed(0)}',
  );

  final overwaterer = byName['overwaterer']!;
  check(
    'deliberate overwaterer never reaches critical from routine play',
    !overwaterer.everReachedCritical,
    'min health ${overwaterer.minHealth.toStringAsFixed(0)}',
  );

  final weekend = byName['weekend_only']!;
  final weeks = days / 7.0;
  check(
    'weekend-only player gains at least a level a week',
    weekend.last.level >= 1 + (weeks * 0.9).floor(),
    'level ${weekend.last.level} after ${weeks.toStringAsFixed(1)} weeks',
  );

  final daily = byName['daily_two_sessions']!;
  check(
    'daily player reaches level 8 within 30 days',
    daily.last.level >= 8,
    'level ${daily.last.level}',
  );

  check(
    'no archetype is ever blocked from acting for long',
    summaries.every((s) => s.totalBlocked <= days),
    'worst: ${summaries.map((s) => s.totalBlocked).reduce((a, b) => a > b ? a : b)}',
  );

  check(
    'a careful daily player keeps their tree healthy',
    daily.minHealth >= 60,
    'min health ${daily.minHealth.toStringAsFixed(0)}',
  );

  if (failures.isEmpty) {
    stdout.writeln('\nAll ship criteria met.');
  } else {
    stdout.writeln('\n${failures.length} criteria failed.');
    exit(1);
  }
}

int? _intArg(List<String> a, String flag) {
  final i = a.indexOf(flag);
  return i >= 0 && i + 1 < a.length ? int.tryParse(a[i + 1]) : null;
}

String? _stringArg(List<String> a, String flag) {
  final i = a.indexOf(flag);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
}
