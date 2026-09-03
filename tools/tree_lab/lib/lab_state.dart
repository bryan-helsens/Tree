import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';
import 'package:grow_sim/grow_sim.dart';

/// Tree Lab's state.
///
/// Deliberately driven by **simulation vitals**, not by visual uniforms. The
/// sliders set water, nutrition and health; appearance comes back through the
/// same `WorldProjector` the game uses. Tuning against hand-set uniforms would
/// mean tuning a look the game cannot actually produce.
class LabState extends ChangeNotifier {
  LabState() {
    _rebuild();
  }

  final ContentBundle _content = mvpContent();
  late final WorldProjector _projector = WorldProjector(content: _content);

  SpeciesForm _form = oakForm;
  BranchRules _rules = oakForm.rules;
  int _seed = 4242;
  double _growth = 0.85;

  // Simulation inputs.
  double _water = 58;
  double _nutrition = 52;
  double _health = 95;
  WeatherKind _weather = WeatherKind.sunny;
  double _timeOfDay = 0.5;

  double _time = 0;
  bool _animating = true;
  bool _showSkeleton = false;
  bool _showWorld = true;
  double _windAmplitude = 1.0;

  TreeSkeleton? _skeleton;
  FoliageState _foliage = const FoliageState();
  WorldConditions? _conditions;
  CanopyAtlas? _atlas;
  String _readout = '';

  SpeciesForm get form => _form;
  BranchRules get rules => _rules;
  int get seed => _seed;
  double get growth => _growth;
  double get water => _water;
  double get nutrition => _nutrition;
  double get health => _health;
  WeatherKind get weather => _weather;
  double get timeOfDay => _timeOfDay;
  double get time => _time;
  bool get animating => _animating;
  bool get showSkeleton => _showSkeleton;
  bool get showWorld => _showWorld;
  double get windAmplitude => _windAmplitude;
  TreeSkeleton get skeleton => _skeleton!;
  FoliageState get foliage => _foliage;
  WorldConditions get conditions => _conditions!;
  CanopyAtlas? get atlas => _atlas;

  /// What the projection produced, shown next to the sliders so the causal
  /// chain is visible while tuning.
  String get readout => _readout;

  TreeSpecies get species => _content[SpeciesId(_form.id)];

  void selectSpecies(SpeciesForm f) {
    _form = f;
    _rules = f.rules;
    _rebuild();
  }

  void updateRules(BranchRules r) {
    _rules = r;
    _rebuild();
  }

  void setSeed(int s) {
    _seed = s;
    _rebuild();
  }

  void setGrowth(double g) {
    _growth = g;
    _rebuild();
  }

  void setWater(double v) {
    _water = v;
    _rebuild();
  }

  void setNutrition(double v) {
    _nutrition = v;
    _rebuild();
  }

  void setHealth(double v) {
    _health = v;
    _rebuild();
  }

  void setWeather(WeatherKind w) {
    _weather = w;
    _rebuild();
  }

  void setTimeOfDay(double v) {
    _timeOfDay = v;
    _rebuild();
  }

  void setWind(double a) {
    _windAmplitude = a;
    notifyListeners();
  }

  void toggleAnimating() {
    _animating = !_animating;
    notifyListeners();
  }

  void toggleSkeleton() {
    _showSkeleton = !_showSkeleton;
    notifyListeners();
  }

  void toggleWorld() {
    _showWorld = !_showWorld;
    notifyListeners();
  }

  void tick(double dt) {
    if (!_animating) return;
    _time += dt;
    notifyListeners();
  }

  void reset() {
    _rules = _form.rules;
    _water = 58;
    _nutrition = 52;
    _health = 95;
    _rebuild();
  }

  Future<void> loadAtlas() async {
    final data = await rootBundle.load(
      'packages/grow_render/assets/canopy_oak.png',
    );
    _atlas = await CanopyAtlas.decode(data.buffer.asUint8List());
    notifyListeners();
  }

  void _rebuild() {
    _skeleton = const TreeGenerator().generate(
      rules: _rules,
      seed: _seed,
      growth01: _growth,
    );

    // Build a real tree at these vitals and run it through the real
    // projection, so the appearance shown is the appearance the game derives.
    final stageIndex = (_growth * (GrowthStage.values.length - 1))
        .floor()
        .clamp(0, 6);
    final stage = GrowthStage.values[stageIndex];
    final tree =
        Tree.seedling(
          id: const TreeId('lab'),
          species: SpeciesId(_form.id),
          seed: Seed(_seed),
          slot: 0,
          plantedAt: SimTime.zero,
        ).copyWith(
          water: Vital(_water),
          nutrition: Vital(_nutrition),
          health: Vital(_health),
          stage: stage,
        );

    final conditions = WorldConditions(
      weather: _weather,
      lightLevel: 100 * _weather.light,
      temperature: 15,
      isNight: _timeOfDay < 0.24 || _timeOfDay > 0.80,
      rainRate: _weather.rainPerHour,
    );
    _conditions = conditions;

    final comfort = Comfort.evaluate(
      tree: tree,
      species: species,
      conditions: conditions,
    );
    _foliage = _projector.foliageFor(tree, species, conditions, comfort);
    _readout =
        'comfort ${comfort.overall.toStringAsFixed(2)} · '
        'limited by ${comfort.limitingFactor}\n'
        'droop ${_foliage.droop.toStringAsFixed(2)} · '
        'pallor ${_foliage.pallor.toStringAsFixed(2)} · '
        'scorch ${_foliage.scorch.toStringAsFixed(2)} · '
        'wet ${_foliage.wetness.toStringAsFixed(2)}';
    notifyListeners();
  }

  /// The tuned parameters, ready to paste into `species_forms.dart` or, once
  /// the numbers settle, into `content.json`.
  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'id': _form.id, 'branchRules': _rules.toJson()});

  String get stats =>
      '${skeleton.branches.length} branches · '
      '${skeleton.clusters.length} clusters · '
      '${skeleton.leafCount} leaves';
}
