import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/core/redaction.dart';

void main() {
  test('apiKey query values are redacted', () {
    final url = 'https://api.the-odds-api.com/v4/sports/x/odds?apiKey=SECRET123&regions=us';
    final safe = redactSecrets(url);
    expect(safe, contains('apiKey=<redacted>'));
    expect(safe, isNot(contains('SECRET123')));
  });

  test('bearer tokens and labeled secrets are redacted', () {
    expect(redactSecrets('Bearer abc.def-123'),
        'Bearer <redacted>');
    expect(redactSecrets('password=hunter2'),
        'password=<redacted>');
  });

  test('looksSecret detects leftover credentials', () {
    expect(looksSecret('apiKey=<redacted>&regions=us'), isFalse);
    expect(looksSecret('https://x.dev/?apiKey=abc123'), isTrue);
    expect(looksSecret('plain text about markets and regions'), isFalse);
  });

  test('error objects are scrubbed before logging', () {
    final err = Exception('GET https://api.the-odds-api.com/v4/x?apiKey=TOPSECRET failed');
    final text = redactSecrets(err.toString());
    expect(text, isNot(contains('TOPSECRET')));
  });
}
