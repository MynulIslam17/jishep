'use strict';
// Melissa gap-filler: nearby addresses from Melissa Reverse GeoCoder, ONLY
// when the app's Overture cells found fewer than 50 homes around a point.
//
// Off unless `enabled` is true (param MELISSA_GAP_FILL_ENABLED). Verified
// price (2026-11-21, credit license): 2 credits per address RETURNED.
// Reverse GeoCoder has no home/business flag; with `verifyResidential`
// each address is also checked with Personator (3 credits) and businesses
// are dropped. Nothing is invented: fewer results are returned as they are.

const { overGlobalLimit, paidDisabled } = require('./budget');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { CHECK_CREDITS, checkAddress } = require('./melissa');

const REVERSE_ENDPOINT =
  'https://reversegeo.melissadata.net/V3/WEB/ReverseGeoCode/doLookup';
const REVERSE_CREDITS_PER_RECORD = 2;
const TARGET = 50;
const MILE_METERS = 1609.344;

const GAP_DEFAULTS = {
  enabled: false,
  // Paid lookups need a valid Firebase App Check token (request.app).
  requireAppCheck: true,
  // Gap fills one user may run per UTC day.
  perUserDaily: 3,
  // Credits all gap fills together may spend per UTC day.
  dailyCredits: 300,
  // App-wide limit over every endpoint (budget.js); 0 = no paid call.
  globalDailyCredits: 0,
  // Search radius (Reverse GeoCoder max is 10 miles).
  maxMiles: 3,
  // Extra records asked for so duplicates/businesses can be dropped.
  buffer: 10,
  verifyResidential: false,
  // Per-user reuse; 0 = never store (if Melissa's terms do not allow it).
  cacheDays: 30,
  outOfCreditsPauseMs: 6 * 60 * 60 * 1000,
};

class DiscoverError extends Error {
  constructor(code, reason) {
    super(reason);
    this.code = code;
    this.reason = reason;
  }
}

// Around the US incl. Alaska, Hawaii, Puerto Rico (same box as the app).
const inUs = (lat, lon) => lat >= 17.8 && lat <= 71.6 && lon >= -179.9 && lon <= -64.5;

function validateDiscover(data) {
  if (!data || typeof data !== 'object') throw new DiscoverError('invalid-argument', 'bad_input');
  const lat = Number(data.latitude);
  const lon = Number(data.longitude);
  const have = Number.isInteger(data.have) ? data.have : NaN;
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new DiscoverError('invalid-argument', 'bad_location');
  if (!inUs(lat, lon)) throw new DiscoverError('invalid-argument', 'outside_us');
  if (!(have >= 0 && have <= TARGET)) throw new DiscoverError('invalid-argument', 'bad_have');
  return { latitude: lat, longitude: lon, have };
}

/** ~110 m grid key, so a nearby repeat request reuses the cached result. */
const areaKey = (lat, lon) => `${lat.toFixed(3)}_${lon.toFixed(3)}`;

function buildReverseUrl({ latitude, longitude, recs, miles, apartments = true }, key) {
  const q = new URLSearchParams({
    t: 'gap',
    lat: latitude.toFixed(6),
    long: longitude.toFixed(6),
    recs: String(recs),
    dist: String(miles),
    opt: `IncludeApartments:${apartments ? 'on' : 'off'};IncludeUndeliverable:off;IncludeEmptyLots:off`,
    format: 'json',
  });
  q.set('id', key);
  return `${REVERSE_ENDPOINT}?${q.toString()}`;
}

const s = (v, max = 120) => {
  const t = String(v == null ? '' : v).trim();
  return t ? t.slice(0, max) : null;
};

/** Reverse GeoCoder JSON → address records (deduped by MAK/address). */
function parseReverseResponse(body) {
  if (!body || typeof body !== 'object') return { status: 'error', error: 'bad_response', records: [] };
  const t = String(body.TransmissionResults || '').trim();
  if (t) {
    const map = { GE05: 'license_invalid', GE06: 'license_disabled', GE08: 'product_not_enabled', GE14: 'out_of_credits', GE29: 'not_available_for_credit_license' };
    const code = t.split(',').map((c) => c.trim()).find((c) => map[c]);
    return { status: 'error', error: code ? map[code] : 'melissa_error', codes: t.split(','), records: [] };
  }
  const seen = new Set();
  const records = [];
  for (const r of Array.isArray(body.Records) ? body.Records : []) {
    const line = s(r.AddressLine1);
    const lat = Number.parseFloat(r.Latitude);
    const lon = Number.parseFloat(r.Longitude);
    if (!line || !/\d/.test(line) || !Number.isFinite(lat) || !Number.isFinite(lon)) continue;
    const suite = s(r.SuiteName, 40);
    const mak = s(r.MelissaAddressKey, 20);
    const dedupe = mak || `${line}|${suite || ''}|${s(r.PostalCode, 10) || ''}`.toUpperCase();
    if (seen.has(dedupe)) continue;
    seen.add(dedupe);
    const miles = Number.parseFloat(r.Distance);
    records.push({
      id: `mel:${mak || dedupe.replace(/[^A-Za-z0-9]/g, '').slice(0, 60)}`,
      line: suite ? `${line} ${suite}`.toUpperCase() : line.toUpperCase(),
      city: s(r.City, 80),
      state: s(r.State, 2),
      zip: s(r.PostalCode, 10),
      latitude: lat,
      longitude: lon,
      distanceMeters: Number.isFinite(miles) ? Math.round(miles * MILE_METERS) : null,
      units: Number.parseInt(r.SuiteCount, 10) || 0,
      mak,
      suite,
      residential: null,
    });
  }
  return { status: 'ok', records };
}

async function reverseLookup(params, key, { fetchImpl = fetch, timeoutMs = 15000 } = {}) {
  if (!key) return { status: 'error', error: 'not_configured', records: [] };
  try {
    const res = await fetchImpl(buildReverseUrl(params, key), {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    if (res.status === 429) return { status: 'error', error: 'rate_limited', records: [] };
    if (res.status === 401 || res.status === 403) return { status: 'error', error: 'license_invalid', records: [] };
    if (!res.ok) return { status: 'error', error: 'unavailable', records: [] };
    return parseReverseResponse(await res.json());
  } catch (e) {
    return { status: 'error', error: e && e.name === 'TimeoutError' ? 'timeout' : 'network', records: [] };
  }
}

const dayKey = (now) => now.toISOString().slice(0, 10);

async function reserveGap(db, uid, now, cfg, credits) {
  const day = db.collection('melissa_usage').doc(dayKey(now));
  const user = day.collection('users').doc(uid);
  const state = db.collection('melissa_usage').doc('state');
  await db.runTransaction(async (tx) => {
    const [d, u, st] = await Promise.all([tx.get(day), tx.get(user), tx.get(state)]);
    if (paidDisabled(st)) throw new DiscoverError('resource-exhausted', 'paid_disabled');
    const paused = st.get('outOfCreditsAt');
    if (paused && now.getTime() - paused.toMillis() < cfg.outOfCreditsPauseMs) {
      throw new DiscoverError('resource-exhausted', 'out_of_credits');
    }
    if ((u.get('gapFills') || 0) >= cfg.perUserDaily) {
      throw new DiscoverError('resource-exhausted', 'user_daily_limit');
    }
    if ((d.get('gapCredits') || 0) + credits > cfg.dailyCredits ||
        overGlobalLimit(d, credits, cfg.globalDailyCredits)) {
      throw new DiscoverError('resource-exhausted', 'app_daily_limit');
    }
    tx.set(day, { gapCredits: FieldValue.increment(credits), gapFills: FieldValue.increment(1) }, { merge: true });
    tx.set(user, { gapFills: FieldValue.increment(1) }, { merge: true });
  });
  return { day, user };
}

async function settle(db, reservation, unusedCredits, { undoFill = false } = {}) {
  if (unusedCredits <= 0 && !undoFill) return;
  const batch = db.batch();
  batch.set(reservation.day, {
    gapCredits: FieldValue.increment(-unusedCredits),
    ...(undoFill ? { gapFills: FieldValue.increment(-1) } : {}),
  }, { merge: true });
  if (undoFill) batch.set(reservation.user, { gapFills: FieldValue.increment(-1) }, { merge: true });
  await batch.commit();
}

/**
 * Returns `{records, source, cached, coverage}` with up to (50 - have)
 * Melissa addresses nearest the point. Throws DiscoverError.
 */
async function discoverNearby({ db, uid, data, key, now = new Date(), config = {}, appVerified = false, reverse = reverseLookup, check = checkAddress, log = () => {} }) {
  const cfg = { ...GAP_DEFAULTS, ...config };
  if (!cfg.enabled) throw new DiscoverError('failed-precondition', 'gap_filler_disabled');
  if (!uid) throw new DiscoverError('unauthenticated', 'sign_in_required');
  const input = validateDiscover(data);
  const need = TARGET - input.have;
  if (need <= 0) return { records: [], cached: false, coverage: 'overture_full' };

  const ref = db.collection('users').doc(uid).collection('gap_areas').doc(areaKey(input.latitude, input.longitude));
  if (cfg.cacheDays > 0) {
    const cached = await ref.get();
    const exp = cached.get('expiresAt');
    if (cached.exists && exp && exp.toMillis() > now.getTime()) {
      log({ event: 'gap', outcome: 'cache_hit' });
      return { records: (cached.get('records') || []).slice(0, need), cached: true, coverage: cached.get('coverage') };
    }
  }

  if (cfg.requireAppCheck && !appVerified) {
    log({ event: 'gap', outcome: 'denied', reason: 'app_check_required' });
    throw new DiscoverError('failed-precondition', 'app_check_required');
  }
  const recs = Math.min(100, need + cfg.buffer);
  const verifyCost = cfg.verifyResidential ? recs * CHECK_CREDITS : 0;
  const reserved = recs * REVERSE_CREDITS_PER_RECORD + verifyCost;
  const reservation = await reserveGap(db, uid, now, cfg, reserved);

  const result = await reverse({ latitude: input.latitude, longitude: input.longitude, recs, miles: cfg.maxMiles }, key);
  if (result.status === 'error') {
    await settle(db, reservation, reserved, { undoFill: true });
    if (result.error === 'out_of_credits') {
      await db.collection('melissa_usage').doc('state').set({ outOfCreditsAt: Timestamp.fromDate(now) }, { merge: true });
    }
    log({ event: 'gap', outcome: 'error', error: result.error });
    const busy = ['out_of_credits', 'rate_limited'].includes(result.error);
    throw new DiscoverError(busy ? 'resource-exhausted' : 'unavailable', result.error);
  }
  // Charged per record returned (before our de-duplication we cannot know
  // Melissa's count exactly; use what it sent, capped at recs).
  const returned = Math.min(recs, result.records.length);
  let spent = returned * REVERSE_CREDITS_PER_RECORD;
  let records = result.records;

  if (cfg.verifyResidential) {
    const kept = [];
    for (const r of records) {
      const c = await check({ line: r.line, city: r.city, state: r.state, zip: r.zip, requestId: r.id }, key, { retries: 1 });
      if (c.status === 'error') {
        if (c.error === 'out_of_credits') break;
        kept.push(r); // unknown, keep as unverified
        continue;
      }
      spent += CHECK_CREDITS;
      if (c.residential === false) continue; // business: drop
      kept.push({ ...r, residential: c.residential });
    }
    records = kept;
  }
  await settle(db, reservation, reserved - spent);

  records = records
    .sort((a, b) => (a.distanceMeters ?? 1e12) - (b.distanceMeters ?? 1e12))
    .slice(0, need);
  const coverage = records.length >= need ? 'filled' : 'partial';
  const doc = {
    records,
    coverage,
    source: 'melissa_reverse_geocoder',
    createdAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + cfg.cacheDays * 864e5),
  };
  if (cfg.cacheDays > 0) await ref.set(doc);
  log({ event: 'gap', outcome: coverage, returned, kept: records.length, credits: spent });
  return { records, cached: false, coverage, credits: spent };
}

module.exports = {
  GAP_DEFAULTS, DiscoverError, REVERSE_CREDITS_PER_RECORD,
  validateDiscover, buildReverseUrl, parseReverseResponse, reverseLookup, discoverNearby, areaKey,
};
