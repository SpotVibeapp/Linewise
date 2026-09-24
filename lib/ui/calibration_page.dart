import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../app_services.dart';
import '../domain/models/calibration.dart';
import '../domain/models/pick.dart';
import '../domain/models/snapshot.dart';
import 'widgets.dart';

/// Manual-outcome calibration dashboard.
///
/// Outcomes are entered BY HAND only. Linewise never settles automatically and
/// never places bets. The dashboard shows reliability buckets vs observed win
/// rates, Brier score and log loss over manually settled picks.
class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  List<PredictionSnapshot> _snaps = const [];
  PredictionSnapshot? _selected;
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
    if (!mounted) return;
    setState(() {
      _snaps = snaps;
      _selected ??= snaps.isEmpty ? null : snaps.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _selected;
    final report =
        snap == null ? null : services.calibration.report(snap.picks);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Manual-outcome calibration. Record outcomes yourself after games — '
          'there is no automatic settlement and no bet placement in Linewise. '
          '$kNoGuaranteeDisclaimer',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<PredictionSnapshot>(
          value: snap,
          decoration: const InputDecoration(
              labelText: 'Snapshot', border: OutlineInputBorder(), isDense: true),
          items: [
            for (final s in _snaps)
              DropdownMenuItem(
                value: s,
                child: Text(
                    '${s.id.substring(0, 12)}… · ${s.createdAt.toIso8601String()}'),
              ),
          ],
          onChanged: (s) => setState(() => _selected = s),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: const TextStyle(fontSize: 13)),
          ),
        if (snap != null && report != null) ...[
          SectionHeader(title: 'Calibration dashboard'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settled (manual): ${report.settledCount} · '
                      'pushes ${report.pushCount} · '
                      'unsettled ${report.unsettledCount}'),
                  Text(
                      'Brier score: ${report.brierScore.toStringAsFixed(4)} '
                      '(lower is better)'),
                  Text(
                      'Log loss: ${report.logLoss.toStringAsFixed(4)} '
                      '(lower is better)'),
                  const SizedBox(height: 8),
                  const Text('Reliability buckets:',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final b in report.buckets)
                    Text(
                      '${b.lowerPct.toStringAsFixed(0)}–${b.upperPct.toStringAsFixed(0)}%: '
                      'n=${b.count}, avg predicted '
                      '${b.avgPredictedWinPct.toStringAsFixed(1)}%, '
                      'observed win rate '
                      '${(b.observedWinRate * 100).toStringAsFixed(1)}%'
                      '${b.pushCount > 0 ? ', pushes ${b.pushCount}' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (report.buckets.isEmpty)
                    const Text('No manually settled picks yet.'),
                ],
              ),
            ),
          ),
          SectionHeader(
            title: 'Record outcomes (manual only)',
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export calibration CSV'),
            onPressed: () async {
              final services = this.services;
              final csv = services.exportService.calibrationCsv(
                  snap.picks, services.calibration.allOutcomes, report);
              final docs = await getApplicationDocumentsDirectory();
              final dir = Directory('${docs.path}/linewise/exports');
              await dir.create(recursive: true);
              final file = File(
                  '${dir.path}/linewise_calibration_${snap.id.substring(0, 12)}.csv');
              await file.writeAsString(csv);
              await Clipboard.setData(ClipboardData(text: csv));
              setState(() => _status = 'Calibration CSV at ${file.path} '
                  '(copied to clipboard).');
            },
          ),
          const SizedBox(height: 8),
          for (final pick in snap.picks)
            if (pick.isDefensible) _outcomeRow(pick),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _outcomeRow(PickCandidate pick) {
    final current = services.calibration.outcomeFor(pick.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          Expanded(
            child: PickListTile(pick: pick),
          ),
          DropdownButton<ManualOutcomeValue?>(
            value: current?.outcome,
            hint: const Text('Outcome', style: TextStyle(fontSize: 12)),
            items: [
              const DropdownMenuItem<ManualOutcomeValue?>(
                  value: null, child: Text('unset')),
              for (final v in ManualOutcomeValue.values)
                DropdownMenuItem(value: v, child: Text(v.label)),
            ],
            onChanged: (v) async {
              final services = this.services;
              if (v == null) {
                services.calibration.clearOutcome(pick.id);
              } else {
                services.calibration.recordOutcome(ManualOutcome(
                  pickId: pick.id,
                  outcome: v,
                  recordedAt: services.clock.now(),
                  note: 'manual entry',
                ));
              }
              await services.calibration.persist();
              setState(() => _status =
                  'Outcome recorded manually for ${pick.id}. No automatic '
                  'settlement is performed by Linewise.');
            },
          ),
        ]),
      ),
    );
  }
}
