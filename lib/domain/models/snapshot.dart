import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/canonical_json.dart';
import 'pick.dart';

/// Immutable prediction snapshot.
///
/// A snapshot freezes every candidate row (defensible **and** withheld) plus
/// provenance. The [id] is the SHA-256 of the canonical JSON payload, so any
/// modification can be detected. Snapshots are append-only: existing ids are
/// never overwritten.
class PredictionSnapshot {
  PredictionSnapshot._({
    required this.id,
    required this.createdAt,
    required this.generatorVersion,
    required this.picks,
    required this.notes,
    required this.payload,
  });

  factory PredictionSnapshot.create({
    required DateTime createdAt,
    required String generatorVersion,
    required List<PickCandidate> picks,
    String? notes,
  }) {
    final payload = <String, Object?>{
      'schema': 'linewise.snapshot.v1',
      'createdAt': createdAt.toUtc().toIso8601String(),
      'generatorVersion': generatorVersion,
      'notes': notes,
      'picks': picks.map((p) => p.toMap()).toList(),
    };
    final id = snapshotContentHash(payload);
    return PredictionSnapshot._(
      id: id,
      createdAt: createdAt.toUtc(),
      generatorVersion: generatorVersion,
      picks: List.unmodifiable(picks),
      notes: notes,
      payload: Map.unmodifiable(payload),
    );
  }

  static String snapshotContentHash(Map<String, Object?> payload) =>
      sha256.convert(utf8.encode(canonicalJson(payload))).toString();

  final String id;
  final DateTime createdAt;
  final String generatorVersion;
  final List<PickCandidate> picks;
  final String? notes;

  /// Canonical payload backing the hash.
  final Map<String, Object?> payload;

  String get contentHash => id;

  /// Recomputes the hash of [storedPayload] and compares to [storedId].
  static bool verifyIntegrity(
          String storedId, Map<String, Object?> storedPayload) =>
      snapshotContentHash(storedPayload) == storedId;

  String encode() => jsonEncode(payload);
}
