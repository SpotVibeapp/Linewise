import 'dart:math';

final Random _random = Random.secure();

/// Opaque identifier for picks, snapshots and rows.
///
/// Randomness is only used for identity; it is never used to fabricate data.
String newId(String prefix) {
  final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '$prefix-$hex';
}
