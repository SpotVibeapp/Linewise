import '../models/evidence.dart';

/// Adjustment policy — the anti-double-counting contract.
///
/// 1. Each [Factor.signalId] may appear once per pick ([DoubleCountGuard]).
/// 2. `descriptiveOnly` signals (recent form, exact-line history, overall
///    player/team quality) are already inside the empirical baseline and can
///    never carry adjustments.
/// 3. Adjustments are capped per group and overall.
const Map<FactorGroup, double> kPerGroupAdjustmentCapPP = {
  FactorGroup.availabilityHealth: 6.0,
  FactorGroup.roleUsage: 5.0,
  FactorGroup.matchupGame: 6.0,
  FactorGroup.situational: 4.0,
  FactorGroup.environment: 4.0,
};

/// Overall cap on |total adjustment| in percentage points.
const double kOverallAdjustmentCapPP = 12.0;

/// Applies caps and the double-count guard; returns the total adjustment in
/// percentage points (signed).
double applyAdjustmentPolicy(List<Factor> factors, DoubleCountGuard guard) {
  guard.registerAll(factors);

  var total = 0.0;
  final perGroup = <FactorGroup, double>{};
  for (final f in factors) {
    if (f.descriptiveOnly && f.adjustmentPP != 0) {
      throw StateError(
          'descriptive-only factor "${f.signalId}" must not adjust (double-counting)');
    }
    final cap = kPerGroupAdjustmentCapPP[f.group];
    if (cap == null) {
      // Baseline/marketHistory groups never adjust.
      if (f.adjustmentPP != 0) {
        throw StateError(
            'group ${f.group.name} must not adjust ("${f.signalId}")');
      }
      continue;
    }
    perGroup[f.group] = (perGroup[f.group] ?? 0) + f.adjustmentPP;
  }

  perGroup.forEach((group, value) {
    final cap = kPerGroupAdjustmentCapPP[group]!;
    final clamped = value < -cap ? -cap : (value > cap ? cap : value);
    total += clamped;
  });

  if (total > kOverallAdjustmentCapPP) total = kOverallAdjustmentCapPP;
  if (total < -kOverallAdjustmentCapPP) total = -kOverallAdjustmentCapPP;
  return total;
}
