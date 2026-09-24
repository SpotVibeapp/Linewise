/// The four request classes Linewise distinguishes, and the credit cost model
/// for The Odds API (documented: odds requests cost `markets × regions`
/// credits; historical odds cost 10×; the sports and events listings do not
/// count against the usage quota).
library;

enum RequestKind {
  /// Filtering lines already loaded into the app. No network at all.
  loadedLineFiltering(
      'Loaded-line filtering', 'Local — no network, no cost', false),

  /// Free public player-history analysis (ESPN) and weather (Open-Meteo).
  freePublicHistory('Free public player-history analysis',
      'Free public sources — no API key, no cost', false),

  /// The Odds API sports/events listings (0 credits, but needs your key).
  marketDiscovery(
      'Market discovery',
      'The Odds API listings — 0 credits (does not count against quota)',
      false),

  /// The Odds API odds endpoints — billable.
  exactProviderLines(
      'Exact provider-line loading', 'The Odds API odds — BILLABLE', true);

  const RequestKind(this.label, this.costClassLabel, this.billable);

  final String label;
  final String costClassLabel;
  final bool billable;
}

/// Pre-computed, disclosed cost of a provider request.
class CreditCostEstimate {
  CreditCostEstimate({
    required this.kind,
    required this.credits,
    required this.marketsCount,
    required this.regionsCount,
    this.historical = false,
  });

  final RequestKind kind;
  final int credits;
  final int marketsCount;
  final int regionsCount;
  final bool historical;

  bool get isBillable => kind.billable && credits > 0;

  /// Full multi-line explanation shown before every provider request.
  String get explanation {
    final b = StringBuffer()
      ..writeln('Request class: ${kind.label}')
      ..writeln('Cost class: ${kind.costClassLabel}');
    if (kind == RequestKind.exactProviderLines) {
      b.writeln('Estimate: $marketsCount market(s) × $regionsCount region(s) '
          '× ${historical ? '10 (historical)' : '1'} = $credits credit(s).');
    } else if (kind == RequestKind.marketDiscovery) {
      b.writeln('Estimated cost: 0 credits (sports/events listings are free).');
    } else {
      b.writeln('Estimated cost: 0 credits.');
    }
    if (isBillable) {
      b.writeln(
          'WARNING: a request can consume credits even when it returns zero lines.');
    }
    return b.toString().trim();
  }

  String get zeroResultWarning =>
      'A request can consume credits even when it returns zero lines.';

  Map<String, Object?> toMap() => {
        'kind': kind.name,
        'credits': credits,
        'marketsCount': marketsCount,
        'regionsCount': regionsCount,
        'historical': historical,
      };
}

/// Computes estimates for The Odds API request shapes.
class OddsCostModel {
  const OddsCostModel();

  /// `/odds` and `/events/{id}/odds`: cost = markets × regions (×10 historical).
  CreditCostEstimate oddsRequest({
    required List<String> markets,
    required List<String> regions,
    bool historical = false,
  }) =>
      CreditCostEstimate(
        kind: RequestKind.exactProviderLines,
        credits: markets.length * regions.length * (historical ? 10 : 1),
        marketsCount: markets.length,
        regionsCount: regions.length,
        historical: historical,
      );

  /// `/sports` and `/sports/{sport}/events`: free (0 credits).
  CreditCostEstimate discoveryRequest() => CreditCostEstimate(
        kind: RequestKind.marketDiscovery,
        credits: 0,
        marketsCount: 0,
        regionsCount: 0,
      );

  CreditCostEstimate localFilteringRequest() => CreditCostEstimate(
        kind: RequestKind.loadedLineFiltering,
        credits: 0,
        marketsCount: 0,
        regionsCount: 0,
      );

  CreditCostEstimate freePublicRequest() => CreditCostEstimate(
        kind: RequestKind.freePublicHistory,
        credits: 0,
        marketsCount: 0,
        regionsCount: 0,
      );
}
