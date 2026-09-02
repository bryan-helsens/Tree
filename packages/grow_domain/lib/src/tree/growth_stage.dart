/// Visible growth stages. Growth within a stage is continuous, so the renderer
/// interpolates the silhouette rather than swapping sprites at these points.
enum GrowthStage {
  seed('Seed'),
  sprout('Sprout'),
  seedling('Seedling'),
  sapling('Sapling'),
  young('Young tree'),
  mature('Mature tree'),
  ancient('Ancient');

  const GrowthStage(this.label);
  final String label;

  bool get isFinal => this == GrowthStage.ancient;
  GrowthStage get next => isFinal ? this : GrowthStage.values[index + 1];

  /// Relative water draw. A mature tree drinks five times what a seed does.
  static const List<double> drinkFactor = [
    0.30,
    0.50,
    0.65,
    0.80,
    1.00,
    1.30,
    1.50,
  ];

  /// How strongly a tree at this stage attracts wildlife.
  static const List<double> attractWeight = [
    0.0,
    0.05,
    0.15,
    0.35,
    0.65,
    1.00,
    1.30,
  ];

  double get drink => drinkFactor[index];
  double get attract => attractWeight[index];
}
