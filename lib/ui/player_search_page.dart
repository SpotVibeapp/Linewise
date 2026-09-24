import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/billing/cost_model.dart';
import '../domain/models/exact_line.dart';
import '../domain/models/pick.dart';
import '../domain/models/slate_date.dart';
import '../domain/sports.dart';
import 'widgets.dart';

/// Safe player search — the Derrick Henry fix.
///
/// Every action on this screen is labeled with its request class:
/// * Search → loaded-line filtering (LOCAL, 0 credits) + free public search.
/// * Player-history analysis → free public (ESPN, 0 credits).
/// * Market discovery → provider listings (0 credits, explicit approval).
/// * Load exact provider lines → BILLABLE (markets × regions credits, explicit
///   cost preview with the zero-line warning, blocked in safe mode).
///
/// Typing, pressing "Search" or running history analysis NEVER issues a
/// billable request (structurally enforced: this page only calls
/// [PlayerSearchService], which has no provider access).
class PlayerSearchPage extends StatefulWidget {
  const PlayerSearchPage({super.key});

  @override
  State<PlayerSearchPage> createState() => _PlayerSearchPageState();
}

class _PlayerSearchPageState extends State<PlayerSearchPage> {
  final TextEditingController _controller = TextEditingController();
  SportLeague _sport = supportedSports.first;
  bool _busy = false;
  String? _status;
  dynamic _result; // PlayerSearchResult?
  dynamic _history; // SubjectHistory?
  List<dynamic> _generated = const [];
  List<dynamic> _providerEvents = const [];
  String? _selectedEventId;
  final Set<String> _selectedMarkets = {};

  AppServices get services => AppScope.of(context);

  Future<void> _runSearch() async {
    setState(() {
      _busy = true;
      _status = 'Loaded-line filtering + free public search… (LOCAL/FREE — '
          '0 credits, no billable request)';
      _result = null;
      _history = null;
      _generated = const [];
      _providerEvents = const [];
    });
    try {
      final res = await services.search.search(_controller.text);
      setState(() {
        _result = res;
        _status = res.hasNoMatches
            ? res.emptyStateMessage
            : '${res.loadedLines.length} loaded line(s) matched locally. '
                '${res.athletes.length} free public player result(s).';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyzeHistory(dynamic athlete) async {
    final services = this.services;
    setState(() {
      _busy = true;
      _status =
          'Free public player-history analysis (ESPN)… (FREE — 0 credits)';
    });
    try {
      final history =
          await services.search.analyzeHistory(sport: _sport, athlete: athlete);
      final slateDate = SlateDate.fromUtc(services.clock.now());
      final generated = services.playerGenerator.generate(
        subjectId: athlete.id,
        subjectName: athlete.displayName,
        sportId: _sport.id,
        slateDate: slateDate,
        history: history,
        linesByStatKey:
            services.lines.linesByStatForPlayer(athlete.displayName),
      );
      setState(() {
        _history = history;
        _generated = generated;
        services.model.setLastGenerated(generated.cast<PickCandidate>());
        final withLine =
            generated.where((p) => (p as PickCandidate).line != null).length;
        _status = 'History: ${history.observations.length} observation rows. '
            '${generated.length} Higher/Lower candidate rows generated '
            '($withLine with an exact line). Everything above was free — '
            'no Odds API credits used.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discoverEvents() async {
    final services = this.services;
    setState(() {
      _busy = true;
      _status = 'Market discovery via provider… (PROVIDER — 0 credits)';
    });
    try {
      final res = await services.loader.discoverEvents(_sport);
      setState(() {
        _providerEvents = res.value;
        _status = res.value.isEmpty
            ? 'Provider lists zero events for ${_sport.displayName}. '
                'This discovery call cost 0 credits.'
            : '${res.value.length} provider event(s). Discovery cost 0 credits '
                '(does not count against quota). Remaining quota: '
                '${res.usage.remaining ?? 'unknown'}.';
      });
    } catch (e) {
      setState(() => _status = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadExactLines() async {
    final services = this.services;
    final eventId = _selectedEventId;
    if (eventId == null || _selectedMarkets.isEmpty) return;
    final markets = _selectedMarkets.toList()..sort();
    final estimate = services.odds.costModel
        .oddsRequest(markets: markets, regions: const ['us']);
    // The gate re-checks safe mode + approval; the dialog shows the full
    // cost explanation including the zero-line warning.
    try {
      final res = await services.loader.loadExactLines(
        sport: _sport,
        eventId: eventId,
        markets: markets,
      );
      services.lines.addAll(res.value);
      await services.lines.persist();
      setState(() {
        _status = res.value.isEmpty
            ? 'Request completed and may still have consumed '
                '${res.usage.lastCost ?? estimate.credits} credit(s) even though '
                'it returned ZERO lines. Exact lines depend on provider '
                'coverage and quota.'
            : 'Loaded ${res.value.length} exact provider line(s). '
                'Last cost: ${res.usage.lastCost ?? '?'} credit(s). '
                'Remaining quota: ${res.usage.remaining ?? 'unknown'}.';
      });
    } catch (e) {
      setState(() => _status = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 8, runSpacing: 4, children: [
          RequestKindBadge(kind: RequestKind.loadedLineFiltering),
          RequestKindBadge(kind: RequestKind.freePublicHistory),
          RequestKindBadge(kind: RequestKind.marketDiscovery),
          RequestKindBadge(kind: RequestKind.exactProviderLines),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Searching a player never makes a billable request. Empty searches '
          'offer free public player-history analysis (no Odds API credits).',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Player name (e.g. Derrick Henry)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _runSearch(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _busy ? null : _runSearch,
            child: const Text('Search'),
          ),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<SportLeague>(
          value: _sport,
          decoration: const InputDecoration(
              labelText: 'Sport / league',
              border: OutlineInputBorder(),
              isDense: true),
          items: [
            for (final s in supportedSports)
              DropdownMenuItem(value: s, child: Text(s.displayName)),
          ],
          onChanged: (s) => setState(() => _sport = s ?? _sport),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_status!, style: const TextStyle(fontSize: 13)),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (result != null) ...[
          SectionHeader(
            title: 'Loaded lines matched (local filter)',
            kind: RequestKind.loadedLineFiltering,
            subtitle: 'Lines already loaded into the app. Filtering is free.',
          ),
          if ((result.loadedLines as List).isEmpty)
            const Text('No loaded lines matched.',
                style: TextStyle(fontSize: 13))
          else
            for (final line in result.loadedLines as List<ExactLine>)
              ListTile(
                dense: true,
                title: Text(
                    '${line.playerName ?? line.teamId} · ${line.statDisplayName}'
                    ' ${line.value ?? ''}'),
                subtitle: Text(
                    '${line.source} · ${line.sourceTimestamp.toIso8601String()}'),
              ),
          SectionHeader(
            title: 'Free public player results',
            kind: RequestKind.freePublicHistory,
            subtitle:
                'Even with zero loaded lines, history analysis is free and needs no credits.',
          ),
          for (final athlete in result.athletes as List)
            Card(
              child: ExpansionTile(
                title: Text('${athlete.displayName}'),
                subtitle: Text(
                    '${athlete.teamName ?? ''} ${athlete.position ?? ''}'
                        .trim()),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FilledButton.tonal(
                          onPressed:
                              _busy ? null : () => _analyzeHistory(athlete),
                          child: const Text('Run free player-history analysis'),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Produces Higher/Lower candidates for every '
                          'statistic with ≥20 valid observations. Uses public '
                          'game logs only — 0 credits.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          SectionHeader(
            title: 'Exact provider lines (billable)',
            kind: RequestKind.exactProviderLines,
            subtitle: kBillableHelp,
          ),
          _providerPanel(),
        ],
        if (_generated.isNotEmpty) ...[
          SectionHeader(
              title: 'Candidates (incl. withheld)',
              kind: RequestKind.freePublicHistory),
          for (final p in _generated) PickListTile(pick: p as PickCandidate),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _providerPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(services.safeModeCache
                ? 'Safe mode: ON — provider requests disabled.'
                : 'Safe mode: OFF — provider requests allowed after explicit '
                    'cost approval.'),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton(
                onPressed: _busy ? null : _discoverEvents,
                child: const Text('Discover provider events (0 credits)'),
              ),
            ]),
            if (_providerEvents.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: 'Provider event',
                    border: OutlineInputBorder(),
                    isDense: true),
                items: [
                  for (final ev in _providerEvents)
                    DropdownMenuItem(
                      value: ev.id as String,
                      child: Text('${ev.awayTeam} @ ${ev.homeTeam}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() => _selectedEventId = id),
              ),
              const SizedBox(height: 8),
              const Text('Player prop markets:',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 4,
                children: [
                  for (final m in kPlayerPropMarketsBySport[_sport.id] ??
                      const <String>[])
                    FilterChip(
                      label: Text(m, style: const TextStyle(fontSize: 11)),
                      selected: _selectedMarkets.contains(m),
                      onSelected: (sel) => setState(() {
                        sel
                            ? _selectedMarkets.add(m)
                            : _selectedMarkets.remove(m);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700),
                onPressed: (_busy ||
                        services.safeModeCache ||
                        _selectedMarkets.isEmpty)
                    ? null
                    : _loadExactLines,
                icon: const Icon(Icons.payments_outlined),
                label: Text(
                  'Load exact provider lines — BILLABLE '
                  '(${_selectedMarkets.length} market(s) × 1 region = '
                  '${_selectedMarkets.length} credit(s))',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                services.safeModeCache ? kSafeModeHelp : kZeroLineHelp,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
