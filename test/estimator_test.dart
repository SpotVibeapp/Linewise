import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/domain/models/exact_line.dart';
import 'package:linewise/domain/probability/estimator.dart';

void main() {
  const est = EmpiricalEstimator();

  group('EmpiricalEstimator', () {
    test('refuses to invent probabilities below 20 valid observations', () {
      final values = [for (var i = 0; i < 19; i++) 80.0];
      expect(
        est.estimate(
            values: values, line: 74.5, direction: PropDirection.higher),
        isNull,
      );
    });

    test('computes win/push/tie/lower shares from raw observations only', () {
      // 24 observations vs line 75: 12 above, 3 exactly 75, 9 below.
      final values = <double>[
        for (var i = 0; i < 12; i++) 90,
        for (var i = 0; i < 3; i++) 75,
        for (var i = 0; i < 9; i++) 60,
      ];
      final higher = est.estimate(
          values: values, line: 75, direction: PropDirection.higher)!;
      expect(higher.sampleSize, 24);
      expect(higher.observedWins, 12);
      expect(higher.observedPushes, 3);
      expect(higher.observedLosses, 9);
      expect(higher.winPct, closeTo(50.0, 1e-9));
      expect(higher.pushPct, closeTo(12.5, 1e-9));
      expect(higher.losePct, closeTo(37.5, 1e-9));
      expect(higher.winPct + higher.pushPct + higher.losePct,
          closeTo(100.0, 1e-9));

      final lower = est.estimate(
          values: values, line: 75, direction: PropDirection.lower)!;
      expect(lower.winPct, closeTo(37.5, 1e-9));
      expect(lower.pushPct, closeTo(12.5, 1e-9));
    });

    test('90% Wilson interval brackets the empirical share', () {
      final values = [for (var i = 0; i < 20; i++) i.isEven ? 100.0 : 50.0];
      final e = est.estimate(
          values: values, line: 75, direction: PropDirection.higher)!;
      expect(e.interval90Low, lessThan(e.winPct));
      expect(e.interval90High, greaterThan(e.winPct));
    });

    test('adjustment is clamped and never eats the push mass', () {
      final values = <double>[
        for (var i = 0; i < 20; i++) 90,
        for (var i = 0; i < 5; i++) 75,
      ];
      final e = est.estimate(
        values: values,
        line: 75,
        direction: PropDirection.higher,
        adjustmentPP: 40,
      )!;
      // win 20/25 = 80%, push 20% → max win after adjustment = 80%.
      expect(e.winPct, lessThanOrEqualTo(80.0 + 1e-9));
      expect(e.losePct, greaterThanOrEqualTo(-1e-9));
    });

    test('moneyline variant reports push/tie as 0 (not applicable)', () {
      final won = [for (var i = 0; i < 13; i++) true, for (var i = 0; i < 10; i++) false];
      final e = est.estimateBinaryWins(
          wonGames: won, direction: PropDirection.higher)!;
      expect(e.pushPct, 0);
      expect(e.winPct, closeTo(13 / 23 * 100, 1e-9));
      expect(e.sampleSize, 23);
      expect(est.estimateBinaryWins(
          wonGames: [true, false], direction: PropDirection.higher), isNull);
    });
  });
}
