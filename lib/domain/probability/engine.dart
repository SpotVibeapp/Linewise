import '../../core/clock.dart';
import '../models/evidence.dart';
import '../models/exact_line.dart';
import '../models/pick.dart';
import '../models/player_history.dart';
import '../models/slate_date.dart';
import 'estimator.dart';
import 'factor_groups.dart';

/// Context facts about the upcoming game, all source-tagged when present.
class GameContext {
  GameContext({
    this.gameDescription,
    this.isHome,
    this.restDays,
    this.travelKm,
    this.scheduleNote,
    this.venueNote,
    this.weatherNote,
    this.injuryNotes = const [],
    this.availabilityNote,
    this.roleNote,
    this.workloadNote,
    this.matchupNote,
    this.paceVolumeNote,
    this.opponentStrengthNote,
    this.lineupNote,
    this.unavailableNotes = const [],
  });

  final String? gameDescription;
  final bool? isHome;
  final int? restDays;
  final double? travelKm;
  final String? scheduleNote;
  final String? venueNote;
  final String? weatherNote;
  final List<String> injuryNotes;
  final String? availabilityNote;
  final String? roleNote;
  final String? workloadNote;
  final String? matchupNote;
  final String? paceVolumeNote;
  final String? opponentStrengthNote;
  final String? lineupNote;
  final List<String> unavailableNotes;
}

/// Builds the full candidate row (or withheld row) for one direction of one
/// statistic, enforcing the display contract.
class ProbabilityEngine {
  ProbabilityEngine({
    required this.clock,
    this.estimator = const EmpiricalEstimator(),
  });

  final Clock clock;
  final EmpiricalEstimator estimator;

  PickCandidate buildCandidate({
    required String id,
    required String subjectId,
    required String subjectName,
    required String sportId,
    required SlateDate slateDate,
    required MarketType market,
    required String statKey,
    required String statDisplayName,
    required PropDirection direction,
    required SubjectHistory history,
    required ExactLine? line,
    List<Factor> extraFactors = const [],
    GameContext context = const GameContext(),
  }) {
    final now = clock.now();
    final values = history.validValuesByStat()[statKey] ?? const <double>[];
    final n = values.length;
    final unknowns = <String>[...context.unavailableNotes];

    // Staleness disclosures (never silently drop or alter data).
    if (line != null) {
      final age = line.ageAt(now);
      if (age.inHours >= 24) {
        unknowns.add(
            'Line is stale: observed ${age.inHours}h ago (${line.sourceTimestamp.toIso8601String()}).');
      }
    }
    final historyAge = now.difference(history.fetchedAt);
    if (historyAge.inDays >= 7) {
      unknowns.add(
          'Player history last fetched ${historyAge.inDays}d ago and may be stale.');
    }

    // Context factors with unique signal ids; descriptive-only where the
    // signal is already inside the baseline (no double-counting).
    final factors = <Factor>[
      Factor(
        signalId: 'baseline.sample',
        group: FactorGroup.baseline,
        stance: FactorStance.neutral,
        label: 'Baseline sample',
        detail:
            'Empirical distribution over the last $n valid observations (ties: Push/Tie).',
        source: history.source,
        observedAt: history.fetchedAt,
        descriptiveOnly: true,
      ),
      if (line != null)
        Factor(
          signalId: 'market.exact_line_history',
          group: FactorGroup.marketHistory,
          stance: _hitRateStance(values, line.value, direction),
          label: 'Exact-line history',
          detail: line.value == null
              ? 'Market has no numeric line (moneyline); evaluated on game results.'
              : 'Historical finishes vs the exact line ${_fmt(line.value!)}: '
                  '${_hitText(values, line.value!, direction)}. Folded into the '
                  'baseline — not adjusted again.',
          source: line.source,
          observedAt: line.sourceTimestamp,
          descriptiveOnly: true,
        ),
      Factor(
        signalId: 'role.recent_form',
        group: FactorGroup.roleUsage,
        stance: _recentFormStance(values, line),
        label: 'Recent form',
        detail: _recentFormText(values, line),
        source: history.source,
        observedAt: history.fetchedAt,
        descriptiveOnly: true,
      ),
      Factor(
        signalId: 'role.player_quality',
        group: FactorGroup.roleUsage,
        stance: FactorStance.neutral,
        label: 'Player strengths/weaknesses',
        detail: _qualityText(values),
        source: history.source,
        observedAt: history.fetchedAt,
        descriptiveOnly: true,
      ),
      ..._contextFactors(context, now),
      ...extraFactors,
    ];

    // Withheld cases — always exported as rows. A moneyline has no numeric
    // line value; its source-backed side selection is the line.
    final bool needsNumericLine = !isMoneyline;
    if (line == null || (needsNumericLine && line.value == null)) {
      return _withheld(
        id: id,
        subjectId: subjectId,
        subjectName: subjectName,
        sportId: sportId,
        slateDate: slateDate,
        market: market,
        statKey: statKey,
        statDisplayName: statDisplayName,
        direction: direction,
        line: originalLine ?? line,
        history: history,
        generatedAt: now,
        factors: factors,
        unknowns: unknowns,
        reason: WithheldReason.noSourceBackedLine,
        context: context,
      );
    }
    if (n < kMinObservations) {
      return _withheld(
        id: id,
        subjectId: subjectId,
        subjectName: subjectName,
        sportId: sportId,
        slateDate: slateDate,
        market: market,
        statKey: statKey,
        statDisplayName: statDisplayName,
        direction: direction,
        line: line,
        history: history,
        generatedAt: now,
        factors: factors,
        unknowns: unknowns,
        reason: WithheldReason.insufficientObservations,
        context: context,
      );
    }

    final guard = DoubleCountGuard();
    final adjustmentPP = applyAdjustmentPolicy(factors, guard);
    final ProbabilityEstimate? estimate;
    if (isMoneyline) {
      estimate = estimator.estimateBinaryWins(
        wonGames: values.map((v) => v == 1).toList(),
        direction: direction,
        adjustmentPP: adjustmentPP,
      );
    } else {
      estimate = estimator.estimate(
        values: values,
        line: line.value!,
        direction: direction,
        adjustmentPP: adjustmentPP,
      );
    }
    if (estimate == null) {
      return _withheld(
        id: id,
        subjectId: subjectId,
        subjectName: subjectName,
        sportId: sportId,
        slateDate: slateDate,
        market: market,
        statKey: statKey,
        statDisplayName: statDisplayName,
        direction: direction,
        line: originalLine ?? line,
        history: history,
        generatedAt: now,
        factors: factors,
        unknowns: unknowns,
        reason: WithheldReason.insufficientObservations,
        context: context,
      );
    }

    final quality = scoreEvidenceQuality(
      sampleSize: n,
      historyFetchedAt: history.fetchedAt,
      lineObservedAt: line.sourceTimestamp,
      now: now,
      distinctFactorSources: factors
          .where((f) => !f.descriptiveOnly)
          .map((f) => f.source)
          .toSet()
          .length,
      unknownCount: unknowns.length,
    );

    return PickCandidate(
      id: id,
      subjectName: subjectName,
      subjectId: subjectId,
      sportId: sportId,
      slateDate: slateDate,
      market: market,
      statKey: statKey,
      statDisplayName: statDisplayName,
      direction: direction,
      line: originalLine ?? line,
      status: PickStatus.defensible,
      estimate: estimate,
      quality: quality,
      factors: List.unmodifiable(factors),
      unknowns: List.unmodifiable(unknowns),
      historySource: history.source,
      historyFetchedAt: history.fetchedAt,
      gameDescription: context.gameDescription,
      pushLabel: isMoneyline ? 'Push/Tie: not applicable' : 'Push/Tie',
      generatedAt: now,
    );
  }

  PickCandidate _withheld({
    required String id,
    required String subjectId,
    required String subjectName,
    required String sportId,
    required SlateDate slateDate,
    required MarketType market,
    required String statKey,
    required String statDisplayName,
    required PropDirection direction,
    required ExactLine? line,
    required SubjectHistory history,
    required DateTime generatedAt,
    required List<Factor> factors,
    required List<String> unknowns,
    required WithheldReason reason,
    required GameContext context,
  }) =>
      PickCandidate(
        id: id,
        subjectName: subjectName,
        subjectId: subjectId,
        sportId: sportId,
        slateDate: slateDate,
        market: market,
        statKey: statKey,
        statDisplayName: statDisplayName,
        direction: direction,
        line: line,
        status: PickStatus.withheld,
        withheldReason: reason,
        factors: List.unmodifiable(factors),
        unknowns: List.unmodifiable(unknowns),
        historySource: history.source,
        historyFetchedAt: history.fetchedAt,
        gameDescription: context.gameDescription,
        pushLabel: market == MarketType.moneyline
            ? 'Push/Tie: not applicable'
            : 'Push/Tie',
        generatedAt: generatedAt,
      );

  List<Factor> _contextFactors(GameContext c, DateTime now) {
    final out = <Factor>[];
    void add(String signalId, FactorGroup group, FactorStance stance,
        String label, String detail, String source, double adj) {
      out.add(Factor(
        signalId: signalId,
        group: group,
        stance: stance,
        label: label,
        detail: detail,
        source: source,
        observedAt: now,
        adjustmentPP: adj,
      ));
    }

    if (c.injuryNotes.isNotEmpty || c.availabilityNote != null) {
      final detail = [
        ...c.injuryNotes,
        if (c.availabilityNote != null) c.availabilityNote!,
      ].join(' ');
      final opposed = RegExp(r'out|doubtful|ruled out|unavailable|questionable',
              caseSensitive: false)
          .hasMatch(detail);
      add(
        'availability.injuries_availability',
        FactorGroup.availabilityHealth,
        opposed ? FactorStance.opposing : FactorStance.supporting,
        'Injuries & availability',
        detail,
        'public injury report',
        opposed ? -4.0 : 2.0,
      );
    }
    if (c.lineupNote != null) {
      add(
          'availability.lineup_changes',
          FactorGroup.availabilityHealth,
          FactorStance.neutral,
          'Lineup changes',
          c.lineupNote!,
          'lineup feed',
          0.0);
    }
    if (c.roleNote != null) {
      final favorable =
          RegExp(r'expanded|starter|more snaps|increased', caseSensitive: false)
              .hasMatch(c.roleNote!);
      add(
        'role.role_change',
        FactorGroup.roleUsage,
        favorable ? FactorStance.supporting : FactorStance.opposing,
        'Role',
        c.roleNote!,
        'role analysis',
        favorable ? 3.0 : -3.0,
      );
    }
    if (c.workloadNote != null) {
      add('role.workload', FactorGroup.roleUsage, FactorStance.supporting,
          'Workload', c.workloadNote!, 'workload analysis', 2.0);
    }
    if (c.matchupNote != null) {
      final favorable = RegExp(r'favourable|favorable|soft|weak|good matchup',
              caseSensitive: false)
          .hasMatch(c.matchupNote!);
      add(
        'matchup.opponent',
        FactorGroup.matchupGame,
        favorable ? FactorStance.supporting : FactorStance.opposing,
        'Opponent matchup',
        c.matchupNote!,
        'matchup analysis',
        favorable ? 4.0 : -4.0,
      );
    }
    if (c.paceVolumeNote != null) {
      add('matchup.pace_volume', FactorGroup.matchupGame, FactorStance.neutral,
          'Pace & play volume', c.paceVolumeNote!, 'team profile', 2.0);
    }
    if (c.opponentStrengthNote != null) {
      add(
          'matchup.team_strength',
          FactorGroup.matchupGame,
          FactorStance.neutral,
          'Player/team strength vs opponent',
          c.opponentStrengthNote!,
          'team profile',
          0.0);
    }
    if (c.isHome != null) {
      add(
        'situational.home_away',
        FactorGroup.situational,
        c.isHome! ? FactorStance.supporting : FactorStance.opposing,
        'Home/away',
        c.isHome! ? 'Home game.' : 'Away game.',
        'schedule',
        c.isHome! ? 2.0 : -1.0,
      );
    }
    if (c.restDays != null) {
      final rest = c.restDays!;
      add(
        'situational.rest',
        FactorGroup.situational,
        rest >= 3 ? FactorStance.supporting : FactorStance.neutral,
        'Rest',
        '$rest days rest.',
        'schedule',
        rest >= 3 ? 1.5 : (rest <= 2 ? -1.5 : 0.0),
      );
    }
    if (c.travelKm != null) {
      final heavy = c.travelKm! > 1500;
      add(
          'situational.travel',
          FactorGroup.situational,
          heavy ? FactorStance.opposing : FactorStance.neutral,
          'Travel',
          'Travel ≈ ${c.travelKm!.round()} km.',
          'venue locations',
          heavy ? -1.5 : 0.0);
    }
    if (c.scheduleNote != null) {
      add('situational.schedule', FactorGroup.situational, FactorStance.neutral,
          'Schedule spot', c.scheduleNote!, 'schedule', -1.5);
    }
    if (c.venueNote != null) {
      add('environment.venue', FactorGroup.environment, FactorStance.neutral,
          'Venue', c.venueNote!, 'venue data', 0.0);
    }
    if (c.weatherNote != null) {
      final adverse = RegExp(r'rain|snow|wind|storm|heat|cold|extreme',
              caseSensitive: false)
          .hasMatch(c.weatherNote!);
      add(
        'environment.weather',
        FactorGroup.environment,
        adverse ? FactorStance.opposing : FactorStance.neutral,
        'Weather',
        c.weatherNote!,
        'Open-Meteo',
        adverse ? -3.0 : 0.0,
      );
    }
    return out;
  }

  FactorStance _hitRateStance(
      List<double> values, double? line, PropDirection d) {
    if (line == null || values.isEmpty) return FactorStance.neutral;
    final wins = values
        .where((v) => d == PropDirection.higher ? v > line : v < line)
        .length;
    final rate = wins / values.length;
    if (rate >= 0.55) return FactorStance.supporting;
    if (rate <= 0.45) return FactorStance.opposing;
    return FactorStance.neutral;
  }

  String _hitText(List<double> values, double line, PropDirection d) {
    if (values.isEmpty) return 'no observations';
    final wins = values
        .where((v) => d == PropDirection.higher ? v > line : v < line)
        .length;
    final pushes = values.where((v) => v == line).length;
    return '$wins of ${values.length} above/below as needed, $pushes ties';
  }

  FactorStance _recentFormStance(List<double> values, ExactLine? line) {
    if (values.length < 6 || line?.value == null) return FactorStance.neutral;
    final newestFirst = values.reversed.toList();
    final recent = newestFirst.take(3).toList();
    final older = newestFirst.skip(3).take(10).toList();
    if (older.isEmpty) return FactorStance.neutral;
    final recentAvg = recent.reduce((a, b) => a + b) / recent.length;
    final olderAvg = older.reduce((a, b) => a + b) / older.length;
    if (recentAvg > olderAvg * 1.05) return FactorStance.supporting;
    if (recentAvg < olderAvg * 0.95) return FactorStance.opposing;
    return FactorStance.neutral;
  }

  String _recentFormText(List<double> values, ExactLine? line) {
    if (values.length < 4) return 'Not enough games for a recent-form read.';
    final recent = values.reversed.take(3).toList();
    final avg = recent.reduce((a, b) => a + b) / recent.length;
    return 'Last ${recent.length} games avg ${_fmt(avg)} (newest first). Folded '
        'into the baseline — not adjusted again.';
  }

  String _qualityText(List<double> values) {
    if (values.isEmpty) return 'No source-backed observations yet.';
    final sorted = [...values]..sort();
    final median = sorted[sorted.length ~/ 2];
    final avg = values.reduce((a, b) => a + b) / values.length;
    return 'Descriptive only (already inside the baseline): median ${_fmt(median)}, '
        'mean ${_fmt(avg)} over ${values.length} games.';
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
}
