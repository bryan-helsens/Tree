/// The save format's identity, its stability promise, and its migrations.
///
/// GROW persists a save as one JSON document. That is a **deliberately
/// temporary** choice: docs/10 specifies normalised SQLite (Drift) as the
/// shipping design, and [ADR-0005](../../../../docs/adr/0005-json-save-format.md)
/// records why the slice does not implement it yet and exactly what has to be
/// true before it does.
///
/// The point of this file is that the promise is **enforced rather than
/// remembered**. `save_format_test.dart` fails the build if the migration
/// chain has a hole in it once the format has been released to anyone.
library;

/// One step from a document at version `n` to a document at version `n + 1`.
///
/// Steps operate on the raw map, never on `GameState`. A migration has to be
/// able to read a shape the current domain classes no longer describe — that
/// is the whole reason it exists.
typedef SaveMigration = Map<String, Object?> Function(Map<String, Object?> doc);

class SaveFormat {
  const SaveFormat._();

  /// The version this build writes.
  static const int version = 1;

  /// Versions that have been inside a build handed to anyone outside the team
  /// — TestFlight and internal tracks included.
  ///
  /// **This is the migration boundary.** While it is empty the format is
  /// private: a breaking change may simply bump [version] and let dev saves
  /// reset, because the only saves in existence belong to people who can be
  /// told. The moment a version is added here, that stops being true forever
  /// and every later change owes a migration.
  ///
  /// Adding to this set is the act of shipping. Do it in the same commit as
  /// the release, not afterwards.
  static const Set<int> released = {};

  /// Whether any save format has escaped into the world.
  static bool get isPublic => released.isNotEmpty;

  /// Steps keyed by the version they migrate *from*.
  ///
  /// Empty at version 1, and correctly so: there is nothing older to read.
  /// The machinery exists now rather than later because adding it after a
  /// format has shipped means writing the first migration under pressure.
  static const Map<int, SaveMigration> migrations = <int, SaveMigration>{};

  /// Brings [doc] up to [version], or throws explaining why it cannot.
  ///
  /// A document from a *newer* build is refused rather than half-read: a
  /// downgrade that silently drops fields is data loss the player never
  /// agreed to.
  static Map<String, Object?> migrate(Map<String, Object?> doc) {
    final found = (doc['schemaVersion'] as num?)?.toInt() ?? 0;
    if (found > version) throw SaveVersionError(found, version);
    if (found == version) return doc;

    var current = doc;
    for (var v = found; v < version; v++) {
      final step = migrations[v];
      if (step == null) throw SaveMigrationError(found, v);
      current = step(current);
      current = {...current, 'schemaVersion': v + 1};
    }
    return current;
  }
}

/// A save written by a newer build than this one.
class SaveVersionError implements Exception {
  const SaveVersionError(this.found, this.supported);
  final int found;
  final int supported;

  @override
  String toString() =>
      'Save is version $found; this build understands up to $supported.';
}

/// A save this build cannot read because a migration step is missing.
class SaveMigrationError implements Exception {
  const SaveMigrationError(this.from, this.missingAt);
  final int from;
  final int missingAt;

  @override
  String toString() =>
      'Cannot migrate a version $from save: no step from $missingAt. '
      'Every released version needs an unbroken path to '
      'SaveFormat.version (${SaveFormat.version}).';
}
