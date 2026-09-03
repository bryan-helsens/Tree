import 'package:flutter/widgets.dart';

/// Every colour, size, duration and curve in one place.
///
/// No widget may use a literal for any of these. The palette is desaturated
/// naturals — moss, bark, clay, overcast — with exactly one accent, a soft
/// gold reserved for discovery and level-up and nothing else. Spending the
/// accent anywhere else is what makes an interface feel busy.
class GrowTokens {
  const GrowTokens._();

  // ── surfaces ──────────────────────────────────────────────────────────
  static const Color scrim = Color(0x33141712);
  static const Color panel = Color(0xF2F3F2EC);
  static const Color panelRaised = Color(0xFFFAF9F4);
  static const Color panelSunken = Color(0xFFE9E7DD);

  // ── ink ───────────────────────────────────────────────────────────────
  static const Color ink = Color(0xFF1E241D);
  static const Color inkSoft = Color(0xFF4C544A);
  static const Color inkMuted = Color(0xFF7C837A);
  static const Color onDark = Color(0xFFF4F3EC);

  // ── the world's own colours, echoed in the interface ──────────────────
  static const Color moss = Color(0xFF446A3E);
  static const Color bark = Color(0xFF554639);

  // ── vitals ────────────────────────────────────────────────────────────
  static const Color water = Color(0xFF4E7E96);
  static const Color nutrition = Color(0xFF6E8140);
  static const Color health = Color(0xFF9C5C4E);
  static const Color growth = Color(0xFF4F7A50);

  /// The single accent. Discovery and level-up only.
  static const Color accent = Color(0xFFC9A24B);

  // ── state ─────────────────────────────────────────────────────────────
  static const Color good = Color(0xFF3F6B4A);
  static const Color caution = Color(0xFF8A6116);
  static const Color alarm = Color(0xFF8C3A2E);

  static const Color hairline = Color(0x1A1E241D);

  // ── spacing ───────────────────────────────────────────────────────────
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 22;
  static const double xl = 34;

  static const double radius = 16;
  static const double radiusSmall = 10;

  // ── motion ────────────────────────────────────────────────────────────
  /// Nothing blocks input for longer than this.
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration settle = Duration(milliseconds: 380);
  static const Duration unhurried = Duration(milliseconds: 900);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve overshoot = Curves.easeOutBack;

  static const double minTapTarget = 48;
}

/// Type. One humanist sans for the interface; species names get a little more
/// weight and letter-spacing so they read as names rather than labels.
class GrowType {
  const GrowType._();

  static const TextStyle display = TextStyle(
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    color: GrowTokens.ink,
  );

  static const TextStyle title = TextStyle(
    fontSize: 19,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: GrowTokens.ink,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    color: GrowTokens.inkSoft,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w500,
    color: GrowTokens.inkSoft,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11.5,
    height: 1.3,
    letterSpacing: 0.5,
    color: GrowTokens.inkMuted,
  );

  static const TextStyle numeral = TextStyle(
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: GrowTokens.ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Colour, glyph and word for a health state.
///
/// Colour is never the only carrier (Design Charter C6): every state also has
/// a glyph and a word, and they travel together.
class StateStyle {
  const StateStyle(this.colour, this.glyph, this.label);
  final Color colour;
  final String glyph;
  final String label;
}
