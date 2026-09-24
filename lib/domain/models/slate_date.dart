/// Exact slate date (a calendar day, e.g. 2026-09-24).
///
/// Slate-date filtering is exact equality on the calendar day — never ranges,
/// never "closest game", never timezone guessing at filter time. The offset
/// used when *deriving* a slate date from a UTC kickoff is configurable and
/// fixed (default US Eastern standard offset, UTC-5), and the derivation is
/// done exactly once when data is ingested.
class SlateDate implements Comparable<SlateDate> {
  SlateDate(this.year, this.month, this.day)
      : assert(month >= 1 && month <= 12),
        assert(day >= 1 && day <= 31);

  /// Strict `YYYY-MM-DD` parse. Throws [FormatException] on anything else.
  factory SlateDate.parse(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text.trim());
    if (m == null) {
      throw FormatException('Slate date must be YYYY-MM-DD, got "$text"');
    }
    return SlateDate(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  /// Derives the slate date from a UTC instant using a fixed [offset].
  ///
  /// The default offset is UTC-5 (US Eastern standard time). It is a fixed,
  /// disclosed offset — not a timezone database guess — so the mapping from
  /// kickoff to slate date is deterministic and reproducible.
  factory SlateDate.fromUtc(
    DateTime utc, {
    Duration offset = const Duration(hours: -5),
  }) {
    final shifted = utc.toUtc().add(offset);
    return SlateDate(shifted.year, shifted.month, shifted.day);
  }

  final int year;
  final int month;
  final int day;

  String get iso =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  DateTime get asUtcDate => DateTime.utc(year, month, day);

  /// Exact slate-date match — the only filter semantics in the app.
  bool matchesExactly(SlateDate other) =>
      year == other.year && month == other.month && day == other.day;

  @override
  int compareTo(SlateDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) => other is SlateDate && matchesExactly(other);

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}
