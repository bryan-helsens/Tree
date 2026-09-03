import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_data/grow_data.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_render/grow_render.dart';
import 'package:grow_sim/grow_sim.dart';

import 'game_controller.dart';
import 'time_authority.dart';

final contentProvider = Provider<ContentBundle>((ref) => mvpContent());

/// Where the save lives.
///
/// In-memory by default, which is honest: there is no platform storage wired
/// yet, so a real launch starts fresh rather than pretending otherwise. Tests
/// override this to drive relaunch and crash-recovery paths against the same
/// controller the app uses, and a device build overrides it with a
/// file-backed repository — no other code changes when it does.
final saveRepositoryProvider = Provider<SaveRepository>(
  (ref) => GuardedSaveRepository(InMemorySaveRepository()),
);

/// The one place a real clock is read.
final timeAuthorityProvider = Provider<TimeAuthority>(
  (ref) => SystemTimeAuthority(),
);

/// The one thing that owns the game.
final gameControllerProvider = ChangeNotifierProvider<GameController>((ref) {
  final content = ref.watch(contentProvider);
  return GameController(
    content: content,
    initial: GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    ),
    repository: ref.watch(saveRepositoryProvider),
    clock: ref.watch(timeAuthorityProvider),
  );
});

/// The render projection. Derived, never assigned.
final snapshotProvider = Provider<WorldSnapshot>(
  (ref) => ref.watch(gameControllerProvider).snapshot,
);

/// The canopy atlas, loaded once.
final canopyAtlasProvider = FutureProvider<CanopyAtlas>((ref) async {
  final atlas = await loadCanopyAtlas('quercus_robur');
  ref.onDispose(atlas.dispose);
  return atlas;
});
