import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/clock.dart';
import '../core/logger.dart';
import '../core/redaction.dart';
import '../domain/generation/player_generator.dart' show statDisplayName;
import '../domain/models/exact_line.dart';
import 'billing/billable_gate.dart';
import 'billing/cost_model.dart';
import 'key_store.dart';
import 'settings_repository.dart';

/// Market keys supported for provider loading.
const List<String> kTeamMarkets = ['h2h', 'spreads', 'totals'];

/// Player prop market keys per league (provider-published keys only; the
/// exact Higher/Lower line is used verbatim when the provider supplies one).
const Map<String, List<String>> kPlayerPropMarketsBySport = {
  'nfl': [
    'player_pass_yds',
    'player_pass_tds',
    'player_pass_completions',
    'player_pass_attempts',
    'player_pass_interceptions',
    'player_rush_yds',
    'player_rush_att',
    'player_reception_yds',
    'player_receptions',
    'player_anytime_td',
  ],
  'ncaaf': [
    'player_pass_yds',
    'player_rush_yds',
    'player_reception_yds',
    'player_receptions',
  ],
  'nba': [
    'player_points',
    'player_rebounds',
    'player_assists',
    'player_threes',
    'player_points_rebounds_assists',
    'player_blocks',
    'player_steals',
    'player_turnovers',
  ],
  'ncaab': [
    'player_points',
    'player_rebounds',
    'player_assists',
    'player_threes'
  ],
  'wnba': [
    'player_points',
    'player_rebounds',
    'player_assists',
    'player_threes'
  ],
  'mlb': [
    'batter_hits',
    'batter_home_runs',
    'batter_rbis',
    'batter_total_bases',
    'pitcher_strikeouts',
    'pitcher_hits_allowed',
  ],
  'nhl': [
    'player_goals',
    'player_assists',
    'player_points',
    'player_shots_on_goal',
    'player_saves',
  ],
};

/// Provider event listing (no odds).
class ProviderEvent {
  ProviderEvent({
    required this.id,
    required this.sportKey,
    required this.commenceTime,
    required this.homeTeam,
    required this.awayTeam,
  });

  final String id;
  final String sportKey;
  final DateTime commenceTime;
  final String homeTeam;
  final String awayTeam;
}

/// Quota counters returned in response headers (`x-requests-*`).
class ProviderCallResult<T> {
  ProviderCallResult({
    required this.value,
    required this.usage,
  });

  final T value;
  final ProviderUsage usage;
}

/// The Odds API client (v4).
///
/// Safety contract:
/// * The API key is read from encrypted storage at call time and is never
///   logged, never exported and never cached in memory beyond the call.
/// * Every method declares its [RequestKind]; billable methods must go through
///   [BillableGate.run] (safe mode + explicit cost approval).
/// * Player search never calls this client (see PlayerSearchService).
class OddsApiClient {
  OddsApiClient({
    required this.httpClient,
    required this.apiKeyStore,
    required this.settings,
    required this.gate,
    required this.log,
    required this.clock,
    this.costModel = const OddsCostModel(),
    this.host = 'api.the-odds-api.com',
  });

  final http.Client httpClient;
  final ApiKeyStore apiKeyStore;
  final SettingsRepository settings;
  final BillableGate gate;
  final AppLog log;
  final Clock clock;
  final OddsCostModel costModel;
  final String host;

  static const RequestKind sportsKind = RequestKind.marketDiscovery;
  static const RequestKind eventsKind = RequestKind.marketDiscovery;
  static const RequestKind oddsKind = RequestKind.exactProviderLines;

  /// GET /v4/sports — market discovery, 0 credits (still gated by safe mode
  /// and explicit approval: it is provider traffic).
  Future<ProviderCallResult<List<SportKeyEntry>>> listSports() {
    final estimate = costModel.discoveryRequest();
    return gate.run(estimate, () async {
      final body = await _get('v4/sports/', const {});
      return ProviderCallResult(
        value: _parseSports(body.body),
        usage: body.usage,
      );
    });
  }

  /// GET /v4/sports/{sport}/events — market discovery, 0 credits.
  Future<ProviderCallResult<List<ProviderEvent>>> listEvents(String sportKey) {
    final estimate = costModel.discoveryRequest();
    return gate.run(estimate, () async {
      final body = await _get('v4/sports/$sportKey/events', const {});
      return ProviderCallResult(
        value: _parseEvents(body.body),
        usage: body.usage,
      );
    });
  }

  /// GET /v4/sports/{sport}/odds — BILLABLE (markets × regions credits).
  ///
  /// Callers must show `estimate.explanation` (which includes the zero-line
  /// warning) before invoking; the gate enforces approval again.
  Future<ProviderCallResult<List<ExactLine>>> fetchOdds({
    required String sportKey,
    required List<String> markets,
    required List<String> regions,
  }) {
    final estimate = costModel.oddsRequest(markets: markets, regions: regions);
    return gate.run(estimate, () async {
      final body = await _get('v4/sports/$sportKey/odds', {
        'markets': markets.join(','),
        'regions': regions.join(','),
        'oddsFormat': 'decimal',
        'dateFormat': 'iso',
      });
      return ProviderCallResult(
        value: _parseOddsToLines(body.body, sportKey),
        usage: body.usage,
      );
    });
  }

  /// GET /v4/sports/{sport}/events/{id}/odds — BILLABLE. Player props live
  /// here (one event at a time), per provider documentation.
  Future<ProviderCallResult<List<ExactLine>>> fetchEventOdds({
    required String sportKey,
    required String eventId,
    required List<String> markets,
    required List<String> regions,
  }) {
    final estimate = costModel.oddsRequest(markets: markets, regions: regions);
    return gate.run(estimate, () async {
      final body = await _get('v4/sports/$sportKey/events/$eventId/odds', {
        'markets': markets.join(','),
        'regions': regions.join(','),
        'oddsFormat': 'decimal',
        'dateFormat': 'iso',
      });
      return ProviderCallResult(
        value: _parseOddsToLines(body.body, sportKey, eventId: eventId),
        usage: body.usage,
      );
    });
  }

  Future<({String body, ProviderUsage usage})> _get(
    String path,
    Map<String, String> params,
  ) async {
    final key = await apiKeyStore.readKey();
    if (key == null || key.isEmpty) {
      throw MissingApiKeyException();
    }
    final uri = Uri.https(host, path, {
      ...params,
      'apiKey': key,
    });
    try {
      final resp =
          await httpClient.get(uri).timeout(const Duration(seconds: 30));
      final usage = ProviderUsage(
        remaining: int.tryParse(resp.headers['x-requests-remaining'] ?? ''),
        used: int.tryParse(resp.headers['x-requests-used'] ?? ''),
        lastCost: int.tryParse(resp.headers['x-requests-last'] ?? ''),
        observedAt: clock.now(),
      );
      await settings.saveProviderUsage(usage);
      if (resp.statusCode != 200) {
        log.error('provider HTTP ${resp.statusCode}: '
            '${redactSecrets(resp.body)}');
        throw ProviderHttpException(resp.statusCode, redactSecrets(resp.body));
      }
      log.info('provider OK ${redactSecrets(uri.toString())} '
          'remaining=${usage.remaining ?? "?"} last=${usage.lastCost ?? "?"}');
      return (body: resp.body, usage: usage);
    } catch (e) {
      // Any error text may embed the request URL — redact before it can leak.
      log.error('provider request failed', redactSecrets(e.toString()));
      if (e is ProviderHttpException) rethrow;
      throw ProviderHttpException(0, redactSecrets(e.toString()));
    }
  }

  List<SportKeyEntry> _parseSports(String body) {
    final list = (jsonDecode(body) as List).cast<Object?>();
    return [
      for (final item in list)
        if (item is Map)
          SportKeyEntry(
            key: item['key']?.toString() ?? '',
            title: item['title']?.toString() ?? '',
            active: item['active'] == true,
          ),
    ];
  }

  List<ProviderEvent> _parseEvents(String body) {
    final list = (jsonDecode(body) as List).cast<Object?>();
    return [
      for (final item in list)
        if (item is Map)
          ProviderEvent(
            id: item['id']?.toString() ?? '',
            sportKey: item['sport_key']?.toString() ?? '',
            commenceTime:
                DateTime.tryParse(item['commence_time']?.toString() ?? '') ??
                    DateTime.now().toUtc(),
            homeTeam: item['home_team']?.toString() ?? '',
            awayTeam: item['away_team']?.toString() ?? '',
          ),
    ];
  }

  /// Parses odds JSON into exact lines, preserving the supplied values
  /// verbatim (never rounded or moved) with full provenance.
  List<ExactLine> _parseOddsToLines(
    String body,
    String sportKey, {
    String? eventId,
  }) {
    final decoded = jsonDecode(body);
    final events = decoded is List ? decoded : [decoded];
    final out = <ExactLine>[];
    for (final ev in events) {
      if (ev is! Map) continue;
      final id = ev['id']?.toString() ?? eventId ?? '';
      final books = (ev['bookmakers'] as List? ?? const []).cast<Object?>();
      for (final book in books) {
        if (book is! Map) continue;
        final bookKey = book['key']?.toString() ?? '';
        final lastUpdate =
            DateTime.tryParse(book['last_update']?.toString() ?? '') ??
                DateTime.now().toUtc();
        final markets = (book['markets'] as List? ?? const []).cast<Object?>();
        for (final market in markets) {
          if (market is! Map) continue;
          final marketKey = market['key']?.toString() ?? '';
          final outcomes =
              (market['outcomes'] as List? ?? const []).cast<Object?>();
          for (final outcome in outcomes) {
            if (outcome is! Map) continue;
            final name = outcome['name']?.toString() ?? '';
            final point = (outcome['point'] as num?)?.toDouble();
            final price = (outcome['price'] as num?)?.toDouble();
            final isPlayerProp = marketKey.startsWith('player_') ||
                marketKey.startsWith('batter_') ||
                marketKey.startsWith('pitcher_');
            final MarketType marketType;
            final String statKey;
            if (isPlayerProp) {
              marketType = MarketType.playerProp;
              statKey = providerMarketToStatKey(marketKey);
            } else if (marketKey == 'h2h') {
              marketType = MarketType.moneyline;
              statKey = 'moneyline';
            } else if (marketKey == 'spreads') {
              marketType = MarketType.spread;
              statKey = 'spread';
            } else if (marketKey == 'totals') {
              marketType = MarketType.total;
              statKey = 'total';
            } else {
              marketType = MarketType.playerProp;
              statKey = providerMarketToStatKey(marketKey);
            }
            out.add(ExactLine(
              id: 'prov-$sportKey-$id-$bookKey-$marketKey-$name',
              market: marketType,
              statKey: statKey,
              statDisplayName: statDisplayName(statKey),
              value: point,
              playerName: isPlayerProp ? name : null,
              teamId: isPlayerProp ? null : name,
              source: 'The Odds API/$sportKey/$bookKey/$marketKey',
              sourceTimestamp: lastUpdate,
              providerEventId: id,
              providerBookmaker: bookKey,
              raw: {
                'outcome': name,
                if (point != null) 'point': point.toString(),
                if (price != null) 'price': price.toString(),
                'market': marketKey,
                'book': bookKey,
              },
            ));
          }
        }
      }
    }
    return out;
  }
}

class SportKeyEntry {
  SportKeyEntry({required this.key, required this.title, required this.active});

  final String key;
  final String title;
  final bool active;
}

class ProviderHttpException implements Exception {
  ProviderHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Provider request failed (HTTP $statusCode): $message';
}

/// Maps provider market keys to Linewise statistic keys.
String providerMarketToStatKey(String marketKey) {
  switch (marketKey) {
    case 'player_pass_yds':
      return 'pass_yds';
    case 'player_pass_tds':
      return 'pass_td';
    case 'player_pass_completions':
      return 'pass_completions';
    case 'player_pass_attempts':
      return 'pass_att';
    case 'player_pass_interceptions':
      return 'pass_int';
    case 'player_rush_yds':
      return 'rush_yds';
    case 'player_rush_att':
      return 'rush_att';
    case 'player_reception_yds':
      return 'rec_yds';
    case 'player_receptions':
      return 'receptions';
    case 'player_points':
      return 'points';
    case 'player_rebounds':
      return 'rebounds';
    case 'player_assists':
      return 'assists';
    case 'player_threes':
      return 'threes';
    case 'player_points_rebounds_assists':
      return 'pra';
    case 'batter_hits':
      return 'hits';
    case 'batter_home_runs':
      return 'home_runs';
    case 'batter_rbis':
      return 'rbi';
    case 'pitcher_strikeouts':
      return 'strikeouts';
    case 'player_goals':
      return 'goals';
    case 'player_saves':
      return 'saves';
    default:
      return marketKey;
  }
}
