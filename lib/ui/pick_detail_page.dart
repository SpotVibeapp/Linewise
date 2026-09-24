import 'package:flutter/material.dart';

import '../domain/models/pick.dart';
import 'widgets.dart';

/// Full display of one candidate row — every field the product contract
/// requires for defensible picks, plus disclosures.
class PickDetailPage extends StatelessWidget {
  const PickDetailPage({super.key, required this.pick});

  final PickCandidate pick;

  @override
  Widget build(BuildContext context) {
    final e = pick.estimate;
    final supporting = pick.supportingFactors;
    final opposing = pick.opposingFactors;
    return Scaffold(
      appBar: AppBar(
          title: Text('${pick.direction.label} · ${pick.statDisplayName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(pick.subjectName,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (pick.gameDescription != null)
            Text(pick.gameDescription!,
                style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            Chip(
              label: Text(pick.isDefensible ? 'Defensible' : 'Withheld'),
              visualDensity: VisualDensity.compact,
              backgroundColor: pick.isDefensible
                  ? Colors.teal.shade50
                  : Colors.grey.shade200,
            ),
            if (pick.quality != null)
              QualityBadge(quality: pick.quality!.label),
            RequestKindBadgeSpacer(market: pick.market),
          ]),
          if (!pick.isDefensible)
            Card(
              color: Colors.grey.shade100,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  pick.displayProbability,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          if (e != null) ...[
            _section('Probability'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Win ${e.winPct.toStringAsFixed(2)}% · '
                      '${pick.pushLabel} ${e.pushPct.toStringAsFixed(2)}% · '
                      'Lose ${e.losePct.toStringAsFixed(2)}%',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    FactRow(
                        label: 'Win % definition', value: kWinPctDefinition),
                    FactRow(
                        label: 'Uncertainty (90%)',
                        value:
                            '${e.interval90Low.toStringAsFixed(2)}% – ${e.interval90High.toStringAsFixed(2)}% (Wilson interval on the empirical win share)'),
                    FactRow(
                        label: 'Sample size',
                        value: '${e.sampleSize} valid observations '
                            '(wins ${e.observedWins}, ties ${e.observedPushes}, losses ${e.observedLosses})'),
                    FactRow(
                        label: 'Baseline shares',
                        value:
                            'Higher ${e.pHigher.toStringAsFixed(3)} · Tie ${e.pPush.toStringAsFixed(3)} · Lower ${e.pLower.toStringAsFixed(3)}'),
                    FactRow(
                        label: 'Adjustment',
                        value:
                            '${e.adjustmentPP.toStringAsFixed(2)} pp (capped, each signal counted once)'),
                    const SizedBox(height: 6),
                    const Text(kNoGuaranteeDisclaimer,
                        style: TextStyle(
                            fontStyle: FontStyle.italic, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
          _section('Source & provenance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  FactRow(
                      label: 'Line',
                      value: pick.line?.value == null
                          ? 'none (market has no numeric line)'
                          : 'exact ${pick.line!.value} as supplied'),
                  FactRow(label: 'Source', value: pick.line?.source ?? '—'),
                  FactRow(
                      label: 'Line timestamp',
                      value:
                          pick.line?.sourceTimestamp.toIso8601String() ?? '—'),
                  FactRow(
                      label: 'History source',
                      value: pick.historySource ?? '—'),
                  FactRow(
                      label: 'History fetched',
                      value: pick.historyFetchedAt?.toIso8601String() ?? '—'),
                  FactRow(
                      label: 'Generated at',
                      value: pick.generatedAt.toIso8601String()),
                  FactRow(label: 'Slate date', value: pick.slateDate.iso),
                ],
              ),
            ),
          ),
          _section('Supporting factors'),
          _factorCard(supporting, empty: 'No supporting factors identified.'),
          _section('Opposing factors & weaknesses'),
          _factorCard(opposing, empty: 'No opposing factors identified.'),
          _section('Neutral / descriptive (never double-counted)'),
          _factorCard(
            pick.factors.where((f) => f.stance.name == 'neutral').toList(),
            empty: 'None.',
          ),
          _section('Unknown or stale information'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: pick.unknowns.isEmpty
                  ? const Text('None noted.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final u in pick.unknowns)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $u'),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      );

  Widget _factorCard(List factors, {required String empty}) {
    if (factors.isEmpty) {
      return Card(
          child:
              Padding(padding: const EdgeInsets.all(12), child: Text(empty)));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final f in factors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${f.label} · ${f.source}'
                        '${f.descriptiveOnly ? ' (descriptive — inside baseline, not adjusted again)' : ''}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                        '${f.detail}'
                        '${f.adjustmentPP != 0 ? ' [adj ${f.adjustmentPP.toStringAsFixed(1)} pp]' : ''}',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small helper chip showing the market family.
class RequestKindBadgeSpacer extends StatelessWidget {
  const RequestKindBadgeSpacer({super.key, required this.market});

  final dynamic market;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$market', style: const TextStyle(fontSize: 11)),
      padding: EdgeInsets.zero,
    );
  }
}
