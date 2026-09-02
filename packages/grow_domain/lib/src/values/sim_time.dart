/// Simulation time: milliseconds since the save was created.
///
/// Never wall-clock time. Nothing in the domain or simulation layers may read
/// a real clock; elapsed time arrives as an argument after passing through
/// `ClockGuard`. See docs/05-simulation.md §8.
extension type const SimTime(int ms) {
  static const SimTime zero = SimTime(0);

  /// The simulation advances on a fixed 60-second grid anchored to absolute
  /// time. This is what makes `run(a→c)` equal `run(a→b)` then `run(b→c)`.
  static const int stepMs = 60 * 1000;
  static const int hourMs = 60 * 60 * 1000;
  static const int dayMs = 24 * hourMs;

  /// Index of the 60-second step containing this instant.
  int get stepIndex => ms ~/ stepMs;

  /// Index of the hour slot containing this instant. Event rolls are keyed to
  /// this, so an event either happens or does not regardless of how the
  /// elapsed window was chunked.
  int get hourIndex => ms ~/ hourMs;

  int get dayIndex => ms ~/ dayMs;

  /// Hour of day in `[0, 24)`, as a real number.
  double get hourOfDay => (ms % dayMs) / hourMs;

  /// Rounds down to the nearest step boundary. State always sits on the grid;
  /// the sub-step remainder stays unsimulated until it accumulates.
  SimTime get floorToStep => SimTime(stepIndex * stepMs);

  bool get isOnGrid => ms % stepMs == 0;

  SimTime operator +(Duration d) => SimTime(ms + d.inMilliseconds);
  SimTime operator -(Duration d) => SimTime(ms - d.inMilliseconds);
  Duration difference(SimTime other) => Duration(milliseconds: ms - other.ms);

  bool operator <(SimTime o) => ms < o.ms;
  bool operator <=(SimTime o) => ms <= o.ms;
  bool operator >(SimTime o) => ms > o.ms;
  bool operator >=(SimTime o) => ms >= o.ms;
}
