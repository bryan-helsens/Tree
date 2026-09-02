import 'dart:convert';

import 'package:grow_domain/grow_domain.dart';

import 'tree_species.dart';

/// Everything the simulation needs to know about the world's content.
///
/// Loaded once, immutable, and validated on construction so a content error is
/// a build/startup failure rather than a mid-game crash.
class ContentBundle {
  ContentBundle({
    required Map<SpeciesId, TreeSpecies> species,
    required this.version,
    required this.weatherTable,
    required this.biomeBaseTemperature,
    required this.biomeBaseLight,
  }) : _species = Map.unmodifiable(species) {
    if (_species.isEmpty) {
      throw ArgumentError('content bundle contains no species');
    }
    final totalWeight = weatherTable.values.fold<double>(0, (a, b) => a + b);
    if (totalWeight <= 0) {
      throw ArgumentError('weather table has no positive weights');
    }
  }

  final Map<SpeciesId, TreeSpecies> _species;
  final int version;

  /// Which weather kinds this build ships, and how likely each is.
  ///
  /// The MVP renders sunny/cloudy/rain only, so those are the only entries.
  /// Adding storm or snow later is a content change, not an engine change.
  final Map<WeatherKind, double> weatherTable;

  final double biomeBaseTemperature;
  final double biomeBaseLight;

  Iterable<TreeSpecies> get allSpecies => _species.values;

  TreeSpecies operator [](SpeciesId id) {
    final s = _species[id];
    if (s == null) {
      throw StateError(
        'species "${id.raw}" is not in content bundle v$version. '
        'A save referencing a removed species must be migrated by the loader.',
      );
    }
    return s;
  }

  bool has(SpeciesId id) => _species.containsKey(id);

  static ContentBundle fromJson(Map<String, Object?> j) {
    final speciesList = (j['species']! as List<Object?>).map(
      (e) => TreeSpecies.fromJson(e! as Map<String, Object?>),
    );
    final table = <WeatherKind, double>{};
    for (final e in (j['weather']! as Map<String, Object?>).entries) {
      final kind = WeatherKind.values.firstWhere(
        (w) => w.name == e.key,
        orElse: () => throw ArgumentError('unknown weather "${e.key}"'),
      );
      table[kind] = (e.value! as num).toDouble();
    }
    return ContentBundle(
      species: {for (final s in speciesList) s.id: s},
      version: (j['version']! as num).toInt(),
      weatherTable: table,
      biomeBaseTemperature: (j['biomeBaseTemperature']! as num).toDouble(),
      biomeBaseLight: (j['biomeBaseLight']! as num).toDouble(),
    );
  }

  static ContentBundle parse(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);
}
