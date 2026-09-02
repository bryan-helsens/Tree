import 'dart:convert';
import 'dart:io';

import 'package:grow_content/grow_content.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:test/test.dart';

/// Loads the on-disk content and hands back the first species map, so a test
/// can corrupt one field and assert the loader rejects it.
({Map<String, Object?> bundle, Map<String, Object?> species}) mutableContent() {
  final bundle = jsonDecode(
    File('assets/content.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final species =
      (bundle['species']! as List<Object?>).first as Map<String, Object?>;
  return (bundle: bundle, species: species);
}

void main() {
  final content = mvpContent();

  group('the embedded asset matches its source', () {
    test('assets/content.json has not drifted from the generated constant', () {
      // The JSON is the source of truth; the constant is what ships. If these
      // diverge, someone edited one and forgot to regenerate the other.
      final onDisk = File('assets/content.json').readAsStringSync();
      final embedded = ContentBundle.parse(onDisk);
      expect(embedded.version, content.version);
      expect(
        embedded.allSpecies.map((s) => s.id.raw).toSet(),
        content.allSpecies.map((s) => s.id.raw).toSet(),
        reason: 'run: dart run tool/embed_content.dart',
      );
    });
  });

  group('MVP content', () {
    test('ships exactly the two species the vertical slice needs', () {
      expect(content.allSpecies.map((s) => s.id.raw).toSet(), {
        'quercus_robur',
        'betula_pendula',
      });
    });

    test('every species declares one stageHours entry per growth stage', () {
      for (final s in content.allSpecies) {
        expect(
          s.stageHours,
          hasLength(GrowthStage.values.length),
          reason: s.id.raw,
        );
      }
    });

    test('every band is well-formed and every rate is positive', () {
      for (final s in content.allSpecies) {
        for (final b in [s.water, s.nutrition, s.light, s.temperature]) {
          expect(b.min, lessThanOrEqualTo(b.max), reason: s.id.raw);
          expect(b.tolLow, greaterThan(0), reason: s.id.raw);
          expect(b.tolHigh, greaterThan(0), reason: s.id.raw);
        }
        expect(s.waterUse, greaterThan(0), reason: s.id.raw);
        expect(s.growthRate, greaterThan(0), reason: s.id.raw);
        expect(s.absorption, greaterThan(0), reason: s.id.raw);
        expect(s.resilience, inInclusiveRange(0, 1), reason: s.id.raw);
        expect(s.pestResistance, inInclusiveRange(0, 1), reason: s.id.raw);
      }
    });

    test('water and nutrition tolerate under- more than over-supply', () {
      // The asymmetry is a design rule, not a per-species accident.
      for (final s in content.allSpecies) {
        expect(s.water.tolHigh, lessThan(s.water.tolLow), reason: s.id.raw);
        expect(
          s.nutrition.tolHigh,
          lessThan(s.nutrition.tolLow),
          reason: s.id.raw,
        );
      }
    });

    test('the two species are meaningfully different to care for', () {
      final oak = content[const SpeciesId('quercus_robur')];
      final birch = content[const SpeciesId('betula_pendula')];
      expect(oak.water.min, isNot(birch.water.min));
      expect(oak.nutrition.max, isNot(birch.nutrition.max));
      expect(
        oak.family,
        isNot(birch.family),
        reason: 'diversity scoring rewards distinct families',
      );
    });

    test('every species carries hidden traits to discover', () {
      for (final s in content.allSpecies) {
        expect(s.hiddenTraits, isNotEmpty, reason: s.id.raw);
      }
    });

    test('i18n keys are used rather than bare literals', () {
      for (final s in content.allSpecies) {
        expect(s.nameKey, startsWith('species.'), reason: s.id.raw);
      }
    });
  });

  group('loading', () {
    test('an unknown species fails loudly, with a migration hint', () {
      expect(
        () => content[const SpeciesId('nope')],
        throwsA(isA<StateError>()),
      );
    });

    test('a bad rarity is rejected at parse time, not at runtime', () {
      final c = mutableContent();
      c.species['rarity'] = 'legendary';
      expect(
        () => ContentBundle.fromJson(c.bundle),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a wrong stageHours length is rejected at parse time', () {
      final c = mutableContent();
      c.species['stageHours'] = [1.0, 2.0];
      expect(
        () => ContentBundle.fromJson(c.bundle),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('the bundle is cached, not reparsed on every call', () {
      expect(identical(mvpContent(), mvpContent()), isTrue);
    });
  });
}
