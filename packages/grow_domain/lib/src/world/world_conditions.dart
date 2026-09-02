import 'weather.dart';

/// Environmental state at a point in simulated time. Derived deterministically
/// from the world seed, so it is also forecastable.
class WorldConditions {
  const WorldConditions({
    required this.weather,
    required this.lightLevel,
    required this.temperature,
    required this.isNight,
    required this.rainRate,
  });

  final WeatherKind weather;

  /// Site light in 0..100. Deliberately *not* zero at night: this represents
  /// the daily light available to the site, not the instantaneous sun, so a
  /// tree is not reported as stressed simply because it is 3am.
  final double lightLevel;

  /// Degrees Celsius.
  final double temperature;

  /// Drives evaporation and which animals are active — not the light band.
  final bool isNight;

  /// Moisture actually falling right now, in percentage points per hour.
  ///
  /// Zero for most hours of a rainy day: showers are bursts, not a
  /// twenty-four-hour tap. The renderer reads this too, so the visible rain
  /// and the simulated rain are the same number.
  final double rainRate;

  bool get isRaining => rainRate > 0;

  @override
  String toString() =>
      '${weather.label} ${temperature.toStringAsFixed(1)}°C '
      'light ${lightLevel.toStringAsFixed(0)}${isNight ? ' (night)' : ''}';
}
