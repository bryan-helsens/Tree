import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grow_flora/grow_flora.dart';

import 'lab_state.dart';

/// Every tunable on a slider, grouped the way you actually reason about a
/// tree: its frame, how it branches, how it responds to light and gravity, and
/// what its foliage does.
class LabControls extends StatelessWidget {
  const LabControls({required this.state, super.key});

  final LabState state;

  @override
  Widget build(BuildContext context) {
    final r = state.rules;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            for (final f in [oakForm, birchForm])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f.id.split('_').first),
                  selected: state.form.id == f.id,
                  onSelected: (_) => state.selectSpecies(f),
                ),
              ),
            const Spacer(),
            IconButton(
              tooltip: 'Reset to the shipped values',
              onPressed: state.reset,
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _slider('Growth', state.growth, 0.02, 1, state.setGrowth),
        Row(
          children: [
            Expanded(
              child: _slider(
                'Seed',
                state.seed.toDouble(),
                1,
                9999,
                (v) => state.setSeed(v.round()),
                digits: 0,
              ),
            ),
            IconButton(
              tooltip: 'Another individual',
              onPressed: () => state.setSeed((state.seed * 7919 + 13) % 9999),
              icon: const Icon(Icons.casino_outlined),
            ),
          ],
        ),

        _header('Frame'),
        _rule(
          'Trunk length',
          r.trunkLength,
          20,
          260,
          (v) => state.updateRules(r.copyWith(trunkLength: v)),
        ),
        _rule(
          'Trunk width',
          r.trunkWidth,
          2,
          40,
          (v) => state.updateRules(r.copyWith(trunkWidth: v)),
        ),
        _rule(
          'Sinuosity',
          r.trunkSinuosity,
          0,
          2,
          (v) => state.updateRules(r.copyWith(trunkSinuosity: v)),
        ),
        _rule(
          'Taper',
          r.taper,
          0.4,
          0.95,
          (v) => state.updateRules(r.copyWith(taper: v)),
        ),

        _header('Branching'),
        _rule(
          'Depth',
          r.maxDepth.toDouble(),
          1,
          7,
          (v) => state.updateRules(r.copyWith(maxDepth: v.round())),
          digits: 0,
        ),
        _rule(
          'Children per branch',
          r.childrenPerBranch.toDouble(),
          1,
          4,
          (v) => state.updateRules(r.copyWith(childrenPerBranch: v.round())),
          digits: 0,
        ),
        _rule(
          'Angle min',
          r.branchAngleMin,
          5,
          80,
          (v) => state.updateRules(r.copyWith(branchAngleMin: v)),
        ),
        _rule(
          'Angle max',
          r.branchAngleMax,
          5,
          90,
          (v) => state.updateRules(r.copyWith(branchAngleMax: v)),
        ),
        _rule(
          'Angle jitter',
          r.angleJitter,
          0,
          40,
          (v) => state.updateRules(r.copyWith(angleJitter: v)),
        ),
        _rule(
          'Angle decay per depth',
          r.angleDecay,
          0.4,
          1.2,
          (v) => state.updateRules(r.copyWith(angleDecay: v)),
        ),
        _rule(
          'Length decay',
          r.lengthDecay,
          0.4,
          0.95,
          (v) => state.updateRules(r.copyWith(lengthDecay: v)),
        ),
        _rule(
          'First node at',
          r.firstNodeAt,
          0.05,
          0.9,
          (v) => state.updateRules(r.copyWith(firstNodeAt: v)),
        ),
        _rule(
          'Apical extension',
          r.apicalExtension,
          0,
          1.2,
          (v) => state.updateRules(r.copyWith(apicalExtension: v)),
        ),
        _rule(
          'Asymmetry',
          r.asymmetry,
          0,
          0.8,
          (v) => state.updateRules(r.copyWith(asymmetry: v)),
        ),

        _header('Forces'),
        _rule(
          'Phototropism',
          r.phototropism,
          0,
          1.2,
          (v) => state.updateRules(r.copyWith(phototropism: v)),
        ),
        _rule(
          'Gravity droop',
          r.gravityDroop,
          0,
          1.2,
          (v) => state.updateRules(r.copyWith(gravityDroop: v)),
        ),
        _rule(
          'Wobble',
          r.wobble,
          0,
          1.5,
          (v) => state.updateRules(r.copyWith(wobble: v)),
        ),

        _header('Foliage'),
        _rule(
          'Density',
          r.leafDensity,
          1,
          60,
          (v) => state.updateRules(r.copyWith(leafDensity: v)),
        ),
        _rule(
          'Leaf size',
          r.leafSize,
          1,
          14,
          (v) => state.updateRules(r.copyWith(leafSize: v)),
        ),
        _rule(
          'Canopy bias',
          r.canopyBias,
          0,
          1,
          (v) => state.updateRules(r.copyWith(canopyBias: v)),
        ),

        _header('Condition'),
        _foliageSlider(
          'Droop',
          state.foliage.droop,
          (v) => _setFoliage(droop: v),
        ),
        _foliageSlider(
          'Pallor',
          state.foliage.pallor,
          (v) => _setFoliage(pallor: v),
        ),
        _foliageSlider(
          'Scorch',
          state.foliage.scorch,
          (v) => _setFoliage(scorch: v),
        ),
        _foliageSlider(
          'Wetness',
          state.foliage.wetness,
          (v) => _setFoliage(wetness: v),
        ),
        _foliageSlider(
          'Bareness',
          state.foliage.bareness,
          (v) => _setFoliage(bareness: v),
        ),
        _foliageSlider(
          'Flowering',
          state.foliage.flowering,
          (v) => _setFoliage(flowering: v),
        ),
        _foliageSlider(
          'Sparkle',
          state.foliage.sparkle,
          (v) => _setFoliage(sparkle: v),
        ),

        _header('View'),
        _slider('Wind', state.windAmplitude, 0, 3, state.setWind),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Animate'),
          value: state.animating,
          onChanged: (_) => state.toggleAnimating(),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Skeleton only'),
          value: state.showSkeleton,
          onChanged: (_) => state.toggleSkeleton(),
        ),

        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: state.exportJson()));
          },
          icon: const Icon(Icons.copy_all),
          label: const Text('Copy parameters as JSON'),
        ),
      ],
    );
  }

  void _setFoliage({
    double? droop,
    double? pallor,
    double? scorch,
    double? wetness,
    double? bareness,
    double? flowering,
    double? sparkle,
  }) {
    final f = state.foliage;
    state.setFoliage(
      FoliageState(
        droop: droop ?? f.droop,
        pallor: pallor ?? f.pallor,
        scorch: scorch ?? f.scorch,
        wetness: wetness ?? f.wetness,
        bareness: bareness ?? f.bareness,
        flowering: flowering ?? f.flowering,
        sparkle: sparkle ?? f.sparkle,
      ),
    );
  }

  Widget _header(String s) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 2),
    child: Text(
      s.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w600,
        color: Color(0xFF2F6B4F),
      ),
    ),
  );

  Widget _rule(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int digits = 2,
  }) => _slider(label, value, min, max, onChanged, digits: digits);

  Widget _foliageSlider(
    String label,
    double v,
    ValueChanged<double> onChanged,
  ) => _slider(label, v, 0, 1, onChanged);

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int digits = 2,
  }) {
    final safe = value.clamp(min, max).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: const TextStyle(fontSize: 12.5)),
          ),
          Expanded(
            child: Slider(
              value: safe,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              safe.toStringAsFixed(digits),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
                color: Color(0xFF6B7370),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
