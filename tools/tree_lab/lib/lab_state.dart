import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:grow_render/grow_render.dart';

/// Everything Tree Lab can change, and the derived skeleton.
///
/// The skeleton is regenerated only when an input that affects geometry
/// changes — the same caching rule the game uses, so what is tuned here is
/// what ships.
class LabState extends ChangeNotifier {
  LabState() {
    _regenerate();
  }

  SpeciesForm _form = oakForm;
  BranchRules _rules = oakForm.rules;
  int _seed = 4242;
  double _growth = 0.85;
  double _time = 0;
  bool _animating = true;
  bool _showSkeleton = false;
  double _windAmplitude = 1.0;

  FoliageState _foliage = const FoliageState();

  TreeSkeleton? _skeleton;
  CanopyAtlas? _atlas;

  SpeciesForm get form => _form;
  BranchRules get rules => _rules;
  int get seed => _seed;
  double get growth => _growth;
  double get time => _time;
  bool get animating => _animating;
  bool get showSkeleton => _showSkeleton;
  double get windAmplitude => _windAmplitude;
  FoliageState get foliage => _foliage;
  TreeSkeleton get skeleton => _skeleton!;

  /// The canopy atlas, once loaded. Tuning against the unbatched fallback
  /// would mean tuning a look the game does not ship.
  CanopyAtlas? get atlas => _atlas;

  Future<void> loadAtlas() async {
    final data = await rootBundle.load(
      'packages/grow_render/assets/canopy_oak.png',
    );
    _atlas = await CanopyAtlas.decode(data.buffer.asUint8List());
    notifyListeners();
  }

  void selectSpecies(SpeciesForm f) {
    _form = f;
    _rules = f.rules;
    _regenerate();
  }

  void updateRules(BranchRules r) {
    _rules = r;
    _regenerate();
  }

  void setSeed(int s) {
    _seed = s;
    _regenerate();
  }

  void setGrowth(double g) {
    _growth = g;
    _regenerate();
  }

  void setFoliage(FoliageState f) {
    _foliage = f;
    notifyListeners();
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

  void tick(double dt) {
    if (!_animating) return;
    _time += dt;
    notifyListeners();
  }

  void reset() {
    _rules = _form.rules;
    _foliage = const FoliageState();
    _regenerate();
  }

  void _regenerate() {
    _skeleton = const TreeGenerator().generate(
      rules: _rules,
      seed: _seed,
      growth01: _growth,
    );
    notifyListeners();
  }

  /// The tuned parameters, ready to paste into `species_forms.dart` or, once
  /// the numbers settle, into `content.json`.
  String exportJson() => const JsonEncoder.withIndent(
    '  ',
  ).convert({'id': _form.id, 'branchRules': _rules.toJson()});

  String get stats =>
      '${skeleton.branches.length} branches · '
      '${skeleton.leafCount} leaves · '
      '${skeleton.segmentCount} segments';
}
