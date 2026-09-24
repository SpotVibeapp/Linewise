import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'app_services.dart';
import 'core/clock.dart';
import 'data/key_store.dart';
import 'data/kv_store.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  final services = AppServices(
    clock: const SystemClock(),
    apiKeyStore: SecureApiKeyStore(),
    kvStore: PrefsKeyValueStore(prefs),
    storage: Directory('${docs.path}/linewise'),
  );
  await services.init();
  runApp(LinewiseApp(services: services));
}
