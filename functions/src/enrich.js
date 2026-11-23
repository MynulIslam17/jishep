'use strict';
// Core of the enrichHousehold callable: validation, cache, credit budget,
// Melissa call and the stored result. Firebase wiring is in index.js so this
// file can be tested against the Firestore emulator.

const { overGlobalLimit } = require('./budget');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { CHECK_CREDITS, PROPERTY_CREDITS, checkAddress, lookupProperty } = require('./melissa');

const DEFAULTS = {
  // Lookups one user may make per UTC day (each costs CHECK_CREDITS).
  perUserDailyLookups: 20,
  // Credits the whole app (every endpoint) may spend per UTC day.
  // 0 = no paid call at all (fail closed: also when unset).
  globalDailyCredits: 0,
  // Days a user's own result is reused before Melissa is asked again.
  // 0 = never store (use this if Melissa's terms do not allow caching).
  cacheDays: 30,
  // After GE14 (out of credits), Melissa is not called for this long.
  outOfCreditsPauseMs: 6 * 60 * 60 * 1000,
  // Ask Property for the recorded owner (public record). OFF until Melissa's
  // license is confirmed to allow showing owner names (app owner's
  // instruction, 2026-11-22). MELISSA_ALLOW_OWNER_NAMES=true turns it on.
  allowOwnerNames: false,
};

class EnrichError extends Error {
  /** `code` is a Firebase HttpsError code; `reason` is shown to the app. */
  constructor(code, reason) {
    super(reason);
    this.code = code;
    this.reason = reason;
  }
}

const ID = /^[A-Za-z0-9:_.-]{1,128}$/;
const STATE = /^[A-Z]{2}$/;
const ZIP = /^\d{5}(-\d{4})?$/;

/** Validates and normalises the callable's input, or throws EnrichError. */
function validateInput(data) {
  if (!data || typeof data !== 'object') {
    throw new EnrichError('invalid-argument', 'bad_input');
  }
  const clean = (v, max) =>
    typeof v === 'string' ? v.replace(/[\u0000-\u001f]/g, ' ').trim().slice(0, max) : '';
  const householdId = typeof data.householdId === 'string' ? data.householdId : '';
  const line = clean(data.line, 200);
  const city = clean(data.city, 80);
  const state = clean(data.state, 3).toUpperCase();
  const zip = clean(data.zip, 10);
  if (!ID.test(householdId)) throw new EnrichError('invalid-argument', 'bad_household_id');
  // A street line needs a house number; Overture records always have one.
  if (line.length < 3 || !/\d/.test(line)) {
    throw new EnrichError('invalid-argument', 'no_street_address');
  }
  if (!STATE.test(state)) throw new EnrichError('invalid-argument', 'bad_state');
  if (zip && !ZIP.test(zip)) throw new EnrichError('invalid-argument', 'bad_zip');
  if (!zip && !city) throw new EnrichError('invalid-argument', 'need_city_or_zip');
  return { householdId, line, city, state, zip, includeProperty: data.includeProperty === true };
}

const dayKey = (now) => now.toISOString().slice(0, 10);

/**
 * Reserves one lookup (CHECK_CREDITS credits) for `uid` today, or throws
 * EnrichError('resource-exhausted', ...) when a budget is used up.
 */
async function reserve(db, uid, now, cfg, credits) {
  const day = db.collection('melissa_usage').doc(dayKey(now));
  const user = day.collection('users').doc(uid);
  const state = db.collection('melissa_usage').doc('state');
  await db.runTransaction(async (tx) => {
    const [daySnap, userSnap, stateSnap] = await Promise.all([
      tx.get(day), tx.get(user), tx.get(state),
    ]);
    const pausedAt = stateSnap.get('outOfCreditsAt');
    if (pausedAt && now.getTime() - pausedAt.toMillis() < cfg.outOfCreditsPauseMs) {
      throw new EnrichError('resource-exhausted', 'out_of_credits');
    }
    if ((userSnap.get('lookups') || 0) >= cfg.perUserDailyLookups) {
      throw new EnrichError('resource-exhausted', 'user_daily_limit');
    }
    if (overGlobalLimit(daySnap, credits, cfg.globalDailyCredits)) {
      throw new EnrichError('resource-exhausted', 'app_daily_limit');
    }
    tx.set(day, {
      credits: FieldValue.increment(credits),
      lookups: FieldValue.increment(1),
    }, { merge: true });
    tx.set(user, { lookups: FieldValue.increment(1) }, { merge: true });
  });
  return { day, user };
}

/** Gives back a reservation when Melissa did not process the record. */
async function refund(db, reservation, credits, { lookup = true } = {}) {
  const batch = db.batch();
  batch.set(reservation.day, {
    credits: FieldValue.increment(-credits),
    ...(lookup ? { lookups: FieldValue.increment(-1) } : {}),
    refunds: FieldValue.increment(1),
  }, { merge: true });
  if (lookup) batch.set(reservation.user, { lookups: FieldValue.increment(-1) }, { merge: true });
  await batch.commit();
}

// Transmission-level failures: Melissa processed no record (no charge).
const UNCHARGED = new Set([
  'not_configured', 'license_invalid', 'license_disabled', 'product_not_enabled',
  'out_of_credits', 'not_available_for_credit_license', 'timeout', 'network',
  'rate_limited', 'unavailable', 'melissa_internal_error', 'bad_response',
  'melissa_error',
]);

/**
 * Checks one household address for `uid`. Returns the stored result
 * (plus `cached: true` when reused). Throws EnrichError.
 */
async function enrichHousehold({ db, uid, data, key, now = new Date(), config = {}, check = checkAddress, property = lookupProperty, log = () => {} }) {
  if (!uid) throw new EnrichError('unauthenticated', 'sign_in_required');
  const cfg = { ...DEFAULTS, ...config };
  const input = validateInput(data);
  const ref = db.collection('users').doc(uid).collection('enrichment').doc(input.householdId);

  if (cfg.cacheDays > 0) {
    const cached = await ref.get();
    const expires = cached.get('expiresAt');
    const cachedProperty = cached.get('property');
    // A result cached before owner names were allowed is looked up again.
    const ownerWanted = input.includeProperty && cfg.allowOwnerNames === true;
    const hasWanted = (!input.includeProperty || cachedProperty != null) &&
      (!ownerWanted || cachedProperty?.ownerRequested === true ||
        cachedProperty?.status !== 'found');
    if (cached.exists && expires && expires.toMillis() > now.getTime() && hasWanted) {
      log({ event: 'enrich', outcome: 'cache_hit' });
      return { ...serialize(cached.data()), cached: true };
    }
  }

  const credits = CHECK_CREDITS + (input.includeProperty ? PROPERTY_CREDITS : 0);
  const reservation = await reserve(db, uid, now, cfg, credits);
  const result = await check({ ...input, requestId: input.householdId }, key);

  if (result.status === 'error') {
    if (UNCHARGED.has(result.error)) await refund(db, reservation, credits);
    if (result.error === 'out_of_credits') {
      await db.collection('melissa_usage').doc('state').set(
        { outOfCreditsAt: Timestamp.fromDate(now) }, { merge: true });
    }
    log({ event: 'enrich', outcome: 'error', error: result.error, codes: result.codes });
    const busy = ['out_of_credits', 'rate_limited'].includes(result.error);
    throw new EnrichError(busy ? 'resource-exhausted' : 'unavailable', result.error);
  }

  let propertyDoc = null;
  if (input.includeProperty) {
    const p = await property({ ...input, requestId: input.householdId }, key,
      { includeOwner: cfg.allowOwnerNames === true });
    if (p.status === 'error') {
      if (UNCHARGED.has(p.error)) await refund(db, reservation, PROPERTY_CREDITS, { lookup: false });
      log({ event: 'enrich', outcome: 'property_error', error: p.error, codes: p.codes });
      propertyDoc = { status: 'unavailable' };
    } else {
      propertyDoc = { ...p, source: 'melissa_property',
        ownerRequested: cfg.allowOwnerNames === true };
      delete propertyDoc.codes;
    }
  }

  const doc = {
    status: result.status,
    property: propertyDoc,
    address: result.address ?? null,
    residential: result.residential ?? null,
    deliveryIndicator: result.deliveryIndicator ?? null,
    addressTypeCode: result.addressTypeCode ?? null,
    latitude: result.latitude ?? null,
    longitude: result.longitude ?? null,
    geocodeLevel: result.geocodeLevel ?? null,
    melissaAddressKey: result.melissaAddressKey ?? null,
    codes: result.codes ?? [],
    source: 'melissa_personator_check',
    checkedAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + cfg.cacheDays * 864e5),
  };
  if (cfg.cacheDays > 0) await ref.set(doc);
  log({ event: 'enrich', outcome: result.status, codes: result.codes });
  return { ...serialize(doc), cached: false };
}

/** Timestamps → ISO strings for the callable response. */
function serialize(doc) {
  const out = { ...doc };
  for (const k of ['checkedAt', 'expiresAt']) {
    if (out[k] && typeof out[k].toDate === 'function') out[k] = out[k].toDate().toISOString();
  }
  return out;
}

module.exports = { DEFAULTS, EnrichError, validateInput, enrichHousehold, dayKey };
