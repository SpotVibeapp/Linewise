import 'package:flutter/material.dart';

import '../app_services.dart';
import '../domain/models/exact_line.dart';
import '../core/ids.dart';

/// Manual entry and paste import of exact lines (CSV/JSON).
///
/// Manual lines are source-backed by definition of user-supplied provenance:
/// every stored line records `manual:…`/`import:…` source and timestamp.
class ManualEntryPage extends StatefulWidget {
  const ManualEntryPage({super.key});

  @override
  State<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends State<ManualEntryPage> {
  final _player = TextEditingController();
  final _stat = TextEditingController();
  final _value = TextEditingController();
  final _source = TextEditingController();
  final _paste = TextEditingController();
  String? _status;

  AppServices get services => AppScope.of(context);

  @override
  void dispose() {
    _player.dispose();
    _stat.dispose();
    _value.dispose();
    _source.dispose();
    _paste.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manual entry / import')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Manual line entry',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
              controller: _player,
              decoration: const InputDecoration(
                  labelText: 'Player or team', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: _stat,
              decoration: const InputDecoration(
                  labelText: 'Statistic (e.g. rush_yds)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: _value,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Exact line value (as supplied)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: _source,
              decoration: const InputDecoration(
                  labelText: 'Where did this line come from?',
                  helperText: 'Required — Linewise never invents lines.',
                  border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final source = _source.text.trim();
              if (source.isEmpty ||
                  _player.text.trim().isEmpty ||
                  _stat.text.trim().isEmpty ||
                  double.tryParse(_value.text.trim()) == null) {
                setState(() => _status =
                    'Player, statistic, numeric value and a source are all '
                        'required. Lines are never invented.');
                return;
              }
              services.lines.add(ExactLine(
                id: newId('manual'),
                market: MarketType.playerProp,
                statKey: _stat.text.trim().toLowerCase(),
                statDisplayName: _stat.text.trim(),
                value: double.parse(_value.text.trim()),
                playerName: _player.text.trim(),
                source: 'manual:$source',
                sourceTimestamp: services.clock.now(),
              ));
              services.lines.persist();
              setState(() => _status = 'Manual line stored with source '
                  '"manual:$source".');
            },
            child: const Text('Store line'),
          ),
          const Divider(height: 32),
          const Text('Paste import (CSV or JSON)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'CSV: player,stat,value,source[,timestamp] — one row per line.\n'
            'JSON: [{"player":"…","stat":"…","value":74.5,"source":"…"}]',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _paste,
            maxLines: 8,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: 'Paste rows here…'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () {
              final res = services.importService.importLines(_paste.text);
              services.lines.addAll(res.lines);
              services.lines.persist();
              setState(() {
                _status = 'Imported ${res.lines.length} line(s), '
                    '${res.errors.length} row(s) skipped.\n'
                    '${res.errors.join('\n')}';
              });
            },
            child: const Text('Import pasted rows'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!, style: const TextStyle(fontSize: 13)),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
