import 'slate_date.dart';

/// Market families Linewise models.
enum MarketType {
  /// Team moneyline (The Odds API `h2h`).
  moneyline,

  /// Team point spread (`spreads`).
  spread,

  /// Game total (`totals`).
  total,

  /// Higher/Lower player statistic line (Underdog-style; provider `player_*`).
  playerProp,
}

/// Higher/Lower direction (Underdog wording). `Higher` maps to provider
/// "Over", `lower` maps to provider "Under". Exact provider lines are shown
/// verbatim as supplied — the app never rounds, moves or invents a line.
enum PropDirection {
  higher,
  lower;

  String get label => this == PropDirection.higher ? 'Higher' : 'Lower';

  String get providerSide => this == PropDirection.higher ? 'Over' : 'Under';
}

/// A source-backed exact line.
///
/// There is no way to construct a line without a [source] and a
/// [sourceTimestamp]; anything else is a programming error. The original raw
/// provider payload fragments are preserved verbatim in [raw] for audit, and
/// [value] keeps the exact supplied number.
class ExactLine {
  ExactLine({
    required this.id,
    required this.market,
    required this.statKey,
    required this.statDisplayName,
    required this.value,
    required this.source,
    required this.sourceTimestamp,
    this.playerName,
    this.playerId,
    this.teamId,
    this.providerEventId,
    this.providerBookmaker,
    Map<String, String>? raw,
    DateTime? loadedAt,
  })  : assert(source.trim().isNotEmpty, 'Exact lines must name their source'),
        raw = Map.unmodifiable(raw ?? const {}),
        loadedAt = loadedAt ?? sourceTimestamp;

  final String id;
  final MarketType market;

  /// Statistic key, e.g. `rush_yds`, `pass_yds`, `spread`, `total`, `moneyline`.
  final String statKey;
  final String statDisplayName;

  /// The exact line number as supplied by the source, or `null` for markets
  /// without a line number (moneyline).
  final double? value;

  /// Player name for player props; null for team markets.
  final String? playerName;
  final String? playerId;

  /// Team id/name for team markets (or the player's team).
  final String? teamId;

  /// Provenance, e.g. `The Odds API/americanfootball_nfl/fanduel/player_rush_yds`
  /// or `manual:typed-by-user` or `import:csv-2026-09-24`.
  final String source;

  /// When the source reported the line (bookmaker `last_update` for provider
  /// lines; entry time for manual lines).
  final DateTime sourceTimestamp;

  /// When this copy was loaded into the app.
  final DateTime loadedAt;

  final String? providerEventId;
  final String? providerBookmaker;
  final Map<String, String> raw;

  /// Age of the line relative to [now] — surfaced as staleness, never used to
  /// silently drop or alter the line.
  Duration ageAt(DateTime now) => now.difference(sourceTimestamp);

  Map<String, Object?> toMap() => {
        'id': id,
        'market': market.name,
        'statKey': statKey,
        'statDisplayName': statDisplayName,
        'value': value,
        'playerName': playerName,
        'playerId': playerId,
        'teamId': teamId,
        'source': source,
        'sourceTimestamp': sourceTimestamp.toIso8601String(),
        'loadedAt': loadedAt.toIso8601String(),
        'providerEventId': providerEventId,
        'providerBookmaker': providerBookmaker,
        'raw': raw,
      };

  static ExactLine fromMap(Map<String, Object?> m) => ExactLine(
        id: m['id']! as String,
        market: MarketType.values.byName(m['market']! as String),
        statKey: m['statKey']! as String,
        statDisplayName: m['statDisplayName']! as String,
        value: (m['value'] as num?)?.toDouble(),
        playerName: m['playerName'] as String?,
        playerId: m['playerId'] as String?,
        teamId: m['teamId'] as String?,
        source: m['source']! as String,
        sourceTimestamp: DateTime.parse(m['sourceTimestamp']! as String),
        loadedAt: DateTime.parse(m['loadedAt']! as String),
        providerEventId: m['providerEventId'] as String?,
        providerBookmaker: m['providerBookmaker'] as String?,
        raw: ((m['raw'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
}

/// A scheduled game (slate row).
class GameEvent {
  GameEvent({
    required this.id,
    required this.sportId,
    required this.slateDate,
    required this.commenceUtc,
    required this.homeTeam,
    required this.awayTeam,
    required this.source,
    this.providerEventId,
    this.venueName,
    this.venueOutdoor,
    this.latitude,
    this.longitude,
  });

  final String id;
  final String sportId;
  final SlateDate slateDate;
  final DateTime commenceUtc;
  final String homeTeam;
  final String awayTeam;
  final String source;
  final String? providerEventId;
  final String? venueName;
  final bool? venueOutdoor;
  final double? latitude;
  final double? longitude;

  Map<String, Object?> toMap() => {
        'id': id,
        'sportId': sportId,
        'slateDate': slateDate.iso,
        'commenceUtc': commenceUtc.toIso8601String(),
        'homeTeam': homeTeam,
        'awayTeam': awayTeam,
        'source': source,
        'providerEventId': providerEventId,
        'venueName': venueName,
        'venueOutdoor': venueOutdoor,
        'latitude': latitude,
        'longitude': longitude,
      };

  static GameEvent fromMap(Map<String, Object?> m) => GameEvent(
        id: m['id']! as String,
        sportId: m['sportId']! as String,
        slateDate: SlateDate.parse(m['slateDate']! as String),
        commenceUtc: DateTime.parse(m['commenceUtc']! as String),
        homeTeam: m['homeTeam']! as String,
        awayTeam: m['awayTeam']! as String,
        source: m['source']! as String,
        providerEventId: m['providerEventId'] as String?,
        venueName: m['venueName'] as String?,
        venueOutdoor: m['venueOutdoor'] as bool?,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
      );
}
