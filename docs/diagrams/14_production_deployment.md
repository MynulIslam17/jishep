# 14. Production deployment

```mermaid
flowchart TD
  A["tool/deploy_blueprint.sh --approve=gps-para-el-cielo — PREPARED, NOT RUN"] --> S0["0 safety: GLOBAL_DAILY=0, DISCOVERY=false, GAP=false, CACHE_DAYS=365, REQUIRE_VERIFIED=true, gcloud ADC"]
  S0 --> S1["1 backups → .local-backups/prod-blueprint-ts: rules release, functions list, TTL backup"]
  S1 --> S2["2 firebase deploy --dry-run"]
  S2 --> S3["3 firestore:rules + firestore:indexes"]
  S3 --> S4["4 functions"]
  S4 --> S5["5 TTL migration apply + verify"]
  S5 --> S6["6 live check: unauthenticated discoverOwners → sign_in_required, melissa_ops status"]
  S6 --> DONE["record commit in release log"]
  S3 -. "rollback" .-> RB1["re-release saved ruleset"]
  S4 -. "rollback" .-> RB2["redeploy previous commit's functions"]
  S5 -. "rollback" .-> RB3["migrate_cache_ttl.js rollback"]
```

```mermaid
flowchart LR
  BE["Backend deploy — Firebase"] --- SEP["separate releases"] --- MOB["Mobile release — Codemagic → TestFlight / App Store, Play Console"]
  MOB --> N1["new app build: no location editor, setup write falls back if old rules live"]
  BE --> N2["old 1.0.x app: its address editor is refused by new rules once deployed"]
```

**What this shows / where in code.** `tool/deploy_blueprint.sh` and `codemagic.yaml`. As of 2026-11-24 nothing from this change is deployed: the project owner chose local only. The live production state is the 2026-11-23 cutover, with rules, 4 functions, owner names from the cache only, and 0 credits.
