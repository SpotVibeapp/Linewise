import 'package:flutter/material.dart';

import '../app_services.dart';
import '../domain/models/pick.dart';
import 'widgets.dart';

/// Generated candidates (defensible + withheld) and snapshot creation/export.
class PicksPage extends StatefulWidget {
  const PicksPage({super.key});

  @override
  State<PicksPage> createState() => _PicksPageState();
}

class _PicksPageState extends State<PicksPage> {
  String _filter = 'all';
  String? _status;

  AppServices get services => AppScope.of(context);

  @override
  Widget build(BuildContext context) {
    final all = services.model.lastGenerated;
    final picks = all.where((p) {
      if (_filter == 'defensible') return p.isDefensible;
      if (_filter == 'withheld') return !p.isDefensible;
      return true;
    }).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 8, children: [
          ChoiceChip(
            label: const Text('All'),
            selected: _filter == 'all',
            onSelected: (_) => setState(() => _filter = 'all'),
          ),
          ChoiceChip(
            label: const Text('Defensible'),
            selected: _filter == 'defensible',
            onSelected: (_) => setState(() => _filter = 'defensible'),
          ),
          ChoiceChip(
            label: const Text('Withheld'),
            selected: _filter == 'withheld',
            onSelected: (_) => setState(() => _filter = 'withheld'),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          '${all.length} candidate row(s), '
          '${all.where((p) => p.isDefensible).length} defensible, '
          '${all.where((p) => !p.isDefensible).length} withheld. '
          '$kNoGuaranteeDisclaimer',
          style: const TextStyle(fontSize: 12),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_status!, style: const TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: const Text('Save immutable snapshot'),
            onPressed: all.isEmpty
                ? null
                : () async {
                    final services = this.services;
                    final snap = await services.model.saveSnapshot(
                      createdAt: services.clock.now(),
                      generatorVersion: kGeneratorVersion,
                      notes: 'Generated from the Picks screen',
                    );
                    setState(() {
                      _status =
                          'Snapshot saved (immutable, append-only). id: ${snap.id}';
                    });
                  },
          ),
        ]),
        const SizedBox(height: 8),
        for (final p in picks) PickListTile(pick: p),
        const SizedBox(height: 24),
      ],
    );
  }
}
