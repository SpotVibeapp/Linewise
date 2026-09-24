/// Registry of supported sports and leagues.
///
/// Only sports covered by the free public sources (ESPN) and, where present,
/// the user's The Odds API key appear here. Player-prop coverage follows the
/// provider's published market list; team moneyline/spread/total markets are
/// supported for every league in the registry.
class SportLeague {
  const SportLeague({
    required this.id,
    required this.displayName,
    required this.group,
    required this.oddsApiKey,
    required this.espnPath,
    required this.supportsPlayerProps,
    required this.typicallyOutdoor,
  });

  /// Stable local id, e.g. `nfl`.
  final String id;

  /// Human name, e.g. `NFL`.
  final String displayName;

  /// League group label, e.g. `American Football`.
  final String group;

  /// Sport key used by The Odds API, e.g. `americanfootball_nfl`.
  final String oddsApiKey;

  /// Path segment used by ESPN site APIs, e.g. `football/nfl`.
  final String espnPath;

  /// Whether Higher/Lower player prop markets are published for the league.
  final bool supportsPlayerProps;

  /// Whether games are typically exposed to weather (for the weather factor).
  final bool typicallyOutdoor;
}

/// Every sport and league Linewise supports.
const List<SportLeague> supportedSports = [
  SportLeague(
    id: 'nfl',
    displayName: 'NFL',
    group: 'American Football',
    oddsApiKey: 'americanfootball_nfl',
    espnPath: 'football/nfl',
    supportsPlayerProps: true,
    typicallyOutdoor: true,
  ),
  SportLeague(
    id: 'ncaaf',
    displayName: 'NCAAF',
    group: 'American Football',
    oddsApiKey: 'americanfootball_ncaaf',
    espnPath: 'football/college-football',
    supportsPlayerProps: true,
    typicallyOutdoor: true,
  ),
  SportLeague(
    id: 'nba',
    displayName: 'NBA',
    group: 'Basketball',
    oddsApiKey: 'basketball_nba',
    espnPath: 'basketball/nba',
    supportsPlayerProps: true,
    typicallyOutdoor: false,
  ),
  SportLeague(
    id: 'ncaab',
    displayName: 'NCAAB',
    group: 'Basketball',
    oddsApiKey: 'basketball_ncaab',
    espnPath: 'mens-college-basketball',
    supportsPlayerProps: true,
    typicallyOutdoor: false,
  ),
  SportLeague(
    id: 'wnba',
    displayName: 'WNBA',
    group: 'Basketball',
    oddsApiKey: 'basketball_wnba',
    espnPath: 'basketball/wnba',
    supportsPlayerProps: true,
    typicallyOutdoor: false,
  ),
  SportLeague(
    id: 'mlb',
    displayName: 'MLB',
    group: 'Baseball',
    oddsApiKey: 'baseball_mlb',
    espnPath: 'baseball/mlb',
    supportsPlayerProps: true,
    typicallyOutdoor: true,
  ),
  SportLeague(
    id: 'nhl',
    displayName: 'NHL',
    group: 'Ice Hockey',
    oddsApiKey: 'icehockey_nhl',
    espnPath: 'hockey/nhl',
    supportsPlayerProps: true,
    typicallyOutdoor: false,
  ),
];

SportLeague? sportById(String id) {
  for (final s in supportedSports) {
    if (s.id == id) return s;
  }
  return null;
}

SportLeague? sportByOddsKey(String oddsKey) {
  for (final s in supportedSports) {
    if (s.oddsApiKey == oddsKey) return s;
  }
  return null;
}
