import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/domain/models/evidence.dart';
import 'package:linewise/domain/probability/factor_groups.dart';

Factor f(String id, FactorGroup g, double adj,
        {bool descriptive = false, FactorStance stance = FactorStance.supporting}) =>
    Factor(
      signalId: id,
      group: g,
      stance: stance,
      label: id,
      detail: id,
      source: 'test',
      observedAt: DateTime.utc(2026, 9, 24),
      adjustmentPP: adj,
      descriptiveOnly: descriptive,
    );

void main() {
  group('Double-count guard', () {
    test('rejects the same signal id twice (no double-counting)', () {
      final guard = DoubleCountGuard();
      final factors = [
        f('matchup.opponent', FactorGroup.matchupGame, 4),
        f('matchup.opponent', FactorGroup.matchupGame, 4),
      ];
      expect(() => applyAdjustmentPolicy(factors, guard), throwsStateError);
    });

    test('descriptive-only factors can never adjust', () {
      final guard = DoubleCountGuard();
      expect(
        () => f('role.recent_form', FactorGroup.roleUsage, 3,
            descriptive: true),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Adjustment policy caps', () {
    test('per-group cap clamps the group total', () {
      final guard = DoubleCountGuard();
      final total = applyAdjustmentPolicy([
        f('availability.injuries_availability', FactorGroup.availabilityHealth, -6),
        f('availability.lineup_changes', FactorGroup.availabilityHealth, -6,
            stance: FactorStance.opposing),
      ], guard);
      expect(total, -6.0);
    });

    test('overall cap clamps the grand total', () {
      final guard = DoubleCountGuard();
      final total = applyAdjustmentPolicy([
        f('availability.x', FactorGroup.availabilityHealth, 6),
        f('role.x', FactorGroup.roleUsage, 5),
        f('matchup.x', FactorGroup.matchupGame, 6),
        f('situational.x', FactorGroup.situational, 4),
        f('environment.x', FactorGroup.environment, 4),
      ], guard);
      expect(total, kOverallAdjustmentCapPP);
    });

    test('baseline and marketHistory groups must not adjust', () {
      final guard = DoubleCountGuard();
      expect(
        () => applyAdjustmentPolicy(
            [f('baseline.sample', FactorGroup.baseline, 2)], guard),
        throwsStateError,
      );
    });
  });

  group('Evidence quality rubric', () {
    final now = DateTime.utc(2026, 9, 24, 12);
    test('high quality for large fresh sample with corroboration', () {
      final q = scoreEvidenceQuality(
        sampleSize: 34,
        historyFetchedAt: now.subtract(const Duration(days: 1)),
        lineObservedAt: now.subtract(const Duration(hours: 5)),
        now: now,
        distinctFactorSources: 3,
        unknownCount: 0,
      );
      expect(q, EvidenceQuality.high);
    });

    test('low quality when line is missing/old and unknowns stack up', () {
      final q = scoreEvidenceQuality(
        sampleSize: 21,
        historyFetchedAt: now.subtract(const Duration(days: 30)),
        lineObservedAt: now.subtract(const Duration(days: 3)),
        now: now,
        distinctFactorSources: 0,
        unknownCount: 4,
      );
      expect(q, EvidenceQuality.low);
    });
  });
}
