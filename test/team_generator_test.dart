import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/core/clock.dart';
import 'package:linewise/domain/generation/team_generator.dart';
import 'package:linewise/domain/models/exact_line.dart';
import 'package:linewise/domain/models/pick.dart';
import 'package:linewise/domain/models/slate_date.dart';
import 'package:linewise/domain/probability/engine.dart';

ExactLine teamLine(MarketType market, String stat, double? value) => ExactLine(
      id: 't-$stat',
      market: market,
      statKey: stat,
      statDisplayName: stat,
      value: value,
      teamId: 'Baltimore Ravens',
      source: 'The Odds API/nfl/draftkings/$stat',
      sourceTimestamp: DateTime.utc(2026, 9, 24, 11),
    );

void main() {
  final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
  final gen = TeamGenerator(engine: ProbabilityEngine(clock: clock));
  final slate = SlateDate.parse('2026-09-24');

  // 25 games: 15 wins, 10 losses. Margins 8 home: +10..; totals vary.
  final history = TeamHistory(
    wonGames: [for (var i = 0; i < 25; i++) i < 15],
    margins: [for (var i = 0; i < 25; i++) i.isEven ? 7.0 : -3.0],
    totals: [for (var i = 0; i < 25; i++) 44.0 + (i % 5)],
    gameDates: [for (var i = 0; i < 25; i++) DateTime.utc(2026, 8, 1 + i)],
    source: 'ESPN team gamelog',
    fetchedAt: DateTime.utc(2026, 9, 24, 10),
  );

  List<PickCandidate> generate({
    ExactLine? ml,
    ExactLine? sp,
    ExactLine? tot,
  }) =>
      gen.generate(
        teamId: 'bal',
        teamName: 'Baltimore Ravens',
        sportId: 'nfl',
        slateDate: slate,
        history: history,
        moneylineLine: ml,
        spreadLine: sp,
        totalLine: tot,
        moneylineSide: PropDirection.higher,
        spreadSide: PropDirection.higher,
        totalSide: PropDirection.higher,
      );

  test('moneyline is defensible with source-backed side and n>=20', () {
    final picks =
        generate(ml: teamLine(MarketType.moneyline, 'moneyline', null));
    final ml = picks.firstWhere((p) => p.statKey == 'moneyline');
    expect(ml.isDefensible, isTrue);
    expect(ml.estimate!.winPct, closeTo(60.0, 1e-9)); // 15/25
    expect(ml.estimate!.pushPct, 0); // moneyline has no push/tie
    expect(ml.pushLabel, contains('not applicable'));
  });

  test('spread with an exact line: covers vs fails, pushes on exact ties', () {
    // Team margins are 7.0 or -3.0. Spread line team -3 → threshold margin > 3
    // for "higher" (cover). margin == 3 would push — construct that case.
    final pushyHistory = TeamHistory(
      wonGames: [for (var i = 0; i < 22; i++) i < 14],
      margins: [
        for (var i = 0; i < 22; i++) i < 5 ? 3.0 : (i.isEven ? 10.0 : -1.0)
      ],
      totals: [for (var i = 0; i < 22; i++) 48.0],
      gameDates: [for (var i = 0; i < 22; i++) DateTime.utc(2026, 8, 1 + i)],
      source: 'ESPN team gamelog',
      fetchedAt: DateTime.utc(2026, 9, 24, 10),
    );
    final picks = gen.generate(
      teamId: 'bal',
      teamName: 'Baltimore Ravens',
      sportId: 'nfl',
      slateDate: slate,
      history: pushyHistory,
      moneylineLine: null,
      spreadLine: teamLine(MarketType.spread, 'spread', -3),
      totalLine: null,
      moneylineSide: PropDirection.higher,
      spreadSide: PropDirection.higher,
      totalSide: PropDirection.higher,
    );
    final spread = picks.firstWhere((p) => p.statKey == 'spread');
    expect(spread.isDefensible, isTrue);
    expect(spread.estimate!.observedPushes, 5); // 5 games with margin == 3
    expect(spread.estimate!.pushPct, closeTo(5 / 22 * 100, 1e-9));
  });

  test('totals: over/under with push on exact ties', () {
    final pushy = TeamHistory(
      wonGames: [for (var i = 0; i < 20; i++) i < 10],
      margins: [for (var i = 0; i < 20; i++) 1.0],
      totals: [
        for (var i = 0; i < 20; i++) i < 4 ? 48.0 : (i.isEven ? 52.0 : 41.0)
      ],
      gameDates: [for (var i = 0; i < 20; i++) DateTime.utc(2026, 8, 1 + i)],
      source: 'ESPN team gamelog',
      fetchedAt: DateTime.utc(2026, 9, 24, 10),
    );
    final picks = gen.generate(
      teamId: 'bal',
      teamName: 'Baltimore Ravens',
      sportId: 'nfl',
      slateDate: slate,
      history: pushy,
      moneylineLine: null,
      spreadLine: null,
      totalLine: teamLine(MarketType.total, 'total', 48),
      moneylineSide: PropDirection.higher,
      spreadSide: PropDirection.higher,
      totalSide: PropDirection.higher,
    );
    final total = picks.firstWhere((p) => p.statKey == 'total');
    expect(total.isDefensible, isTrue);
    expect(total.estimate!.observedPushes, 4);
  });

  test('without lines every team market is withheld — no invented lines', () {
    final picks = generate();
    expect(picks.length, 3);
    for (final p in picks) {
      expect(p.isDefensible, isFalse);
      expect(p.withheldReason, WithheldReason.noSourceBackedLine);
      expect(p.displayProbability, contains('Probability unavailable'));
    }
  });
}
