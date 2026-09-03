import 'package:flutter/widgets.dart';
import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:grow_sim/grow_sim.dart';

import '../../design_system/care_button.dart';
import '../../design_system/tokens.dart';
import '../../design_system/vital_bar.dart';

/// The tree panel: a sheet over the living world, never a full screen.
///
/// The world stays visible and animating above it, because the terrarium is
/// the thing the player came for — and because watering a tree while watching
/// it is the whole feedback loop.
///
/// Deliberately not a spreadsheet. Bars carry water, nutrition and growth with
/// the ideal range drawn on the track; numbers appear only where they help a
/// decision. What the tree needs is one sentence, not a table.
class TreeDetailSheet extends StatelessWidget {
  const TreeDetailSheet({
    required this.tree,
    required this.species,
    required this.visual,
    required this.waterPreview,
    required this.feedPreview,
    required this.waterAvailable,
    required this.nutrientsAvailable,
    required this.onWater,
    required this.onFeed,
    required this.onClose,
    this.refusal,
    super.key,
  });

  final Tree tree;
  final TreeSpecies species;
  final TreeVisual visual;
  final ActionPreview waterPreview;
  final ActionPreview feedPreview;
  final int waterAvailable;
  final int nutrientsAvailable;
  final VoidCallback? onWater;
  final VoidCallback? onFeed;
  final VoidCallback onClose;
  final String? refusal;

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(tree.state);

    return Container(
      decoration: const BoxDecoration(
        color: GrowTokens.panel,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GrowTokens.lg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  GrowTokens.lg,
                  GrowTokens.sm,
                  GrowTokens.lg,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: GrowTokens.md),
                        decoration: BoxDecoration(
                          color: GrowTokens.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    _header(style),
                    const SizedBox(height: GrowTokens.md),
                    _needs(),
                    const SizedBox(height: GrowTokens.md),
                    VitalBar(
                      label: 'Water',
                      value: tree.water.value,
                      colour: GrowTokens.water,
                      band: species.water,
                      pending: waterPreview.to,
                    ),
                    const SizedBox(height: GrowTokens.md),
                    VitalBar(
                      label: 'Nutrition',
                      value: tree.nutrition.value,
                      colour: GrowTokens.nutrition,
                      band: species.nutrition,
                      pending: feedPreview.to,
                    ),
                    const SizedBox(height: GrowTokens.md),
                    VitalBar(
                      label: tree.stage.isFinal ? 'Fully grown' : 'Growing',
                      value: tree.stage.isFinal ? 100 : tree.growth.value,
                      colour: GrowTokens.growth,
                    ),
                    if (tree.afflictions.isNotEmpty) ...[
                      const SizedBox(height: GrowTokens.md),
                      _symptoms(),
                    ],
                    const SizedBox(height: GrowTokens.md),
                  ],
                ),
              ),
            ),
            // Pinned. The two things a player came here to do must never be
            // below the fold.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GrowTokens.lg,
                0,
                GrowTokens.lg,
                GrowTokens.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CareButton(
                          label: 'Water',
                          glyph: '💧',
                          colour: GrowTokens.water,
                          preview: waterPreview,
                          cost: 1,
                          available: waterAvailable,
                          onPressed: onWater,
                        ),
                      ),
                      const SizedBox(width: GrowTokens.md),
                      Expanded(
                        child: CareButton(
                          label: 'Feed',
                          glyph: '🌱',
                          colour: GrowTokens.nutrition,
                          preview: feedPreview,
                          cost: 1,
                          available: nutrientsAvailable,
                          onPressed: onFeed,
                        ),
                      ),
                    ],
                  ),
                  if (refusal != null) ...[
                    const SizedBox(height: GrowTokens.sm),
                    Text(
                      refusal!,
                      style: GrowType.label.copyWith(color: GrowTokens.caution),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(StateStyle style) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(species.displayName, style: GrowType.display),
            const SizedBox(height: 2),
            Text('${tree.stage.label} · ${_age()}', style: GrowType.body),
          ],
        ),
      ),
      // Glyph, word and colour together — never colour alone.
      Semantics(
        label: 'Condition: ${style.label}',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: GrowTokens.sm + 2,
              vertical: GrowTokens.xs + 2,
            ),
            decoration: BoxDecoration(
              color: style.colour.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(GrowTokens.radiusSmall),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  style.glyph,
                  style: TextStyle(fontSize: 13, color: style.colour),
                ),
                const SizedBox(width: GrowTokens.xs + 2),
                Text(
                  style.label,
                  style: GrowType.label.copyWith(color: style.colour),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  /// One sentence about what this tree needs, and nothing else.
  Widget _needs() {
    final line = _needsLine();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(GrowTokens.md),
      decoration: BoxDecoration(
        color: GrowTokens.panelRaised,
        borderRadius: BorderRadius.circular(GrowTokens.radiusSmall),
      ),
      child: Text(line, style: GrowType.body.copyWith(color: GrowTokens.ink)),
    );
  }

  String _needsLine() {
    if (tree.isSnag) {
      return 'Standing deadwood now. It still shelters life, and its seeds '
          'can be collected.';
    }
    final water = species.water.excursion(tree.water.value);
    final food = species.nutrition.excursion(tree.nutrition.value);

    if (water > 8) {
      return 'The soil is waterlogged. Leave it to drain — it will come back '
          'on its own.';
    }
    if (food > 6) {
      return 'Overfed. The leaf edges are scorched; hold off feeding until it '
          'recovers.';
    }
    if (water < -8) {
      return 'Thirsty. A drink would bring it back into range.';
    }
    if (food < -6) {
      return 'Hungry. The leaves are pale for want of feeding.';
    }
    if (tree.state == HealthState.thriving) {
      return 'Thriving. Nothing needed — this is exactly where it wants to be.';
    }
    if (tree.state == HealthState.dormant) {
      return 'Resting after a long quiet spell. A little care will wake it.';
    }
    return 'Comfortable. Growing steadily.';
  }

  Widget _symptoms() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'WHAT YOU CAN SEE',
        style: GrowType.caption.copyWith(letterSpacing: 1.2),
      ),
      const SizedBox(height: GrowTokens.sm),
      for (final a in tree.afflictions)
        Padding(
          padding: const EdgeInsets.only(bottom: GrowTokens.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7, right: GrowTokens.sm),
                decoration: const BoxDecoration(
                  color: GrowTokens.caution,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${a.kind.label}. ',
                        style: GrowType.label.copyWith(color: GrowTokens.ink),
                      ),
                      TextSpan(text: a.kind.explanation, style: GrowType.body),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  String _age() {
    final days = tree.ageAt(visual.ageReference).inDays;
    if (days < 1) return 'planted today';
    return days == 1 ? '1 day old' : '$days days old';
  }

  static StateStyle _styleFor(HealthState s) => switch (s) {
    HealthState.thriving => StateStyle(GrowTokens.good, s.glyph, s.label),
    HealthState.healthy => StateStyle(GrowTokens.good, s.glyph, s.label),
    HealthState.stressed => StateStyle(GrowTokens.caution, s.glyph, s.label),
    HealthState.ailing => StateStyle(GrowTokens.caution, s.glyph, s.label),
    HealthState.critical => StateStyle(GrowTokens.alarm, s.glyph, s.label),
    HealthState.dormant => StateStyle(GrowTokens.inkMuted, s.glyph, s.label),
    HealthState.snag => StateStyle(GrowTokens.bark, s.glyph, s.label),
  };
}
