import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/models/calibration.dart';
import '../domain/models/pick.dart';
import '../domain/models/slate_date.dart';

/// CSV/JSON export of pick rows — **including withheld rows** (with their
/// withheld reasons) so audits see everything the generator produced.
///
/// Exports never contain the API key or any credential (verified by tests).
class ExportService {
  const ExportService();

  static const List<String> csvHeader = [
    'pick_id',
    'snapshot_id',
    'slate_date',
    'sport',
    'subject',
    'market',
    'stat',
    'direction',
    'line_value',
    'line_source',
    'line_source_timestamp',
    'status',
    'withheld_reason',
    'win_pct',
    'push_pct',
    'lose_pct',
    'win_pct_definition',
    'interval90_low',
    'interval90_high',
    'sample_size',
    'evidence_quality',
    'supporting_factors',
    'opposing_factors',
    'unknown_or_stale',
    'history_source',
    'history_fetched_at',
    'game',
    'generated_at',
  ];

  String toCsv(PredictionSnapshotRowBundle bundle) {
    final rows = <List<String>>[csvHeader];
    for (final pick in bundle.picks) {
      rows.add(_csvRow(bundle.snapshotId, pick));
    }
    return rows.map(_joinCsv).join('\n');
  }

  List<String> _csvRow(String snapshotId, PickCandidate p) {
    final e = p.estimate;
    return [
      p.id,
      snapshotId,
      p.slateDate.iso,
      p.sportId,
      p.subjectName,
      p.market.name,
      p.statDisplayName,
      p.direction.label,
      p.line?.value?.toString() ?? '',
      p.line?.source ?? '',
      p.line?.sourceTimestamp.toIso8601String() ?? '',
      p.status.name,
      p.withheldReason?.name ?? '',
      e == null ? '' : e.winPct.toStringAsFixed(2),
      e == null ? '' : e.pushPct.toStringAsFixed(2),
      e == null ? '' : e.losePct.toStringAsFixed(2),
      e == null ? '' : kWinPctDefinition,
      e == null ? '' : e.interval90Low.toStringAsFixed(2),
      e == null ? '' : e.interval90High.toStringAsFixed(2),
      e?.sampleSize.toString() ?? '',
      p.quality?.label ?? '',
      p.supportingFactors.map((f) => '${f.label}: ${f.detail}').join(' | '),
      p.opposingFactors.map((f) => '${f.label}: ${f.detail}').join(' | '),
      p.unknowns.join(' | '),
      p.historySource ?? '',
      p.historyFetchedAt?.toIso8601String() ?? '',
      p.gameDescription ?? '',
      p.generatedAt.toIso8601String(),
    ];
  }

  String _joinCsv(List<String> fields) => fields.map(_escapeCsv).join(',');

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  String toJson(PredictionSnapshotRowBundle bundle) => jsonEncode({
        'schema': 'linewise.export.v1',
        'snapshot_id': bundle.snapshotId,
        'includes_withheld_rows': true,
        'win_pct_definition': kWinPctDefinition,
        'disclaimer': kNoGuaranteeDisclaimer,
        'picks': [for (final p in bundle.picks) p.toMap()],
      });

  String calibrationCsv(List<PickCandidate> picks, List<ManualOutcome> outcomes,
      CalibrationReport report) {
    final byId = {for (final o in outcomes) o.pickId: o};
    final rows = <List<String>>[
      [
        'pick_id',
        'win_pct',
        'outcome',
        'recorded_at',
        'note',
      ],
      for (final p in picks)
        [
          p.id,
          p.estimate?.winPct.toStringAsFixed(2) ?? '',
          byId[p.id]?.outcome.name ?? '',
          byId[p.id]?.recordedAt.toIso8601String() ?? '',
          byId[p.id]?.note ?? '',
        ],
      const [],
      [
        'bucket_low',
        'bucket_high',
        'count',
        'avg_predicted_pct',
        'observed_win_rate',
        'push_count'
      ],
      for (final b in report.buckets)
        [
          b.lowerPct.toStringAsFixed(0),
          b.upperPct.toStringAsFixed(0),
          b.count.toString(),
          b.avgPredictedWinPct.toStringAsFixed(2),
          b.observedWinRate.toStringAsFixed(4),
          b.pushCount.toString(),
        ],
    ];
    return rows.map(_joinCsv).join('\n');
  }
}

/// A snapshot's rows with the snapshot id, ready for export.
class PredictionSnapshotRowBundle {
  PredictionSnapshotRowBundle({
    required this.snapshotId,
    required this.picks,
    required this.slateDate,
  });

  final String snapshotId;
  final List<PickCandidate> picks;
  final SlateDate slateDate;

  /// Integrity fingerprint of the export itself.
  String get exportFingerprint =>
      sha256.convert(utf8.encode('${snapshotId}:${picks.length}')).toString();
}
