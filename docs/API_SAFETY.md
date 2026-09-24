# API safety contract

## Request classes

| Class | Network | Key | Credits |
| --- | --- | --- | --- |
| Loaded-line filtering | none | no | 0 |
| Free public player-history analysis (ESPN, Open-Meteo) | yes | no | 0 |
| Market discovery (The Odds API `/v4/sports`, `/events`) | yes | yes | 0 (does not count against quota) |
| Exact provider-line loading (The Odds API `/odds`, `/events/{id}/odds`) | yes | yes | BILLABLE: `markets × regions` (`×10` historical) |

## Guarantees

1. **Searching a player never silently makes a billable request.**
   `PlayerSearchService` has no reference to the provider client at all — the
   test suite proves that search + free history analysis issue zero provider
   requests even when the key is configured and safe mode is off.
2. **Empty searches are still useful.** With zero loaded lines, search offers
   free public player-history analysis (the “Derrick Henry” fix): Higher/Lower
   candidates for every statistic with at least 20 valid observations, with
   “Probability unavailable — no source-backed exact line” until a line is
   supplied by the provider (explicit, billable) or by manual entry/import.
3. **Estimated cost before every provider request**, with the explicit warning
   that **a request can consume credits even when it returns zero lines**.
4. **Safe mode** (default ON) disables all The Odds API requests.
5. **Never scrape private Underdog endpoints.** Exact Underdog-style
   Higher/Lower lines appear only when a permitted source or the user's own
   entry actually supplies them. Lines and probabilities are never invented.
6. **No API credits are spent during testing** — tests use mock transports only.
7. The **key lives in encrypted Android storage**, is excluded from backups,
   logs, exports, snapshots and source archives, and is redacted from every log
   line (`lib/core/redaction.dart`).
