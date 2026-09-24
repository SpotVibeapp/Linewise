import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'core/canonical_json.dart';
import 'data/calibration_repository.dart';
import 'data/line_repository.dart';
import 'domain/models/pick.dart';
import 'data/snapshot_repository.dart';
import 'domain/models/snapshot.dart';

/// In-memory model + wiring for the UI layer.
///
/// Contains no secrets; the API key lives only in [ApiKeyStore] behind
/// [KeyVault] (see app_services.dart).
class AppModel {
  AppModel({
    required this.lines,
    required this.snapshots,
    required this.calibration,
  });

  final LineRepository lines;
  final SnapshotRepository snapshots;
  final CalibrationRepository calibration;

  final List<PickCandidate> lastGenerated = [];
  PredictionSnapshot? lastSnapshot;

  void setLastGenerated(List<PickCandidate> picks) {
    lastGenerated
      ..clear()
      ..addAll(picks);
  }

  Future<PredictionSnapshot> saveSnapshot({
    required DateTime createdAt,
    required String generatorVersion,
    String? notes,
  }) async {
    final snap = PredictionSnapshot.create(
      createdAt: createdAt,
      generatorVersion: generatorVersion,
      picks: List.of(lastGenerated),
      notes: notes,
    );
    await snapshots.save(snap); // append-only: throws if id exists
    lastSnapshot = snap;
    return snap;
  }
}

/// Deterministic id helpers used across UI and export.
String pickFingerprint(PickCandidate p) =>
    sha256.convert(utf8.encode(canonicalJson(p.toMap()))).toString();

/// App-wide version surfaced in Settings and snapshots.
const String kAppVersion = '1.11.0';
const int kVersionCode = 12;
const String kGeneratorVersion = 'linewise-generator-1.11.0';
