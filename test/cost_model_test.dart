import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/data/billing/cost_model.dart';

void main() {
  const model = OddsCostModel();

  test('odds cost = markets × regions (provider documented)', () {
    expect(model.oddsRequest(markets: ['h2h'], regions: ['us']).credits, 1);
    expect(
        model.oddsRequest(
            markets: ['h2h', 'spreads', 'totals'], regions: ['us']).credits,
        3);
    expect(
        model.oddsRequest(
            markets: ['h2h', 'spreads', 'totals'],
            regions: ['us', 'uk', 'eu']).credits,
        9);
  });

  test('historical odds cost 10×', () {
    expect(
        model.oddsRequest(
            markets: ['player_pass_yds'],
            regions: ['us'],
            historical: true).credits,
        10);
  });

  test('discovery is 0 credits but still labeled provider', () {
    final d = model.discoveryRequest();
    expect(d.credits, 0);
    expect(d.kind, RequestKind.marketDiscovery);
    expect(d.isBillable, isFalse);
    expect(d.explanation, contains('0 credits'));
  });

  test('billable estimates include the zero-line warning', () {
    final e = model.oddsRequest(
        markets: ['player_rush_yds', 'player_rec_yds'], regions: ['us']);
    expect(e.isBillable, isTrue);
    expect(e.credits, 2);
    expect(
        e.explanation,
        contains(
            'A request can consume credits even when it returns zero lines.'));
    expect(e.zeroResultWarning, contains('zero lines'));
  });

  test('all four request classes are distinguished', () {
    expect(RequestKind.values.length, 4);
    expect(RequestKind.loadedLineFiltering.billable, isFalse);
    expect(RequestKind.freePublicHistory.billable, isFalse);
    expect(RequestKind.marketDiscovery.billable, isFalse);
    expect(RequestKind.exactProviderLines.billable, isTrue);
  });
}
