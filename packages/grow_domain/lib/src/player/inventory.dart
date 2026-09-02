import '../values/ids.dart';

/// Four resources, deliberately. No premium currency, no energy, no timer with
/// a skip price (Design Charter C8).
class Inventory {
  const Inventory({
    required this.water,
    required this.waterCap,
    required this.nutrients,
    required this.nutrientCap,
    required this.seeds,
    required this.dew,
  });

  const Inventory.starting()
    : water = 4,
      waterCap = 15,
      nutrients = 1,
      nutrientCap = 5,
      seeds = const {},
      dew = 0;

  final int water;
  final int waterCap;
  final int nutrients;
  final int nutrientCap;
  final Map<SpeciesId, int> seeds;

  /// Passive trickle accrued while away: +1 per 3 hours, capped. Guarantees a
  /// returning player always has at least one meaningful action available
  /// (Design Charter C5).
  final int dew;

  static const int dewCap = 5;
  static const int dewIntervalHours = 3;

  static int capacityForLevel(int level) {
    final c = 15 + 2 * (level ~/ 2);
    return c > 45 ? 45 : c;
  }

  static int nutrientCapacityForLevel(int level) {
    final c = 5 + level ~/ 3;
    return c > 20 ? 20 : c;
  }

  int get totalWaterAvailable => water + dew;

  Inventory copyWith({
    int? water,
    int? waterCap,
    int? nutrients,
    int? nutrientCap,
    Map<SpeciesId, int>? seeds,
    int? dew,
  }) => Inventory(
    water: (water ?? this.water).clamp(0, waterCap ?? this.waterCap),
    waterCap: waterCap ?? this.waterCap,
    nutrients: (nutrients ?? this.nutrients).clamp(
      0,
      nutrientCap ?? this.nutrientCap,
    ),
    nutrientCap: nutrientCap ?? this.nutrientCap,
    seeds: seeds ?? this.seeds,
    dew: (dew ?? this.dew).clamp(0, dewCap),
  );

  @override
  String toString() =>
      'Inventory(💧$water/$waterCap +$dew dew, 🌱$nutrients/$nutrientCap)';
}
