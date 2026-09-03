import 'package:grow_data/grow_data.dart';
import 'package:grow_domain/grow_domain.dart';
import 'package:test/test.dart';

/// Persistence and crash recovery, deterministically.
void main() {
  const codec = SaveCodec();

  GameState sample() {
    final base = GameState.newGame(
      worldSeed: const Seed(20260903),
      starterSpecies: const SpeciesId('quercus_robur'),
    );
    return base
        .copyWith(
          simTime: const SimTime(9 * 3600 * 1000),
          lastInteractionAt: const SimTime(8 * 3600 * 1000),
          trees: [
            base.trees.first.copyWith(
              stage: GrowthStage.sapling,
              water: Vital(58.5),
              nutrition: Vital(41.25),
              health: Vital(87.125),
              growth: Vital(62),
              state: HealthState.healthy,
              timesWatered: 7,
              timesFed: 2,
              criticalHours: 1.5,
              criticalSightings: 1,
              careNotificationSent: true,
              isFlowering: true,
              afflictions: const [
                Affliction(
                  kind: AfflictionKind.nutrientBurn,
                  severity: 0.42,
                  startedAtMs: 12345,
                ),
              ],
              discoveredTraits: const {TraitId('fast_grower')},
            ),
          ],
          inventory: const Inventory.starting().copyWith(
            water: 9,
            nutrients: 4,
            dew: 3,
          ),
          progression: const Progression.starting().copyWith(
            level: 5,
            xp: 412,
            focusStreakDays: 4,
            longestStreak: 9,
            streakShields: 0,
            lastStreakDayIndex: 3,
            today: const DailyStats(
              dayIndex: 3,
              sessionsCompleted: 2,
              growthPointsEarned: 310,
              deepFocusUsed: true,
            ),
          ),
          clock: const ClockMeta(
            lastWallMs: 1700000000000,
            lastMonotonicMs: 999000,
            bootId: 'boot-7',
            simTimeHighMs: 9 * 3600 * 1000,
            anomalies: 2,
          ),
        )
        .withSession(
          const FocusSession(
            id: 'session-1',
            planned: Duration(minutes: 45),
            startedAt: SimTime(8 * 3600 * 1000),
            startedAtWallMs: 1699999000000,
            phase: FocusPhase.completed,
            finishedAt: SimTime(8 * 3600 * 1000 + 45 * 60 * 1000),
          ),
        );
  }

  group('the codec round-trips everything', () {
    test('a full save survives encode and decode', () {
      final before = sample();
      final after = codec.decode(codec.encode(before));

      expect(after.simTime.ms, before.simTime.ms);
      expect(after.worldSeed.raw, before.worldSeed.raw);
      expect(after.biome.raw, before.biome.raw);
      expect(after.lastInteractionAt.ms, before.lastInteractionAt.ms);

      final a = after.trees.first;
      final b = before.trees.first;
      expect(a.water.value, b.water.value);
      expect(a.nutrition.value, b.nutrition.value);
      expect(a.health.value, b.health.value);
      expect(a.stage, b.stage);
      expect(a.state, b.state);
      expect(a.timesWatered, b.timesWatered);
      expect(a.criticalHours, b.criticalHours);
      expect(a.careNotificationSent, isTrue);
      expect(a.afflictions.single.kind, AfflictionKind.nutrientBurn);
      expect(a.afflictions.single.severity, 0.42);
      expect(a.discoveredTraits, contains(const TraitId('fast_grower')));

      expect(after.inventory.dew, 3);
      expect(after.progression.longestStreak, 9);
      expect(after.progression.today.growthPointsEarned, 310);
      expect(after.clock.bootId, 'boot-7');
      expect(after.clock.simTimeHighMs, before.clock.simTimeHighMs);
    });

    test('the session survives, including its phase', () {
      final after = codec.decode(codec.encode(sample()));
      expect(after.session!.id, 'session-1');
      expect(after.session!.phase, FocusPhase.completed);
      expect(after.session!.planned, const Duration(minutes: 45));
      expect(after.session!.finishedAt!.ms, sample().session!.finishedAt!.ms);
    });

    test('a claimed outcome survives, so a reward is never recomputed', () {
      final claimed = sample().withSession(
        sample().session!.copyWith(
          phase: FocusPhase.claimed,
          outcome: const SessionOutcome(
            actual: Duration(minutes: 45),
            integrity: 1,
            growthPoints: 210,
            water: 4,
            nutrients: 2,
            xp: 210,
            growthInjection: 4.2,
            deepFocusBonus: true,
            levelsGained: 1,
          ),
        ),
      );
      final after = codec.decode(codec.encode(claimed));
      expect(after.session!.phase, FocusPhase.claimed);
      expect(after.session!.outcome!.growthPoints, 210);
      expect(after.session!.outcome!.deepFocusBonus, isTrue);
    });

    test('encoding is stable, so equal states produce equal documents', () {
      expect(codec.encode(sample()), codec.encode(sample()));
    });

    test('a save with no session round-trips', () {
      final none = sample().withSession(null);
      expect(codec.decode(codec.encode(none)).session, isNull);
    });
  });

  group('version handling', () {
    test('a save from a newer build is refused, not half-read', () {
      final doc = codec.toJson(sample())
        ..['schemaVersion'] = SaveCodec.schemaVersion + 1;
      expect(() => codec.fromJson(doc), throwsA(isA<SaveVersionError>()));
    });

    test('the current version loads', () {
      expect(
        codec.fromJson(codec.toJson(sample())).simTime.ms,
        sample().simTime.ms,
      );
    });
  });

  group('the repository', () {
    test('an empty store has no save', () async {
      expect(await InMemorySaveRepository().load(), isNull);
    });

    test('what was written is what comes back', () async {
      final repo = InMemorySaveRepository();
      await repo.save(sample());
      final loaded = await repo.load();
      expect(loaded!.session!.phase, FocusPhase.completed);
      expect(loaded.progression.level, 5);
    });

    test('a failed write leaves the previous save intact', () async {
      final repo = InMemorySaveRepository();
      await repo.save(sample());
      final before = repo.document;

      repo.failNextWrite = true;
      await expectLater(
        repo.save(sample().copyWith(simTime: const SimTime(999))),
        throwsA(isA<StateError>()),
      );
      expect(repo.document, before, reason: 'no partial document');
    });

    test('writes are serialised, so the newest one wins', () async {
      final repo = GuardedSaveRepository(InMemorySaveRepository());
      await Future.wait([
        for (var i = 1; i <= 20; i++)
          repo.save(sample().copyWith(simTime: SimTime(i * 60000))),
      ]);
      expect((await repo.load())!.simTime.ms, 20 * 60000);
    });

    test('a corrupt primary falls back to the last good save', () async {
      final inner = InMemorySaveRepository();
      final repo = GuardedSaveRepository(inner);
      await repo.save(sample());

      // Corrupt the store underneath.
      final broken = _BrokenRepository(inner);
      final guarded = GuardedSaveRepository(broken);
      await guarded.save(sample().copyWith(simTime: const SimTime(120000)));
      broken.corrupt = true;

      final recovered = await guarded.load();
      expect(recovered, isNotNull);
      expect(
        recovered!.simTime.ms,
        120000,
        reason: 'the last good save, not nothing',
      );
    });
  });
}

class _BrokenRepository implements SaveRepository {
  _BrokenRepository(this._inner);
  final SaveRepository _inner;
  bool corrupt = false;

  @override
  Future<GameState?> load() {
    if (corrupt) throw const FormatException('corrupt save');
    return _inner.load();
  }

  @override
  Future<void> save(GameState state) => _inner.save(state);

  @override
  Future<void> delete() => _inner.delete();
}
