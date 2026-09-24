import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:linewise/core/clock.dart';
import 'package:linewise/data/snapshot_repository.dart';
import 'package:linewise/domain/generation/player_generator.dart';
import 'package:linewise/domain/models/player_history.dart';
import 'package:linewise/domain/models/slate_date.dart';
import 'package:linewise/domain/models/snapshot.dart';
import 'package:linewise/domain/probability/engine.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('snap_test');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  PredictionSnapshot build(FixedClock clock, {String? tag}) {
    final generator = PlayerGenerator(engine: ProbabilityEngine(clock: clock));
    final obs = <StatObservation>[
      for (var i = 0; i < 21; i++)
        StatObservation(
            statKey: 'rush_yds',
            value: 70.0 + i + (tag == null ? 0 : 1),
            gameDate: DateTime.utc(2026, 8, 1 + i),
            source: 'ESPN gamelog'),
    ];
    final picks = generator.generate(
      subjectId: 'a-1',
      subjectName: 'Derrick Henry',
      sportId: 'nfl',
      slateDate: SlateDate.parse('2026-09-24'),
      history: SubjectHistory(
        subjectId: 'a-1',
        subjectName: 'Derrick Henry',
        observations: obs,
        source: 'ESPN public gamelog',
        fetchedAt: clock.now(),
      ),
      linesByStatKey: const {},
    );
    return PredictionSnapshot.create(
      createdAt: clock.now(),
      generatorVersion: 'test-gen',
      picks: picks,
      notes: tag,
    );
  }

  test('snapshots are immutable: same id cannot be overwritten', () async {
    final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
    final repo = SnapshotRepository(storageDir: dir);
    final snap = build(clock);
    await repo.save(snap);
    expect(() => repo.save(snap), throwsStateError);
  });

  test('content hash verifies intact snapshots and detects tampering',
      () async {
    final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
    final repo = SnapshotRepository(storageDir: dir);
    final snap = build(clock);
    await repo.save(snap);
    expect(await repo.verify(snap.id), isTrue);

    // Tamper directly with the stored bytes.
    final file = File('${dir.path}/${snap.id}.json');
    final tampered = (jsonDecode(await file.readAsString()) as Map)
      ..['notes'] = 'tampered';
    await file.writeAsString(jsonEncode(tampered));
    expect(await repo.verify(snap.id), isFalse);
  });

  test('identical payloads hash identically; changed payloads differ', () {
    final clock = FixedClock(DateTime.utc(2026, 9, 24, 12));
    final a = build(clock);
    final b = build(clock);
    expect(a.id, b.id);
    final c = build(clock, tag: 'different');
    expect(c.id, isNot(a.id));
    expect(PredictionSnapshot.verifyIntegrity(a.id, a.payload), isTrue);
  });
}
