import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../app_services.dart';
import '../data/export_service.dart';
import '../domain/models/snapshot.dart';

/// Immutable prediction snapshots: verify, browse and export (CSV/JSON —
/// including withheld rows). Exports never contain credentials.
class SnapshotsPage extends StatefulWidget {
  const SnapshotsPage({super.key});

  @override
  State<SnapshotsPage> createState() => _SnapshotsPageState();
}

class _SnapshotsPageState extends State<SnapshotsPage> {
  List<PredictionSnapshot> _snaps = const [];
  final Map<String, String> _verifyResults = {};
  String? _status;

  AppServices get services => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final services = this.services;
    final snaps = await services.snapshots.list();
    if (mounted) setState(() => _snaps = snaps);
  }

  Future<void> _export(PredictionSnapshot snap, bool asJson) async {
    final services = this.services;
    final bundle = PredictionSnapshotRowBundle(
      snapshotId: snap.id,
      picks: snap.picks,
      slateDate: snap.picks.isEmpty
          ? throw StateError('empty')
          : snap.picks.first.slateDate,
    );
    final content =
        asJson ? services.exportService.toJson(bundle) : services.exportService.toCsv(bundle);
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/linewise/exports');
    await dir.create(recursive: true);
    final file = File(
        '${dir.path}/linewise_${snap.id.substring(0, 12)}.${asJson ? 'json' : 'csv'}');
    await file.writeAsString(content);
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      setState(() => _status =
          'Export written to ${file.path} (includes withheld rows) and copied '
          'to the clipboard. No credentials are included.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Snapshots are immutable and append-only: content id = SHA-256 of the '
          'canonical payload. Editing creates a new snapshot; existing ones are '
          'never overwritten.',
          style: TextStyle(fontSize: 12),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 8),
        for (final snap in _snaps)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Snapshot ${snap.id.substring(0, 16)}…',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                      '${snap.createdAt.toIso8601String()} · '
                      '${snap.picks.length} rows '
                      '(${snap.picks.where((p) => p.isDefensible).length} defensible, '
                      '${snap.picks.where((p) => !p.isDefensible).length} withheld)',
                      style: const TextStyle(fontSize: 12)),
                  Text('generator: ${snap.generatorVersion}',
                      style: const TextStyle(fontSize: 12)),
                  if (_verifyResults[snap.id] != null)
                    Text(_verifyResults[snap.id]!,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, children: [
                    OutlinedButton(
                      onPressed: () async {
                        final services = this.services;
                        final ok = await services.snapshots.verify(snap.id);
                        setState(() => _verifyResults[snap.id] = ok
                            ? 'Integrity OK — content hash matches.'
                            : 'Integrity FAILED — content does not match its id.');
                      },
                      child: const Text('Verify integrity'),
                    ),
                    OutlinedButton(
                        onPressed: () => _export(snap, false),
                        child: const Text('Export CSV')),
                    OutlinedButton(
                        onPressed: () => _export(snap, true),
                        child: const Text('Export JSON')),
                  ]),
                ],
              ),
            ),
          ),
        if (_snaps.isEmpty)
          const Text('No snapshots yet. Generate picks on the Players screen, '
              'then save an immutable snapshot from Picks.'),
        const SizedBox(height: 24),
      ],
    );
  }
}
