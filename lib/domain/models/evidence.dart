/// Evidence: factors, double-count guard, quality rubric.
///
/// Every factor carries exactly one [signalId]; a pick may register each
/// signal at most once ([DoubleCountGuard]). Factors marked [descriptiveOnly]
/// are already reflected in the baseline distribution and are shown for the
/// reader but never receive an adjustment ("avoid double-counting").
library;

/// How evidence a factor draws on.
enum FactorGroup {
  /// Baseline sample itself (history vs the exact line).
  baseline,

  /// Injuries, availability, lineup changes (grouped as one health/availability
  /// adjustment so they cannot be double-counted against each other).
  availabilityHealth,

  /// Role and workload (including recent form — descriptive only).
  roleUsage,

  /// Opponent matchup: defense vs position, team offense/defense, pace, volume.
  matchupGame,

  /// Home/away, rest, travel, schedule spot.
  situational,

  /// Venue and weather.
  environment,

  /// Exact-line history (folded into the baseline; descriptive only).
  marketHistory,
}

enum FactorStance {
  /// Pushes toward the pick.
  supporting,

  /// Pushes against the pick (weakness / opposing factor).
  opposing,

  /// Neutral disclosure (e.g. descriptive-only notes).
  neutral,
}

class Factor {
  Factor({
    required this.signalId,
    required this.group,
    required this.stance,
    required this.label,
    required this.detail,
    required this.source,
    required this.observedAt,
    this.adjustmentPP = 0.0,
    this.descriptiveOnly = false,
  }) : assert(
          descriptiveOnly ? adjustmentPP == 0.0 : true,
          'descriptive-only factors must not carry adjustments (double-counting)',
        );

  /// Unique-within-a-pick identifier of the underlying signal.
  final String signalId;
  final FactorGroup group;
  final FactorStance stance;
  final String label;
  final String detail;
  final String source;
  final DateTime observedAt;

  /// Adjustment in percentage points applied to the win probability.
  /// Capped per group and overall by the engine.
  final double adjustmentPP;

  /// True when the signal is already inside the baseline distribution
  /// (recent form, exact-line history, overall player quality). Never adjusted.
  final bool descriptiveOnly;

  Map<String, Object?> toMap() => {
        'signalId': signalId,
        'group': group.name,
        'stance': stance.name,
        'label': label,
        'detail': detail,
        'source': source,
        'observedAt': observedAt.toIso8601String(),
        'adjustmentPP': adjustmentPP,
        'descriptiveOnly': descriptiveOnly,
      };
}

/// Rejects any attempt to register the same signal twice for one pick.
class DoubleCountGuard {
  final Set<String> _seen = <String>{};

  void register(Factor factor) {
    if (!_seen.add(factor.signalId)) {
      throw StateError(
        'Double-counting rejected: signal "${factor.signalId}" already used',
      );
    }
  }

  void registerAll(Iterable<Factor> factors) => factors.forEach(register);

  bool get isEmpty => _seen.isEmpty;

  Set<String> get seenSignals => Set.unmodifiable(_seen);
}

/// Evidence quality rubric (documented in the UI):
///
/// * sample size `n >= 30` → 2 points; `20 <= n < 30` → 1 point
/// * history data fetched within 14 days → 1 point
/// * exact line observed within 24 hours → 1 point
/// * at least two distinct non-baseline factor sources → 1 point
/// * at most one unknown/stale disclosure → 1 point
///
/// High: ≥4 points, Medium: 2–3, Low: ≤1.
enum EvidenceQuality {
  high,
  medium,
  low;

  String get label {
    switch (this) {
      case EvidenceQuality.high:
        return 'High';
      case EvidenceQuality.medium:
        return 'Medium';
      case EvidenceQuality.low:
        return 'Low';
    }
  }
}

EvidenceQuality scoreEvidenceQuality({
  required int sampleSize,
  required DateTime historyFetchedAt,
  required DateTime? lineObservedAt,
  required DateTime now,
  required int distinctFactorSources,
  required int unknownCount,
}) {
  var points = 0;
  if (sampleSize >= 30) {
    points += 2;
  } else if (sampleSize >= 20) {
    points += 1;
  }
  if (now.difference(historyFetchedAt).inDays <= 14) points += 1;
  if (lineObservedAt != null &&
      now.difference(lineObservedAt).inHours <= 24 &&
      now.isAfter(lineObservedAt.subtract(const Duration(days: 1)))) {
    points += 1;
  }
  if (distinctFactorSources >= 2) points += 1;
  if (unknownCount <= 1) points += 1;
  if (points >= 4) return EvidenceQuality.high;
  if (points >= 2) return EvidenceQuality.medium;
  return EvidenceQuality.low;
}
