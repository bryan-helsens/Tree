import 'package:grow_domain/grow_domain.dart';

/// Reads the device's clocks.
///
/// The one place in the application permitted to call `DateTime.now()`. A lint
/// rule forbids it everywhere else, which is what keeps the simulation
/// testable and the clock guard meaningful.
abstract class TimeAuthority {
  ClockReading now();
}

/// The real device clocks.
///
/// `monotonicMs` is a stopwatch started when the process began, offset by a
/// per-process boot id. It is not a true boot-relative clock — Android's
/// `elapsedRealtimeNanos` and Darwin's `CLOCK_MONOTONIC` are, and the platform
/// plugin will supply them (docs/07). Until then a per-process anchor is
/// honest about what it can prove: within one run of the app the monotonic
/// clock cannot be moved, and across runs the guard falls back to the wall
/// clock with a cap, exactly as it does after a reboot.
class SystemTimeAuthority implements TimeAuthority {
  SystemTimeAuthority() : _bootId = _newBootId() {
    _stopwatch.start();
  }

  final String _bootId;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  ClockReading now() => ClockReading(
    // ignore: avoid_dynamic_calls
    wallMs: DateTime.now().millisecondsSinceEpoch,
    monotonicMs: _stopwatch.elapsedMilliseconds,
    bootId: _bootId,
  );

  static String _newBootId() => 'run-${DateTime.now().microsecondsSinceEpoch}';
}

/// A clock a test drives by hand.
class FakeTimeAuthority implements TimeAuthority {
  FakeTimeAuthority({
    int wallMs = 1700000000000,
    int monotonicMs = 0,
    this.bootId = 'boot-test',
  }) : _wallMs = wallMs,
       _monotonicMs = monotonicMs;

  int _wallMs;
  int _monotonicMs;
  String bootId;

  /// Both clocks move together: ordinary time passing.
  void advance(Duration d) {
    _wallMs += d.inMilliseconds;
    _monotonicMs += d.inMilliseconds;
  }

  /// Only the wall clock moves: someone changed the date.
  void skewWallClock(Duration d) => _wallMs += d.inMilliseconds;

  /// A restart: the monotonic clock resets and the boot id changes.
  void reboot({Duration off = Duration.zero}) {
    _wallMs += off.inMilliseconds;
    _monotonicMs = 0;
    bootId = 'boot-${_wallMs.hashCode}';
  }

  @override
  ClockReading now() =>
      ClockReading(wallMs: _wallMs, monotonicMs: _monotonicMs, bootId: bootId);
}
