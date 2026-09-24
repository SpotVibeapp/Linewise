/// One historical game observation of a statistic.
///
/// Observations are only ever ingested from source-backed data (public player
/// game logs or user-supplied manual records). [valid] is false for DNP or
/// incomplete records — those are kept for transparency but excluded from the
/// sample size used by the probability engine.
class StatObservation {
  StatObservation({
    required this.statKey,
    required this.value,
    required this.gameDate,
    required this.source,
    this.opponent,
    this.home,
    this.valid = true,
  });

  final String statKey;
  final double value;
  final DateTime gameDate;
  final String source;
  final String? opponent;
  final bool? home;

  /// False when the game must not count toward the sample (DNP etc.).
  final bool valid;

  Map<String, Object?> toMap() => {
        'statKey': statKey,
        'value': value,
        'gameDate': gameDate.toIso8601String(),
        'source': source,
        'opponent': opponent,
        'home': home,
        'valid': valid,
      };

  static StatObservation fromMap(Map<String, Object?> m) => StatObservation(
        statKey: m['statKey']! as String,
        value: (m['value']! as num).toDouble(),
        gameDate: DateTime.parse(m['gameDate']! as String),
        source: m['source']! as String,
        opponent: m['opponent'] as String?,
        home: m['home'] as bool?,
        valid: m['valid'] as bool? ?? true,
      );
}

/// Source-backed game log for one player (or team totals).
class SubjectHistory {
  SubjectHistory({
    required this.subjectId,
    required this.subjectName,
    required this.observations,
    required this.source,
    required this.fetchedAt,
    this.isTeam = false,
  });

  final String subjectId;
  final String subjectName;
  final List<StatObservation> observations;
  final String source;
  final DateTime fetchedAt;
  final bool isTeam;

  /// Valid (countable) observations per statistic key.
  Map<String, List<double>> validValuesByStat() {
    final out = <String, List<double>>{};
    for (final o in observations) {
      if (!o.valid) continue;
      out.putIfAbsent(o.statKey, () => []).add(o.value);
    }
    return out;
  }

  /// All valid + invalid observations per statistic key (for transparency).
  Map<String, List<StatObservation>> observationsByStat() {
    final out = <String, List<StatObservation>>{};
    for (final o in observations) {
      out.putIfAbsent(o.statKey, () => []).add(o);
    }
    return out;
  }

  Map<String, Object?> toMap() => {
        'subjectId': subjectId,
        'subjectName': subjectName,
        'source': source,
        'fetchedAt': fetchedAt.toIso8601String(),
        'isTeam': isTeam,
        'observations': observations.map((o) => o.toMap()).toList(),
      };

  static SubjectHistory fromMap(Map<String, Object?> m) => SubjectHistory(
        subjectId: m['subjectId']! as String,
        subjectName: m['subjectName']! as String,
        source: m['source']! as String,
        fetchedAt: DateTime.parse(m['fetchedAt']! as String),
        isTeam: m['isTeam'] as bool? ?? false,
        observations: ((m['observations']! as List).cast<Map>())
            .map((o) => StatObservation.fromMap(
                o.map((k, v) => MapEntry(k.toString(), v))))
            .toList(),
      );
}
