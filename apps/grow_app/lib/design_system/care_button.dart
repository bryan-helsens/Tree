import 'package:flutter/widgets.dart';
import 'package:grow_sim/grow_sim.dart';

import 'tokens.dart';

/// A care action, showing what it would do before it is taken.
///
/// It warns and it does not block. The player is allowed to overwater — making
/// the mistake is how the system teaches, and a button that refuses would take
/// the lesson away.
class CareButton extends StatefulWidget {
  const CareButton({
    required this.label,
    required this.glyph,
    required this.colour,
    required this.preview,
    required this.cost,
    required this.available,
    required this.onPressed,
    super.key,
  });

  final String label;
  final String glyph;
  final Color colour;
  final ActionPreview preview;

  /// How many units this costs, and how many the player holds.
  final int cost;
  final int available;

  final VoidCallback? onPressed;

  bool get affordable => available >= cost;

  @override
  State<CareButton> createState() => _CareButtonState();
}

class _CareButtonState extends State<CareButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final risky = widget.preview.leavesBand;
    final enabled = widget.affordable && widget.onPressed != null;

    final hint = !widget.affordable
        ? 'none left'
        : risky
        ? 'would overshoot'
        : widget.preview.enters
        ? 'brings it into range'
        : null;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: ['takes it to ${widget.preview.to.round()}', ?hint].join(', '),
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedScale(
            scale: _down ? 0.97 : 1,
            duration: GrowTokens.quick,
            curve: GrowTokens.ease,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.45,
              duration: GrowTokens.quick,
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: GrowTokens.minTapTarget + 12,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: GrowTokens.md,
                  vertical: GrowTokens.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: GrowTokens.panelRaised,
                  borderRadius: BorderRadius.circular(GrowTokens.radiusSmall),
                  border: Border.all(
                    color: risky
                        ? GrowTokens.caution.withValues(alpha: 0.55)
                        : GrowTokens.hairline,
                    width: risky ? 1.4 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.glyph,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: GrowTokens.sm),
                        // Flexible, not fixed: two of these sit side by side
                        // on a 320 dp screen, and large text has to fit too.
                        Flexible(
                          child: Text(
                            widget.label,
                            style: GrowType.title,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(width: GrowTokens.xs),
                        Text(
                          '${widget.available}',
                          style: GrowType.numeral.copyWith(
                            color: widget.affordable
                                ? GrowTokens.inkSoft
                                : GrowTokens.alarm,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: GrowTokens.xs),
                    // The preview: what the action does, before doing it.
                    // Wrapped so the hint drops to its own line rather than
                    // clipping when space is tight.
                    Wrap(
                      spacing: GrowTokens.sm,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${widget.preview.from.round()} → '
                          '${widget.preview.to.round()}',
                          style: GrowType.label.copyWith(color: widget.colour),
                        ),
                        if (hint != null)
                          Text(
                            hint,
                            style: GrowType.caption.copyWith(
                              color: risky || !widget.affordable
                                  ? GrowTokens.caution
                                  : GrowTokens.good,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
