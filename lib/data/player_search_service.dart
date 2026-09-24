import '../domain/models/exact_line.dart';
import '../domain/models/player_history.dart';
import '../domain/models/slate_date.dart';
import '../domain/sports.dart';
import 'espn_client.dart';
import 'line_repository.dart';

/// Result of the safe player search.
///
/// [loadedLines] come from **loaded-line filtering** (local, free).
/// [athletes] and [history] come from **free public player-history analysis**
/// (ESPN). Nothing here can ever cost The Odds API credits — this service has
/// no reference to the provider client at all (by design; see tests).
class PlayerSearchResult {
  PlayerSearchResult({
    required this.query,
    required this.athletes,
    required this.loadedLines,
    this.history,
    this.freeAnalysisNote,
  });

  final String query;
  final List<AthleteSummary> athletes;
  final List<ExactLine> loadedLines;
  final SubjectHistory? history;
  final String? freeAnalysisNote;

  bool get hasNoMatches => athletes.isEmpty && loadedLines.isEmpty;

  String get emptyStateMessage => hasNoMatches
      ? 'No selections matched "$query" among loaded lines, and the free public '
        'search found no players. Try a different spelling. No provider credits '
        'were used.'
      : 'Free public player-history analysis is available even when zero '
        'provider lines are loaded. Exact provider lines depend on provider '
        'coverage and quota.';
}

/// The known-problem fix: searching a player (e.g. "Derrick Henry") must
/// never silently make a billable request and must still offer free public
/// player-history analysis when zero provider lines are loaded.
///
/// This class performs exactly two classes of work:
/// 1. loaded-line filtering (local)
/// 2. free public player-history analysis (ESPN)
///
/// It is structurally incapable of spending The Odds API credits.
class PlayerSearchService {
  PlayerSearchService({
    required this.esp,
    required this.lineRepository,
  });

  final EspnClient esp;
  final LineRepository lineRepository;

  /// Local + free public search. Zero cost. Never billable.
  Future<PlayerSearchResult> search(String query) async {
    final local = lineRepository.filterLoaded(playerName: query);
    final localTeams = lineRepository.filterLoaded(teamId: query);
    final athletes = await esp.searchAthletes(query);
    return PlayerSearchResult(
      query: query,
      athletes: athletes,
      loadedLines: [...local, ...{for (final l in localTeams) l.id: l}.values],
      freeAnalysisNote: local.isEmpty
          ? 'Zero provider lines are loaded for this search. You can still run '
            'free public player-history analysis below — it does not use Odds '
            'API credits. Exact provider lines require a separate, explicitly '
            'approved billable request and depend on provider coverage and quota.'
          : 'Matched ${local.length} loaded line(s) locally (loaded-line '
            'filtering — no network, no cost).',
    );
  }

  /// Free public player-history analysis (ESPN gamelog). Zero cost.
  ///
  /// Offered automatically when a search returns zero loaded lines — this is
  /// the Derrick Henry fix: useful analysis without spending credits.
  /// Never throws: an empty history is returned when public data is missing.
  Future<SubjectHistory> analyzeHistory({
    required SportLeague sport,
    required AthleteSummary athlete,
  }) =>
      esp.fetchPlayerGameLog(
        sport: sport,
        athleteId: athlete.id,
        athleteName: athlete.displayName,
      );

  /// Free public slate lookup (ESPN). Zero cost.
  Future<List<SlateGame>> slate(SportLeague sport, SlateDate date) =>
      esp.fetchSlate(sport: sport, slateDate: date);
}
