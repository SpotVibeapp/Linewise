# Linewise

Source-backed sports line research, Higher/Lower pick generation, immutable
prediction snapshots and manual-outcome calibration. Android app built with
Flutter. Package id: `app.linewise.linewise`.

Linewise is a research and record-keeping tool. It does **not** place bets,
does **not** settle results automatically, and never claims guaranteed accuracy.

## Feature map

| Feature | Where |
| --- | --- |
| All supported sports and leagues (NFL, NCAAF, NBA, NCAAB, WNBA, MLB, NHL) | `lib/domain/sports.dart`, sport selector on Slates |
| Team moneyline, spread, total markets | `lib/domain/generation/team_generator.dart` |
| Exact Underdog-style Higher/Lower player lines when actually supplied | `lib/domain/models/exact_line.dart`, player generator |
| Specific-player selection | Players tab (`lib/ui/player_search_page.dart`) |
| Higher and Lower candidates for every statistic with ≥20 valid observations | `lib/domain/generation/player_generator.dart` |
| Manual entry / import | `lib/ui/manual_entry_page.dart`, `lib/data/import_service.dart` |
| Source-backed exact lines only; never invent lines or probabilities | `ExactLine` requires source + timestamp; estimator refuses `n < 20` |
| CSV/JSON export including withheld rows | `lib/data/export_service.dart` |
| Exact slate-date filtering | `lib/domain/models/slate_date.dart`, Slates tab |
| Manual-outcome calibration dashboard | `lib/ui/calibration_page.dart` (manual outcomes only) |
| Immutable prediction snapshots | `lib/data/snapshot_repository.dart` (append-only, SHA-256 verified) |
| No automatic settlement or bet placement | nowhere in the codebase; manual outcome entry only |
| Win % + definition, push/tie %, source, timestamp, sample size, uncertainty, evidence quality, supporting factors, opposing factors/weaknesses, unknown/stale info | `lib/domain/models/pick.dart`, `lib/ui/pick_detail_page.dart` |
| Injuries, availability, role, workload, strengths/weaknesses, matchup, offense/defense, pace, play volume, home/away, rest, travel, schedule, venue, weather, lineup changes, recent form, exact-line history — without double-counting | `lib/domain/probability/factor_groups.dart` (double-count guard, capped adjustments) |
| “Probability unavailable” on insufficient evidence | `lib/domain/probability/engine.dart` |

## Request classes and API credit safety

The app distinguishes four request classes everywhere in the UI:

1. **Loaded-line filtering** — local filtering of lines already loaded. No
   network, no key, no cost. Player search always runs this class first.
2. **Free public player-history analysis** — ESPN public endpoints and
   Open-Meteo weather. No API key, no cost.
3. **Market discovery** — The Odds API `/v4/sports` and `/v4/sports/{sport}/events`.
   Requires your key but does **not** count against the usage quota (0 credits).
4. **Exact provider-line loading** — The Odds API `/odds` and `/events/{id}/odds`.
   **Billable**: estimated cost = `markets × regions` credits (×10 for
   historical odds). Every billable request is preceded by a cost estimate and
   an explicit confirmation, including the warning that **a request can consume
  credits even when it returns zero lines**.

Additional guarantees:

- Searching a player **never** silently makes a billable request
  (`PlayerSearchService` has no access to the billable client at all).
- **Safe mode** (default ON) disables all The Odds API requests.
- Your The Odds API key is stored in **encrypted Android storage**
  (Android Keystore). Backups are disabled (`android:allowBackup="false"`), and
  the key is never written to logs, exports, snapshots or source.
- No API credits are spent during testing; tests use fakes only.
- Private Underdog endpoints are never contacted. When exact provider lines are
  unavailable, the app says so instead of inventing lines.

## Probabilities

Win percentage = the share of the last *N* valid, source-logged observations in
which the statistic finished strictly on the winning side of the exact listed
line (ties counted separately as Push/Tie). Uncertainty is a 90% Wilson
interval. Capped contextual adjustments (each signal counted once, see
`factor_groups.dart`) are applied and disclosed. If the evidence is
insufficient (`n < 20` observations, or no source-backed exact line) the pick is
shown as **“Probability unavailable”** and exported as a withheld row. These are
estimates with disclosed uncertainty — never guarantees.

## Building a signed release APK

```bash
flutter pub get
dart format .
flutter analyze
flutter test
# Provide android/key.properties + a keystore (see docs/BUILDING.md), then:
flutter build apk --release
```

CI (`.github/workflows/build-apk.yml`) runs format → pub get → analyze → test
and only then builds, signs, zipaligns, verifies and publishes the APK.
Signing credentials are read from Actions secrets (`ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`); see
`docs/BUILDING.md`. Nothing secret is ever committed to this repository.
