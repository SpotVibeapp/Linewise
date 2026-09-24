/// Redaction of secrets from anything that could reach logs, exports or UI.
///
/// The Odds API key travels in a query parameter (`apiKey=...`), so every log
/// line and error message is scrubbed here before it can be stored anywhere.
library;

// Quote characters appear as regex escapes (\x22 = ", \x27 = ') because a Dart
// raw string cannot contain its own quote character.
final RegExp _apiKeyParam =
    RegExp(r'(apiKey=)[^&\s\x22\x27\\]+', caseSensitive: false);
final RegExp _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false);
final RegExp _keyLabel = RegExp(
  r'((?:api[_-]?key|access[_-]?token|secret|password)[\x22\s:=]+)'
  r"(?:\x27[^\x27]*\x27|\x22[^\x22]*\x22|[^\s\x22\x27,;]+)",
  caseSensitive: false,
);

/// Returns [input] with any credential-looking material replaced by a marker.
String redactSecrets(String input) {
  var out = input.replaceAllMapped(_apiKeyParam, (m) => '${m[1]}<redacted>');
  out = out.replaceAllMapped(_bearer, (m) => '${m[1]}<redacted>');
  out = out.replaceAllMapped(_keyLabel, (m) => '${m[1]}<redacted>');
  return out;
}

/// True if [input] still appears to contain credential material.
bool looksSecret(String input) {
  final stripped = input
      .replaceAll('apiKey=<redacted>', '')
      .replaceAll('Bearer <redacted>', '');
  return _apiKeyParam.hasMatch(stripped) || _bearer.hasMatch(stripped);
}
