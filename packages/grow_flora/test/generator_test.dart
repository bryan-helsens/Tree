import 'package:grow_domain/grow_domain.dart';
import 'package:grow_flora/grow_flora.dart';
import 'package:test/test.dart';

void main() {
  const gen = TreeGenerator();

  TreeSkeleton oak({int seed = 4242, double growth = 0.85}) =>
      gen.generate(rules: oakForm.rules, seed: seed, growth01: growth);

  group('determinism', () {
    test('the same inputs always produce the same tree', () {
      final a = oak();
      final b = oak();
      expect(a.branches.length, b.branches.length);
      expect(a.leafCount, b.leafCount);
      for (var i = 0; i < a.branches.length; i++) {
        expect(a.branches[i].tip.x, closeTo(b.branches[i].tip.x, 1e-12));
        expect(a.branches[i].tip.y, closeTo(b.branches[i].tip.y, 1e-12));
      }
    });

    test('different seeds produce visibly different individuals', () {
      final a = oak(seed: 1);
      final b = oak(seed: 2);
      final differs = a.branches.asMap().entries.any(
        (e) =>
            e.key < b.branches.length &&
            (e.value.tip.x - b.branches[e.key].tip.x).abs() > 1.0,
      );
      expect(
        differs,
        isTrue,
        reason: 'every tree of a species would otherwise be identical',
      );
    });
  });

  group('growth is continuous and monotonic', () {
    test('the structure never shrinks, across 40 seeds and both species', () {
      // The strict version of "nothing pops". A tree that reshuffles as it
      // grows fails this by a wide margin: before per-branch seeding, the
      // worst case here was a 106px collapse.
      //
      // The small tolerance is for weeping species only — a birch tip
      // genuinely falls as it lengthens, which is the behaviour we want.
      for (final form in [oakForm, birchForm]) {
        final tolerance = form.rules.gravityDroop > 0.4 ? 12.0 : 0.5;
        for (var seed = 0; seed < 40; seed++) {
          var last = 0.0;
          for (var i = 1; i <= 60; i++) {
            final t = gen.generate(
              rules: form.rules,
              seed: seed,
              growth01: i / 60,
            );
            var top = 0.0;
            for (final b in t.branches) {
              for (final p in b.spine) {
                if (p.y < top) top = p.y;
              }
            }
            expect(
              -top,
              greaterThanOrEqualTo(last - tolerance),
              reason: '${form.id} seed $seed shrank at growth ${i / 60}',
            );
            last = -top;
          }
        }
      }
    });

    test('a branch never moves once it has emerged', () {
      // Was an open defect: children attached at a *fraction* along their
      // parent, so the attachment point travelled outward as the parent
      // extended — measured at up to 92px (oak) and 128px (birch) across a
      // growth sweep. Branches visibly migrated along their parents.
      //
      // Attachment is now an absolute arc length on the mature form, so a
      // base is fixed from the moment the growth front reaches it. The bound
      // is exact equality, not a tolerance.
      for (final form in [oakForm, birchForm]) {
        for (var seed = 0; seed < 30; seed++) {
          final seen = <int, Vec2>{};
          for (var i = 1; i <= 40; i++) {
            final t = gen.generate(
              rules: form.rules,
              seed: seed,
              growth01: i / 40,
            );
            for (final b in t.branches) {
              final was = seen[b.branchId];
              if (was != null) {
                expect(
                  (b.base - was).length,
                  lessThan(1e-9),
                  reason:
                      '${form.id} seed $seed: branch ${b.branchId} '
                      'moved after emerging',
                );
              }
              seen[b.branchId] = b.base;
            }
          }
        }
      }
    });

    test('a branch only ever extends, never shortens or reshapes', () {
      for (final form in [oakForm, birchForm]) {
        for (var seed = 0; seed < 20; seed++) {
          final lastLength = <int, double>{};
          final firstSpine = <int, List<Vec2>>{};
          for (var i = 1; i <= 40; i++) {
            final t = gen.generate(
              rules: form.rules,
              seed: seed,
              growth01: i / 40,
            );
            for (final b in t.branches) {
              final prev = lastLength[b.branchId];
              if (prev != null) {
                expect(
                  b.length,
                  greaterThanOrEqualTo(prev - 1e-9),
                  reason: 'branch ${b.branchId} shortened',
                );
              }
              lastLength[b.branchId] = b.length;

              // The points that exist must be the same points: growth reveals
              // a prefix of the mature spine, it does not rescale it.
              final earlier = firstSpine[b.branchId];
              if (earlier != null) {
                for (var k = 0; k < earlier.length - 1; k++) {
                  expect(
                    (b.spine[k] - earlier[k]).length,
                    lessThan(1e-9),
                    reason: 'branch ${b.branchId} point $k moved',
                  );
                }
              }
              firstSpine[b.branchId] = b.spine;
            }
          }
        }
      }
    });
  });

  group('foliage', () {
    test('even the youngest visible tree carries leaves', () {
      // A seedling rendered as a bare stick is the worst possible first
      // impression, and it is what a fixed leaf-depth threshold produces.
      for (var g = 0.10; g <= 1.0; g += 0.05) {
        final t = gen.generate(rules: oakForm.rules, seed: 11, growth01: g);
        expect(t.leafCount, greaterThan(0), reason: 'bare at growth $g');
      }
    });

    test('leaf count grows with the tree', () {
      final young = gen.generate(rules: oakForm.rules, seed: 3, growth01: 0.3);
      final old = gen.generate(rules: oakForm.rules, seed: 3, growth01: 1.0);
      expect(old.leafCount, greaterThan(young.leafCount * 3));
    });
  });

  group('geometry is well-formed', () {
    test('no NaN or infinite coordinates, at any growth or seed', () {
      for (var seed = 0; seed < 40; seed++) {
        for (final g in [0.01, 0.2, 0.5, 0.99, 1.0]) {
          for (final form in [oakForm, birchForm]) {
            final t = gen.generate(rules: form.rules, seed: seed, growth01: g);
            for (final b in t.branches) {
              expect(b.spine.length, greaterThanOrEqualTo(2));
              expect(b.widthBase.isFinite && b.widthBase > 0, isTrue);
              for (final p in b.spine) {
                expect(p.x.isFinite && p.y.isFinite, isTrue);
              }
            }
            for (final c in t.clusters) {
              for (final l in c.leaves) {
                expect(l.position.x.isFinite && l.position.y.isFinite, isTrue);
                expect(l.scale.isFinite && l.scale >= 0, isTrue);
              }
            }
          }
        }
      }
    });

    test('growth is clamped, so out-of-range input cannot corrupt a tree', () {
      expect(
        gen.generate(rules: oakForm.rules, seed: 1, growth01: -5).growth01,
        0,
      );
      expect(
        gen.generate(rules: oakForm.rules, seed: 1, growth01: 99).growth01,
        1,
      );
    });

    test('trees grow upward', () {
      final t = oak();
      expect(t.bounds.minY, lessThan(0), reason: 'canopy above the origin');
      expect(t.bounds.maxY, lessThanOrEqualTo(1.0), reason: 'roots not drawn');
    });
  });

  group('species read differently', () {
    test('birch is narrower than oak at the same maturity', () {
      final o = gen.generate(rules: oakForm.rules, seed: 5, growth01: 1);
      final b = gen.generate(rules: birchForm.rules, seed: 5, growth01: 1);
      expect(
        b.bounds.width / b.bounds.height,
        lessThan(o.bounds.width / o.bounds.height),
        reason: 'the two silhouettes must be tellable apart',
      );
    });
  });

  group('branch rules', () {
    test('round-trip through JSON, including angle decay', () {
      final back = BranchRules.fromJson(oakForm.rules.toJson());
      expect(back.angleDecay, oakForm.rules.angleDecay);
      expect(back.maxDepth, oakForm.rules.maxDepth);
      expect(back.leafDensity, oakForm.rules.leafDensity);
    });

    test('older parameter files without angleDecay still load', () {
      final j = oakForm.rules.toJson()..remove('angleDecay');
      expect(BranchRules.fromJson(j).angleDecay, 1.0);
    });
  });

  group('wind', () {
    test('is deterministic and bounded', () {
      const w = WindField();
      for (var t = 0.0; t < 40; t += 0.37) {
        final a = w.at(t, -120);
        expect(a, w.at(t, -120));
        expect(a.abs(), lessThan(6.0));
        expect(a.isFinite, isTrue);
      }
    });

    test('thin branches respond more than thick ones', () {
      const w = WindField();
      var thinTotal = 0.0, thickTotal = 0.0;
      for (var t = 0.0; t < 20; t += 0.1) {
        thinTotal += w.swayFor(t, -100, 0.4, 2.5).abs();
        thickTotal += w.swayFor(t, -100, 0.4, 0.2).abs();
      }
      expect(thinTotal, greaterThan(thickTotal * 5));
    });
  });

  group('foliage palette', () {
    test('pallor moves leaves toward yellow, not grey', () {
      final p = oakForm.palette;
      final healthy = p.leafColor(0.5, const FoliageState());
      final starved = p.leafColor(0.5, const FoliageState(pallor: 1));
      int r(int c) => (c >> 16) & 0xFF;
      int b(int c) => c & 0xFF;
      expect(r(starved), greaterThan(r(healthy)));
      expect(b(starved), lessThanOrEqualTo(b(healthy) + 10));
    });

    test('every condition produces a valid opaque colour', () {
      final p = oakForm.palette;
      for (final s in [
        const FoliageState(),
        const FoliageState(pallor: 1),
        const FoliageState(scorch: 1),
        const FoliageState(wetness: 1),
        const FoliageState(pallor: 1, scorch: 1, wetness: 1),
      ]) {
        for (final tone in [0.0, 0.5, 1.0]) {
          final c = p.leafColor(tone, s);
          expect((c >> 24) & 0xFF, 0xFF);
        }
      }
    });
  });
}
