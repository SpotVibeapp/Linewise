import 'dart:convert';
import 'dart:io';

import '../domain/models/exact_line.dart';

/// Cache of exact lines already loaded into the app (from the provider, manual
/// entry or import). Filtering this cache is the "loaded-line filtering"
/// request class: pure local work, zero cost, zero network.
class LineRepository {
  LineRepository({Directory? storageDir}) : _dir = storageDir;

  final Directory? _dir;
  final List<ExactLine> _lines = [];

  static const String _fileName = 'loaded_lines.json';

  List<ExactLine> get all => List.unmodifiable(_lines);

  void add(ExactLine line) {
    _lines.removeWhere((l) => l.id == line.id);
    _lines.add(line);
  }

  void addAll(Iterable<ExactLine> lines) => lines.forEach(add);

  void remove(String id) => _lines.removeWhere((l) => l.id == id);

  void clear() => _lines.clear();

  /// Local-only filtering — used by player search. Never touches the network.
  List<ExactLine> filterLoaded({
    String? playerName,
    String? playerId,
    String? teamId,
    String? statKey,
    MarketType? market,
  }) =>
      _lines.where((l) {
        if (playerName != null) {
          final q = playerName.toLowerCase();
          final n = l.playerName?.toLowerCase() ?? '';
          if (!n.contains(q)) return false;
        }
        if (playerId != null && l.playerId != playerId) return false;
        if (teamId != null && l.teamId != teamId) return false;
        if (statKey != null && l.statKey != statKey) return false;
        if (market != null && l.market != market) return false;
        return true;
      }).toList();

  Map<String, ExactLine> linesByStatForPlayer(String playerName) {
    final out = <String, ExactLine>{};
    for (final l in filterLoaded(playerName: playerName)) {
      out.putIfAbsent(l.statKey, () => l);
    }
    return out;
  }

  Future<void> persist() async {
    final dir = _dir;
    if (dir == null) return;
    await dir.create(recursive: true);
    final file = File('${dir.path}/$_fileName');
    await file.writeAsString(
        jsonEncode([for (final l in _lines) l.toMap()]));
  }

  Future<void> load() async {
    final dir = _dir;
    if (dir == null) return;
    final file = File('${dir.path}/$_fileName');
    if (!await file.exists()) return;
    final list = (jsonDecode(await file.readAsString()) as List).cast<Object?>();
    _lines
      ..clear()
      ..addAll([
        for (final item in list)
          if (item is Map)
            ExactLine.fromMap(item.map((k, v) => MapEntry(k.toString(), v))),
      ]);
  }
}
