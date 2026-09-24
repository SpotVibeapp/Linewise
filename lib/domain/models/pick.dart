import 'evidence.dart';
import 'exact_line.dart';
import 'slate_date.dart';

/// Definition of "win percentage", shown verbatim on every defensible pick.
const String kWinPctDefinition =
    'Win percentage = share of the last N valid, source-logged game observations '
    'in which the statistic finished strictly on the winning side of the exact '
    'listed line. Ties land in the Push/Tie percentage and are not counted as '
    'wins. Capped, disclosed context adjustments are applied once on top of the '
    'empirical baseline. It is an estimate with a 90% uncertainty interval — '
    'not a guarantee.';

/// Disclaimer shown wherever probabilities are displayed.
const String kNoGuaranteeDisclaimer =
    'Estimates only. Linewise never claims guaranteed accuracy, never places '
    'bets and never settles outcomes automatically.';

enum PickStatus {
  /// Probability could be computed from source-backed evidence.
  defensible,

  /// Row kept and exported, but probability withheld.
  withheld,
}

enum WithheldReason {
  /// No source-backed exact line exists for this statistic.
  noSourceBackedLine('Probability unavailable — no source-backed exact line'),

  /// Fewer than 20 valid observations.
  insufficientObservations(
      'Probability unavailable — fewer than 20 valid observations');

  const WithheldReason(this.label);

  final String label;
}

/// The result of the empirical engine for one direction.
class ProbabilityEstimate {
  ProbabilityEstimate({
    required this.pHigher,
    required this.pPush,
    required this.pLower,
    required this.winPct,
    required this.pushPct,
    required this.losePct,
    required this.interval90Low,
    required this.interval90High,
    required this.sampleSize,
    required this.adjustmentPP,
    required this.observedWins,
    required this.observedPushes,
    required this.observedLosses,
  });

  /// Outcome shares strictly above / equal to / below the line (baseline).
  final double pHigher;
  final double pPush;
  final double pLower;

  /// Final numbers for the chosen direction (baseline + capped adjustment).
  final double winPct;
  final double pushPct;
  final double losePct;

  /// 90% Wilson interval on the empirical win share (before adjustment).
  final double interval90Low;
  final double interval90High;
  final int sampleSize;
  final double adjustmentPP;

  /// Raw empirical counts backing the baseline.
  final int observedWins;
  final int observedPushes;
  final int observedLosses;

  Map<String, Object?> toMap() => {
        'pHigher': pHigher,
        'pPush': pPush,
        'pLower': pLower,
        'winPct': winPct,
        'pushPct': pushPct,
        'losePct': losePct,
        'interval90Low': interval90Low,
        'interval90High': interval90High,
        'sampleSize': sampleSize,
        'adjustmentPP': adjustmentPP,
        'observedWins': observedWins,
        'observedPushes': observedPushes,
        'observedLosses': observedLosses,
      };
}

/// One candidate row: a (subject, statistic, direction) triple.
///
/// Defensible rows carry a [ProbabilityEstimate] and must display every field
/// in the product contract. Withheld rows carry a [WithheldReason] and are
/// always exported.
class PickCandidate {
  PickCandidate({
    required this.id,
    required this.subjectName,
    required this.subjectId,
    required this.sportId,
    required this.slateDate,
    required this.market,
    required this.statKey,
    required this.statDisplayName,
    required this.direction,
    required this.line,
    required this.status,
    required this.generatedAt,
    required this.factors,
    required this.unknowns,
    this.withheldReason,
    this.estimate,
    this.quality,
    this.historySource,
    this.historyFetchedAt,
    this.gameDescription,
    this.pushLabel = 'Push/Tie',
  }) : assert(
          (status == PickStatus.defensible &&
                  estimate != null &&
                  line != null) ||
              (status == PickStatus.withheld && withheldReason != null),
          'defensible picks need an estimate and a line; withheld picks need a reason',
        );

  final String id;
  final String subjectName;
  final String subjectId;
  final String sportId;
  final SlateDate slateDate;
  final MarketType market;
  final String statKey;
  final String statDisplayName;
  final PropDirection direction;

  /// The exact line this pick is evaluated against (null ⇒ withheld).
  final ExactLine? line;

  final PickStatus status;
  final WithheldReason? withheldReason;
  final ProbabilityEstimate? estimate;
  final EvidenceQuality? quality;

  /// Supporting + opposing + neutral factors (each signal exactly once).
  final List<Factor> factors;

  /// Unknown or stale information disclosures.
  final List<String> unknowns;

  final String? historySource;
  final DateTime? historyFetchedAt;
  final String? gameDescription;

  /// Wording for the tie bucket (`Push/Tie`; `Push` for numeric lines).
  final String pushLabel;

  final DateTime generatedAt;

  bool get isDefensible => status == PickStatus.defensible;

  List<Factor> get supportingFactors =>
      factors.where((f) => f.stance == FactorStance.supporting).toList();

  List<Factor> get opposingFactors =>
      factors.where((f) => f.stance == FactorStance.opposing).toList();

  String get displayProbability =>
      isDefensible ? '' : (withheldReason?.label ?? 'Probability unavailable');

  Map<String, Object?> toMap() => {
        'id': id,
        'subjectName': subjectName,
        'subjectId': subjectId,
        'sportId': sportId,
        'slateDate': slateDate.iso,
        'market': market.name,
        'statKey': statKey,
        'statDisplayName': statDisplayName,
        'direction': direction.name,
        'line': line?.toMap(),
        'status': status.name,
        'withheldReason': withheldReason?.name,
        'estimate': estimate?.toMap(),
        'quality': quality?.name,
        'factors': factors.map((f) => f.toMap()).toList(),
        'unknowns': unknowns,
        'historySource': historySource,
        'historyFetchedAt': historyFetchedAt?.toIso8601String(),
        'gameDescription': gameDescription,
        'pushLabel': pushLabel,
        'generatedAt': generatedAt.toIso8601String(),
      };
}
