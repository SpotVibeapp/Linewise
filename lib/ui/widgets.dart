import 'package:flutter/material.dart';

import '../data/billing/cost_model.dart';
import '../domain/models/pick.dart';
import 'pick_detail_page.dart';

/// Chips showing evidence quality and status.
class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.quality});

  final String quality;

  @override
  Widget build(BuildContext context) {
    final color = quality == 'High'
        ? Colors.green.shade700
        : quality == 'Medium'
            ? Colors.orange.shade800
            : Colors.red.shade700;
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('Evidence: $quality',
          style: TextStyle(fontSize: 11, color: color)),
      side: BorderSide(color: color),
      backgroundColor: Colors.transparent,
      padding: EdgeInsets.zero,
    );
  }
}

/// Compact tile for one pick candidate row in lists.
class PickListTile extends StatelessWidget {
  const PickListTile({super.key, required this.pick});

  final PickCandidate pick;

  @override
  Widget build(BuildContext context) {
    final defensible = pick.isDefensible;
    final e = pick.estimate;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: ListTile(
        dense: true,
        title: Text(
          '${pick.direction.label} ${pick.statDisplayName}'
          '${pick.line?.value != null ? ' (${pick.line!.value})' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${pick.subjectName}'
                '${pick.gameDescription != null ? ' · ${pick.gameDescription}' : ''}'),
            const SizedBox(height: 2),
            Wrap(
              spacing: 6,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  defensible
                      ? 'Win ${e!.winPct.toStringAsFixed(1)}% · '
                          '${pick.pushLabel} ${e.pushPct.toStringAsFixed(1)}%'
                      : pick.displayProbability,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: defensible
                        ? Colors.teal.shade800
                        : Colors.grey.shade700,
                  ),
                ),
                if (defensible && pick.quality != null)
                  QualityBadge(quality: pick.quality!.label),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => PickDetailPage(pick: pick)),
          );
        },
      ),
    );
  }
}

/// Section header with a request-class badge.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.kind,
    this.subtitle,
  });

  final String title;
  final RequestKind? kind;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (kind != null)
              RequestKindBadge(kind: kind!),
          ]),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            ),
        ],
      ),
    );
  }
}

/// Labeled read-only row used on detail screens.
class FactRow extends StatelessWidget {
  const FactRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                    fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
