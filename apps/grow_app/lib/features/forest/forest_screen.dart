import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';
import 'package:grow_sim/grow_sim.dart';

import '../../design_system/tokens.dart';
import '../../game/game_controller.dart';
import '../../game/game_providers.dart';
import '../tree_detail/tree_detail_sheet.dart';
import 'hud.dart';

/// The main screen: the forest, with the interface over it.
///
/// The world is never replaced by a panel. Opening a tree slides a sheet up
/// over a still-living scene, so watering it and watching it respond happen in
/// the same glance.
class ForestScreen extends ConsumerStatefulWidget {
  const ForestScreen({super.key});

  @override
  ConsumerState<ForestScreen> createState() => _ForestScreenState();
}

class _ForestScreenState extends ConsumerState<ForestScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _clock = 0;

  /// Smoothed appearance per tree. Eased toward what the projection says —
  /// the target always comes from simulation state, never from a gesture.
  final Map<String, FoliageState> _shown = {};

  TreeId? _open;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.5) return;
    _clock += dt;

    final snapshot = ref.read(snapshotProvider);
    for (final tree in snapshot.trees) {
      final key = tree.id.raw;
      _shown[key] = approachFoliage(
        _shown[key] ?? tree.foliage,
        tree.foliage,
        dt,
      );
    }
    // Advance the simulation on the same clock the world is drawn on.
    ref
        .read(gameControllerProvider)
        .tick(Duration(microseconds: (dt * 1e6).round()));
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(gameControllerProvider);
    final snapshot = ref.watch(snapshotProvider);
    final atlas = ref.watch(canopyAtlasProvider).valueOrNull;

    final trees = [
      for (var i = 0; i < snapshot.trees.length; i++)
        _toForestTree(snapshot.trees[i], controller, i, snapshot.trees.length),
    ];

    final openTree = _open == null ? null : controller.state.treeById(_open!);

    return ColoredBox(
      color: GrowTokens.ink,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ForestView(
            trees: trees,
            conditions: snapshot.conditions,
            timeOfDay01: snapshot.timeOfDay01,
            timeSeconds: _clock,
            worldSeed: controller.state.worldSeed.raw,
            atlas: atlas,
            onTapTree: _openTree,
          ),
          // One HUD. The call to action is simply absent while a tree is
          // open — two competing primary actions on one screen is one too
          // many, and cross-fading a second copy of the HUD just leaves a
          // ghost behind the sheet.
          ForestHud(
            progression: controller.state.progression,
            inventory: controller.state.inventory,
            conditions: snapshot.conditions,
            onStartFocus: () {},
            focusHint: _hint(snapshot),
            showCall: openTree == null,
          ),
          if (openTree != null) _sheet(controller, openTree),
        ],
      ),
    );
  }

  ForestTree _toForestTree(
    TreeVisual visual,
    GameController controller,
    int index,
    int count,
  ) {
    final tree = controller.state.treeById(visual.id)!;
    return ForestTree(
      id: visual.id,
      skeleton: const TreeGenerator().generate(
        rules: formFor(visual.speciesId.raw).rules,
        seed: visual.seed,
        growth01: visual.growth01,
      ),
      form: formFor(visual.speciesId.raw),
      foliage: _shown[visual.id.raw] ?? visual.foliage,
      groundX: count == 1 ? 0.5 : 0.24 + 0.52 * (index / (count - 1)),
      depth: count == 1 ? 0 : 0.35 * (index / (count - 1)),
      seed: visual.seed,
      semanticLabel: visual.label,
      semanticValue: visual.detail,
      // Domain counters: the care burst follows these, not the button.
      timesWatered: tree.timesWatered,
      timesFed: tree.timesFed,
    );
  }

  void _openTree(TreeId id) {
    // Seeing a tree in trouble is a domain fact that gates its death.
    ref.read(gameControllerProvider).noteSighting(id);
    setState(() => _open = id);
  }

  Widget _sheet(GameController c, Tree tree) {
    final visual = ref
        .read(snapshotProvider)
        .trees
        .firstWhere((t) => t.id == tree.id);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        // The world stays visible above the sheet. A panel that covers the
        // tree removes the thing the player opened it to look at.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.56,
        ),
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 320) setState(() => _open = null);
          },
          child: TreeDetailSheet(
            tree: tree,
            species: c.speciesOf(tree),
            visual: visual,
            waterPreview: c.previewWater(tree),
            feedPreview: c.previewFeed(tree),
            waterAvailable: c.state.inventory.totalWaterAvailable,
            nutrientsAvailable: c.state.inventory.nutrients,
            refusal: c.refusal?.message,
            // The button asks the controller. It does not touch appearance,
            // and it does not start an animation.
            onWater: () => c.water(tree.id),
            onFeed: () => c.feed(tree.id),
            onClose: () => setState(() => _open = null),
          ),
        ),
      ),
    );
  }

  /// One line under the focus button. Never a countdown, never a nag.
  String _hint(WorldSnapshot snapshot) => switch (snapshot.conditions.weather) {
    WeatherKind.rain ||
    WeatherKind.storm => 'Rain is watering your forest while you are away',
    _ => 'Your forest grows while you are away',
  };
}
