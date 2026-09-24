import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/clock.dart';
import '../core/logger.dart';
import '../core/redaction.dart';

/// Free public weather (Open-Meteo) used for the weather factor on outdoor
/// venues. No key, no cost.
class OpenMeteoClient {
  OpenMeteoClient({
    required this.httpClient,
    required this.log,
    required this.clock,
    this.host = 'api.open-meteo.com',
  });

  final http.Client httpClient;
  final AppLog log;
  final Clock clock;
  final String host;

  /// Returns a short weather note for [when] (UTC) at the venue coordinates,
  /// or null when data is unavailable (surfaced as an "unknown" disclosure —
  /// never invented).
  Future<String?> forecastNote({
    required double latitude,
    required double longitude,
    required DateTime when,
  }) async {
    final day =
        '${when.toUtc().year}-${when.toUtc().month.toString().padLeft(2, '0')}-${when.toUtc().day.toString().padLeft(2, '0')}';
    final uri = Uri.https(host, 'v1/forecast', {
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      'hourly': 'temperature_2m,precipitation,wind_speed_10m',
      'start_date': day,
      'end_date': day,
    });
    try {
      final resp = await httpClient.get(uri).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        log.warn('Open-Meteo HTTP ${resp.statusCode}');
        return null;
      }
      final json = jsonDecode(resp.body);
      if (json is! Map) return null;
      final hourly = json['hourly'];
      if (hourly is! Map) return null;
      final temps = (hourly['temperature_2m'] as List? ?? const []);
      final wind = (hourly['wind_speed_10m'] as List? ?? const []);
      final precip = (hourly['precipitation'] as List? ?? const []);
      double avg(List list) {
        final nums = list.whereType<num>().toList();
        if (nums.isEmpty) return 0;
        return nums.reduce((a, b) => a + b) / nums.length;
      }
      final t = avg(temps);
      final w = avg(wind);
      final p = avg(precip);
      final desc = <String>[
        'avg ${t.toStringAsFixed(0)}°C',
        'wind ${w.toStringAsFixed(0)} km/h',
        if (p > 0.2) 'precipitation ${p.toStringAsFixed(1)} mm/h',
        if (w > 30) 'strong wind',
        if (t <= 0) 'freezing',
        if (t >= 32) 'extreme heat',
      ];
      return 'Forecast for game day: ${desc.join(', ')}. (Open-Meteo)';
    } catch (e) {
      log.error('Open-Meteo request failed', redactSecrets(e.toString()));
      return null;
    }
  }
}
