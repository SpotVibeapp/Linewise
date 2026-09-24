import 'redaction.dart';

/// Minimal logger that redacts secrets and keeps an in-memory ring buffer.
///
/// Nothing is printed to the system log (which could be captured by bug
/// reports); debug lines are only shown in the in-app diagnostics panel.
class AppLog {
  AppLog({this.capacity = 500});

  final int capacity;
  final List<String> lines = [];

  void info(String message) => _add('I', message);

  void warn(String message) => _add('W', message);

  void error(String message, [Object? error]) {
    final suffix = error == null ? '' : ' ${redactSecrets(error.toString())}';
    _add('E', '$message$suffix');
  }

  void _add(String level, String message) {
    final safe = redactSecrets(message);
    lines.add('${DateTime.now().toUtc().toIso8601String()} [$level] $safe');
    if (lines.length > capacity) {
      lines.removeAt(0);
    }
  }
}
