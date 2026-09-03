import 'package:flutter/widgets.dart';
import 'package:grow_domain/grow_domain.dart';

import '../../design_system/tokens.dart';

/// The HUD.
///
/// It has one job: make the loop legible in the first five seconds.
///
///   put the phone down → earn something → care for the tree → the world grows
///
/// So the top carries what you *have* (level, water, feed) and the bottom
/// carries the one thing that earns more of it. Nothing else competes.
class ForestHud extends StatelessWidget {
  const ForestHud({
    required this.progression,
    required this.inventory,
    required this.conditions,
    required this.onStartFocus,
    this.focusHint,
    this.showCall = true,
    super.key,
  });

  final Progression progression;
  final Inventory inventory;
  final WorldConditions conditions;
  final VoidCallback onStartFocus;

  /// One line under the focus button. Kept short and never a countdown.
  final String? focusHint;

  /// Hidden while a sheet is open, so there is only ever one primary action
  /// on screen.
  ///
  /// This flag was accepted and never read for two weeks, which is what the
  /// "ghost focus call behind the open sheet" was: not a rendering artifact,
  /// a `const` that nothing consumed. A parameter that does nothing is worse
  /// than a missing one — it reads as a decision that was made.
  final bool showCall;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GrowTokens.md,
            GrowTokens.sm,
            GrowTokens.md,
            0,
          ),
          // Wrap, not Row: at 320 dp with large text these chips do not
          // fit on one line, and a HUD that clips is worse than one that
          // takes two rows.
          child: Wrap(
            spacing: GrowTokens.sm,
            runSpacing: GrowTokens.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _LevelChip(progression: progression),
              _Resource(
                glyph: '💧',
                label: 'Water',
                value: inventory.totalWaterAvailable,
                cap: inventory.waterCap,
              ),
              _Resource(
                glyph: '🌱',
                label: 'Feed',
                value: inventory.nutrients,
                cap: inventory.nutrientCap,
              ),
              if (progression.focusStreakDays > 0)
                _Streak(days: progression.focusStreakDays),
            ],
          ),
        ),
        const Spacer(),
        if (showCall)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GrowTokens.lg,
              0,
              GrowTokens.lg,
              GrowTokens.lg,
            ),
            child: _FocusCall(onPressed: onStartFocus, hint: focusHint),
          ),
      ],
    ),
  );
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.progression});
  final Progression progression;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Forest level ${progression.level}, '
        '${progression.xp} of ${progression.xpForNextLevel} experience',
    child: ExcludeSemantics(
      child: _Glass(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Level ${progression.level}',
              style: GrowType.label.copyWith(color: GrowTokens.onDark),
            ),
            const SizedBox(width: GrowTokens.sm),
            SizedBox(
              width: 34,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  children: [
                    Container(height: 5, color: const Color(0x33FFFFFF)),
                    AnimatedFractionallySizedBox(
                      duration: GrowTokens.unhurried,
                      curve: GrowTokens.ease,
                      widthFactor: progression.levelProgress,
                      child: Container(height: 5, color: GrowTokens.accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Resource extends StatelessWidget {
  const _Resource({
    required this.glyph,
    required this.label,
    required this.value,
    required this.cap,
  });

  final String glyph;
  final String label;
  final int value;
  final int cap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $value of $cap',
    child: ExcludeSemantics(
      child: _Glass(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(glyph, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: GrowTokens.xs + 2),
            // A tally, not a fraction: the cap matters only when it bites.
            Text(
              value >= cap ? '$value (full)' : '$value',
              style: GrowType.numeral.copyWith(
                color: GrowTokens.onDark,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Streak extends StatelessWidget {
  const _Streak({required this.days});
  final int days;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$days day focus streak',
    child: ExcludeSemantics(
      child: _Glass(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🔥', style: TextStyle(fontSize: 13)),
            const SizedBox(width: GrowTokens.xs + 2),
            Text(
              '$days',
              style: GrowType.numeral.copyWith(
                color: GrowTokens.onDark,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The call to action. Deliberately the largest thing on screen after the
/// forest itself, and phrased as an invitation rather than a task.
class _FocusCall extends StatelessWidget {
  const _FocusCall({required this.onPressed, this.hint});

  final VoidCallback onPressed;
  final String? hint;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Put your phone down',
    hint: hint ?? 'Start a focus session to earn water and feed',
    child: ExcludeSemantics(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            minHeight: GrowTokens.minTapTarget + 14,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: GrowTokens.lg,
            vertical: GrowTokens.md,
          ),
          decoration: BoxDecoration(
            color: GrowTokens.panelRaised.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(GrowTokens.radius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Put your phone down', style: GrowType.title),
              const SizedBox(height: 2),
              Text(
                hint ?? 'Your forest grows while you are away',
                style: GrowType.body,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A translucent chip that sits over the world without hiding it.
class _Glass extends StatelessWidget {
  const _Glass({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: GrowTokens.sm + 2,
      vertical: GrowTokens.xs + 3,
    ),
    decoration: BoxDecoration(
      color: const Color(0x59141712),
      borderRadius: BorderRadius.circular(GrowTokens.radiusSmall),
    ),
    child: child,
  );
}
