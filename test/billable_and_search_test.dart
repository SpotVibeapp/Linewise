import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:linewise/app_services.dart';
import 'package:linewise/core/clock.dart';
import 'package:linewise/data/billing/billable_gate.dart';
import 'package:linewise/data/key_store.dart';
import 'package:linewise/data/kv_store.dart';
import 'package:linewise/domain/models/slate_date.dart';
import 'package:linewise/domain/sports.dart';

const String kFakeKey = 'TESTKEY123456789abcdef';

http.Response espnSearch(_) => http.Response(
    jsonEncode({
      'sports': [
        {
          'leagues': [
            {
              'entries': [
                {
                  'athlete': {
                    'id': '311',
                    'displayName': 'Derrick Henry',
                    'team': {'displayName': 'Baltimore Ravens'},
                    'position': {'abbreviation': 'RB'},
                    'uid': 's:20_l:28_a:311',
                  },
                  'type': 'athlete',
                }
              ]
            }
          ]
        }
      ]
    }),
    200);

http.Response espnGamelog(_) => http.Response(
    jsonEncode({
      'seasonTypes': [
        {
          'categories': [
            {
              'events': [
                for (var i = 0; i < 22; i++)
                  {
                    'gameDate': '2026-09-${(i % 28) + 1}T17:00:00Z',
                    'opponent': {'displayName': 'Team $i'},
                    'stats': {'rushYds': 70 + i, 'recYds': 20 + i},
                    'played': true,
                  }
              ]
            }
          ]
        }
      ]
    }),
    200);

http.Response oddsBody(_) => http.Response(
    jsonEncode([
      {
        'id': 'ev1',
        'sport_key': 'americanfootball_nfl',
        'commence_time': '2026-09-24T20:00:00Z',
        'home_team': 'Baltimore Ravens',
        'away_team': 'Dallas Cowboys',
        'bookmakers': [
          {
            'key': 'fanduel',
            'last_update': '2026-09-24T11:00:00Z',
            'markets': [
              {
                'key': 'player_rush_yds',
                'outcomes': [
                  {'name': 'Derrick Henry', 'point': 87.5, 'price': 1.91}
                ]
              }
            ]
          }
        ]
      }
    ]),
    200,
    headers: {
      'x-requests-remaining': '400',
      'x-requests-used': '2',
      'x-requests-last': '1',
    });

AppServices makeServices(MockClient client, {String? apiKey}) {
  final keys = MemoryApiKeyStore();
  if (apiKey != null) {
    keys.writeKey(apiKey);
  }
  return AppServices(
    clock: FixedClock(DateTime.utc(2026, 9, 24, 12)),
    apiKeyStore: keys,
    kvStore: MemoryKeyValueStore(),
    storage: Directory.systemTemp.createTempSync('svc'),
    client: client,
  );
}

void main() {
  final sport = supportedSports.first; // NFL
  final slate = SlateDate.parse('2026-09-24');

  test(
      'KNOWN PROBLEM FIX: searching "Derrick Henry" with zero loaded lines is '
      'free, returns selections, and never touches the billable client',
      () async {
    var billableCalls = 0;
    final client = MockClient((request) {
      if (request.url.host.contains('the-odds-api')) {
        billableCalls++;
        return oddsBody(request);
      }
      if (request.url.path.contains('gamelog')) return espnGamelog(request);
      return espnSearch(request);
    });
    final services = makeServices(client, apiKey: kFakeKey);
    // Safe mode OFF so the provider COULD be called — but search must not.
    await services.setSafeMode(false);
    services.approval.handler = (est) {
      billableCalls += 100; // any approval request would already be a failure
      return Future.value(true);
    };

    final result = await services.search.search('Derrick Henry');
    expect(result.hasNoMatches, isFalse,
        reason: 'free public search must find the player');
    expect(result.loadedLines, isEmpty,
        reason: 'zero provider lines are loaded');
    expect(result.freeAnalysisNote, contains('Zero provider lines'));

    final history = await services.search.analyzeHistory(
        sport: sport, athlete: result.athletes.first);
    expect(history.observations, isNotEmpty);

    final generated = services.playerGenerator.generate(
      subjectId: '311',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: slate,
      history: history,
      linesByStatKey: const {},
    );
    expect(generated, isNotEmpty,
        reason: 'Higher/Lower candidates must exist even with zero lines');
    expect(generated.every((p) => !p.isDefensible), isTrue,
        reason: 'without exact lines every row is withheld (never invented)');

    expect(billableCalls, 0,
        reason: 'player search and history analysis must never be billable');
  });

  test('loaded-line filtering matches local cache without any network',
      () async {
    var networkCalls = 0;
    final client = MockClient((request) {
      networkCalls++;
      return espnSearch(request);
    });
    final services = makeServices(client);
    services.lines.add(services.importService
        .importLines('Derrick Henry,rush_yds,87.5,manual:clipboard',
            now: DateTime.utc(2026, 9, 24, 9))
        .lines
        .first);

    // Pure local filter (the first step of search) — zero network.
    final local = services.lines.filterLoaded(playerName: 'derrick');
    expect(local.length, 1);
    expect(local.first.value, 87.5);
    expect(networkCalls, 0);
  });

  test('safe mode blocks provider requests entirely', () async {
    var networkCalls = 0;
    final client = MockClient((request) {
      networkCalls++;
      return oddsBody(request);
    });
    final services = makeServices(client, apiKey: kFakeKey);
    await services.setSafeMode(true); // default is ON
    services.approval.handler = (_) => Future.value(true);

    await expectLater(
      services.loader.loadExactLines(
        sport: sport,
        eventId: 'ev1',
        markets: const ['player_rush_yds'],
      ),
      throwsA(isA<SafeModeActiveException>()),
    );
    expect(networkCalls, 0);
  });

  test('declining the cost preview sends nothing', () async {
    var networkCalls = 0;
    final client = MockClient((request) {
      networkCalls++;
      return oddsBody(request);
    });
    final services = makeServices(client, apiKey: kFakeKey);
    await services.setSafeMode(false);
    services.approval.handler = (_) => Future.value(false);

    await expectLater(
      services.loader.loadExactLines(
        sport: sport,
        eventId: 'ev1',
        markets: const ['player_rush_yds'],
      ),
      throwsA(isA<UnapprovedRequestException>()),
    );
    expect(networkCalls, 0);
  });

  test('approved billable load works, keeps exact lines, redacts logs',
      () async {
    final client = MockClient((request) {
      expect(request.url.queryParameters['apiKey'], kFakeKey,
          reason: 'the wire request carries the key');
      return oddsBody(request);
    });
    final services = makeServices(client, apiKey: kFakeKey);
    await services.setSafeMode(false);
    services.approval.handler = (_) => Future.value(true);

    final res = await services.loader.loadExactLines(
      sport: sport,
      eventId: 'ev1',
      markets: const ['player_rush_yds'],
    );
    expect(res.value, isNotEmpty);
    expect(res.value.first.value, 87.5,
        reason: 'exact supplied line preserved verbatim');
    expect(res.value.first.source, contains('The Odds API'));
    expect(res.usage.remaining, 400);

    for (final line in services.log.lines) {
      expect(line, isNot(contains(kFakeKey)),
          reason: 'logs must never contain the key');
    }
  });

  test('cost preview shows the math and the zero-line warning', () async {
    final services = makeServices(MockClient(oddsBody), apiKey: kFakeKey);
    final estimate = services.odds.costModel.oddsRequest(
        markets: const ['player_rush_yds', 'player_rec_yds'],
        regions: const ['us']);
    expect(estimate.credits, 2);
    expect(estimate.explanation, contains('2 market(s) × 1 region(s)'));
    expect(estimate.explanation, contains('BILLABLE'));
    expect(estimate.explanation,
        contains('A request can consume credits even when it returns zero lines.'));
  });
}
