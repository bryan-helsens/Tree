/// Deterministic, seedable randomness.
///
/// Nothing in the simulation may use `math.Random()` — a lint rule forbids it.
/// Every roll is keyed to `(worldSeed, entity, absolute hour slot)` so an event
/// either happens or does not, regardless of how the elapsed window was
/// chunked into simulation calls.
library;

const int _mask32 = 0xFFFFFFFF;

/// SplitMix64-style avalanche. Cheap, well-distributed, and deterministic.
int mixHash(int x) {
  var z = x;
  z ^= z >>> 30;
  z *= 0xBF58476D1CE4E5B9;
  z ^= z >>> 27;
  z *= 0x94D049BB133111EB;
  z ^= z >>> 31;
  return z;
}

/// Combines several values into one seed. Order matters.
int hashAll(List<int> parts) {
  var h = 0x243F6A8885A308D3;
  for (final p in parts) {
    h = mixHash(h ^ p);
  }
  return h;
}

int hashString(String s) {
  // FNV-1a, 64-bit.
  var h = 0xCBF29CE484222325;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h *= 0x100000001B3;
  }
  return h;
}

/// xorshift128. Fast, tiny state, adequate for gameplay rolls.
class Xorshift128 {
  Xorshift128(int seed) {
    final a = mixHash(seed);
    final b = mixHash(a ^ 0x9E3779B97F4A7C15);
    _x = a & _mask32;
    _y = (a >>> 32) & _mask32;
    _z = b & _mask32;
    _w = (b >>> 32) & _mask32;
    // All-zero state is a fixed point for xorshift; nudge it.
    if ((_x | _y | _z | _w) == 0) _x = 0x9E3779B9;
  }

  factory Xorshift128.forSlot(List<int> parts) => Xorshift128(hashAll(parts));

  late int _x, _y, _z, _w;

  int next32() {
    final t = (_x ^ ((_x << 11) & _mask32)) & _mask32;
    _x = _y;
    _y = _z;
    _z = _w;
    _w = ((_w ^ (_w >>> 19)) ^ (t ^ (t >>> 8))) & _mask32;
    return _w;
  }

  /// Uniform in `[0, 1)`.
  double nextDouble() => next32() / 4294967296.0;

  /// Uniform in `[min, max)`.
  double range(double min, double max) => min + nextDouble() * (max - min);

  /// True with probability [p].
  bool chance(double p) => nextDouble() < p;

  int nextInt(int maxExclusive) => next32() % maxExclusive;
}

/// Smooth 1-D value noise. Used for weather, which needs day-to-day
/// autocorrelation (a stateless hash would flip randomly every day) while
/// staying a pure function of `(seed, day)` so the forecast is exact.
double valueNoise1D(int seed, double x) {
  final i = x.floor();
  final f = x - i;
  final a = _unit(seed, i);
  final b = _unit(seed, i + 1);
  final u = f * f * (3 - 2 * f); // smoothstep
  return a + (b - a) * u;
}

double _unit(int seed, int i) =>
    (mixHash(seed ^ mixHash(i)) >>> 11) / 9007199254740992.0;
