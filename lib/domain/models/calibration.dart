/// Manual outcome records and calibration reporting.
///
/// Outcomes are recorded **only** by the user, explicitly. There is no
/// automatic settlement anywhere in Linewise.
library;

enum ManualOutcomeValue {
  won,
  lost,
  push;

  String get label {
    switch (this) {
      case ManualOutcomeValue.won:
        return 'Won';
      case ManualOutcomeValue.lost:
        return 'Lost';
      case ManualOutcomeValue.push:
        return 'Push/Tie';
    }
  }
}

class ManualOutcome {
  ManualOutcome({
    required this.pickId,
    required this.outcome,
    required this.recordedAt,
    this.note,
  });

  final String pickId;
  final ManualOutcomeValue outcome;
  final DateTime recordedAt;
  final String? note;

  Map<String, Object?> toMap() => {
        'pickId': pickId,
        'outcome': outcome.name,
        'recordedAt': recordedAt.toIso8601String(),
        'note': note,
      };

  static ManualOutcome fromMap(Map<String, Object?> m) => ManualOutcome(
        pickId: m['pickId']! as String,
        outcome: ManualOutcomeValue.values.byName(m['outcome']! as String),
        recordedAt: DateTime.parse(m['recordedAt']! as String),
        note: m['note'] as String?,
      );
}

/// One reliability-diagram bucket of settled picks.
class CalibrationBucket {
  CalibrationBucket({
    required this.lowerPct,
    required this.upperPct,
    required this.count,
    required this.avgPredictedWinPct,
    required this.observedWinRate,
    required this.pushCount,
  });

  /// Bucket bounds in percent, e.g. 60–65.
  final double lowerPct;
  final double upperPct;
  final int count;
  final double avgPredictedWinPct;

  /// Wins / (wins + losses); pushes excluded from the denominator.
  final double observedWinRate;
  final int pushCount;

  Map<String, Object?> toMap() => {
        'lowerPct': lowerPct,
        'upperPct': upperPct,
        'count': count,
        'avgPredictedWinPct': avgPredictedWinPct,
        'observedWinRate': observedWinRate,
        'pushCount': pushCount,
      };
}

class CalibrationReport {
  CalibrationReport({
    required this.buckets,
    required this.brierScore,
    required this.logLoss,
    required this.settledCount,
    required this.pushCount,
    required this.unsettledCount,
  });

  final List<CalibrationBucket> buckets;

  /// Mean squared error of predicted win probability vs observed outcome
  /// (pushes excluded).
  final double brierScore;

  /// Mean negative log-likelihood (pushes excluded).
  final double logLoss;
  final int settledCount;
  final int pushCount;
  final int unsettledCount;

  Map<String, Object?> toMap() => {
        'buckets': buckets.map((b) => b.toMap()).toList(),
        'brierScore': brierScore,
        'logLoss': logLoss,
        'settledCount': settledCount,
        'pushCount': pushCount,
        'unsettledCount': unsettledCount,
      };
}
