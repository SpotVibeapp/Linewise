import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/core/clock.dart';
import 'package:linewise/data/calibration_repository.dart';
import 'package:linewise/data/snapshot_repository.dart';
import 'package:linewise/domain/generation/player_generator.dart';
import 'package:linewise/domain/models/calibration.dart';
import 'package:linewise/domain/models/exact_line.dart';
import 'package:linewise/domain/models/player_history.dart';
import 'package:linewise/domain/models/slate_date.dart';
import 'package:linewise/domain/probability/engine.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cal_test');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('outcomes are manual-only and the report is computed from them',
      () async {
    final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
    final calibration =
        CalibrationRepository(storageDir: Directory('${dir.path}/cal'));
    final generator = PlayerGenerator(engine: ProbabilityEngine(clock: clock));

    // 40 obs split evenly above/below the line → 50% win estimate.
    final obs = <StatObservation>[
      for (var i = 0; i < 40; i++)
        StatObservation(
            statKey: 'rush_yds',
            value: i.isEven ? 120.0 : 40.0,
            gameDate: DateTime.utc(2026, 8, 1 + i),
            source: 'ESPN gamelog'),
    ];
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: SlateDate.parse('2026-09-24'),
      history: SubjectHistory(
        subjectId: 'a-1',
        subjectName: 'Derrick Henry',
        observations: obs,
        source: 'ESPN public gamelog',
        fetchedAt: DateTime.utc(2026, 9, 24, 10),
      ),
      linesByStatKey: {
        'rush_yds': ExactLine(
          id: 'l1',
          market: MarketType.playerProp,
          statKey: 'rush_yds',
          statDisplayName: 'Rush Yards',
          value: 80,
          playerName: 'Derrick Henry',
          source: 'manual:test',
          sourceTimestamp: DateTime.utc(2026, 9, 24, 11),
        ),
      },
    );
    final defensible = picks.where((p) => p.isDefensible).toList();
    expect(defensible.length, 2); // higher + lower

    // Nothing settled yet.
    var report = calibration.report(picks);
    expect(report.settledCount, 0);
    expect(report.unsettledCount, picks.length);

    // Manual settlement only.
    calibration.recordOutcome(ManualOutcome(
      pickId: defensible.first.id,
      outcome: ManualOutcomeValue.won,
      recordedAt: clock.now(),
      note: 'manual entry',
    ));
    calibration.recordOutcome(ManualOutcome(
      pickId: defensible.last.id,
      outcome: ManualOutcomeValue.push,
      recordedAt: clock.now(),
    ));
    report = calibration.report(picks);
    expect(report.settledCount, 2);
    expect(report.pushCount, 1);
    // Brier for the single decided pick at 50% that won: (0.5-1)^2 = 0.25.
    expect(report.brierScore, closeTo(0.25, 1e-9));
    expect(report.buckets, isNotEmpty);

    // Persist + reload keeps manual outcomes.
    await calibration.persist();
    final reloaded =
        CalibrationRepository(storageDir: Directory('${dir.path}/cal'));
    await reloaded.load();
    expect(reloaded.outcomeFor(defensible.first.id)?.outcome,
        ManualOutcomeValue.won);
  });

  test('calibration never auto-settles: no outcome means no score', () async {
    final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
    final calibration =
        CalibrationRepository(storageDir: Directory('${dir.path}/cal2'));
    // SnapshotRepository is not consulted for outcomes at all.
    SnapshotRepository(storageDir: Directory('${dir.path}/snaps'));
    final generator = PlayerGenerator(engine: ProbabilityEngine(clock: clock));
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: SlateDate.parse('2026-09-24'),
      history: SubjectHistory(
        subjectId: 'a-1',
        subjectName: 'Derrick Henry',
        observations: const [],
        source: 'ESPN public gamelog',
        fetchedAt: clock.now(),
      ),
      linesByStatKey: const {},
    );
    final report = calibration.report(picks);
    expect(report.settledCount, 0);
    expect(report.brierScore, 0);
  });
}
