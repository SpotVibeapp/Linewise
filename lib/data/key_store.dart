import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for the user's The Odds API key.
///
/// The production implementation keeps the key in encrypted Android storage
/// (Android Keystore via flutter_secure_storage) so it survives normal signed
/// updates while remaining excluded from backups (`android:allowBackup` is
/// false) and out of logs, exports and source.
abstract class ApiKeyStore {
  Future<String?> readKey();

  Future<void> writeKey(String value);

  Future<void> deleteKey();

  /// Never returns the key itself.
  Future<bool> hasKey();
}

class SecureApiKeyStore implements ApiKeyStore {
  SecureApiKeyStore()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  final FlutterSecureStorage _storage;
  static const String _keyName = 'linewise.odds_api_key.v1';

  @override
  Future<String?> readKey() => _storage.read(key: _keyName);

  @override
  Future<void> writeKey(String value) =>
      _storage.write(key: _keyName, value: value);

  @override
  Future<void> deleteKey() => _storage.delete(key: _keyName);

  @override
  Future<bool> hasKey() async => (await _storage.read(key: _keyName)) != null;
}

/// In-memory store for tests and fallback when secure storage is unavailable.
class MemoryApiKeyStore implements ApiKeyStore {
  String? _value;

  @override
  Future<String?> readKey() async => _value;

  @override
  Future<void> writeKey(String value) async => _value = value;

  @override
  Future<void> deleteKey() async => _value = null;

  @override
  Future<bool> hasKey() async => _value != null;
}
