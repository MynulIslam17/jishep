'use strict';
// Melissa-first neighborhood: real residential properties with their
// RECORDED PROPERTY OWNER (public record) around a point. CACHE FIRST.
//
//   1. Serve from the property index (src/property_cache.js): stored
//      Reverse GeoCoder scans + one stored Property answer per address.
//      Complete coverage → returned with 0 credits.
//   2. Otherwise, only when `enabled` (MELISSA_OWNER_DISCOVERY_ENABLED):
//      one paid job per area (lease in discovery_jobs), credits reserved
//      against per-request / daily / monthly budgets, and only the missing
//      part is bought: a Reverse GeoCoder scan here (2 credits per address,
//      max 100) and/or Property lookups by Melissa Address Key (9 each),
//      nearest first, until `target` named homes. Every answer is stored as
//      it arrives (resumable).
//   3. Kept only when: Melissa found the parcel at the SAME address key (or
//      the same house number and ZIP), the property use is residential, and
//      a recorded owner name exists. Nothing is invented.
//
// `enabled` off = cache-only (what is stored + what is missing). Refused
// unless owner names are allowed (MELISSA_ALLOW_OWNER_NAMES). LeadGen
// Property is not enabled on this account (status 116, 2026-11-22).
//
// Location authority (blueprint §2.1, §8): the point searched is ALWAYS the
// caller's saved primary location (users/{uid}.latitude/longitude), never a
// coordinate the client chooses. A client may still send its coordinates
// (older app versions do); if they are farther than `locationToleranceMeters`
// from the saved home, the request is refused (`location_not_authorized`).
// Paid discovery additionally needs a verified account (email verified, or a
// Google / Apple / phone sign-in) and the kill switch off
// (melissa_usage/state.paidDisabled).

const { overGlobalLimit, paidDisabled } = require('./budget');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { PROPERTY_CREDITS, lookupProperty } = require('./melissa');
const { REVERSE_CREDITS_PER_RECORD, reverseLookup, areaKey } = require('./discover');
const { QUEUE_DEFAULTS, QUEUE_REASONS, enqueueDiscovery } = require('./queue');

const MAX_TARGET = 50;

const OWNER_DEFAULTS = {
  // App-wide limit over every endpoint (budget.js); 0 = no paid call.
  globalDailyCredits: 0,
  // May this function CALL Melissa (spend credits)? Off: cache-only.
  enabled: false,
  allowOwnerNames: false,
  // Reverse GeoCoder radius and records (Melissa caps: 10 miles, 100).
  maxMiles: 1,
  // Largest scan radius ever stored (finds scans that reach the point).
  maxScanMiles: 1,
  reverseRecords: 100,
  // Property lookups per discovery (9 credits each).
  maxLookups: 80,
  concurrency: 4,
  // Condos, townhouses, mobile homes: residential, owner usually lives there.
  includeCondos: true,
  // Apartment buildings / multi-family: the owner is usually a landlord.
  includeMultiFamily: false,
  // Property use not given by Melissa.
  includeUnclassified: false,
  perUserDaily: 5,
  dailyCredits: 2000,
  monthlyCredits: 20000,
  // Hard ceiling for one discovery (one Reverse + 80 Property = 920).
  perRequestMaxCredits: 920,
  // Owner records: fresh for this many days (MELISSA_CACHE_DAYS, 365 by
  // the 2026-11-24 blueprint). 0 = not stored. Expiry never deletes.
  cacheDays: 365,
  // Exclusions (not found, commercial, no owner): no owner data. As long as
  // the scans that list them (365): a shorter window would make a still-fresh
  // scan's excluded addresses "unknown" again and buy them a second time.
  negativeCacheDays: 365,
  // Scans (addresses only); null = the same as cacheDays.
  scanCacheDays: null,
  // Client coordinates farther than this from the saved home are refused.
  locationToleranceMeters: 250,
  // Paid discovery only for verified accounts (anti account-farming).
  requireVerified: true,
  // Paid discovery only from a genuine app (valid Firebase App Check token:
  // Play Integrity / DeviceCheck). Requests without one keep cached data.
  requireAppCheck: true,
  // true = one stored result per area for every user (needs Melissa's OK).
  sharedCache: false,
  // Expected share of looked-up addresses that end up named (pilot 50/52).
  namedRate: 0.9,
  // Pay to PROVE the nearest 50 even when 50 named homes are already
  // stored (a scan here + closer lookups)? Off: pay only to fill gaps.
  completeCoverage: false,
  // Serve results stored by the earlier per-user, per-area cache.
  legacyCache: true,
  coverageStepMeters: 10,
  // Discovery lock: one paid job per area at a time.
  leaseMs: 150000,
  waitMs: 20000,
  pollMs: 500,
  outOfCreditsPauseMs: 6 * 60 * 60 * 1000,
  // Pending discovery queue (src/queue.js): a budget refusal records the
  // area so the lookup resumes when the budget allows.
  ...QUEUE_DEFAULTS,
};

class OwnerError extends Error {
  constructor(code, reason) {
    super(reason);
    this.code = code;
    this.reason = reason;
  }
}

const inUs = (lat, lon) => lat >= 17.8 && lat <= 71.6 && lon >= -179.9 && lon <= -64.5;

/**
 * Checks the request. Coordinates are optional (the saved home is used);
 * when given they must be valid US coordinates. Returns
 * `{latitude, longitude, target}` with null coordinates when none were sent.
 */
function validateOwners(data) {
  if (data == null) data = {};
  if (typeof data !== 'object') throw new OwnerError('invalid-argument', 'bad_input');
  let lat = null;
  let lon = null;
  if (data.latitude != null || data.longitude != null) {
    lat = Number(data.latitude);
    lon = Number(data.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new OwnerError('invalid-argument', 'bad_location');
    if (!inUs(lat, lon)) throw new OwnerError('invalid-argument', 'outside_us');
  }
  const target = data.target == null ? MAX_TARGET : Number(data.target);
  if (!Number.isInteger(target) || target < 1 || target > MAX_TARGET) {
    throw new OwnerError('invalid-argument', 'bad_target');
  }
  return { latitude: lat, longitude: lon, target };
}

/**
 * The caller's authoritative primary location.
 *
 * primary_locations/{uid} (server-only, never client-writable) pins the home
 * the first time the server sees it, copied from users/{uid}. Later client
 * edits of users/{uid} (or deleting and re-creating it) do not move it; only
 * the audited admin correction (src/location.js) does. Throws
 * `failed-precondition/no_primary_location` when no home is saved.
 */
async function primaryLocation(db, uid, now = new Date()) {
  const ref = db.collection('primary_locations').doc(uid);
  const read = (snap) => {
    const lat = snap.exists ? snap.get('latitude') : null;
    const lon = snap.exists ? snap.get('longitude') : null;
    if (typeof lat !== 'number' || typeof lon !== 'number' || !Number.isFinite(lat) || !Number.isFinite(lon)) return null;
    return { latitude: lat, longitude: lon };
  };
  const pinned = read(await ref.get());
  if (pinned) {
    if (!inUs(pinned.latitude, pinned.longitude)) throw new OwnerError('failed-precondition', 'outside_us');
    return pinned;
  }
  const saved = read(await db.collection('users').doc(uid).get());
  if (!saved) throw new OwnerError('failed-precondition', 'no_primary_location');
  if (!inUs(saved.latitude, saved.longitude)) throw new OwnerError('failed-precondition', 'outside_us');
  try {
    await ref.create({ ...saved, version: 1, source: 'first_use', pinnedAt: Timestamp.fromDate(now) });
    return saved;
  } catch (e) {
    // Another request pinned it first (ALREADY_EXISTS): that one wins.
    if (e && (e.code === 6 || /ALREADY_EXISTS/.test(String(e.message)))) {
      const won = read(await ref.get());
      if (won) return won;
    }
    throw e;
  }
}

/** Email verified, or a provider that verifies identity itself. */
/** True when the callable carried a valid Firebase App Check token
 *  (`request.app`, set by the Functions SDK after verifying it). */
function isAppCheckVerified(app) {
  return Boolean(app && typeof app.appId === 'string' && app.appId.length > 0);
}

function isVerifiedToken(token) {
  if (!token || typeof token !== 'object') return false;
  if (token.email_verified === true) return true;
  const provider = token.firebase && token.firebase.sign_in_provider;
  return ['google.com', 'apple.com', 'phone'].includes(provider);
}

// Melissa PropertyUseStandardized codes (Property reference guide).
const SINGLE_FAMILY = new Set(['181', '306', '363', '364', '376', '384', '385', '390', '452', '616', '618']);
const CONDO_LIKE = new Set(['366', '367', '371', '373', '375', '386', '617']);
const MULTI_FAMILY = new Set(['358', '360', '372', '381', '421', '461']);
const LABELS = {
  181: 'Single Family Residential', 306: 'Historical Residence', 363: 'Bungalow',
  364: 'Cluster Home', 376: 'Patio Home', 384: 'Seasonal / Vacation Residence',
  385: 'Single Family Residential', 390: 'Zero Lot Line Residence', 452: 'Garden Home',
  616: 'Single Family Residential with ADU', 618: 'Single Family Residential (2+ homes on parcel)',
  366: 'Condominium', 367: 'Cooperative', 371: 'Manufactured Home', 373: 'Mobile Home',
  375: 'Residential', 386: 'Townhouse', 617: 'Accessory Dwelling Unit',
  358: 'High-rise Apartments', 360: 'Apartments', 372: 'Multi-family Dwelling',
  381: 'Residential Income (Multi-family)', 421: 'Condominium Building', 461: 'Cooperative Building',
};

/**
 * Property use → {kind, label}. kind: single_family | condo | multi_family
 * | residential (group only) | unclassified | non_residential.
 */
function classify(property) {
  const code = String(property.useCode || '').trim();
  const group = String(property.useGroup || '').trim();
  if (SINGLE_FAMILY.has(code)) return { kind: 'single_family', label: LABELS[code], code, group };
  if (CONDO_LIKE.has(code)) return { kind: 'condo', label: LABELS[code], code, group };
  if (MULTI_FAMILY.has(code)) return { kind: 'multi_family', label: LABELS[code], code, group };
  if (code && code !== '0') return { kind: 'non_residential', label: group || null, code, group };
  // No use code: fall back on the group.
  if (/multi/i.test(group) && /resid/i.test(group)) return { kind: 'multi_family', label: group, code: null, group };
  if (/^residential$/i.test(group)) return { kind: 'residential', label: 'Residential', code: null, group };
  if (group && !/unknown|miscellaneous/i.test(group)) return { kind: 'non_residential', label: group, code: null, group };
  return { kind: 'unclassified', label: null, code: null, group: group || null };
}

function accepts(kind, cfg) {
  switch (kind) {
    case 'single_family':
    case 'residential': return true;
    case 'condo': return cfg.includeCondos;
    case 'multi_family': return cfg.includeMultiFamily;
    case 'unclassified': return cfg.includeUnclassified;
    default: return false;
  }
}

const houseNumber = (line) => (String(line || '').match(/^\s*(\d+)/) || [])[1] || null;
const zip5 = (zip) => String(zip || '').slice(0, 5);

/** The parcel Melissa returned is the address we asked about. */
function sameAddress(candidate, property) {
  if (candidate.mak && property.mak) return candidate.mak === property.mak;
  const a = property.address || {};
  return Boolean(houseNumber(candidate.line)) &&
    houseNumber(candidate.line) === houseNumber(a.line) &&
    zip5(candidate.zip) === zip5(a.zip);
}

const cache = require('./property_cache');

const dayKey = (now) => now.toISOString().slice(0, 10);
const monthKey = (now) => `month-${now.toISOString().slice(0, 7)}`;

/** Best-effort counters (cache hits/misses, requests); never blocks a result. */
async function countUsage(db, now, fields) {
  const inc = {};
  for (const [k, v] of Object.entries(fields)) if (v) inc[k] = FieldValue.increment(v);
  if (!Object.keys(inc).length) return;
  try {
    await db.collection('melissa_usage').doc(dayKey(now)).set(inc, { merge: true });
  } catch (_) { /* counters are informational */ }
}

/**
 * Atomic credit reservation (ESTIMATED credits, not Melissa's bill): per
 * request, per user per day, app per day and per month, and the
 * out-of-credits pause. Unused credits are given back by `settleOwners`.
 */
async function reserveOwners(db, uid, now, cfg, credits) {
  if (!(credits > 0)) throw new OwnerError('resource-exhausted', 'request_budget');
  if (credits > cfg.perRequestMaxCredits) throw new OwnerError('resource-exhausted', 'request_budget');
  const day = db.collection('melissa_usage').doc(dayKey(now));
  const month = db.collection('melissa_usage').doc(monthKey(now));
  const user = day.collection('users').doc(uid);
  const state = db.collection('melissa_usage').doc('state');
  await db.runTransaction(async (tx) => {
    const [d, m, u, st] = await Promise.all([tx.get(day), tx.get(month), tx.get(user), tx.get(state)]);
    if (paidDisabled(st)) throw new OwnerError('resource-exhausted', 'paid_disabled');
    const paused = st.get('outOfCreditsAt');
    if (paused && now.getTime() - paused.toMillis() < cfg.outOfCreditsPauseMs) {
      throw new OwnerError('resource-exhausted', 'out_of_credits');
    }
    if ((u.get('ownerDiscoveries') || 0) >= cfg.perUserDaily) {
      throw new OwnerError('resource-exhausted', 'user_daily_limit');
    }
    if ((d.get('ownerCredits') || 0) + credits > cfg.dailyCredits ||
        overGlobalLimit(d, credits, cfg.globalDailyCredits)) {
      throw new OwnerError('resource-exhausted', 'app_daily_limit');
    }
    if ((m.get('ownerCredits') || 0) + credits > cfg.monthlyCredits) {
      throw new OwnerError('resource-exhausted', 'app_monthly_limit');
    }
    tx.set(day, { ownerCredits: FieldValue.increment(credits), ownerDiscoveries: FieldValue.increment(1) }, { merge: true });
    tx.set(month, { ownerCredits: FieldValue.increment(credits) }, { merge: true });
    tx.set(user, { ownerDiscoveries: FieldValue.increment(1) }, { merge: true });
  });
  return { day, month, user };
}

async function settleOwners(db, reservation, unused, { undo = false } = {}) {
  if (unused <= 0 && !undo) return;
  const batch = db.batch();
  batch.set(reservation.day, {
    ownerCredits: FieldValue.increment(-unused),
    ...(undo ? { ownerDiscoveries: FieldValue.increment(-1) } : {}),
  }, { merge: true });
  batch.set(reservation.month, { ownerCredits: FieldValue.increment(-unused) }, { merge: true });
  if (undo) batch.set(reservation.user, { ownerDiscoveries: FieldValue.increment(-1) }, { merge: true });
  await batch.commit();
}

// Errors where Melissa did not process the record (no charge).
const UNCHARGED = new Set(['not_configured', 'license_invalid', 'license_disabled',
  'product_not_enabled', 'not_available_for_credit_license', 'out_of_credits',
  'network', 'timeout', 'rate_limited', 'unavailable']);
const STOP = new Set(['out_of_credits', 'license_invalid', 'license_disabled', 'product_not_enabled']);

/**
 * One paid discovery per area at a time: a lease in discovery_jobs/{jobId}
 * (job id = scope + geohash-6 cell of the point, ~1.2 × 0.6 km). A crashed
 * holder's lease expires, and the next request continues from what was
 * already stored (scans and properties are written as they arrive).
 */
async function acquireLease(db, jobId, owner, clock, cfg, meta) {
  const ref = db.collection('discovery_jobs').doc(jobId);
  const held = (job) => {
    const lease = job.get('leaseExpiresAt');
    return job.exists && job.get('status') === 'running' && lease && lease.toMillis() > clock();
  };
  // Cheap read first: when someone holds the lease, do not contend for it.
  if (held(await ref.get())) return false;
  try {
    return await lockTransaction(db, ref, owner, clock, cfg, meta, held);
  } catch (e) {
    // Heavy contention (many requests at once): someone else won.
    if (e && (e.code === 10 || /ABORTED|contention|lock timeout/i.test(String(e.message)))) return false;
    throw e;
  }
}

function lockTransaction(db, ref, owner, clock, cfg, meta, held) {
  return db.runTransaction(async (tx) => {
    const job = await tx.get(ref);
    if (held(job)) return false;
    tx.set(ref, {
      ...meta,
      status: 'running',
      leaseOwner: owner,
      leaseExpiresAt: Timestamp.fromMillis(clock() + cfg.leaseMs),
      idempotencyKey: ref.id,
      attempts: FieldValue.increment(1),
      startedAt: Timestamp.fromMillis(clock()),
    }, { merge: true });
    return true;
  }, { maxAttempts: 3 });
}

async function finishLease(db, jobId, owner, fields, clock) {
  const ref = db.collection('discovery_jobs').doc(jobId);
  await db.runTransaction(async (tx) => {
    const job = await tx.get(ref);
    if (job.get('leaseOwner') !== owner) return; // lease was taken over
    tx.set(ref, { ...fields, leaseExpiresAt: Timestamp.fromMillis(clock()), finishedAt: Timestamp.fromMillis(clock()) }, { merge: true });
  });
}

/** Waits for another request's discovery; true when it finished in time. */
async function waitForLease(db, jobId, clock, sleep, cfg) {
  const ref = db.collection('discovery_jobs').doc(jobId);
  const until = clock() + cfg.waitMs;
  while (clock() < until) {
    await sleep(cfg.pollMs);
    const job = await ref.get();
    const lease = job.get('leaseExpiresAt');
    if (job.get('status') !== 'running' || !lease || lease.toMillis() <= clock()) return true;
  }
  return false;
}

const NO_MISSING = Object.freeze({
  scanNeeded: false, lookupsNeeded: 0, estimatedCredits: 0, exhaustedAtPoint: false,
  toProve: { scanNeeded: false, lookupsNeeded: 0, estimatedCredits: 0 },
});

function shape(served, target, extra = {}) {
  const records = served.records.slice(0, target);
  const { stats: extraStats, ...rest } = extra;
  return {
    records,
    coverage: records.length >= target ? 'full' : 'partial',
    completeness: served.completeness,
    coveredMeters: served.coveredMeters,
    firestoreReads: served.reads,
    credits: 0,
    cached: true,
    pending: false,
    missing: NO_MISSING,
    ...rest,
    stats: { ...served.stats, ...(extraStats || {}), named: records.length },
  };
}

/**
 * Cache first, then (only when `enabled`) a controlled paid discovery for
 * exactly what is missing. Returns `{records, coverage, completeness,
 * coveredMeters, missing, stats, credits, cached, pending}`. Each record:
 * `{id, line, city, state, zip, latitude, longitude, distanceMeters,
 *   owner: {name, secondName, isCompany, isTrust},
 *   classification: {kind, label, code, group}, yearBuilt}`.
 */
async function discoverOwners({ db, uid, data, key, now = new Date(), config = {},
  verified = false, appVerified = false, queue = true, expectJobId = null,
  reverse = reverseLookup, property = lookupProperty, log = () => {},
  clock = () => Date.now(), sleep = (ms) => new Promise((r) => setTimeout(r, ms)) }) {
  const cfg = { ...OWNER_DEFAULTS, ...config };
  if (cfg.scanCacheDays == null) cfg.scanCacheDays = cfg.cacheDays;
  if (!cfg.allowOwnerNames) throw new OwnerError('failed-precondition', 'owner_names_disabled');
  if (!uid) throw new OwnerError('unauthenticated', 'sign_in_required');
  if (!(cfg.cacheDays > 0)) throw new OwnerError('failed-precondition', 'owner_cache_disabled');
  const input = validateOwners(data);
  const { target } = input;
  // Server-authoritative point: the saved primary location only.
  const home = await primaryLocation(db, uid, now);
  if (input.latitude != null) {
    const away = cache.haversineMeters(input.latitude, input.longitude, home.latitude, home.longitude);
    if (away > cfg.locationToleranceMeters) {
      await countUsage(db, now, { deniedSecurity: 1 });
      log({ event: 'owners', outcome: 'denied', reason: 'location_not_authorized' });
      throw new OwnerError('permission-denied', 'location_not_authorized');
    }
  }
  const { latitude, longitude } = home;
  const scope = cache.scopeOf(db, { shared: cfg.sharedCache, uid });
  const jobId = cache.jobIdFor(scope.id, latitude, longitude);
  // A queued job is processed only for a requester whose home is still in
  // that area (an audited correction may have moved it).
  if (expectJobId && expectJobId !== jobId) throw new OwnerError('failed-precondition', 'queue_area_changed');
  // Budget refusal of a verified, genuine request: record the area so the
  // lookup resumes later (deduplicated per area, capped; src/queue.js).
  const enqueue = async (reason) => {
    if (!queue || !QUEUE_REASONS.has(reason)) return {};
    try {
      const q = await enqueueDiscovery(db, {
        jobId, scopeId: scope.id, area: areaKey(latitude, longitude), uid, appVerified, reason, now, cfg,
      });
      if (q.queued) await countUsage(db, now, { queuedRequests: 1 });
      log({ event: 'queue', outcome: q.queued ? (q.created ? 'queued' : 'joined') : 'refused', reason: q.why || reason });
      return q.queued ? { queued: true } : {};
    } catch (e) {
      // The queue is best effort: the stored data is still answered.
      log({ event: 'queue', outcome: 'error', message: String(e && e.message) });
      return {};
    }
  };
  const serve = () => cache.serveFromCache(scope, { latitude, longitude, target, now, cfg });

  let served = await serve();
  const reuse = (sv) => ({
    propertiesReused: sv.stats.resolved, duplicatesAvoided: sv.stats.duplicateAddresses,
    overlapScansUsed: sv.stats.scans > 1 ? sv.stats.scans : 0,
  });
  if (served.completeness === 'complete' || served.completeness === 'empty') {
    await countUsage(db, now, { ownerCacheHits: 1, ...reuse(served) });
    log({ event: 'owners', outcome: 'cache_hit', completeness: served.completeness, reads: served.reads });
    return shape(served, target);
  }
  if (served.completeness === 'unknown' && cfg.legacyCache) {
    // Results stored by the earlier per-user, per-area cache (still valid).
    const legacy = await db.collection('users').doc(uid).collection('owner_areas')
      .doc(areaKey(latitude, longitude)).get();
    const exp = legacy.get('expiresAt');
    if (legacy.exists && exp && exp.toMillis() > now.getTime() && (legacy.get('records') || []).length) {
      await countUsage(db, now, { ownerCacheHits: 1 });
      log({ event: 'owners', outcome: 'legacy_cache_hit' });
      const records = legacy.get('records').slice(0, target);
      return {
        records, coverage: legacy.get('coverage'), completeness: 'legacy', coveredMeters: 0,
        stats: legacy.get('stats') || {}, credits: 0, cached: true, pending: false,
        missing: NO_MISSING,
      };
    }
  }

  let plan = cache.planMissing(served, { target, cfg });
  const missingOf = (p) => ({
    scanNeeded: p.scanNeeded, lookupsNeeded: p.lookupsNeeded, estimatedCredits: p.estimatedCredits,
    exhaustedAtPoint: Boolean(p.exhaustedAtPoint),
    toProve: { scanNeeded: p.prove.scanNeeded, lookupsNeeded: p.prove.lookupsNeeded, estimatedCredits: p.prove.estimatedCredits },
  });
  const missing = missingOf(plan);
  if (!cfg.enabled || (!plan.scanNeeded && plan.lookupsNeeded === 0)) {
    // Cache-only: what is stored, and exactly what a paid discovery would add.
    await countUsage(db, now, { ownerCacheMisses: 1, ...reuse(served) });
    log({ event: 'owners', outcome: 'cache_only', completeness: served.completeness, ...missing });
    return shape(served, target, { missing });
  }
  // Paid discovery is wanted: refuse before any lease or reservation when
  // the account is unverified or the kill switch is on (cached data stays).
  const gate = cfg.requireVerified && !verified ? 'unverified'
    : cfg.requireAppCheck && !appVerified ? 'app_check'
    : paidDisabled(await db.collection('melissa_usage').doc('state').get()) ? 'paid_disabled' : null;
  if (gate) {
    await countUsage(db, now, { ownerCacheMisses: 1, ...(gate !== 'paid_disabled' ? { deniedSecurity: 1 } : { deniedBudget: 1 }), ...reuse(served) });
    log({ event: 'owners', outcome: 'limited', reason: gate });
    return shape(served, target, { missing, limited: gate, ...(await enqueue(gate)) });
  }

  const owner = cache.newLeaseOwner();
  const got = await acquireLease(db, jobId, owner, clock, cfg, { area: areaKey(latitude, longitude) });
  if (got) {
    // Double-checked: another request may have finished this area between
    // our first read and taking the lease. Plan again from fresh data.
    served = await serve();
    plan = cache.planMissing(served, { target, cfg });
    if (served.completeness === 'complete' || served.completeness === 'empty'
      || (!plan.scanNeeded && plan.lookupsNeeded === 0)) {
      await finishLease(db, jobId, owner, { status: 'done', creditsReserved: 0, creditsUsed: 0 }, clock);
      await countUsage(db, now, { ownerCacheHits: 1 });
      return shape(served, target, { missing: NO_MISSING });
    }
  }
  const reverseCost = cfg.reverseRecords * REVERSE_CREDITS_PER_RECORD;
  const scanCost = plan.scanNeeded ? reverseCost : 0;
  const affordable = Math.max(0, Math.floor((cfg.perRequestMaxCredits - scanCost) / PROPERTY_CREDITS));
  const lookupBudget = Math.min(cfg.maxLookups, affordable,
    plan.scanNeeded ? cfg.maxLookups : plan.lookupsNeeded);
  const reserved = scanCost + lookupBudget * PROPERTY_CREDITS;
  if (!got) {
    // Someone is already paying for this area: wait, then read their result.
    const finished = await waitForLease(db, jobId, clock, sleep, cfg);
    served = await serve();
    await countUsage(db, now, { ownerWaited: 1 });
    log({ event: 'owners', outcome: finished ? 'joined' : 'pending', completeness: served.completeness });
    // The holder was refused for budget: this user's area waits in the
    // queue too (joins the same job as a requester).
    const held = finished ? await db.collection('discovery_jobs').doc(jobId).get() : null;
    const skipped = held && held.get('status') === 'skipped' && QUEUE_REASONS.has(held.get('error'))
      ? held.get('error') : null;
    if (skipped && served.completeness !== 'complete' && served.completeness !== 'empty') {
      return shape(served, target, { missing, limited: skipped, ...(await enqueue(skipped)) });
    }
    return shape(served, target, { pending: !finished, missing });
  }

  let reservation;
  let spent = 0;
  let requests = 0;
  let failed = 0;
  let stop = null;
  const dstats = {
    addressesFound: 0, lookups: 0, notFound: 0, mismatch: 0, nonResidential: 0,
    multiFamily: 0, unclassified: 0, noOwner: 0, errors: 0,
  };
  try {
    try {
      reservation = await reserveOwners(db, uid, now, cfg, reserved);
    } catch (e) {
      // Over a limit (or paused, or switched off): show what is already
      // stored (possibly nothing) with the reason; never retried by itself.
      if (!(e instanceof OwnerError)) throw e;
      await finishLease(db, jobId, owner, { status: 'skipped', error: e.reason, creditsReserved: 0, creditsUsed: 0 }, clock);
      await countUsage(db, now, { ownerCacheMisses: 1, deniedBudget: 1 });
      log({ event: 'owners', outcome: 'limited', reason: e.reason });
      return shape(served, target, { missing, limited: e.reason, ...(await enqueue(e.reason)) });
    }
    const pause = () => db.collection('melissa_usage').doc('state')
      .set({ outOfCreditsAt: Timestamp.fromDate(now) }, { merge: true });

    if (plan.scanNeeded) {
      const found = await reverse({
        latitude, longitude, recs: cfg.reverseRecords, miles: cfg.maxMiles, apartments: false,
      }, key);
      requests++;
      if (found.status === 'error') {
        await settleOwners(db, reservation, reserved, { undo: true });
        reservation = null;
        if (found.error === 'out_of_credits') await pause();
        log({ event: 'owners', outcome: 'error', step: 'reverse', error: found.error });
        const busy = ['out_of_credits', 'rate_limited'].includes(found.error);
        throw new OwnerError(busy ? 'resource-exhausted' : 'unavailable', found.error);
      }
      spent += Math.min(cfg.reverseRecords, found.records.length) * REVERSE_CREDITS_PER_RECORD;
      dstats.addressesFound = found.records.length;
      await scope.scans.doc(cache.scanIdFor(latitude, longitude, cache.SCAN_OPTIONS)).set(cache.scanDoc({
        latitude, longitude, records: found.records, recs: cfg.reverseRecords, miles: cfg.maxMiles,
        now, days: cfg.scanCacheDays,
      }));
      served = await serve();
    }

    const queue = served.unresolved;
    let named = served.records.length;
    let next = 0;
    let budget = lookupBudget;
    const store = (c, status, p, cls) => scope.properties.doc(c.id).set(cache.propertyDoc({
      candidate: c, status, property: p, classification: cls, now,
      days: status === cache.NAMED ? cfg.cacheDays : cfg.negativeCacheDays,
    }));
    const one = async (c) => {
      const p = await property({
        mak: c.mak, line: c.line, city: c.city, state: c.state, zip: c.zip, requestId: c.id,
      }, key, { includeOwner: true, retries: 1 });
      requests++;
      if (p.status === 'error') {
        // Not stored: a later discovery may try this address again.
        if (!UNCHARGED.has(p.error)) spent += PROPERTY_CREDITS;
        failed++;
        dstats.errors++;
        if (STOP.has(p.error)) stop = p.error;
        return;
      }
      spent += PROPERTY_CREDITS;
      if (p.status !== 'found') { dstats.notFound++; await store(c, 'not_found', null, null); return; }
      if (!sameAddress(c, p)) { dstats.mismatch++; await store(c, 'mismatch', null, null); return; }
      const cls = classify(p);
      if (!accepts(cls.kind, cfg)) {
        const status = cls.kind === 'multi_family' ? 'multi_family'
          : cls.kind === 'unclassified' ? 'unclassified' : 'non_residential';
        if (status === 'multi_family') dstats.multiFamily++;
        else if (status === 'unclassified') dstats.unclassified++;
        else dstats.nonResidential++;
        await store(c, status, p, cls);
        return;
      }
      if (!p.owner || !p.owner.name) { dstats.noOwner++; await store(c, 'no_owner', p, cls); return; }
      await store(c, cache.NAMED, p, cls);
      named++;
    };
    // Nearest first, a few at a time, until enough named homes are found.
    while (!stop && next < queue.length && budget > 0 && (named < target || cfg.completeCoverage)) {
      const room = Math.min(cfg.concurrency, budget, queue.length - next);
      const batch = queue.slice(next, next + room);
      next += room;
      budget -= room;
      dstats.lookups += batch.length;
      await Promise.all(batch.map(one));
    }
    if (stop === 'out_of_credits') await pause();
    await settleOwners(db, reservation, Math.max(0, reserved - spent));
    reservation = null;
    served = await serve();
    await finishLease(db, jobId, owner, {
      status: stop ? 'stopped' : 'done', creditsReserved: reserved, creditsUsed: spent,
      requests, failedLookups: failed, completeness: served.completeness,
    }, clock);
    await countUsage(db, now, {
      ownerCacheMisses: 1, melissaRequests: requests, failedLookups: failed, estimatedCredits: spent,
      ...(stop ? { failedDiscoveries: 1 } : { successfulDiscoveries: 1 }),
    });
    // Counts only: no address, name or uid in logs.
    log({ event: 'owners', outcome: served.completeness, stopped: stop, credits: spent, ...dstats });
    return shape(served, target, {
      cached: false, credits: spent, stats: dstats,
      missing: missingOf(cache.planMissing(served, { target, cfg })),
      ...(stop ? { stopped: stop } : {}),
    });
  } catch (e) {
    if (reservation) await settleOwners(db, reservation, Math.max(0, reserved - spent), { undo: spent === 0 });
    await countUsage(db, now, { failedDiscoveries: 1, ...(spent ? { estimatedCredits: spent } : {}) });
    await finishLease(db, jobId, owner, {
      status: 'failed', error: e instanceof OwnerError ? e.reason : 'internal',
      creditsReserved: reserved, creditsUsed: spent, requests,
    }, clock);
    throw e;
  }
}

module.exports = {
  OWNER_DEFAULTS, OwnerError, validateOwners, primaryLocation, isVerifiedToken, isAppCheckVerified, inUs,
  classify, accepts, sameAddress, discoverOwners, reserveOwners, acquireLease,
};
