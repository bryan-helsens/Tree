import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:grow_sim/grow_sim.dart';

import '../../design_system/tokens.dart';
import '../../game/focus_view.dart';

/// The focus surface: choose, sit through, finish.
///
/// Every one of these widgets is a **pure function of [FocusView]**, which is
/// itself a projection of the save. None of them holds session state, none of
/// them decides when a session ends, and none of them grants anything. The
/// completion panel reports a reward that was committed before it was built —
/// possibly on a previous launch, while the app was closed.
///
/// The picker is the one place with local state, and only for the duration a
/// player is considering. That is not a session until they say so.
class FocusSheet extends StatelessWidget {
  const FocusSheet({
    required this.view,
    required this.onStart,
    required this.onEndEarly,
    required this.onDismiss,
    required this.onClose,
    this.economy = const FocusEconomy(),
    this.refusal,
    super.key,
  });

  final FocusView view;
  final void Function(Duration planned) onStart;
  final VoidCallback onEndEarly;
  final VoidCallback onDismiss;
  final VoidCallback onClose;
  final FocusEconomy economy;
  final String? refusal;

  @override
  Widget build(BuildContext context) => _Panel(
    child: switch (view) {
      FocusIdle() => _Picker(
        economy: economy,
        onStart: onStart,
        onClose: onClose,
        refusal: refusal,
      ),
      FocusRunning() => _Running(
        view: view as FocusRunning,
        onEndEarly: onEndEarly,
        onClose: onClose,
      ),
      // The gap between finishing and being paid. It lasts a frame; showing a
      // spinner for it would be a lie about how long it takes.
      FocusSettling() => const _Settling(),
      FocusFinished() => _Finished(
        view: view as FocusFinished,
        onDismiss: onDismiss,
      ),
    },
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: const BoxDecoration(
      color: GrowTokens.panel,
      borderRadius: BorderRadius.vertical(top: Radius.circular(GrowTokens.lg)),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
      ),
    ),
  );
}

// ── choosing ────────────────────────────────────────────────────────────

/// Duration options, in minutes. Data, not a switch statement: the economy's
/// own bounds decide which are offered.
const _options = <int>[15, 25, 45, 60];

class _Picker extends StatefulWidget {
  const _Picker({
    required this.economy,
    required this.onStart,
    required this.onClose,
    this.refusal,
  });

  final FocusEconomy economy;
  final void Function(Duration) onStart;
  final VoidCallback onClose;
  final String? refusal;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  int _minutes = 25;

  @override
  Widget build(BuildContext context) {
    final offered = _options
        .where(
          (m) =>
              m >= widget.economy.minSessionMinutes &&
              m <= widget.economy.maxSessionMinutes,
        )
        .toList();

    final yield_ = widget.economy.yieldFor(
      minutes: _minutes,
      sessionIndexToday: 0,
      streakDays: 0,
      gpAlreadyEarnedToday: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Grip(),
        Text('Put your phone down', style: GrowType.display),
        const SizedBox(height: GrowTokens.xs),
        Text(
          'Your oak keeps growing while you are away. Come back when you '
          'are ready — nothing here is lost if you do not.',
          style: GrowType.body,
        ),
        const SizedBox(height: GrowTokens.lg),
        Row(
          children: [
            for (final m in offered) ...[
              Expanded(
                child: _DurationChip(
                  minutes: m,
                  selected: m == _minutes,
                  deep: m >= widget.economy.deepFocusMinutes,
                  onTap: () => setState(() => _minutes = m),
                ),
              ),
              if (m != offered.last) const SizedBox(width: GrowTokens.sm),
            ],
          ],
        ),
        const SizedBox(height: GrowTokens.md),
        // Two numbers, not a table. Enough to choose by.
        Semantics(
          label:
              '$_minutes minutes earns about ${yield_.water} water '
              'and ${yield_.totalNutrients} feed',
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Earns about ', style: GrowType.label),
                Text('💧 ${yield_.water}', style: GrowType.numeral),
                Text('   ', style: GrowType.label),
                Text('🌱 ${yield_.totalNutrients}', style: GrowType.numeral),
              ],
            ),
          ),
        ),
        if (widget.refusal != null) ...[
          const SizedBox(height: GrowTokens.sm),
          Text(
            widget.refusal!,
            style: GrowType.label.copyWith(color: GrowTokens.caution),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: GrowTokens.lg),
        _PrimaryButton(
          label: 'Begin',
          onPressed: () => widget.onStart(Duration(minutes: _minutes)),
        ),
        const SizedBox(height: GrowTokens.xs),
        _QuietButton(label: 'Not now', onPressed: widget.onClose),
      ],
    );
  }
}

class _DurationChip extends StatelessWidget {
  const _DurationChip({
    required this.minutes,
    required this.selected,
    required this.deep,
    required this.onTap,
  });

  final int minutes;
  final bool selected;
  final bool deep;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '$minutes minutes${deep ? ', deep focus' : ''}',
    child: ExcludeSemantics(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: GrowTokens.quick,
          curve: GrowTokens.ease,
          constraints: const BoxConstraints(minHeight: GrowTokens.minTapTarget),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? GrowTokens.moss : GrowTokens.panelSunken,
            borderRadius: BorderRadius.circular(GrowTokens.radiusSmall),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$minutes',
                style: GrowType.numeral.copyWith(
                  color: selected ? GrowTokens.onDark : GrowTokens.ink,
                  fontSize: 17,
                ),
              ),
              Text(
                deep ? 'deep' : 'min',
                style: GrowType.caption.copyWith(
                  color: selected ? GrowTokens.onDark : GrowTokens.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── underway ────────────────────────────────────────────────────────────

class _Running extends StatelessWidget {
  const _Running({
    required this.view,
    required this.onEndEarly,
    required this.onClose,
  });

  final FocusRunning view;
  final VoidCallback onEndEarly;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final left = view.minutesLeft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Grip(),
        Center(
          child: _ProgressRing(
            progress: view.progress,
            // Minutes, never seconds. A per-second countdown asks to be
            // watched, which is the opposite of what this screen is for.
            label: left <= 1 ? 'nearly' : '$left',
            caption: left <= 1 ? 'there' : 'min left',
          ),
        ),
        const SizedBox(height: GrowTokens.lg),
        Text('Growing', style: GrowType.title, textAlign: TextAlign.center),
        const SizedBox(height: GrowTokens.xs),
        Text(
          'You can close the app. The session keeps its own time and will '
          'be waiting when you come back.',
          style: GrowType.body,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GrowTokens.lg),
        _PrimaryButton(label: 'Leave it running', onPressed: onClose),
        const SizedBox(height: GrowTokens.xs),
        // Quiet, and honest about the consequence. Ending early is a choice,
        // not a failure, and the copy must not imply otherwise.
        _QuietButton(
          label: 'Finish early — you keep what you have earned',
          onPressed: onEndEarly,
        ),
      ],
    );
  }
}

class _Settling extends StatelessWidget {
  const _Settling();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const _Grip(),
      Text('Finishing up', style: GrowType.title),
      const SizedBox(height: GrowTokens.md),
    ],
  );
}

// ── finished ────────────────────────────────────────────────────────────

/// What a session paid.
///
/// Reports, never grants. By the time this is on screen the reward is in the
/// save and the tree has already started moving toward its new size behind
/// this panel — which is the point: the number is a caption for something the
/// player can see, not the event itself.
class _Finished extends StatelessWidget {
  const _Finished({required this.view, required this.onDismiss});

  final FocusFinished view;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final o = view.outcome;
    final minutes = o.actual.inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Grip(),
        Text(
          view.endedEarly ? 'You came back' : 'Your oak grew',
          style: GrowType.display,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GrowTokens.xs),
        Text(
          view.endedEarly
              ? 'You were away $minutes ${_min(minutes)}, and every one of '
                    'them counted.'
              : 'You were away $minutes ${_min(minutes)}.',
          style: GrowType.body,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GrowTokens.lg),
        // Three things, at most. Water and feed are what the player spends;
        // growth is what they came for. No XP counter, no gp, no streak
        // fanfare — those live in the HUD and can be noticed, not announced.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Gain(glyph: '💧', label: 'water', value: '${o.water}'),
            _Gain(glyph: '🌱', label: 'feed', value: '${o.nutrients}'),
            if (o.growthInjection > 0)
              _Gain(
                glyph: '🌳',
                label: 'growth',
                value: '+${o.growthInjection.toStringAsFixed(1)}%',
              ),
          ],
        ),
        if (o.deepFocusBonus) ...[
          const SizedBox(height: GrowTokens.md),
          Text(
            'Deep focus — the long ones are worth more.',
            style: GrowType.label.copyWith(color: GrowTokens.moss),
            textAlign: TextAlign.center,
          ),
        ],
        if (o.levelsGained > 0) ...[
          const SizedBox(height: GrowTokens.md),
          Text(
            o.levelsGained == 1
                ? 'Your forest reached a new level.'
                : 'Your forest gained ${o.levelsGained} levels.',
            style: GrowType.label.copyWith(color: GrowTokens.accent),
            textAlign: TextAlign.center,
          ),
        ],
        if (o.growthInjection == 0) ...[
          const SizedBox(height: GrowTokens.md),
          Text(
            'Your oak is fully grown. The time still earned its keep.',
            style: GrowType.label,
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: GrowTokens.lg),
        _PrimaryButton(label: 'Back to the forest', onPressed: onDismiss),
      ],
    );
  }

  static String _min(int n) => n == 1 ? 'minute' : 'minutes';
}

class _Gain extends StatelessWidget {
  const _Gain({required this.glyph, required this.label, required this.value});
  final String glyph;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$value $label',
    child: ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(glyph, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: GrowTokens.xs),
          Text(value, style: GrowType.numeral.copyWith(fontSize: 17)),
          Text(label, style: GrowType.caption),
        ],
      ),
    ),
  );
}

// ── pieces ──────────────────────────────────────────────────────────────

class _Grip extends StatelessWidget {
  const _Grip();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 38,
      height: 4,
      margin: const EdgeInsets.only(bottom: GrowTokens.md),
      decoration: BoxDecoration(
        color: GrowTokens.hairline,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

/// A slowly filling ring. The precise carrier of progress; the number beside
/// it is deliberately coarse.
class _ProgressRing extends StatelessWidget {
  const _ProgressRing({
    required this.progress,
    required this.label,
    required this.caption,
  });

  final double progress;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Reduced motion still *moves* — it just does not interpolate.
          // A ring that never changes is not an accessible ring, it is a
          // broken one.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: progress, end: progress),
            duration: reduceMotion ? Duration.zero : GrowTokens.unhurried,
            curve: GrowTokens.ease,
            builder: (context, value, _) => CustomPaint(
              size: const Size.square(132),
              painter: _Ring(value),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: GrowType.display.copyWith(fontSize: 30)),
              Text(caption, style: GrowType.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _Ring extends CustomPainter {
  const _Ring(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.width / 2 - 6;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = GrowTokens.panelSunken;
    canvas.drawCircle(centre, radius, track);

    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..color = GrowTokens.moss;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.progress != progress;
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ExcludeSemantics(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: GrowTokens.minTapTarget),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GrowTokens.moss,
            borderRadius: BorderRadius.circular(GrowTokens.radiusSmall),
          ),
          child: Text(
            label,
            style: GrowType.title.copyWith(
              color: GrowTokens.onDark,
              fontSize: 16,
            ),
          ),
        ),
      ),
    ),
  );
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ExcludeSemantics(
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(minHeight: GrowTokens.minTapTarget),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GrowType.label,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
