import 'dart:convert';
import 'dart:io';

import '../domain/models/evidence.dart';
import '../domain/models/exact_line.dart';
import '../domain/models/pick.dart';
import '../domain/models/slate_date.dart';
import '../domain/models/snapshot.dart';

/// Append-only store of immutable prediction snapshots.
///
/// Each snapshot is written once as `<hash>.json`. Any attempt to overwrite an
/// existing snapshot id fails. [verify] recomputes the content hash so
/// tampering is detectable.
class SnapshotRepository {
  SnapshotRepository({required Directory storageDir}) : _dir = storageDir;

  final Directory _dir;

  Future<File> save(PredictionSnapshot snapshot) async {
    await _dir.create(recursive: true);
    final file = File('${_dir.path}/${snapshot.id}.json');
    if (await file.exists()) {
      throw StateError(
          'Snapshot ${snapshot.id} already exists — snapshots are immutable');
    }
    return file.writeAsString(snapshot.encode());
  }

  Future<List<PredictionSnapshot>> list() async {
    if (!await _dir.exists()) return const [];
    final out = <PredictionSnapshot>[];
    await for (final entity in _dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final snap = _decode(await entity.readAsString());
      if (snap != null) out.add(snap);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<PredictionSnapshot?> byId(String id) async {
    final file = File('${_dir.path}/$id.json');
    if (!await file.exists()) return null;
    return _decode(await file.readAsString());
  }

  /// Recomputes the content hash of a stored snapshot.
  Future<bool> verify(String id) async {
    final file = File('${_dir.path}/$id.json');
    if (!await file.exists()) return false;
    final payload = jsonDecode(await file.readAsString());
    if (payload is! Map<String, Object?>) return false;
    return PredictionSnapshot.verifyIntegrity(id, payload);
  }

  PredictionSnapshot? _decode(String raw) {
    try {
      final payload = jsonDecode(raw);
      if (payload is! Map) return null;
      final map = payload.map((k, v) => MapEntry(k.toString(), v));
      final created = DateTime.parse(map['createdAt']! as String);
      final generatorVersion = map['generatorVersion']! as String;
      final notes = map['notes'] as String?;
      final picks = ((map['picks']! as List).cast<Map>()).map((p) {
        // Rebuild PickCandidate from its serialized map.
        return pickFromMap(p.map((k, v) => MapEntry(k.toString(), v)));
      }).toList();
      // Re-create with identical payload ⇒ identical hash when intact.
      return PredictionSnapshot.create(
        createdAt: created,
        generatorVersion: generatorVersion,
        picks: picks,
        notes: notes,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Deserializes a pick map produced by [PickCandidate.toMap].
PickCandidate pickFromMap(Map<String, Object?> m) {
  final estimateMap = m['estimate'] as Map?;
  final lineMap = m['line'] as Map?;
  return PickCandidate(
    id: m['id']! as String,
    subjectName: m['subjectName']! as String,
    subjectId: m['subjectId']! as String,
    sportId: m['sportId']! as String,
    slateDate: slateDateFromMap(m),
    market: MarketType.values.byName(m['market']! as String),
    statKey: m['statKey']! as String,
    statDisplayName: m['statDisplayName']! as String,
    direction: PropDirection.values.byName(m['direction']! as String),
    line: lineMap == null
        ? null
        : ExactLine.fromMap(lineMap.map((k, v) => MapEntry(k.toString(), v))),
    status: PickStatus.values.byName(m['status']! as String),
    withheldReason: m['withheldReason'] == null
        ? null
        : WithheldReason.values.byName(m['withheldReason']! as String),
    estimate: estimateMap == null
        ? null
        : _estimateFromMap(estimateMap.map((k, v) => MapEntry(k.toString(), v))),
    quality: m['quality'] == null
        ? null
        : EvidenceQuality.values.byName(m['quality']! as String),
    factors: ((m['factors'] as List? ?? const []).cast<Map>()).map((f) {
      final fm = f.map((k, v) => MapEntry(k.toString(), v));
      return Factor(
        signalId: fm['signalId']! as String,
        group: FactorGroup.values.byName(fm['group']! as String),
        stance: FactorStance.values.byName(fm['stance']! as String),
        label: fm['label']! as String,
        detail: fm['detail']! as String,
        source: fm['source']! as String,
        observedAt: DateTime.parse(fm['observedAt']! as String),
        adjustmentPP: (fm['adjustmentPP'] as num?)?.toDouble() ?? 0,
        descriptiveOnly: fm['descriptiveOnly'] as bool? ?? false,
      );
    }).toList(),
    unknowns: ((m['unknowns'] as List? ?? const []).cast<Object?>())
        .map((e) => e.toString())
        .toList(),
    historySource: m['historySource'] as String?,
    historyFetchedAt: m['historyFetchedAt'] == null
        ? null
        : DateTime.parse(m['historyFetchedAt']! as String),
    gameDescription: m['gameDescription'] as String?,
    pushLabel: m['pushLabel'] as String? ?? 'Push/Tie',
    generatedAt: DateTime.parse(m['generatedAt']! as String),
  );
}

SlateDate slateDateFromMap(Map<String, Object?> m) =>
    SlateDate.parse(m['slateDate']! as String);

ProbabilityEstimate _estimateFromMap(Map<String, Object?> m) => ProbabilityEstimate(
      pHigher: (m['pHigher']! as num).toDouble(),
      pPush: (m['pPush']! as num).toDouble(),
      pLower: (m['pLower']! as num).toDouble(),
      winPct: (m['winPct']! as num).toDouble(),
      pushPct: (m['pushPct']! as num).toDouble(),
      losePct: (m['losePct']! as num).toDouble(),
      interval90Low: (m['interval90Low']! as num).toDouble(),
      interval90High: (m['interval90High']! as num).toDouble(),
      sampleSize: m['sampleSize']! as int,
      adjustmentPP: (m['adjustmentPP']! as num).toDouble(),
      observedWins: m['observedWins']! as int,
      observedPushes: m['observedPushes']! as int,
      observedLosses: m['observedLosses']! as int,
    );
