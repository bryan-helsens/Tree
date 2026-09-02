/// Core entities and value objects for GROW.
///
/// This package has **no runtime dependencies**, by architectural rule
/// (docs/03-project-structure.md). It must never import Flutter, `dart:io`,
/// or anything that can read a clock.
library;

export 'src/game_state.dart';
export 'src/player/inventory.dart';
export 'src/player/progression.dart';
export 'src/tree/affliction.dart';
export 'src/tree/growth_stage.dart';
export 'src/tree/health_state.dart';
export 'src/tree/tree.dart';
export 'src/values/band.dart';
export 'src/values/ids.dart';
export 'src/values/sim_time.dart';
export 'src/values/vital.dart';
export 'src/world/weather.dart';
export 'src/world/world_conditions.dart';
