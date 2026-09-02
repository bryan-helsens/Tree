import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';

import 'rng.dart';

/// Weather as a pure function of `(worldSeed, day)`.
///
/// Being stateless and forward-computable is what makes a real two-day
/// forecast possible (a level-9 unlock) and what lets the notification
/// scheduler avoid nudging about a dry tree that rain is about to fix.
class WeatherOracle {
  const WeatherOracle({required this.worldSeed, required this.content});

  final Seed worldSeed;
  final ContentBundle content;

  /// Smooth "pressure" scalar in 0..1, autocorrelated over ~3 days.
  double _pressure(int dayIndex) =>
      valueNoise1D(worldSeed.raw ^ 0x5EED, dayIndex / 3.0);

  WeatherKind weatherOn(int dayIndex) {
    final p = _pressure(dayIndex);
    final total = content.weatherTable.values.fold<double>(0, (a, b) => a + b);
    var acc = 0.0;
    // Wettest first, so low pressure means bad weather.
    final ordered = content.weatherTable.entries.toList()
      ..sort((a, b) => b.key.rainPerHour.compareTo(a.key.rainPerHour));
    for (final e in ordered) {
      acc += e.value / total;
      if (p < acc) return e.key;
    }
    return ordered.last.key;
  }

  /// Rain falls in bursts, not for twenty-four hours straight.
  ///
  /// This matters more than it looks. Continuous rain on a wet day delivers
  /// roughly +60 moisture — enough to fill a tree from empty and overwhelm
  /// every watering decision the player makes. Overwatering has to be
  /// something the player *does*, not something the weather does to them.
  /// Smooth noise gives clustered showers rather than isolated random hours.
  double rainRateAt(SimTime t) {
    final weather = weatherOn(t.dayIndex);
    if (!weather.isWet) return 0;
    final burst = valueNoise1D(worldSeed.raw ^ 0x2A1F, t.hourIndex / 4.0);
    if (burst <= 0.60) return 0;
    // Ramp in and out of the shower rather than switching it on square.
    final intensity = ((burst - 0.60) / 0.25).clamp(0.0, 1.0);
    return weather.rainPerHour * intensity;
  }

  WorldConditions conditionsAt(SimTime t) {
    final weather = weatherOn(t.dayIndex);
    final hour = t.hourOfDay;
    final isNight = hour < 6.0 || hour >= 20.0;

    // Site light, not instantaneous sun: a tree is not stressed because it is
    // 3am. Weather is what actually varies the light a site receives.
    final light = 100.0 * content.biomeBaseLight * weather.light;

    // Mild seasonal drift plus a diurnal swing. Enough to exercise the
    // temperature band without being a feature yet.
    final seasonal =
        6.0 * valueNoise1D(worldSeed.raw ^ 0x7E11, t.dayIndex / 30.0) - 3.0;
    final diurnal = isNight ? -3.5 : 2.0;
    final temperature =
        content.biomeBaseTemperature + seasonal + diurnal + weather.light * 2.0;

    return WorldConditions(
      weather: weather,
      lightLevel: light,
      temperature: temperature,
      isNight: isNight,
      rainRate: rainRateAt(t),
    );
  }

  /// Forecast for the next [days] days. Exact, because weather is a pure
  /// function of the seed.
  List<({int dayIndex, WeatherKind weather})> forecast(
    SimTime from,
    int days,
  ) => [
    for (var d = 0; d < days; d++)
      (dayIndex: from.dayIndex + d, weather: weatherOn(from.dayIndex + d)),
  ];
}

/// Pins the weather. Used by tests and the balance harness to isolate the
/// effect of player care from the effect of the sky.
class FixedWeatherOracle extends WeatherOracle {
  const FixedWeatherOracle({
    required super.worldSeed,
    required super.content,
    required this.kind,
    this.rainRateOverride,
  });

  final WeatherKind kind;
  final double? rainRateOverride;

  @override
  WeatherKind weatherOn(int dayIndex) => kind;

  @override
  double rainRateAt(SimTime t) => rainRateOverride ?? kind.rainPerHour;
}
