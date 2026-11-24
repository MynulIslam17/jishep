# 13. Data expiration and refresh

```mermaid
stateDiagram-v2
  [*] --> Fresh: stored, expiresAt = checkedAt + MELISSA_CACHE_DAYS (365)
  Fresh --> Stale: now > expiresAt
  Stale --> Stale: NOT served as fresh, NOT deleted
  Stale --> Refreshed: only via an authorized paid discovery (enabled + verified + budget)
  Refreshed --> Fresh
  note right of Stale
    No automatic refresh job exists.
    Paid discovery is OFF in production,
    so stale records stay stale until enabled.
  end note
```

```mermaid
flowchart TD
  POL["Policy per record type"] --> N["named owner_properties: 365 days"]
  POL --> SC["owner_scans: 365 days (scanCacheDays follows cacheDays)"]
  POL --> NEG["exclusions not_found / non_residential / no_owner: 365 days (was 90)"]
  MIG["tool: migrate_cache_ttl.js"] --> PL["plan — read only"]
  PL --> BK["backup — old expiresAt + exact updateTime, mode 600"]
  BK --> AP["apply — only extends, updateTime precondition, ttlPolicy metadata"]
  AP --> VF["verify"]
  AP -. "if needed" .-> RB["rollback — restores old expiresAt on its own docs"]
  STATE["Status 2026-11-24"] --> S1["local emulator: all 53 docs at 365 days, verified, re-apply = 0"]
  STATE -. "not run" .-> S2["production: 52 owner docs + 1 scan still expire 2026-12-22"]
```

**What this shows / where in code.** `valid()` and `serveFromCache` in `functions/src/property_cache.js` hide stale records, which are never deleted. Defaults are `cacheDays: 365` and `negativeCacheDays: 365` in `OWNER_DEFAULTS` (`owners.js`), with `CACHE_DAYS` defaulting to 365 in `index.js`. The migration tool is `functions/tool/migrate_cache_ttl.js`, tested in `functions/test/ops_tools.test.js`. Data-retention cleanup is a separate concern, and no deletion job exists.
