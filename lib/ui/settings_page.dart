import 'package:flutter/material.dart';

import '../app_model.dart';
import '../app_services.dart';
import 'app.dart';
import '../data/billing/cost_model.dart';
import 'widgets.dart';

/// Settings: API key (encrypted Android storage), safe mode, slate-date
/// offset, provider usage and redacted diagnostics.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _keyInput = TextEditingController();
  bool _safeMode = true;
  bool _hasKey = false;
  int _offsetHours = -5;
  String? _status;
  String? _usageText;

  AppServices get services => AppScope.of(context);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final services = this.services;
    final safe = await services.settings.isSafeMode();
    final hasKey = await services.hasApiKey();
    final offset = await services.settings.slateDateOffset();
    final usage = await services.settings.providerUsage();
    if (!mounted) return;
    setState(() {
      _safeMode = safe;
      services.safeModeCache = safe;
      _hasKey = hasKey;
      _offsetHours = offset.inHours;
      _usageText = usage.remaining == null
          ? 'No provider usage observed yet.'
          : 'Remaining credits: ${usage.remaining} · used: ${usage.used} · '
              'last request cost: ${usage.lastCost} · '
              'observed: ${usage.observedAt?.toIso8601String()}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionHeader(title: 'The Odds API key'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_hasKey
                    ? 'A key IS configured. It is kept in encrypted Android '
                        'storage (Android Keystore), excluded from backups, and '
                        'is never shown again, logged, or exported.'
                    : 'No key configured. Provider requests are impossible until '
                        'you add your own key. Free public sources and local '
                        'features work without it.'),
                const SizedBox(height: 8),
                TextField(
                  controller: _keyInput,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Paste your The Odds API key',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton(
                    onPressed: () async {
                      final services = this.services;
                      final v = _keyInput.text.trim();
                      if (v.isEmpty) return;
                      await services.apiKeyStore.writeKey(v);
                      _keyInput.clear();
                      await _refresh();
                      setState(() => _status =
                          'Key saved to encrypted Android storage. It will be '
                              'preserved across normal signed updates and is never '
                              'included in backups, logs, exports or source.');
                    },
                    child: const Text('Save key (encrypted)'),
                  ),
                  if (_hasKey)
                    OutlinedButton(
                      onPressed: () async {
                        final services = this.services;
                        await services.apiKeyStore.deleteKey();
                        await _refresh();
                        setState(
                            () => _status = 'Key removed from the device.');
                      },
                      child: const Text('Remove key'),
                    ),
                ]),
              ],
            ),
          ),
        ),
        SectionHeader(title: 'Safe mode'),
        Card(
          child: SwitchListTile(
            title: const Text('Safe mode (disable all The Odds API requests)'),
            subtitle: Text(kSafeModeHelp),
            value: _safeMode,
            onChanged: (v) async {
              final services = this.services;
              await services.setSafeMode(v);
              await _refresh();
            },
          ),
        ),
        SectionHeader(title: 'Request classes'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final kind in RequestKind.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RequestKindBadge(kind: kind),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(kind.costClassLabel,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                const Text(kBillableHelp, style: TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                const Text(
                  'Never contacted: private Underdog endpoints. Exact '
                  'Higher/Lower lines appear only when a permitted source or '
                  'your own manual entry actually supplies them.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        SectionHeader(title: 'Provider usage'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Text(_usageText ?? '…', style: const TextStyle(fontSize: 13)),
          ),
        ),
        SectionHeader(title: 'Slate-date derivation'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Slate dates are exact calendar days. When derived from a UTC '
                  'kickoff the app applies a fixed, disclosed offset '
                  '($_offsetHours h from UTC). Filtering is exact equality only.',
                  style: const TextStyle(fontSize: 13),
                ),
                Row(children: [
                  const Text('Offset hours: '),
                  DropdownButton<int>(
                    value: _offsetHours,
                    items: const [
                      DropdownMenuItem(value: -8, child: Text('-8')),
                      DropdownMenuItem(value: -7, child: Text('-7')),
                      DropdownMenuItem(value: -6, child: Text('-6')),
                      DropdownMenuItem(value: -5, child: Text('-5 (default)')),
                      DropdownMenuItem(value: -4, child: Text('-4')),
                      DropdownMenuItem(value: 0, child: Text('0')),
                    ],
                    onChanged: (v) async {
                      if (v == null) return;
                      final services = this.services;
                      await services.settings.setSlateDateOffsetHours(v);
                      await _refresh();
                    },
                  ),
                ]),
              ],
            ),
          ),
        ),
        SectionHeader(title: 'About'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Linewise $kAppVersion (versionCode $kVersionCode)'),
                const Text(
                  'Research and record-keeping tool. No bet placement. No '
                  'automatic settlement. Never claims guaranteed accuracy.',
                  style: TextStyle(fontSize: 12),
                ),
                Text(
                    'Diagnostics (redacted): ${services.log.lines.length} lines',
                    style: const TextStyle(fontSize: 12)),
                if (_status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_status!, style: const TextStyle(fontSize: 13)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
