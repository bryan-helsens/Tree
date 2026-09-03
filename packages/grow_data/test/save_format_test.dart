import 'package:grow_data/grow_data.dart';
import 'package:test/test.dart';

void main() {
  group('the save format keeps its promise', () {
    // This is the enforcement behind ADR-0005. The JSON format is temporary,
    // and "temporary" is only meaningful if something fails when it stops
    // being true. These tests are that something.

    test('every released version can still be read', () {
      // While `released` is empty the format is private and may change freely.
      // The moment a version ships, this test starts demanding an unbroken
      // chain of migrations from it to today — and it will fail the build,
      // rather than failing a player's launch.
      for (final released in SaveFormat.released) {
        expect(
          released,
          lessThanOrEqualTo(SaveFormat.version),
          reason: 'a released version cannot be newer than this build',
        );
        for (var v = released; v < SaveFormat.version; v++) {
          expect(
            SaveFormat.migrations.containsKey(v),
            isTrue,
            reason:
                'no migration from v$v, so a player on v$released cannot '
                'reach v${SaveFormat.version}. Write the step, or do not ship.',
          );
        }
      }
    });

    test('a document from a newer build is refused, not half-read', () {
      expect(
        () => SaveFormat.migrate({'schemaVersion': SaveFormat.version + 1}),
        throwsA(isA<SaveVersionError>()),
      );
    });

    test('a document with a hole in its chain fails loudly', () {
      // Simulates a v0 document with no v0→v1 step registered.
      expect(
        () => SaveFormat.migrate({'schemaVersion': 0}),
        throwsA(isA<SaveMigrationError>()),
      );
    });

    test('a current document passes through untouched', () {
      final doc = {'schemaVersion': SaveFormat.version, 'worldSeed': 7};
      expect(SaveFormat.migrate(doc), same(doc));
    });

    test('the codec writes the version the format declares', () {
      expect(SaveCodec.schemaVersion, SaveFormat.version);
    });

    test('the format is still private', () {
      // A deliberate tripwire. When this fails, someone has shipped — and
      // ADR-0005 §"What has to be true before Drift" becomes due, not
      // optional. Update the ADR in the same change that makes it fail.
      expect(
        SaveFormat.isPublic,
        isFalse,
        reason:
            'A save format has been released. Per ADR-0005 the JSON format '
            'may no longer change without a migration step, and the Drift '
            'cutover now owes a dated plan.',
      );
    });
  });
}
