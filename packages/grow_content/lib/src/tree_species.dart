import 'package:grow_domain/grow_domain.dart';

enum Rarity {
  common('Common', 1),
  uncommon('Uncommon', 2),
  rare('Rare', 3),
  veryRare('Very rare', 4),
  mythic('Mythic', 5);

  const Rarity(this.label, this.stars);
  final String label;
  final int stars;

  static Rarity byName(String n) => Rarity.values.firstWhere(
    (r) => r.name == n,
    orElse: () => throw ArgumentError('unknown rarity "$n"'),
  );
}

/// A tree species, defined entirely as data.
///
/// The save stores only a [SpeciesId]; these numbers live in bundled content.
/// Rebalancing a species updates every existing instance of it with no
/// migration (docs/04-data-models.md §6).
class TreeSpecies {
  const TreeSpecies({
    required this.id,
    required this.nameKey,
    required this.displayName,
    required this.scientificName,
    required this.rarity,
    required this.family,
    required this.nativeBiome,
    required this.water,
    required this.nutrition,
    required this.light,
    required this.temperature,
    required this.waterUse,
    required this.nutrientUse,
    required this.absorption,
    required this.growthRate,
    required this.stageHours,
    required this.vigor,
    required this.resilience,
    required this.animalAttraction,
    required this.floweringChance,
    required this.pestResistance,
    required this.traits,
    required this.hiddenTraits,
  });

  final SpeciesId id;
  final String nameKey;
  final String displayName;
  final String scientificName;
  final Rarity rarity;

  /// Botanical family. Ecosystem diversity scoring rewards distinct families
  /// more than distinct species, so a varied forest beats a large one.
  final String family;
  final BiomeId nativeBiome;

  final Band water;
  final Band nutrition;
  final Band light;
  final Band temperature;

  /// Multipliers on the baseline rates. 1.0 is the reference species.
  final double waterUse;
  final double nutrientUse;

  /// Percentage points of moisture gained per Water unit spent.
  final double absorption;

  /// >1 grows faster. Divides the stage durations.
  final double growthRate;

  /// Perfect-care hours per stage transition. Seven entries; the last is unused
  /// because `ancient` is terminal.
  final List<double> stageHours;

  /// Healing speed multiplier.
  final double vigor;

  /// 0..1, reduces the rate at which discomfort costs health.
  final double resilience;

  final double animalAttraction;
  final double floweringChance;
  final double pestResistance;

  /// Traits visible from the moment the species is discovered.
  final List<TraitId> traits;

  /// Traits the player learns only by growing one (docs/09 §4 renders these
  /// as `??????` until discovered).
  final List<TraitId> hiddenTraits;

  double hoursForStage(GrowthStage stage) =>
      stageHours[stage.index] / growthRate;

  factory TreeSpecies.fromJson(Map<String, Object?> j) {
    List<double> doubles(String k) =>
        (j[k]! as List<Object?>).map((e) => (e! as num).toDouble()).toList();
    List<TraitId> traitList(String k) =>
        ((j[k] ?? const <Object?>[]) as List<Object?>)
            .map((e) => TraitId(e! as String))
            .toList();
    Band band(String k) => Band.fromJson(j[k]! as Map<String, Object?>);
    double num_(String k) => (j[k]! as num).toDouble();

    final stages = doubles('stageHours');
    if (stages.length != GrowthStage.values.length) {
      throw ArgumentError(
        'species "${j['id']}" declares ${stages.length} stageHours, '
        'expected ${GrowthStage.values.length}',
      );
    }
    return TreeSpecies(
      id: SpeciesId(j['id']! as String),
      nameKey: j['nameKey']! as String,
      displayName: j['displayName']! as String,
      scientificName: j['scientificName']! as String,
      rarity: Rarity.byName(j['rarity']! as String),
      family: j['family']! as String,
      nativeBiome: BiomeId(j['nativeBiome']! as String),
      water: band('water'),
      nutrition: band('nutrition'),
      light: band('light'),
      temperature: band('temperature'),
      waterUse: num_('waterUse'),
      nutrientUse: num_('nutrientUse'),
      absorption: num_('absorption'),
      growthRate: num_('growthRate'),
      stageHours: stages,
      vigor: num_('vigor'),
      resilience: num_('resilience'),
      animalAttraction: num_('animalAttraction'),
      floweringChance: num_('floweringChance'),
      pestResistance: num_('pestResistance'),
      traits: traitList('traits'),
      hiddenTraits: traitList('hiddenTraits'),
    );
  }

  @override
  String toString() => 'TreeSpecies(${id.raw})';
}
