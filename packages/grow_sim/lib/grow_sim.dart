/// The deterministic simulation for GROW.
///
/// Pure Dart: no Flutter, no `dart:io`, no clock, no unseeded randomness.
/// Everything it needs arrives as an argument, which is what makes a 30-day
/// run testable in milliseconds in CI with no device.
library;

export 'src/actions.dart';
export 'src/comfort.dart';
export 'src/economy.dart';
export 'src/rng.dart';
export 'src/sim_constants.dart';
export 'src/sim_event.dart';
export 'src/simulator.dart';
export 'src/weather_oracle.dart';
