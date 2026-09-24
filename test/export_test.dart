import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/core/clock.dart';
import 'package:linewise/data/export_service.dart';
import 'package:linewise/domain/generation/player_generator.dart';
import 'package:linewise/domain/models/exact_line.dart';
import 'package:linewise/domain/models/player_history.dart';
import 'package:linewise/domain/models/slate_date.dart';
import 'package:linewise/domain/probability/engine.dart';

void main() {
  final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
  final generator = PlayerGenerator(engine: ProbabilityEngine(clock: clock));
  final export = const ExportService();

  final obs = <StatObservation>[
    for (var i = 0; i < 22; i++)
      StatObservation(
          statKey: 'rush_yds',
          value: 70.0 + i,
          gameDate: DateTime.utc(2026, 8, 1 + i),
          source: 'ESPN gamelog'),
    for (var i = 0; i < 22; i++)
      StatObservation(
          statKey: 'rec_yds',
          value: 30.0 + i,
          gameDate: DateTime.utc(2026, 8, 1 + i),
          source: 'ESPN gamelog'),
  ];
  final history = SubjectHistory(
    subjectId: 'a-1',
    subjectName: 'Derrick Henry',
    observations: obs,
    source: 'ESPN public gamelog',
    fetchedAt: DateTime.utc(2026, 9, 24, 10),
  );

  final picks = generator.generate(
    subjectId: 'a-1',
    subjectName: 'Derrick Henry',
    sportId: 'nfl',
    slateDate: SlateDate.parse('2026-09-24'),
    history: history,
    linesByStatKey: {
      'rush_yds': ExactLine(
        id: 'l1',
        market: MarketType.playerProp,
        statKey: 'rush_yds',
        statDisplayName: 'Rush Yards',
        value: 85.5,
        playerName: 'Derrick Henry',
        source: 'The Odds API/nfl/fanduel/player_rush_yds',
        sourceTimestamp: DateTime.utc(2026, 9, 24, 11),
      ),
      // rec_yds intentionally has NO line → withheld rows.
    },
  );

  final bundle = PredictionSnapshotRowBundle(
    snapshotId: 'snap-test',
    picks: picks,
    slateDate: SlateDate.parse('2026-09-24'),
  );

  test('CSV export includes withheld rows with reasons', () {
    final csv = export.toCsv(bundle);
    expect(csv, contains('withheld_reason'));
    expect(csv, contains('noSourceBackedLine'));
    expect(csv, contains('win_pct_definition'));
    // Withheld rec_yds rows present.
    expect(csv, anyOf(contains('Reception'), contains('rec_yds')));
    final rows = csv.split('\n');
    expect(rows.length, picks.length + 1); // header + every row incl withheld
  });

  test('JSON export includes withheld rows and the definition', () {
    final json = export.toJson(bundle);
    expect(json, contains('"includes_withheld_rows":true'));
    expect(
        json, anyOf(contains('Probability unavailable'), contains('withheld')));
    expect(json, contains('Win percentage = share'));
  });

  test('exports never contain credentials', () {
    final csv = export.toCsv(bundle);
    final json = export.toJson(bundle);
    for (final out in [csv, json]) {
      expect(out.toLowerCase(), isNot(contains('apikey=')));
      expect(out, isNot(contains('Bearer ')));
    }
  });
}
