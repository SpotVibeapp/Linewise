import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/clock.dart';
import '../core/logger.dart';
import '../core/redaction.dart';
import '../domain/models/player_history.dart';
import '../domain/models/slate_date.dart';
import '../domain/sports.dart';

/// Free public data client (ESPN public site/core APIs).
///
/// No API key, no cost, no private endpoints. This is the only client used for
/// player search and player-history analysis, so an empty search can never
/// consume The Odds API credits.
class EspnClient {
  EspnClient({
    required this.httpClient,
    required this.log,
    required this.clock,
    this.siteHost = 'site.api.espn.com',
  });

  final http.Client httpClient;
  final AppLog log;
  final Clock clock;
  final String siteHost;

  Future<Map<String, Object?>?> _getJson(String path,
      [Map<String, String> params = const {}]) async {
    final uri = Uri.https(siteHost, path, params);
    try {
      final resp =
          await httpClient.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        log.warn('ESPN HTTP ${resp.statusCode} for $path');
        return null;
      }
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (e) {
      log.error('ESPN request failed for $path', redactSecrets(e.toString()));
      return null;
    }
  }

  /// Free athlete search used by the safe player-search flow.
  Future<List<AthleteSummary>> searchAthletes(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final json = await _getJson('apis/search/v2', {
      'query': q,
      'limit': '20',
    });
    if (json == null) return const [];
    final out = <AthleteSummary>[];
    void consider(Object? node) {
      if (node is! Map) return;
      final type = node['type']?.toString() ?? '';
      final direct = node['athlete'];
      final Map? payload = direct is Map ? direct : node;
      if (payload == null) return;
      final id = payload['id']?.toString();
      final name =
          payload['displayName']?.toString() ?? payload['name']?.toString();
      if (id == null || name == null) return;
      if (type.isNotEmpty && type != 'athlete') {
        // Some shapes nest under results→entries with type on the entry.
      }
      final team = payload['team'] is Map
          ? (payload['team'] as Map)['displayName']?.toString()
          : payload['teamName']?.toString();
      final pos = payload['position'] is Map
          ? (payload['position'] as Map)['abbreviation']?.toString()
          : null;
      out.add(AthleteSummary(
        id: id,
        displayName: name,
        teamName: team,
        position: pos,
        sportPath: '',
      ));
    }

    final sports = (json['sports'] as List? ?? const []).cast<Object?>();
    for (final sport in sports) {
      if (sport is! Map) continue;
      final leagues = (sport['leagues'] as List? ?? const []).cast<Object?>();
      for (final league in leagues) {
        if (league is! Map) continue;
        final entries =
            (league['entries'] as List? ?? const []).cast<Object?>();
        for (final entry in entries) {
          consider(entry);
        }
      }
    }
    // Deduplicate by id.
    final seen = <String>{};
    return out.where((a) => seen.add(a.id)).toList();
  }

  /// Free game log (player history) used for Higher/Lower candidates.
  ///
  /// Returns an empty history (with [source] noted) instead of failing hard,
  /// so the UI can say "history unavailable" rather than inventing data.
  Future<SubjectHistory> fetchPlayerGameLog({
    required SportLeague sport,
    required String athleteId,
    required String athleteName,
  }) async {
    final fetchedAt = clock.now();
    final json = await _getJson(
        'apis/site/v2/sports/${sport.espnPath}/athletes/$athleteId/gamelog');
    final observations = <StatObservation>[];
    if (json != null) {
      final seasonGroups = <Object?>[];
      if (json['seasonTypes'] is List) {
        for (final st in (json['seasonTypes'] as List).cast<Object?>()) {
          if (st is Map && st['categories'] is List) {
            for (final cat in (st['categories'] as List).cast<Object?>()) {
              if (cat is Map && cat['events'] is List) seasonGroups.add(cat);
            }
            // Alternative shape: seasonTypes→categories→events.
          }
        }
      }
      // Fallback shape: {events: [...]} or {games: {...}}.
      final flatEvents = <Object?>[
        ...seasonGroups,
        ...((json['events'] as List?) ?? const []).cast<Object?>(),
      ];
      for (final node in flatEvents) {
        if (node is! Map) continue;
        final events = (node['events'] as List?)?.cast<Object?>();
        if (events == null) continue;
        for (final ev in events) {
          if (ev is! Map) continue;
          final gameDate = DateTime.tryParse(
                  (ev['gameDate'] ?? ev['date'])?.toString() ?? '') ??
              fetchedAt;
          final opponent = ev['opponent'] is Map
              ? (ev['opponent'] as Map)['displayName']?.toString()
              : ev['opponent']?.toString();
          final statsMap = <String, double>{};
          final statsNode = ev['stats'];
          void collectStats(Object? s) {
            if (s is Map) {
              s.forEach((k, v) {
                final num? n = v is num ? v : num.tryParse(v?.toString() ?? '');
                if (n != null) statsMap[k.toString()] = n.toDouble();
              });
            } else if (s is List) {
              for (final item in s) {
                collectStats(item);
              }
            }
          }

          collectStats(statsNode);
          final didNotPlay = ev['played'] == false ||
              '${ev['status'] ?? ''}'.toUpperCase().contains('DNP');
          statsMap.forEach((statKey, value) {
            observations.add(StatObservation(
              statKey: normalizeEspnStatKey(statKey),
              value: value,
              gameDate: gameDate,
              source: 'ESPN gamelog',
              opponent: opponent,
              valid: !didNotPlay,
            ));
          });
        }
      }
    }
    return SubjectHistory(
      subjectId: athleteId,
      subjectName: athleteName,
      observations: observations,
      source: 'ESPN public gamelog',
      fetchedAt: fetchedAt,
    );
  }

  /// Free scoreboard used for slate games (exact date, no ranges).
  Future<List<SlateGame>> fetchSlate({
    required SportLeague sport,
    required SlateDate slateDate,
  }) async {
    final json = await _getJson(
        'apis/site/v2/sports/${sport.espnPath}/scoreboard',
        {'dates': slateDate.iso.replaceAll('-', '')});
    if (json == null) return const [];
    final events = (json['events'] as List? ?? const []).cast<Object?>();
    final out = <SlateGame>[];
    for (final ev in events) {
      if (ev is! Map) continue;
      final id = ev['id']?.toString() ?? '';
      final name = ev['name']?.toString() ?? '';
      final date = DateTime.tryParse(ev['date']?.toString() ?? '') ??
          slateDate.asUtcDate;
      String home = '', away = '';
      final comps = (ev['competitions'] as List? ?? const []).cast<Object?>();
      for (final comp in comps) {
        if (comp is! Map) continue;
        final competitors =
            (comp['competitors'] as List? ?? const []).cast<Object?>();
        for (final c in competitors) {
          if (c is! Map) continue;
          final teamName = c['team'] is Map
              ? (c['team'] as Map)['displayName']?.toString() ?? ''
              : '';
          if (c['homeAway'] == 'home') {
            home = teamName;
          } else if (c['homeAway'] == 'away') {
            away = teamName;
          }
        }
        final venue = comp['venue'];
        String? venueName;
        bool? outdoor;
        double? lat, lon;
        if (venue is Map) {
          venueName = venue['fullName']?.toString();
          outdoor = venue['indoor'] == true
              ? false
              : (venue['indoor'] == false ? true : null);
          final addr = venue['address'];
          if (addr is Map) {
            lat = double.tryParse('${addr['latitude'] ?? ''}');
            lon = double.tryParse('${addr['longitude'] ?? ''}');
          }
        }
        out.add(SlateGame(
          id: id,
          sportId: sport.id,
          name: name,
          commenceUtc: date,
          homeTeam: home,
          awayTeam: away,
          venueName: venueName,
          venueOutdoor: outdoor,
          latitude: lat,
          longitude: lon,
          source: 'ESPN scoreboard',
        ));
      }
      if (comps.isEmpty) {
        out.add(SlateGame(
          id: id,
          sportId: sport.id,
          name: name,
          commenceUtc: date,
          homeTeam: home,
          awayTeam: away,
          source: 'ESPN scoreboard',
        ));
      }
    }
    return out;
  }

  /// Free injury report for a team (availability evidence).
  Future<List<String>> fetchTeamInjuries({
    required SportLeague sport,
    required String teamId,
  }) async {
    final json = await _getJson(
        'apis/site/v2/sports/${sport.espnPath}/teams/$teamId/injuries');
    if (json == null) return const [];
    final out = <String>[];
    final injuries = (json['injuries'] as List? ?? const []).cast<Object?>();
    for (final inj in injuries) {
      if (inj is! Map) continue;
      final athlete = inj['athlete'];
      final name =
          athlete is Map ? athlete['displayName']?.toString() ?? '' : '';
      final status = inj['status']?.toString() ?? '';
      final details = inj['details'] is Map
          ? (inj['details'] as Map)['type']?.toString() ?? ''
          : '';
      if (name.isNotEmpty) {
        out.add('$name: ${status.isEmpty ? details : status}');
      }
    }
    return out;
  }
}

/// Normalizes ESPN stat labels to Linewise statistic keys where known.
String normalizeEspnStatKey(String raw) {
  final k = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  switch (k) {
    case 'rush_yds':
    case 'rushing_yards':
    case 'rushyards':
      return 'rush_yds';
    case 'rush_att':
    case 'car':
    case 'carries':
      return 'rush_att';
    case 'rec_yds':
    case 'receiving_yards':
      return 'rec_yds';
    case 'rec':
    case 'receptions':
      return 'receptions';
    case 'pass_yds':
    case 'passing_yards':
      return 'pass_yds';
    case 'pass_td':
    case 'passing_td':
    case 'pass_tds':
      return 'pass_td';
    case 'rush_td':
    case 'rushing_td':
      return 'rush_td';
    case 'rec_td':
    case 'receiving_td':
      return 'rec_td';
    case 'pts':
    case 'points':
      return 'points';
    case 'reb':
    case 'rebounds':
    case 'treb':
      return 'rebounds';
    case 'ast':
    case 'assists':
      return 'assists';
    case 'tpm':
    case 'fg3m':
    case 'threes':
      return 'threes';
    case 'hits':
      return 'hits';
    case 'hr':
    case 'home_runs':
      return 'home_runs';
    case 'rbi':
    case 'rbis':
      return 'rbi';
    case 'so':
    case 'strikeouts':
      return 'strikeouts';
    default:
      return k;
  }
}

class AthleteSummary {
  AthleteSummary({
    required this.id,
    required this.displayName,
    required this.teamName,
    required this.position,
    required this.sportPath,
  });

  final String id;
  final String displayName;
  final String? teamName;
  final String? position;
  final String sportPath;
}

class SlateGame {
  SlateGame({
    required this.id,
    required this.sportId,
    required this.name,
    required this.commenceUtc,
    required this.homeTeam,
    required this.awayTeam,
    required this.source,
    this.venueName,
    this.venueOutdoor,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String sportId;
  final String name;
  final DateTime commenceUtc;
  final String homeTeam;
  final String awayTeam;
  final String source;
  final String? venueName;
  final bool? venueOutdoor;
  final double? latitude;
  final double? longitude;
}
