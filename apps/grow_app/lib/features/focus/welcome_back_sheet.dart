import 'package:flutter/widgets.dart';
import 'package:grow_domain/grow_domain.dart';

import '../../design_system/tokens.dart';
import '../../game/return_summary.dart';

/// The return moment.
///
/// The feeling to produce is **"I was away, and something happened"** — not
/// "you completed another productivity task". Three rules follow from that,
/// and they are the reason this screen looks the way it does:
///
///  1. **The world speaks first.** What the tree did leads. Resources, levels
///     and streaks are consequences and are either absent or last.
///  2. **Time is described, not measured.** "a few hours", never "187 min".
///  3. **Nothing is claimed here.** Any session reward was committed before
///     this widget existed, possibly on a previous launch. This reports.
///
/// The tree is visible above the sheet the whole time, already easing toward
/// its new size. This panel is the caption for that, not the event.
class WelcomeBackSheet extends StatelessWidget {
  const WelcomeBackSheet({
    required this.summary,
    required this.onDismiss,
    this.treeGrowth = 0,
    super.key,
  });

  final ReturnSummary summary;
  final VoidCallback onDismiss;

  /// Growth the tree made while away, in percentage points of its stage.
  final double treeGrowth;

  @override
  Widget build(BuildContext context) {
    final outcome = summary.sessionOutcome;
    final highlights = summary.highlights;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: GrowTokens.panel,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GrowTokens.lg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GrowTokens.lg,
            GrowTokens.md,
            GrowTokens.lg,
            GrowTokens.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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

              Text('While you were away', style: GrowType.display),
              const SizedBox(height: GrowTokens.xs),
              Text(
                'You were gone ${summary.awayInWords}.',
                style: GrowType.body,
              ),
              const SizedBox(height: GrowTokens.lg),

              // The world's own account, in its own words. These strings come
              // from the simulation journal — they are what happened, not a
              // rendering of what the player earned.
              if (highlights.isEmpty)
                Text(
                  treeGrowth > 0
                      ? 'Your oak kept growing, quietly.'
                      : 'The forest was still. Nothing much changed.',
                  style: GrowType.body,
                )
              else
                for (final event in highlights) ...[
                  _Line(text: event.message),
                  if (event != highlights.last)
                    const SizedBox(height: GrowTokens.sm),
                ],

              if (treeGrowth >= 1) ...[
                const SizedBox(height: GrowTokens.sm),
                _Line(
                  text:
                      'Your oak grew ${treeGrowth.toStringAsFixed(0)}% '
                      'while you were gone.',
                ),
              ],

              // The session, if there was one — quietly, and last. It is the
              // reason the tree grew, not a separate achievement.
              if (outcome != null) ...[
                const SizedBox(height: GrowTokens.lg),
                const _Rule(),
                const SizedBox(height: GrowTokens.md),
                _SessionNote(outcome: outcome),
              ],

              const SizedBox(height: GrowTokens.lg),
              Semantics(
                button: true,
                label: 'Back to the forest',
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: GrowTokens.minTapTarget,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: GrowTokens.moss,
                        borderRadius: BorderRadius.circular(
                          GrowTokens.radiusSmall,
                        ),
                      ),
                      child: Text(
                        'Back to the forest',
                        style: GrowType.title.copyWith(
                          color: GrowTokens.onDark,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.only(top: 7, right: GrowTokens.sm),
        decoration: const BoxDecoration(
          color: GrowTokens.moss,
          shape: BoxShape.circle,
        ),
      ),
      Expanded(
        child: Text(text, style: GrowType.body.copyWith(color: GrowTokens.ink)),
      ),
    ],
  );
}

/// The session's yield, understated on purpose.
class _SessionNote extends StatelessWidget {
  const _SessionNote({required this.outcome});
  final SessionOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final minutes = outcome.actual.inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your $minutes ${minutes == 1 ? 'minute' : 'minutes'} away '
          'brought back',
          style: GrowType.label,
        ),
        const SizedBox(height: GrowTokens.sm),
        Semantics(
          label:
              '${outcome.water} water and ${outcome.nutrients} feed '
              'from your focus session',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Text('💧 ${outcome.water}', style: GrowType.numeral),
                const SizedBox(width: GrowTokens.md),
                Text('🌱 ${outcome.nutrients}', style: GrowType.numeral),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: GrowTokens.hairline);
}
