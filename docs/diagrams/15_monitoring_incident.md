# 15. Monitoring and incident response

```mermaid
flowchart TD
  FN["Functions"] -->|"countUsage, best effort"| U[("melissa_usage/{day}, month-YYYY-MM, state")]
  FN -->|"logger.info: outcome + counts only, no uid/address/name"| LOG["Cloud Logging"]
  U --> REP["functions/tool/melissa_ops.js report/status"]
  REP --> W{"warnings: ≥80% daily or monthly, outOfCreditsAt set"}
  W -- Yes --> INC["Incident"]
  LOG --> INC
  PORTAL["Melissa portal balance — the authority"] --> INC
  INC --> K["melissa_ops.js kill --reason --approve → state.paidDisabled=true, effective next request"]
  K --> INV["investigate: discovery_jobs status, logs, counters"]
  INV --> FIX["fix / adjust env limits / redeploy"]
  FIX --> UK["melissa_ops.js unkill --reason --approve"]
  K -. "cached data still served" .-> USERS["users unaffected except no new paid lookups"]
```

| Counter | Meaning |
|---|---|
| `ownerCacheHits` / `ownerCacheMisses` | served free / coverage incomplete |
| `propertiesReused`, `duplicatesAvoided`, `overlapScansUsed` | reuse from the shared cache |
| `successfulDiscoveries`, `failedDiscoveries`, `estimatedCredits`, `melissaRequests` | paid activity |
| `deniedBudget`, `deniedSecurity` | refusals by limit / kill switch, by location / unverified |

**What this shows / where in code.** `countUsage` (`functions/src/owners.js`) and `usageReport`, `warnings` and `setKill` (`functions/tool/melissa_ops.js`). There is no automated alerting (Cloud Monitoring alert policies or a scheduled report), so the report is run by hand. The kill switch and the new counters are local only until deployed.
