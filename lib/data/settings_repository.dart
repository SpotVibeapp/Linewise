import '../core/clock.dart';
import 'kv_store.dart';

/// Non-secret settings. Safe mode (default ON) is the master switch that
/// disables all The Odds API requests.
class SettingsRepository {
  SettingsRepository({required this.store, required this.clock});

  final KeyValueStore store;
  final Clock clock;

  static const String _safeModeKey = 'settings.safe_mode';
  static const String _slateOffsetKey = 'settings.slate_offset_hours';
  static const String _usageKey = 'settings.provider_usage';

  Future<bool> isSafeMode() async {
    final v = await store.read(_safeModeKey);
    return v == null ? true : v == 'true'; // default ON
  }

  Future<void> setSafeMode(bool value) =>
      store.write(_safeModeKey, value ? 'true' : 'false');

  /// Fixed offset (hours from UTC) used to derive slate dates from UTC
  /// kickoff times. Default -5 (US Eastern standard). Disclosed in the UI.
  Future<Duration> slateDateOffset() async {
    final v = await store.read(_slateOffsetKey);
    if (v == null) return const Duration(hours: -5);
    return Duration(hours: int.tryParse(v) ?? -5);
  }

  Future<void> setSlateDateOffsetHours(int hours) =>
      store.write(_slateOffsetKey, hours.toString());

  /// Last observed quota counters from response headers. Numbers only —
  /// never the API key.
  Future<ProviderUsage> providerUsage() async {
    final v = await store.read(_usageKey);
    if (v == null) return const ProviderUsage.unknown();
    final parts = v.split(',');
    return ProviderUsage(
      remaining: int.tryParse(parts.isNotEmpty ? parts[0] : ''),
      used: int.tryParse(parts.length > 1 ? parts[1] : ''),
      lastCost: int.tryParse(parts.length > 2 ? parts[2] : ''),
      observedAt: parts.length > 3 ? DateTime.tryParse(parts[3]) : null,
    );
  }

  Future<void> saveProviderUsage(ProviderUsage usage) => store.write(
      _usageKey,
      '${usage.remaining ?? ''},${usage.used ?? ''},${usage.lastCost ?? ''},'
      '${usage.observedAt?.toIso8601String() ?? ''}');
}

class ProviderUsage {
  const ProviderUsage({
    this.remaining,
    this.used,
    this.lastCost,
    this.observedAt,
  });

  const ProviderUsage.unknown()
      : remaining = null,
        used = null,
        lastCost = null,
        observedAt = null;

  final int? remaining;
  final int? used;
  final int? lastCost;
  final DateTime? observedAt;
}
