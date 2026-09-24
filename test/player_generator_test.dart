import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/core/clock.dart';
import 'package:linewise/domain/generation/player_generator.dart';
import 'package:linewise/domain/models/exact_line.dart';
import 'package:linewise/domain/models/pick.dart';
import 'package:linewise/domain/models/player_history.dart';
import 'package:linewise/domain/models/slate_date.dart';
import 'package:linewise/domain/probability/engine.dart';

SubjectHistory historyWith({
  int rushYds = 24,
  int recYds = 10,
  int passYds = 24,
  double rushBase = 80,
}) {
  final obs = <StatObservation>[];
  for (var i = 0; i < rushYds; i++) {
    obs.add(StatObservation(
        statKey: 'rush_yds',
        value: rushBase + i,
        gameDate: DateTime.utc(2026, 9, 1).add(Duration(days: i)),
        source: 'ESPN gamelog'));
  }
  for (var i = 0; i < recYds; i++) {
    obs.add(StatObservation(
        statKey: 'rec_yds',
        value: 40 + i,
        gameDate: DateTime.utc(2026, 9, 1).add(Duration(days: i)),
        source: 'ESPN gamelog'));
  }
  for (var i = 0; i < passYds; i++) {
    obs.add(StatObservation(
        statKey: 'pass_yds',
        value: 200 + i.toDouble(),
        gameDate: DateTime.utc(2026, 9, 1).add(Duration(days: i)),
        source: 'ESPN gamelog'));
  }
  return SubjectHistory(
    subjectId: 'a-1',
    subjectName: 'Derrick Henry',
    observations: obs,
    source: 'ESPN public gamelog',
    fetchedAt: DateTime.utc(2026, 9, 24, 10),
  );
}

ExactLine line(String stat, double value) => ExactLine(
      id: 'l-$stat',
      market: MarketType.playerProp,
      statKey: stat,
      statDisplayName: stat,
      value: value,
      playerName: 'Derrick Henry',
      source: 'The Odds API/nfl/fanduel/player_$stat',
      sourceTimestamp: DateTime.utc(2026, 9, 24, 11),
    );

void main() {
  final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
  final generator = PlayerGenerator(engine: ProbabilityEngine(clock: clock));
  final slate = SlateDate.parse('2026-09-24');

  Map<String, ExactLine> withRushLine() => {'rush_yds': line('rush_yds', 100.5)};

  test('Higher and Lower candidates for every statistic in history', () {
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: historyWith(),
      linesByStatKey: withRushLine(),
    );
    // 3 stats × 2 directions.
    expect(picks.length, 6);
    for (final stat in ['rush_yds', 'rec_yds', 'pass_yds']) {
      final forStat = picks.where((p) => p.statKey == stat).toList();
      expect(forStat.length, 2, reason: 'both directions for $stat');
      expect(forStat.map((p) => p.direction).toSet(), {
        PropDirection.higher,
        PropDirection.lower,
      });
    }
  });

  test('defensible with exact line and n>=20 — shows the full contract', () {
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: historyWith(),
      linesByStatKey: withRushLine(),
    );
    final higher = picks.firstWhere((p) =>
        p.statKey == 'rush_yds' && p.direction == PropDirection.higher);
    expect(higher.isDefensible, isTrue);
    final e = higher.estimate!;
    expect(e.sampleSize, 24);
    expect(e.winPct + e.pushPct + e.losePct, closeTo(100, 1e-9));
    expect(kWinPctDefinition, contains('not a guarantee') | contains('estimate'));
    // Every contract field present.
    expect(higher.line!.source, isNotEmpty);
    expect(higher.line!.sourceTimestamp, isNotNull);
    expect(higher.historySource, isNotEmpty);
    expect(higher.historyFetchedAt, isNotNull);
    expect(higher.quality, isNotNull);
    expect(higher.supportingFactors, isNotEmpty);
    expect(higher.factors, isNotEmpty); // includes descriptive + opposing
    expect(higher.unknowns, isA<List<String>>());
  });

  test('without a source-backed line rows are withheld — never invented', () {
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: historyWith(),
      linesByStatKey: const {},
    );
    for (final p in picks) {
      expect(p.isDefensible, isFalse);
      expect(p.withheldReason, WithheldReason.noSourceBackedLine);
      expect(p.displayProbability, contains('Probability unavailable'));
      expect(p.estimate, isNull);
    }
  });

  test('n<20 is withheld with insufficient observations', () {
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: historyWith(),
      linesByStatKey: {'rec_yds': line('rec_yds', 45.5)},
    );
    for (final p in picks.where((p) => p.statKey == 'rec_yds')) {
      expect(p.isDefensible, isFalse);
      expect(p.withheldReason, WithheldReason.insufficientObservations);
    }
  });

  test('stale line is disclosed as unknown/stale, not silently used', () {
    final oldClock = FixedClock(DateTime.utc(2026, 10, 10));
    final gen = PlayerGenerator(engine: ProbabilityEngine(clock: oldClock));
    final picks = gen.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: historyWith(),
      linesByStatKey: withRushLine(),
    );
    final higher = picks.firstWhere((p) =>
        p.statKey == 'rush_yds' && p.direction == PropDirection.higher);
    expect(higher.unknowns.join(' '), contains('stale'));
  });

  test('exact line values are preserved verbatim', () {
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: historyWith(),
      linesByStatKey: withRushLine(),
    );
    final higher = picks.firstWhere((p) =>
        p.statKey == 'rush_yds' && p.direction == PropDirection.higher);
    expect(higher.line!.value, 100.5);
  });
}
