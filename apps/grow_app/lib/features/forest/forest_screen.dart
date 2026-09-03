import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';
import 'package:grow_sim/grow_sim.dart';

import '../../design_system/tokens.dart';
import '../../game/focus_view.dart';
import '../../game/game_controller.dart';
import '../../game/game_providers.dart';
import '../focus/focus_sheet.dart';
import '../focus/welcome_back_sheet.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _clock = 0;

  /// Smoothed appearance per tree. Eased toward what the projection says —
  /// the target always comes from simulation state, never from a gesture.
  final Map<String, FoliageState> _shown = {};

  /// Smoothed *size* per tree, on the same principle.
  ///
  /// A focus session's reward lands as a step change in `tree.growth`. Drawing
  /// that step directly makes the tree pop, which reads as a slot machine
  /// paying out. Easing toward it makes the same reward arrive as the tree
  /// visibly growing — which is the thing the player is supposed to become
  /// attached to. The domain value is still the truth; only its display lags.
  final Map<String, double> _drawnGrowth = {};

  TreeId? _open;

  /// Presentation state, and only presentation state: whether these two
  /// sheets are on screen. What they *say* comes entirely from the save.
  bool _focusOpen = false;
  bool _returnSeen = false;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
    // Load the save, credit the time that passed and settle any session that
    // finished while the app was closed. A session is claimed here, not by
    // anyone tapping anything.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameControllerProvider).resume();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Backgrounding does nothing to the session — it is a record, not a
    // process — but the save's clock anchor is what the next resume reasons
    // about, so this write is the important one.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(gameControllerProvider).onPaused();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;

    final snapshot = ref.read(snapshotProvider);

    // Seed on first sight, *before* the frame-time guard. A tree first seen
    // on a frame that gets skipped (dt of zero, or a long stall) would
    // otherwise be seeded later, from a target that has since moved — and
    // would snap to it instead of easing. That is the difference between a
    // reward that reads as growth and one that reads as a pop.
    for (final tree in snapshot.trees) {
      _shown.putIfAbsent(tree.id.raw, () => tree.foliage);
      _drawnGrowth.putIfAbsent(tree.id.raw, () => tree.growth01);
    }

    if (dt <= 0 || dt > 0.5) return;
    _clock += dt;

    for (final tree in snapshot.trees) {
      final key = tree.id.raw;
      _shown[key] = approachFoliage(_shown[key]!, tree.foliage, dt);
      _drawnGrowth[key] = _approach(_drawnGrowth[key]!, tree.growth01, dt);
    }
    // Advance the simulation on the same clock the world is drawn on.
    ref
        .read(gameControllerProvider)
        .tick(Duration(microseconds: (dt * 1e6).round()));
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

    // Both sheets are decided by the save, not by what the player last
    // tapped. A session that finished while the app was closed is claimed
    // during resume(), so the completion panel is simply what `FocusView`
    // reports on the first frame back.
    final focus = FocusView.of(controller.state);
    final summary = controller.lastReturn;
    final showReturn = !_returnSeen && summary.isWorthShowing;
    final showFocus = _focusOpen || focus is FocusFinished;

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
            onStartFocus: () => setState(() => _focusOpen = true),
            focusHint: _focusHint(focus, snapshot),
            showCall: openTree == null && !showFocus && !showReturn,
          ),
          if (openTree != null) _sheet(controller, openTree),
          // The return moment outranks everything: it is the first thing a
          // player sees on coming back, and it must not be competing with a
          // tree panel left open from last time.
          if (showReturn)
            _bottomSheet(
              WelcomeBackSheet(
                summary: summary,
                treeGrowth: summary.growthFor(controller.state.trees.first.id),
                onDismiss: () => setState(() => _returnSeen = true),
              ),
            )
          else if (showFocus)
            _bottomSheet(
              FocusSheet(
                view: focus,
                refusal: controller.refusal?.message,
                onStart: (planned) => controller.startSession(planned),
                onEndEarly: controller.endSessionEarly,
                // Dismissal only clears the record so another session can
                // start. The reward was committed long before this tap.
                onDismiss: () {
                  controller.dismissSession();
                  setState(() => _focusOpen = false);
                },
                onClose: () => setState(() => _focusOpen = false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomSheet(Widget child) => Align(
    alignment: Alignment.bottomCenter,
    child: ConstrainedBox(
      // The forest stays visible above every sheet. On the return screen that
      // is the whole point: the tree that changed is on screen while the
      // panel says what changed.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: SingleChildScrollView(child: child),
    ),
  );

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
        // The drawn size trails the domain's, so a reward arrives as growth
        // rather than as a jump. Falls back to the true value on the first
        // frame, so a cold launch never animates up from nothing.
        growth01: _drawnGrowth[visual.id.raw] ?? visual.growth01,
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
  String _focusHint(FocusView focus, WorldSnapshot snapshot) => switch (focus) {
    FocusRunning() => 'A session is underway',
    _ => switch (snapshot.conditions.weather) {
      WeatherKind.rain ||
      WeatherKind.storm => 'Rain is watering your forest while you are away',
      _ => 'Your forest grows while you are away',
    },
  };

  /// Framerate-independent approach, matching `approachFoliage`.
  ///
  /// Slower than the foliage easing on purpose: a tree should look like it is
  /// growing, not like it is inflating.
  static double _approach(
    double from,
    double to,
    double dt, {
    double rate = 1.6,
  }) {
    final t = 1 - math.exp(-rate * dt);
    return from + (to - from) * t;
  }
}
