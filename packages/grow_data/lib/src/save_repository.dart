import 'dart:async';

import 'package:grow_domain/grow_domain.dart';

import 'save_codec.dart';

/// Where a save lives.
///
/// The interface is deliberately tiny — load, save, backups — because the
/// interesting guarantees are about *atomicity*, not about queries. Drift is
/// the eventual implementation (docs/10); an implementation that writes one
/// document is enough to make crash recovery correct today, and the port is
/// what keeps swapping it a contained change.
abstract class SaveRepository {
  /// The stored save, or null if there is none.
  Future<GameState?> load();

  /// Writes [state], replacing what was there.
  ///
  /// Must be atomic: a reader either sees the whole previous save or the whole
  /// new one, never a partial write. A half-written save that claimed a
  /// session but lost its reward would break the exactly-once guarantee.
  Future<void> save(GameState state);

  Future<void> delete();
}

/// Serialises writes and keeps a rotating backup.
///
/// Wraps any [SaveRepository]. Two jobs:
///
///  * **One writer.** Saves are queued, so two overlapping writes cannot
///    interleave and leave the newer one behind the older.
///  * **A ladder to fall back on.** The previous good save is kept, so a
///    corrupt document costs one session rather than a forest.
class GuardedSaveRepository implements SaveRepository {
  GuardedSaveRepository(this._inner, {this.backupDepth = 3});

  final SaveRepository _inner;
  final int backupDepth;

  final List<String> _backups = [];
  final SaveCodec _codec = const SaveCodec();

  Future<void> _queue = Future.value();

  @override
  Future<GameState?> load() async {
    try {
      final state = await _inner.load();
      if (state != null) _remember(state);
      return state;
    } catch (_) {
      // The primary is unreadable. Walk back through the backups: a player's
      // forest is worth more than the last few minutes of it.
      for (final snapshot in _backups.reversed) {
        try {
          return _codec.decode(snapshot);
        } catch (_) {
          continue;
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> save(GameState state) {
    // Single-writer: every save waits for the one before it.
    final next = _queue.then((_) async {
      await _inner.save(state);
      _remember(state);
    });
    _queue = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> delete() => _inner.delete();

  void _remember(GameState state) {
    _backups.add(_codec.encode(state));
    while (_backups.length > backupDepth) {
      _backups.removeAt(0);
    }
  }
}

/// A save that lives only in memory. For tests, and for a first run before
/// anything has been written.
class InMemorySaveRepository implements SaveRepository {
  InMemorySaveRepository([this._document]);

  String? _document;
  final SaveCodec _codec = const SaveCodec();

  /// Counts writes, so a test can assert how often the game persisted.
  int writes = 0;

  /// Set to make the next write throw, standing in for a disk failure.
  bool failNextWrite = false;

  @override
  Future<GameState?> load() async =>
      _document == null ? null : _codec.decode(_document!);

  @override
  Future<void> save(GameState state) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('simulated write failure');
    }
    // Encode first, assign second: a throw during encoding must not leave a
    // truncated document behind. This is the in-memory analogue of the
    // write-temp-then-rename the file implementation uses.
    final encoded = _codec.encode(state);
    _document = encoded;
    writes++;
  }

  @override
  Future<void> delete() async => _document = null;

  String? get document => _document;
}
