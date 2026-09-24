import 'dart:convert';
import 'dart:io';

import 'dart:math' as math;

import '../domain/models/calibration.dart';
import '../domain/models/pick.dart';

/// Manual-outcome store and calibration reporting.
///
/// Outcomes can ONLY be created or changed through [recordOutcome] — an
/// explicit user action. There is no automatic settlement code path in
/// Linewise at all.
class CalibrationRepository {
  CalibrationRepository({required Directory storageDir}) : _dir = storageDir;

  final Directory _dir;
  final Map<String, ManualOutcome> _outcomes = {};

  static const String _fileName = 'manual_outcomes.json';

  /// The one and only way outcomes enter the system: explicit, manual.
  void recordOutcome(ManualOutcome outcome) {
    _outcomes[outcome.pickId] = outcome;
  }

  void clearOutcome(String pickId) => _outcomes.remove(pickId);

  ManualOutcome? outcomeFor(String pickId) => _outcomes[pickId];

  List<ManualOutcome> get allOutcomes => List.unmodifiable(_outcomes.values);

  int get settledCount => _outcomes.length;

  Future<void> persist() async {
    await _dir.create(recursive: true);
    final file = File('${_dir.path}/$_fileName');
    await file.writeAsString(jsonEncode(
        [for (final o in _outcomes.values) o.toMap()]));
  }

  Future<void> load() async {
    final file = File('${_dir.path}/$_fileName');
    if (!await file.exists()) return;
    final list = (jsonDecode(await file.readAsString()) as List).cast<Object?>();
    _outcomes.clear();
    for (final item in list) {
      if (item is! Map) continue;
      final o =
          ManualOutcome.fromMap(item.map((k, v) => MapEntry(k.toString(), v)));
      _outcomes[o.pickId] = o;
    }
  }

  /// Reliability + scoring report over snapshot picks that have manual
  /// outcomes recorded.
  CalibrationReport report(List<PickCandidate> picks) {
    const bucketSize = 5.0;
    final buckets = <String, _Acc>{};
    var settled = 0, pushes = 0;
    var brierSum = 0.0, logSum = 0.0, logN = 0;

    for (final pick in picks) {
      final outcome = _outcomes[pick.id];
      if (outcome == null || !pick.isDefensible || pick.estimate == null) {
        continue;
      }
      settled++;
      final lower = (pick.estimate!.winPct ~/ bucketSize) * bucketSize;
      final key = lower.toString();
      final acc = buckets.putIfAbsent(key, () => _Acc(lower));
      acc.count++;
      acc.predictedSum += pick.estimate!.winPct;
      if (outcome.outcome == ManualOutcomeValue.push) {
        pushes++;
        acc.pushes++;
        continue;
      }
      final p = pick.estimate!.winPct / 100.0;
      final won = outcome.outcome == ManualOutcomeValue.won;
      brierSum += math.pow(p - (won ? 1 : 0), 2).toDouble();
      final clamped = p.clamp(0.001, 0.999);
      logSum += -math.log(won ? clamped : 1 - clamped);
      logN++;
      if (won) acc.wins++;
    }

    final settledNonPush = logN == 0 ? 0 : logN;
    final allPicks = picks.length;
    final sortedBuckets = buckets.values.map((a) {
      final decisions = a.wins + (a.count - a.wins - a.pushes);
      return CalibrationBucket(
        lowerPct: a.lower,
        upperPct: a.lower + bucketSize,
        count: a.count,
        avgPredictedWinPct: a.count == 0 ? 0 : a.predictedSum / a.count,
        observedWinRate: decisions == 0 ? 0 : a.wins / decisions,
        pushCount: a.pushes,
      );
    }).toList()
      ..sort((x, y) => x.lowerPct.compareTo(y.lowerPct));
    return CalibrationReport(
      buckets: sortedBuckets,
      brierScore: settledNonPush == 0 ? 0 : brierSum / settledNonPush,
      logLoss: settledNonPush == 0 ? 0 : logSum / settledNonPush,
      settledCount: settled,
      pushCount: pushes,
      unsettledCount: allPicks - settled,
    );
  }
}

class _Acc {
  _Acc(this.lower);

  final double lower;
  int count = 0;
  int wins = 0;
  int pushes = 0;
  double predictedSum = 0;
}
