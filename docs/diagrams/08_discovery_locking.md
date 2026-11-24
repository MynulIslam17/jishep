# 8. Concurrent discovery locking

```mermaid
sequenceDiagram
  participant A as Request A
  participant B as Request B (same area)
  participant J as discovery_jobs/{scope}_{geohash6}
  participant C as owner_scans / owner_properties
  participant M as Melissa
  A->>J: cheap read: lease held?
  J-->>A: no
  A->>J: transaction: status=running, leaseOwner=A, leaseExpiresAt=now+150 s
  B->>J: cheap read: lease held?
  J-->>B: yes (A)
  A->>C: serveFromCache again (double-check) + planMissing
  A->>A: reserveOwners (diagram 7)
  A->>M: Reverse GeoCoder (if scan needed)
  A->>C: store scan immediately
  loop nearest first, 4 at a time, until 50 named or budget used
    A->>M: Property by MAK
    A->>C: store each answer immediately (named or exclusion)
  end
  A->>A: settleOwners
  A->>J: finishLease (only if still leaseOwner=A): done, creditsUsed
  loop every 500 ms, up to 20 s
    B->>J: still running?
  end
  B->>C: serveFromCache → A's results, 0 credits ("joined")
```

```mermaid
stateDiagram-v2
  [*] --> running: acquireLease
  running --> done: finished
  running --> stopped: out_of_credits / licence stop
  running --> failed: error (reservation settled)
  running --> skipped: over a limit
  running --> expired: holder crashed, lease time passed
  expired --> running: next request resumes from stored answers
  done --> running: later request finds something missing
```

**What this shows / where in code.** `acquireLease`, `lockTransaction`, `waitForLease` and `finishLease` in `functions/src/owners.js`, and `jobIdFor` (scope + geohash-6) in `property_cache.js`. Scans and properties are written as each answer arrives, so a restarted job continues where it left off and never repeats a finished lookup. Tests: "100 simultaneous users, same uncached area: ONE paid discovery" (`owners.test.js`), "retry after partial progress never pays twice" and "expired lease from a restarted function" (`blueprint.test.js`). The lock only matters once paid discovery is enabled, which it is not in production.
