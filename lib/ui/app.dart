import 'package:flutter/material.dart';

import '../app_services.dart';
import '../data/billing/cost_model.dart';
import 'billable_request_dialog.dart';
import 'calibration_page.dart';
import 'manual_entry_page.dart';
import 'picks_page.dart';
import 'player_search_page.dart';
import 'settings_page.dart';
import 'slates_page.dart';
import 'snapshots_page.dart';

class LinewiseApp extends StatelessWidget {
  const LinewiseApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'Linewise',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF102040),
            secondary: const Color(0xFF3498DB),
          ),
          appBarTheme: const AppBarTheme(centerTitle: false),
          cardTheme: const CardTheme(elevation: 0),
        ),
        home: const HomeShell(),
      ),
    );
  }
}

/// Simple inherited wiring.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    // Non-dependency lookup: safe from initState and event handlers.
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = [
    'Slates',
    'Players',
    'Picks',
    'Snapshots',
    'Calibration',
    'Settings',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every provider request shows the cost-preview dialog first.
    final services = AppScope.of(context);
    services.approval.handler =
        (estimate) => showBillableRequestDialog(this.context, estimate);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const SlatesPage(),
      const PlayerSearchPage(),
      const PicksPage(),
      const SnapshotsPage(),
      const CalibrationPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Linewise · ${_titles[_index]}'),
        actions: [
          IconButton(
            tooltip: 'Manual entry / import',
            icon: const Icon(Icons.edit_note),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => const ManualEntryPage()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), label: 'Slates'),
          NavigationDestination(
              icon: Icon(Icons.person_search_outlined), label: 'Players'),
          NavigationDestination(
              icon: Icon(Icons.checklist_outlined), label: 'Picks'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'Snaps'),
          NavigationDestination(
              icon: Icon(Icons.tune_outlined), label: 'Calibrate'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Shared badge showing a request class and its cost class.
class RequestKindBadge extends StatelessWidget {
  const RequestKindBadge({super.key, required this.kind});

  final RequestKind kind;

  @override
  Widget build(BuildContext context) {
    final isBillable = kind == RequestKind.exactProviderLines;
    final color = isBillable
        ? Colors.red.shade700
        : kind == RequestKind.marketDiscovery
            ? Colors.orange.shade800
            : Colors.teal.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        requestKindBadges[kind] ?? kind.label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
