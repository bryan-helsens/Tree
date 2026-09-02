/// Weather affects moisture, light and — through both — comfort and growth.
/// It is never purely visual.
enum WeatherKind {
  sunny('Sunny', evaporation: 1.25, light: 1.00, rainPerHour: 0.0),
  cloudy('Cloudy', evaporation: 1.00, light: 0.72, rainPerHour: 0.0),
  rain('Rain', evaporation: 0.60, light: 0.50, rainPerHour: 2.5),
  storm('Storm', evaporation: 0.70, light: 0.35, rainPerHour: 6.0),
  fog('Fog', evaporation: 0.75, light: 0.55, rainPerHour: 0.2),
  snow('Snow', evaporation: 0.50, light: 0.45, rainPerHour: 0.4);

  const WeatherKind(
    this.label, {
    required this.evaporation,
    required this.light,
    required this.rainPerHour,
  });

  final String label;

  /// Multiplier on moisture loss.
  final double evaporation;

  /// Fraction of full daylight reaching the canopy.
  final double light;

  /// Free moisture, in percentage points per hour. Also the mechanism by which
  /// a careless player ends up overwatered.
  final double rainPerHour;

  bool get isWet => rainPerHour > 0;
}
