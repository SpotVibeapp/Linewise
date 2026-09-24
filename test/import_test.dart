import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/data/import_service.dart';
import 'package:linewise/domain/models/exact_line.dart';

void main() {
  const importer = ImportService();
  final now = DateTime.utc(2026, 9, 24, 12);

  test('imports CSV rows with required provenance', () {
    final res = importer.importLines(
      'player,stat,value,source,timestamp\n'
      'Derrick Henry,rush_yds,87.5,manual:chat,2026-09-24T10:00:00Z\n'
      'Lamar Jackson,pass_yds,232.5,manual:chat,2026-09-24T10:00:00Z\n',
      now: now,
    );
    expect(res.errors, isEmpty);
    expect(res.lines.length, 2);
    final first = res.lines.first;
    expect(first.playerName, 'Derrick Henry');
    expect(first.value, 87.5);
    expect(first.source, 'import:manual:chat');
    expect(first.sourceTimestamp.toIso8601String(), '2026-09-24T10:00:00.000Z');
    expect(first.market, MarketType.playerProp);
  });

  test('imports JSON rows and skips malformed ones with explanations', () {
    final res = importer.importLines(
      '[{"player":"A","stat":"points","value":22.5,"source":"book"},'
      '{"player":"B","stat":"rebounds"},'
      '{"nonsense":true}]',
      now: now,
    );
    expect(res.lines.length, 1);
    expect(res.errors.length, 2);
    expect(res.errors.join(' '), contains('skipped'));
  });

  test('never invents a line without player, stat and value', () {
    final res = importer.importLines('only,two\n', now: now);
    expect(res.lines, isEmpty);
    expect(res.errors, isNotEmpty);
  });
}
