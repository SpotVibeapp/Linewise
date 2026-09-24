# Linewise changelog

## 1.11.0 (versionCode 12)

Rebuild of the full application surface after the previous workspace was lost,
plus the safe player-search and API-credit workflow.

- Safe player search: searching a player NEVER makes a billable request.
  Empty results now offer free public player-history analysis (ESPN) with
  Higher/Lower candidates for every statistic with at least 20 valid
  observations, even when zero provider lines are loaded.
- Clear four-way request labeling: loaded-line filtering (local),
  free public player-history analysis, market discovery, exact provider-line
  loading.
- Estimated credit cost shown before every billable request, with an explicit
  warning that a request can consume credits even when it returns zero lines.
- Safe mode (default ON) disables all The Odds API requests.
- The Odds API key is kept in encrypted Android storage (Android Keystore via
  flutter_secure_storage), excluded from backups, logs, exports and source.
- Supported sports/leagues: NFL, NCAAF, NBA, NCAAB, WNBA, MLB, NHL.
- Team moneyline, spread and total markets; exact provider Higher/Lower player
  lines only when actually supplied (never invented).
- Source-backed probabilities only; "Probability unavailable" when evidence is
  insufficient. Win %, push/tie %, uncertainty interval, sample size, source,
  timestamp, evidence quality, supporting factors, opposing factors/weaknesses
  and unknown/stale information shown on every defensible pick. No guarantees
  claimed anywhere.
- Context model covering injuries/availability, role, workload, player and team
  strengths/weaknesses, opponent matchup, offense/defense, pace, play volume,
  home/away, rest, travel, schedule, venue, weather, lineup changes, recent form
  and exact-line history with a double-count guard and capped adjustments.
- Manual entry and paste import of lines (CSV/JSON).
- CSV/JSON export including withheld rows and reasons.
- Exact slate-date filtering.
- Manual-outcome calibration dashboard (no automatic settlement).
- Immutable, hash-verified prediction snapshots.
- No bet placement or automatic settlement anywhere in the app.

## 1.10.0 (versionCode 11)

Previous known release (sources not preserved in this repository).
