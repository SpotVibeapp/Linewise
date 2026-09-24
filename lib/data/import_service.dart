import 'dart:convert';

import '../core/ids.dart';
import '../domain/models/exact_line.dart';

/// Manual import of exact lines from pasted CSV or JSON.
///
/// Imported lines are marked `import:...` sources with the import time, so
/// every line stays source-backed and auditable. The importer never invents
/// values — malformed rows are reported and skipped.
class ImportService {
  const ImportService();

  /// Parses pasted text into exact lines.
  ///
  /// CSV columns: `player,stat,value,source[,timestamp]`
  /// JSON: list of objects with the same fields (or full line maps).
  ImportResult importLines(String text, {DateTime? now}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return ImportResult(
          lines: const [], errors: const ['Nothing to import.']);
    }
    final at = now ?? DateTime.now().toUtc();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      return _importJson(trimmed, at);
    }
    return _importCsv(trimmed, at);
  }

  ImportResult _importJson(String text, DateTime at) {
    final lines = <ExactLine>[];
    final errors = <String>[];
    try {
      final decoded = jsonDecode(text);
      final list = decoded is List ? decoded : [decoded];
      var i = 0;
      for (final item in list) {
        i++;
        if (item is! Map) {
          errors.add('Row $i: not an object — skipped.');
          continue;
        }
        final m = item.map((k, v) => MapEntry(k.toString(), v));
        final player = m['player']?.toString() ?? m['playerName']?.toString();
        final stat = m['stat']?.toString() ?? m['statKey']?.toString();
        final value = num.tryParse('${m['value'] ?? ''}');
        final source = m['source']?.toString();
        if (player == null || stat == null || value == null) {
          errors.add('Row $i: needs player, stat and numeric value — skipped.');
          continue;
        }
        lines.add(_line(
          player: player,
          statKey: _statKey(stat),
          statLabel: stat,
          value: value.toDouble(),
          userSource: source,
          timestamp: DateTime.tryParse('${m['timestamp'] ?? ''}') ?? at,
          at: at,
          extra: {
            for (final e in m.entries)
              if (!const {
                'player',
                'playerName',
                'stat',
                'statKey',
                'value',
                'source',
                'timestamp'
              }.contains(e.key))
                e.key: '${e.value}',
          },
        ));
      }
    } catch (e) {
      errors.add('JSON parse error: $e');
    }
    return ImportResult(lines: lines, errors: errors);
  }

  ImportResult _importCsv(String text, DateTime at) {
    final lines = <ExactLine>[];
    final errors = <String>[];
    final rows = const LineSplitter().convert(text);
    var i = 0;
    for (final row in rows) {
      i++;
      final trimmed = row.trim();
      if (trimmed.isEmpty) continue;
      if (i == 1 && trimmed.toLowerCase().startsWith('player')) continue;
      final cols = _splitCsvRow(trimmed);
      if (cols.length < 3) {
        errors.add('Row $i: needs at least player,stat,value — skipped.');
        continue;
      }
      final player = cols[0].trim();
      final stat = cols[1].trim();
      final value = num.tryParse(cols[2].trim());
      final source = cols.length > 3 ? cols[3].trim() : null;
      final timestamp =
          cols.length > 4 ? DateTime.tryParse(cols[4].trim()) : null;
      if (player.isEmpty || stat.isEmpty || value == null) {
        errors.add('Row $i: bad player/stat/value — skipped.');
        continue;
      }
      lines.add(_line(
        player: player,
        statKey: _statKey(stat),
        statLabel: stat,
        value: value.toDouble(),
        userSource: source,
        timestamp: timestamp ?? at,
        at: at,
      ));
    }
    return ImportResult(lines: lines, errors: errors);
  }

  ExactLine _line({
    required String player,
    required String statKey,
    required String statLabel,
    required double value,
    required String? userSource,
    required DateTime timestamp,
    required DateTime at,
    Map<String, String> extra = const {},
  }) =>
      ExactLine(
        id: newId('import'),
        market: MarketType.playerProp,
        statKey: statKey,
        statDisplayName: statLabel,
        value: value,
        playerName: player,
        source: 'import:${userSource ?? 'user-supplied'}',
        sourceTimestamp: timestamp,
        loadedAt: at,
        raw: {
          'importedAt': at.toIso8601String(),
          'userSource': userSource ?? '',
          ...extra,
        },
      );

  String _statKey(String raw) {
    final k = raw.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return k.endsWith('_') ? k.substring(0, k.length - 1) : k;
  }

  List<String> _splitCsvRow(String row) {
    final out = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < row.length; i++) {
      final c = row[i];
      if (c == '"') {
        if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (c == ',' && !inQuotes) {
        out.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    out.add(buf.toString());
    return out;
  }
}

class ImportResult {
  ImportResult({required this.lines, required this.errors});

  final List<ExactLine> lines;
  final List<String> errors;

  bool get ok => errors.isEmpty;
}
