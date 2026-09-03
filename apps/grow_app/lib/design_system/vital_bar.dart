import 'package:flutter/widgets.dart';
import 'package:grow_domain/grow_domain.dart';

import 'tokens.dart';

/// A vital, with its ideal range drawn on the track.
///
/// The band is the whole point. A player who sees the target as a *region* and
/// their value as a position inside it learns the watering strategy without a
/// tutorial — and, more importantly, learns that the top of the bar is not the
/// goal. A bare percentage teaches the opposite.
class VitalBar extends StatelessWidget {
  const VitalBar({
    required this.label,
    required this.value,
    required this.colour,
    this.band,
    this.pending,
    super.key,
  });

  final String label;
  final double value;
  final Color colour;

  /// The species' ideal range. Null for vitals with no band, like growth.
  final Band? band;

  /// Where a pending action would land, shown as a ghost ahead of the fill.
  final double? pending;

  @override
  Widget build(BuildContext context) {
    final band = this.band;
    final inBand = band == null || band.contains(value);

    return Semantics(
      label: label,
      value: band == null
          ? '${value.round()} percent'
          : '${value.round()}, ideal ${band.min.round()} to ${band.max.round()}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(label, style: GrowType.label),
                const Spacer(),
                if (band != null && !inBand)
                  Padding(
                    padding: const EdgeInsets.only(right: GrowTokens.sm),
                    child: Text(
                      value < band.min ? 'below ideal' : 'above ideal',
                      style: GrowType.caption.copyWith(
                        color: GrowTokens.caution,
                      ),
                    ),
                  ),
                Text('${value.round()}', style: GrowType.numeral),
              ],
            ),
            const SizedBox(height: GrowTokens.xs + 2),
            _Track(value: value, colour: colour, band: band, pending: pending),
          ],
        ),
      ),
    );
  }
}

class _Track extends StatelessWidget {
  const _Track({
    required this.value,
    required this.colour,
    required this.band,
    required this.pending,
  });

  final double value;
  final Color colour;
  final Band? band;
  final double? pending;

  static const double _height = 10;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth;
      double at(double v) => w * (v.clamp(0, 100) / 100);

      return SizedBox(
        height: _height,
        child: Stack(
          children: [
            // Track.
            Container(
              decoration: BoxDecoration(
                color: GrowTokens.panelSunken,
                borderRadius: BorderRadius.circular(_height / 2),
              ),
            ),
            // The ideal range, sitting under the fill.
            if (band != null)
              Positioned(
                left: at(band!.min),
                width: at(band!.max) - at(band!.min),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: GrowTokens.good.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            // Where an action would take it.
            if (pending != null && pending! > value)
              Positioned(
                left: at(value),
                width: at(pending!) - at(value),
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                ),
              ),
            // The value itself. Animated, because it moves when the
            // simulation moves it.
            AnimatedContainer(
              duration: GrowTokens.settle,
              curve: GrowTokens.ease,
              width: at(value),
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(_height / 2),
              ),
            ),
            // Band edges, so the boundary is legible even where the fill
            // covers the tint.
            if (band != null) ...[_edge(at(band!.min)), _edge(at(band!.max))],
          ],
        ),
      );
    },
  );

  Widget _edge(double x) => Positioned(
    left: x - 0.75,
    top: -2,
    bottom: -2,
    child: Container(width: 1.5, color: GrowTokens.good.withValues(alpha: 0.5)),
  );
}
