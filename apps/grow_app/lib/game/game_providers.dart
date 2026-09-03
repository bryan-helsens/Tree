import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_render/grow_render.dart';
import 'package:grow_sim/grow_sim.dart';

import 'game_controller.dart';

final contentProvider = Provider<ContentBundle>((ref) => mvpContent());

/// The one thing that owns the game.
final gameControllerProvider = ChangeNotifierProvider<GameController>((ref) {
  final content = ref.watch(contentProvider);
  return GameController(
    content: content,
    initial: GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    ),
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
