import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_model.dart';
import 'core/clock.dart';
import 'core/logger.dart';
import 'data/billing/billable_gate.dart';
import 'data/billing/cost_model.dart';
import 'data/calibration_repository.dart';
import 'data/espn_client.dart';
import 'data/export_service.dart';
import 'data/import_service.dart';
import 'data/key_store.dart';
import 'data/kv_store.dart';
import 'data/line_repository.dart';
import 'data/odds_api_client.dart';
import 'data/open_meteo_client.dart';
import 'data/player_search_service.dart';
import 'data/settings_repository.dart';
import 'data/snapshot_repository.dart';
import 'domain/generation/player_generator.dart';
import 'domain/generation/team_generator.dart';
import 'domain/models/exact_line.dart';
import 'domain/probability/engine.dart';
import 'domain/sports.dart';

/// Approval wired to a UI dialog (set by the UI at startup). Without a UI
/// handler, nothing is ever approved.
class CallbackUserApproval implements UserApprovalPort {
  Future<bool> Function(CreditCostEstimate estimate)? handler;

  @override
  Future<bool> confirmProviderRequest(CreditCostEstimate estimate) async {
    final h = handler;
    if (h == null) return false;
    return h(estimate);
  }
}

/// The ONLY service allowed to touch The Odds API.
///
/// Player search ([PlayerSearchService]) has no reference to this loader or to
/// [OddsApiClient]; the only path to billable requests is an explicit user
/// action that passes [BillableGate] (safe mode + cost approval).
class ProviderLineLoader {
  ProviderLineLoader({
    required this.client,
    required this.costModel,
  });

  final OddsApiClient client;
  final OddsCostModel costModel;

  /// Market discovery — provider events listing (0 credits).
  Future<ProviderCallResult<List<ProviderEvent>>> discoverEvents(
          SportLeague sport) =>
      client.listEvents(sport.oddsApiKey);

  /// Market discovery — provider sports listing (0 credits).
  Future<ProviderCallResult<List<SportKeyEntry>>> discoverSports() =>
      client.listSports();

  /// Exact provider-line loading — BILLABLE (markets × regions credits).
  Future<ProviderCallResult<List<ExactLine>>> loadExactLines({
    required SportLeague sport,
    required String eventId,
    required List<String> markets,
    List<String> regions = const ['us'],
  }) =>
      client.fetchEventOdds(
        sportKey: sport.oddsApiKey,
        eventId: eventId,
        markets: markets,
        regions: regions,
      );

  /// Team markets for a whole sport — BILLABLE (markets × regions credits).
  Future<ProviderCallResult<List<ExactLine>>> loadTeamOdds({
    required SportLeague sport,
    List<String> markets = kTeamMarkets,
    List<String> regions = const ['us'],
  }) =>
      client.fetchOdds(
        sportKey: sport.oddsApiKey,
        markets: markets,
        regions: regions,
      );
}

/// Composition root. No secrets are held here.
class AppServices {
  AppServices({
    required this.clock,
    required this.apiKeyStore,
    required this.kvStore,
    required Directory storage,
    http.Client? client,
  })  : httpClient = client ?? http.Client(),
        log = AppLog(),
        settings = SettingsRepository(store: kvStore, clock: clock),
        approval = CallbackUserApproval() {
    gate = BillableGate(
      isSafeMode: () => safeModeCache,
      approval: approval,
      clock: clock,
    );
    espn = EspnClient(httpClient: httpClient, log: log, clock: clock);
    openMeteo = OpenMeteoClient(httpClient: httpClient, log: log, clock: clock);
    odds = OddsApiClient(
      httpClient: httpClient,
      apiKeyStore: apiKeyStore,
      settings: settings,
      gate: gate,
      log: log,
      clock: clock,
    );
    loader = ProviderLineLoader(client: odds, costModel: const OddsCostModel());
    lines = LineRepository(storageDir: Directory('${storage.path}/lines'));
    snapshots =
        SnapshotRepository(storageDir: Directory('${storage.path}/snapshots'));
    calibration = CalibrationRepository(
        storageDir: Directory('${storage.path}/calibration'));
    search = PlayerSearchService(esp: espn, lineRepository: lines);
    engine = ProbabilityEngine(clock: clock);
    playerGenerator = PlayerGenerator(engine: engine);
    teamGenerator = TeamGenerator(engine: engine);
    model = AppModel(
      lines: lines,
      snapshots: snapshots,
      calibration: calibration,
    );
    exportService = const ExportService();
    importService = const ImportService();
  }

  final Clock clock;
  final ApiKeyStore apiKeyStore;
  final KeyValueStore kvStore;
  final http.Client httpClient;
  final AppLog log;
  final SettingsRepository settings;
  final CallbackUserApproval approval;
  late final ExportService exportService;
  late final ImportService importService;

  late final BillableGate gate;
  late final EspnClient espn;
  late final OpenMeteoClient openMeteo;
  late final OddsApiClient odds;
  late final ProviderLineLoader loader;
  late final LineRepository lines;
  late final SnapshotRepository snapshots;
  late final CalibrationRepository calibration;
  late final PlayerSearchService search;
  late final ProbabilityEngine engine;
  late final PlayerGenerator playerGenerator;
  late final TeamGenerator teamGenerator;
  late final AppModel model;

  /// Cached mirror of the safe-mode setting (sync read for the gate).
  bool safeModeCache = true;

  Future<void> init() async {
    safeModeCache = await settings.isSafeMode();
    await lines.load();
    await calibration.load();
  }

  Future<void> setSafeMode(bool value) async {
    safeModeCache = value;
    await settings.setSafeMode(value);
  }

  /// Never logs or returns the key.
  Future<bool> hasApiKey() => apiKeyStore.hasKey();
}

/// Request-class labels used for the always-visible cost badges.
const Map<RequestKind, String> requestKindBadges = {
  RequestKind.loadedLineFiltering: 'LOCAL · 0 credits',
  RequestKind.freePublicHistory: 'FREE · 0 credits',
  RequestKind.marketDiscovery: 'PROVIDER · 0 credits',
  RequestKind.exactProviderLines: 'PROVIDER · BILLABLE',
};

/// Shared doc strings.
const String kSafeModeHelp =
    'Safe mode disables all The Odds API requests. Free public sources and '
    'local filtering keep working.';

const String kZeroLineHelp =
    'A request can consume credits even when it returns zero lines.';

const String kBillableHelp =
    'Exact provider-line loading is billable (markets × regions credits). '
    '$kZeroLineHelp Searching a player never triggers it.';
