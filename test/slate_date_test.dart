import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/domain/models/slate_date.dart';

void main() {
  group('SlateDate', () {
    test('parses strict YYYY-MM-DD only', () {
      expect(SlateDate.parse('2026-09-24').iso, '2026-09-24');
      expect(() => SlateDate.parse('2026-9-24'), throwsFormatException);
      expect(() => SlateDate.parse('09/24/2026'), throwsFormatException);
      expect(
          () => SlateDate.parse('2026-09-24T00:00:00Z'), throwsFormatException);
      expect(() => SlateDate.parse(''), throwsFormatException);
    });

    test('exact slate-date filtering is equality — never ranges', () {
      final a = SlateDate.parse('2026-09-24');
      final b = SlateDate.parse('2026-09-24');
      final c = SlateDate.parse('2026-09-25');
      expect(a.matchesExactly(b), isTrue);
      expect(a.matchesExactly(c), isFalse);
      expect(a == b, isTrue);
      expect(a == c, isFalse);
    });

    test('derives slate date from UTC kickoff with fixed disclosed offset', () {
      // 2026-09-25 01:30 UTC is 2026-09-24 20:30 at UTC-5.
      final kickoff = DateTime.utc(2026, 9, 25, 1, 30);
      final slate = SlateDate.fromUtc(kickoff);
      expect(slate.iso, '2026-09-24');
      final slateUtc = SlateDate.fromUtc(kickoff, offset: Duration.zero);
      expect(slateUtc.iso, '2026-09-25');
    });
  });
}
