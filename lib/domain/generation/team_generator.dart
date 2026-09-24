import '../../core/ids.dart';
import '../models/exact_line.dart';
import '../models/pick.dart';
import '../models/player_history.dart';
import '../models/slate_date.dart';
import '../probability/engine.dart';

/// Team moneyline / spread / total candidates.
///
/// History values are game-level and source-backed:
/// * moneyline: win/loss record per game (encoded as 1/0 observations)
/// * spread: point margins (team minus opponent); "Higher" means the team
///   covers its listed spread (margin strictly greater than minus the spread
///   value); an exact tie to the spread is a push
/// * total: combined scores; an exact tie to the total is a push
///
/// Only source-backed exact lines are ever used; with no line the rows are
/// withheld with "Probability unavailable".
class TeamGenerator {
  TeamGenerator({required this.engine});

  final ProbabilityEngine engine;

  List<PickCandidate> generate({
    required String teamId,
    required String teamName,
    required String sportId,
    required SlateDate slateDate,
    required TeamHistory history,
    required ExactLine? moneylineLine,
    required ExactLine? spreadLine,
    required ExactLine? totalLine,
    required PropDirection moneylineSide,
    required PropDirection spreadSide,
    required PropDirection totalSide,
    GameContext context = const GameContext(),
  }) {
    return [
      _build(
        teamId: teamId,
        teamName: teamName,
        sportId: sportId,
        slateDate: slateDate,
        statKey: 'moneyline',
        statDisplayName: 'Moneyline (win the game)',
        market: MarketType.moneyline,
        direction: moneylineSide,
        line: moneylineLine,
        history: history,
        observations: [
          for (var i = 0; i < history.wonGames.length; i++)
            StatObservation(
              statKey: 'moneyline',
              value: history.wonGames[i] ? 1 : 0,
              gameDate: i < history.gameDates.length
                  ? history.gameDates[i]
                  : history.fetchedAt,
              source: history.source,
            )
        ],
        context: context,
      ),
      _build(
        teamId: teamId,
        teamName: teamName,
        sportId: sportId,
        slateDate: slateDate,
        statKey: 'spread',
        statDisplayName: 'Spread (margin vs line)',
        market: MarketType.spread,
        direction: spreadSide,
        line: spreadLine,
        history: history,
        // "Higher" on the spread means covering: evaluate the raw margin
        // against the threshold -spreadValue.
        threshold: spreadLine?.value == null ? null : -spreadLine!.value!,
        observations: [
          for (final m in history.margins)
            StatObservation(
              statKey: 'spread',
              value: m,
              gameDate: history.fetchedAt,
              source: history.source,
            )
        ],
        context: context,
      ),
      _build(
        teamId: teamId,
        teamName: teamName,
        sportId: sportId,
        slateDate: slateDate,
        statKey: 'total',
        statDisplayName: 'Total (combined score)',
        market: MarketType.total,
        direction: totalSide,
        line: totalLine,
        history: history,
        observations: [
          for (final t in history.totals)
            StatObservation(
              statKey: 'total',
              value: t,
              gameDate: history.fetchedAt,
              source: history.source,
            )
        ],
        context: context,
      ),
    ];
  }

  PickCandidate _build({
    required String teamId,
    required String teamName,
    required String sportId,
    required SlateDate slateDate,
    required String statKey,
    required String statDisplayName,
    required MarketType market,
    required PropDirection direction,
    required ExactLine? line,
    required TeamHistory history,
    required List<StatObservation> observations,
    double? threshold,
    required GameContext context,
  }) {
    // For spreads the "line" the engine sees is the derived margin threshold,
    // wrapped in the same source-backed ExactLine (value preserved in `line`).
    ExactLine? engineLine = line;
    if (market == MarketType.spread && line != null && threshold != null) {
      engineLine = ExactLine(
        id: line.id,
        market: MarketType.spread,
        statKey: line.statKey,
        statDisplayName: line.statDisplayName,
        value: threshold,
        source: line.source,
        sourceTimestamp: line.sourceTimestamp,
        teamId: line.teamId,
        providerEventId: line.providerEventId,
        providerBookmaker: line.providerBookmaker,
        raw: line.raw,
      );
    }

    final subjectHistory = SubjectHistory(
      subjectId: teamId,
      subjectName: teamName,
      observations: observations,
      source: history.source,
      fetchedAt: history.fetchedAt,
      isTeam: true,
    );

    return engine.buildCandidate(
      id: newId('pick'),
      subjectId: teamId,
      subjectName: teamName,
      sportId: sportId,
      slateDate: slateDate,
      market: market,
      statKey: statKey,
      statDisplayName: statDisplayName,
      direction: direction,
      history: subjectHistory,
      line: engineLine,
      originalLine: line,
      context: context,
    );
  }
}

/// Game-level history for a team (source-backed).
class TeamHistory {
  TeamHistory({
    required this.wonGames,
    required this.margins,
    required this.totals,
    required this.gameDates,
    required this.source,
    required this.fetchedAt,
  });

  /// Chronological game results (true = win).
  final List<bool> wonGames;

  /// Point margin (team minus opponent) per game.
  final List<double> margins;

  /// Combined score per game.
  final List<double> totals;

  final List<DateTime> gameDates;
  final String source;
  final DateTime fetchedAt;
}
