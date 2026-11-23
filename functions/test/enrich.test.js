'use strict';
// Integration tests against the Firestore emulator (demo- project, no
// network, no Melissa). Melissa is replaced by a fake `check` function.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { enrichHousehold, validateInput, EnrichError, dayKey } = require('../src/enrich');

let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['users', 'melissa_usage']) await db.recursiveDelete(db.collection(c));
});

const NOW = new Date('2026-11-21T12:00:00Z');
const DATA = { householdId: 'ovt:08b2a1', line: '1240 New Jersey Ave NW', city: 'Washington', state: 'dc', zip: '20001' };
const verified = async () => ({
  status: 'verified', codes: ['AS01', 'GS05'], residential: true, deliveryIndicator: 'R',
  addressTypeCode: 'S', latitude: 38.9, longitude: -77.0, geocodeLevel: 'rooftop',
  melissaAddressKey: '8008006245',
  address: { line: '1240 NEW JERSEY AVE NW', suite: null, city: 'Washington', state: 'DC', zip: '20001-1234' },
});
const counting = (impl) => {
  const f = async (...a) => { f.calls++; return impl(...a); };
  f.calls = 0;
  return f;
};
// Paid paths need an explicit app-wide budget (the default is 0: no calls).
const BUDGET = { globalDailyCredits: 1e6 };
const run = (over = {}) => enrichHousehold({ db, uid: 'alice', data: DATA, key: 'k', now: NOW, check: verified, ...over,
  config: { ...BUDGET, ...over.config } });
const rejectsWith = (p, reason) => assert.rejects(p, (e) => e instanceof EnrichError && e.reason === reason);

test('input is validated and normalised', () => {
  assert.deepEqual(validateInput(DATA), { ...DATA, state: 'DC', includeProperty: false });
  assert.equal(validateInput({ ...DATA, includeProperty: true }).includeProperty, true);
  for (const [over, reason] of [
    [{ householdId: '../x' }, 'bad_household_id'],
    [{ line: 'Main Street' }, 'no_street_address'],
    [{ state: 'California' }, 'bad_state'],
    [{ zip: '2000' }, 'bad_zip'],
    [{ zip: '', city: '' }, 'need_city_or_zip'],
  ]) {
    assert.throws(() => validateInput({ ...DATA, ...over }), (e) => e.reason === reason);
  }
});

test('signed-out callers are refused before anything is read', async () => {
  await rejectsWith(run({ uid: null }), 'sign_in_required');
});

test('a check is stored for the user, counted, and reused from the cache', async () => {
  const check = counting(verified);
  const first = await run({ check });
  assert.equal(first.status, 'verified');
  assert.equal(first.cached, false);
  const stored = await db.doc('users/alice/enrichment/ovt:08b2a1').get();
  assert.equal(stored.get('source'), 'melissa_personator_check');
  assert.equal(stored.get('residential'), true);

  const second = await run({ check });
  assert.equal(second.cached, true);
  assert.equal(check.calls, 1);
  const day = await db.doc(`melissa_usage/${dayKey(NOW)}`).get();
  assert.equal(day.get('credits'), 3);
  assert.equal(day.get('lookups'), 1);
});

test('results are per user: Bob does not get Alice\'s cached check', async () => {
  const check = counting(verified);
  await run({ check });
  const bob = await run({ uid: 'bob', check });
  assert.equal(bob.cached, false);
  assert.equal(check.calls, 2);
  assert.ok((await db.doc('users/bob/enrichment/ovt:08b2a1').get()).exists);
});

test('cacheDays 0: nothing is stored and Melissa is asked every time', async () => {
  const check = counting(verified);
  await run({ check, config: { cacheDays: 0 } });
  await run({ check, config: { cacheDays: 0 } });
  assert.equal(check.calls, 2);
  assert.equal((await db.doc('users/alice/enrichment/ovt:08b2a1').get()).exists, false);
});

test('per-user daily limit', async () => {
  const config = { perUserDailyLookups: 2, cacheDays: 0 };
  await run({ config });
  await run({ config });
  await rejectsWith(run({ config }), 'user_daily_limit');
  // Another user still can.
  await run({ uid: 'bob', config });
});

test('app-wide daily credit budget', async () => {
  const config = { globalDailyCredits: 6, cacheDays: 0 };
  await run({ config });
  await run({ uid: 'bob', config });
  await rejectsWith(run({ uid: 'carol', config }), 'app_daily_limit');
});

test('out of credits (GE14): refunded, then Melissa is paused for everyone', async () => {
  const check = counting(async () => ({ status: 'error', error: 'out_of_credits', codes: ['GE14'] }));
  await rejectsWith(run({ check }), 'out_of_credits');
  const day = await db.doc(`melissa_usage/${dayKey(NOW)}`).get();
  assert.equal(day.get('credits'), 0);
  await rejectsWith(run({ uid: 'bob', check }), 'out_of_credits');
  assert.equal(check.calls, 1);
  // After the pause Melissa is tried again.
  await rejectsWith(run({ check, now: new Date(NOW.getTime() + 7 * 3600e3) }), 'out_of_credits');
  assert.equal(check.calls, 2);
});

test('Melissa unavailable: refunded, nothing stored, retry allowed', async () => {
  await rejectsWith(run({ check: async () => ({ status: 'error', error: 'unavailable', codes: [] }) }), 'unavailable');
  assert.equal((await db.doc('users/alice/enrichment/ovt:08b2a1').get()).exists, false);
  assert.equal((await db.doc(`melissa_usage/${dayKey(NOW)}/users/alice`).get()).get('lookups'), 0);
  const ok = await run();
  assert.equal(ok.status, 'verified');
});

test('no match is a normal result and is stored (not invented)', async () => {
  const r = await run({ check: async () => ({ status: 'not_found', codes: ['AE01'], address: {}, residential: null }) });
  assert.equal(r.status, 'not_found');
  assert.equal(r.residential, null);
});

const propertyFound = async (_a, _k, opts) => ({
  status: 'found', codes: ['YS02'], useGroup: 'Residential', useCode: '385', yearBuilt: 1962,
  lotSqft: 6000, buildingSqft: 1450, latitude: 38.9, longitude: -77.0,
  ...(opts.includeOwner ? { owner: { name: 'OWNER NAME', isCompany: false, isTrust: false } } : {}),
});

test('property details: 3 + 9 credits, recorded owner when allowOwnerNames is on', async () => {
  let ownerAsked = null;
  const property = async (a, k, opts) => { ownerAsked = opts.includeOwner; return propertyFound(a, k, opts); };
  const r = await run({ data: { ...DATA, includeProperty: true }, property, config: { allowOwnerNames: true } });
  assert.equal(ownerAsked, true);
  assert.equal(r.property.useGroup, 'Residential');
  assert.equal(r.property.yearBuilt, 1962);
  assert.equal(r.property.owner.name, 'OWNER NAME');
  assert.equal((await db.doc(`melissa_usage/${dayKey(NOW)}`).get()).get('credits'), 12);
  const stored = await db.doc('users/alice/enrichment/ovt:08b2a1').get();
  assert.equal(stored.get('property').owner.name, 'OWNER NAME');
});

test('no owner names by default (license not confirmed)', async () => {
  let ownerAsked = null;
  const property = async (a, k, opts) => { ownerAsked = opts.includeOwner; return propertyFound(a, k, opts); };
  const r = await run({ data: { ...DATA, includeProperty: true }, property });
  assert.equal(ownerAsked, false);
  assert.equal(r.property.owner, undefined);
});

test('a property result cached without the owner is looked up once more', async () => {
  const property = counting(propertyFound);
  await run({ data: { ...DATA, includeProperty: true }, property, config: { allowOwnerNames: false } });
  const r = await run({ data: { ...DATA, includeProperty: true }, property, config: { allowOwnerNames: true } });
  assert.equal(r.cached, false);
  assert.equal(r.property.owner.name, 'OWNER NAME');
  const again = await run({ data: { ...DATA, includeProperty: true }, property, config: { allowOwnerNames: true } });
  assert.equal(again.cached, true);
  assert.equal(again.property.owner.name, 'OWNER NAME');
  assert.equal(property.calls, 2);
});

test('a cached check without property details is refreshed when they are asked for', async () => {
  const check = counting(verified);
  await run({ check });
  const r = await run({ check, data: { ...DATA, includeProperty: true }, property: propertyFound });
  assert.equal(r.cached, false);
  assert.equal(check.calls, 2);
  const again = await run({ check, data: { ...DATA, includeProperty: true }, property: propertyFound });
  assert.equal(again.cached, true);
});

test('property lookup failure: address result kept, property credits refunded', async () => {
  const r = await run({
    data: { ...DATA, includeProperty: true },
    property: async () => ({ status: 'error', error: 'unavailable', codes: [] }),
  });
  assert.equal(r.status, 'verified');
  assert.equal(r.property.status, 'unavailable');
  assert.equal((await db.doc(`melissa_usage/${dayKey(NOW)}`).get()).get('credits'), 3);
});

test('budget counts the property credits too', async () => {
  await rejectsWith(run({ data: { ...DATA, includeProperty: true }, property: propertyFound, config: { globalDailyCredits: 10 } }), 'app_daily_limit');
});
