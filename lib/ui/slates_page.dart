import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/billing/cost_model.dart';
import '../data/espn_client.dart';
import '../domain/models/slate_date.dart';
import '../domain/sports.dart';
import 'widgets.dart';

/// Slates with **exact** slate-date filtering (calendar-day equality only).
class SlatesPage extends StatefulWidget {
  const SlatesPage({super.key});

  @override
  State<SlatesPage> createState() => _SlatesPageState();
}

class _SlatesPageState extends State<SlatesPage> {
  SportLeague _sport = supportedSports.first;
  SlateDate _date = SlateDate.fromUtc(DateTime.now().toUtc());
  List<SlateGame> _games = const [];
  bool _busy = false;
  String? _status;

  AppServices get services => AppScope.of(context);

  Future<void> _load() async {
    final services = this.services;
    setState(() {
      _busy = true;
      _status = 'Loading slate for exact date ${_date.iso} '
          '(FREE public source — 0 credits)…';
    });
    try {
      final games = await services.search.slate(_sport, _date);
      // Exact slate-date filtering: only the chosen calendar day is shown.
      final exact = games
          .where((g) => SlateDate.fromUtc(g.commenceUtc,
                  offset: const Duration(hours: -5))
              .matchesExactly(_date))
          .toList();
      setState(() {
        _games = exact;
        _status = exact.isEmpty
            ? 'No games on ${_date.iso} (exact date filter). '
                'Nothing was invented or approximated.'
            : '${exact.length} game(s) on ${_date.iso} (exact match).';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          RequestKindBadge(kind: RequestKind.freePublicHistory),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Exact slate date: ${_date.iso}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          DropdownButton<SportLeague>(
            value: _sport,
            items: [
              for (final s in supportedSports)
                DropdownMenuItem(value: s, child: Text(s.displayName)),
            ],
            onChanged: (s) => setState(() => _sport = s ?? _sport),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_date.iso),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date.asUtcDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null) {
                setState(() =>
                    _date = SlateDate(picked.year, picked.month, picked.day));
              }
            },
          ),
          FilledButton(
            onPressed: _busy ? null : _load,
            child: const Text('Load slate'),
          ),
        ]),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_status!, style: const TextStyle(fontSize: 13)),
          ),
        if (_busy) const LinearProgressIndicator(),
        const SectionHeader(
            title: 'Games (exact date only)',
            kind: RequestKind.freePublicHistory),
        for (final g in _games)
          Card(
            child: ListTile(
              dense: true,
              title: Text('${g.awayTeam} @ ${g.homeTeam}'),
              subtitle: Text(
                '${g.commenceUtc.toIso8601String()}'
                '${g.venueName != null ? ' · ${g.venueName}' : ''}'
                '${g.venueOutdoor == true ? ' · outdoor' : g.venueOutdoor == false ? ' · indoor' : ''}',
              ),
            ),
          ),
        const SectionHeader(
          title: 'Team market lines loaded in-app',
          kind: RequestKind.loadedLineFiltering,
          subtitle:
              'Moneyline, spread and total lines already loaded (local). Use '
              'Players → provider loading for billable exact lines.',
        ),
        Builder(builder: (context) {
          final teamLines =
              services.lines.all.where((l) => l.playerName == null).toList();
          if (teamLines.isEmpty) {
            return const Text(
              'No team lines loaded. Manual entry/import works without any '
              'provider request.',
              style: TextStyle(fontSize: 13),
            );
          }
          return Column(children: [
            for (final l in teamLines)
              ListTile(
                dense: true,
                title: Text(
                    '${l.teamId ?? ''} · ${l.statDisplayName} ${l.value ?? ''}'),
                subtitle: Text(l.source),
              ),
          ]);
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}
