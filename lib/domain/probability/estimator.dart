import 'dart:math' as math;

import '../models/exact_line.dart';
import '../models/pick.dart';

/// Minimum valid observations before any probability may be published.
const int kMinObservations = 20;

/// Empirical probabilities from source-backed observations only.
///
/// The estimator NEVER invents probabilities: with fewer than
/// [kMinObservations] valid values, or a non-finite line, it refuses to produce
/// an estimate and the pick is shown as "Probability unavailable".
class EmpiricalEstimator {
  const EmpiricalEstimator();

  /// Baseline + capped adjustment for a numeric statistic vs a numeric line.
  ///
  /// [values] are the last N valid observations; [line] the exact supplied
  /// line. `Higher` wins strictly above the line, `Lower` strictly below.
  ProbabilityEstimate? estimate({
    required List<double> values,
    required double line,
    required PropDirection direction,
    double adjustmentPP = 0.0,
  }) {
    final usable = values.where((v) => v.isFinite).toList();
    final n = usable.length;
    if (n < kMinObservations) return null;
    if (!line.isFinite) return null;

    var wins = 0, pushes = 0, losses = 0;
    for (final v in usable) {
      if (v == line) {
        pushes++;
      } else if ((direction == PropDirection.higher && v > line) ||
          (direction == PropDirection.lower && v < line)) {
        wins++;
      } else {
        losses++;
      }
    }

    final pHigher = usable.where((v) => v > line).length / n;
    final pPush = pushes / n;
    final pLower = usable.where((v) => v < line).length / n;
    final empiricalWin = wins / n;

    final (lo, hi) = wilsonInterval90(wins, n);
    // The adjustment may not eat the push mass or go below zero.
    final maxWin = 1.0 - pPush;
    final adjusted =
        _clampRange(empiricalWin + adjustmentPP / 100.0, 0.0, maxWin);

    return ProbabilityEstimate(
      pHigher: pHigher,
      pPush: pPush,
      pLower: pLower,
      winPct: adjusted * 100.0,
      pushPct: pPush * 100.0,
      losePct: (maxWin - adjusted) * 100.0,
      interval90Low: lo * 100.0,
      interval90High: hi * 100.0,
      sampleSize: n,
      adjustmentPP: adjustmentPP,
      observedWins: wins,
      observedPushes: pushes,
      observedLosses: losses,
    );
  }

  /// Bernoulli (win/loss game outcomes) variant for moneylines. Push/tie is
  /// structurally impossible and reported as not applicable (0).
  ProbabilityEstimate? estimateBinaryWins({
    required List<bool> wonGames,
    required PropDirection direction,
    double adjustmentPP = 0.0,
  }) {
    final n = wonGames.length;
    if (n < kMinObservations) return null;
    final wins = direction == PropDirection.higher
        ? wonGames.where((w) => w).length
        : wonGames.where((w) => !w).length;
    final empiricalWin = wins / n;
    final (lo, hi) = wilsonInterval90(wins, n);
    final adjusted = _clamp01(empiricalWin + adjustmentPP / 100.0);
    return ProbabilityEstimate(
      pHigher: wonGames.where((w) => w).length / n,
      pPush: 0,
      pLower: wonGames.where((w) => !w).length / n,
      winPct: adjusted * 100.0,
      pushPct: 0,
      losePct: (1.0 - adjusted) * 100.0,
      interval90Low: lo * 100.0,
      interval90High: hi * 100.0,
      sampleSize: n,
      adjustmentPP: adjustmentPP,
      observedWins: wins,
      observedPushes: 0,
      observedLosses: n - wins,
    );
  }
}

/// 90% Wilson score interval for a binomial proportion.
(double, double) wilsonInterval90(int successes, int total) {
  if (total <= 0) return (0, 0);
  const z = 1.6448536269514722; // Φ⁻¹(0.95)
  final phat = successes / total;
  final z2 = z * z;
  final denom = 1 + z2 / total;
  final center = phat + z2 / (2 * total);
  final margin = z * math.sqrt((phat * (1 - phat) + z2 / (4 * total)) / total);
  final lo = (center - margin) / denom;
  final hi = (center + margin) / denom;
  return (_clamp01(lo), _clamp01(hi));
}

double _clamp01(double v) => _clampRange(v, 0, 1);

double _clampRange(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);
