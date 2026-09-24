import '../../core/ids.dart';
import '../models/exact_line.dart';
import '../models/pick.dart';
import '../models/player_history.dart';
import '../models/slate_date.dart';
import '../probability/engine.dart';

/// Candidate stat keys and display names understood for player props.
///
/// "Higher/Lower candidates for every statistic with at least 20 valid
/// observations": the generator walks every statistic present in the
/// source-backed history, emits BOTH directions for each, and withholds the
/// probability (exported as a withheld row) whenever the contract is not met.
const Map<String, String> kStatDisplayNames = {
  'rush_yds': 'Rush Yards',
  'rush_att': 'Rush Attempts',
  'rec_yds': 'Reception Yards',
  'receptions': 'Receptions',
  'rec_td': 'Reception TDs',
  'rush_td': 'Rush TDs',
  'pass_yds': 'Pass Yards',
  'pass_td': 'Pass TDs',
  'pass_att': 'Pass Attempts',
  'pass_completions': 'Pass Completions',
  'pass_int': 'Interceptions',
  'points': 'Points',
  'rebounds': 'Rebounds',
  'assists': 'Assists',
  'threes': '3-Pointers',
  'pra': 'Pts+Reb+Ast',
  'hits': 'Hits',
  'rbi': 'RBIs',
  'home_runs': 'Home Runs',
  'strikeouts': 'Strikeouts',
  'saves': 'Saves',
  'goals': 'Goals',
  'plus_minus': 'Plus/Minus',
};

String statDisplayName(String statKey) =>
    kStatDisplayNames[statKey] ?? statKey.replaceAll('_', ' ');

class PlayerGenerator {
  PlayerGenerator({required this.engine});

  final ProbabilityEngine engine;

  /// Generates Higher and Lower candidates for every statistic in [history].
  ///
  /// * [linesByStatKey] — exact provider/manual lines, when actually supplied.
  ///   When a statistic has no line, both directions are emitted as withheld
  ///   rows saying "Probability unavailable" (lines are never invented).
  /// * Statistics with `>= 20` valid observations and a line become defensible.
  List<PickCandidate> generate({
    required String subjectId,
    required String subjectName,
    required String sportId,
    required SlateDate slateDate,
    required SubjectHistory history,
    required Map<String, ExactLine> linesByStatKey,
    GameContext context = const GameContext(),
  }) {
    final out = <PickCandidate>[];
    final byStat = history.observationsByStat();
    final statKeys = byStat.keys.toList()..sort();

    for (final statKey in statKeys) {
      final line = linesByStatKey[statKey];
      for (final direction in PropDirection.values) {
        out.add(engine.buildCandidate(
          id: newId('pick'),
          subjectId: subjectId,
          subjectName: subjectName,
          sportId: sportId,
          slateDate: slateDate,
          market: MarketType.playerProp,
          statKey: statKey,
          statDisplayName: statDisplayName(statKey),
          direction: direction,
          history: history,
          line: line,
          context: context,
        ));
      }
    }
    return out;
  }
}
