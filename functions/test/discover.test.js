'use strict';
// Gap-filler tests: Firestore emulator + fake Melissa. One test parses the
// REAL Reverse GeoCoder response saved from the 2026-11-21 probe.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const {
  discoverNearby, DiscoverError, parseReverseResponse, buildReverseUrl, validateDiscover,
} = require('../src/discover');

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
const DAY = '2026-11-21';
const POINT = { latitude: 36.1699, longitude: -115.1398 }; // Las Vegas (sparse in Overture)
const fakeRecords = (n, start = 0) => Array.from({ length: n }, (_, i) => ({
  id: `mel:${1000 + start + i}`, line: `${100 + start + i} MAIN ST`, city: 'Las Vegas', state: 'NV',
  zip: '89101', latitude: 36.17, longitude: -115.14, distanceMeters: (start + i) * 10, units: 0, residential: null,
}));
const reverseOk = (n) => {
  const f = async (params) => { f.calls.push(params); return { status: 'ok', records: fakeRecords(Math.min(n, params.recs)) }; };
  f.calls = [];
  return f;
};
const ENABLED = { enabled: true, globalDailyCredits: 1e6 };
const run = (over = {}) => discoverNearby({
  db, uid: 'alice', data: { ...POINT, have: 12 }, key: 'k', now: NOW, config: ENABLED, reverse: reverseOk(100), ...over,
});
const rejectsWith = (p, reason) => assert.rejects(p, (e) => e instanceof DiscoverError && e.reason === reason);
const usage = async () => (await db.doc(`melissa_usage/${DAY}`).get()).data() || {};

test('disabled by default: refused before anything is read or spent', async () => {
  const reverse = reverseOk(100);
  await rejectsWith(run({ config: {}, reverse }), 'gap_filler_disabled');
  assert.equal(reverse.calls.length, 0);
  assert.deepEqual(await usage(), {});
});

test('input validation: US only, sane counts', () => {
  assert.throws(() => validateDiscover({ latitude: 23.8, longitude: 90.4, have: 0 }), (e) => e.reason === 'outside_us');
  assert.throws(() => validateDiscover({ ...POINT, have: 51 }), (e) => e.reason === 'bad_have');
  assert.throws(() => validateDiscover({ latitude: 'x', longitude: 1, have: 0 }), (e) => e.reason === 'bad_location');
});

test('Overture already has 50: no Melissa call, no cost', async () => {
  const reverse = reverseOk(100);
  const r = await run({ data: { ...POINT, have: 50 }, reverse });
  assert.equal(r.records.length, 0);
  assert.equal(reverse.calls.length, 0);
});

test('fills only the missing homes; charged per record returned', async () => {
  const reverse = reverseOk(100);
  const r = await run({ reverse });
  assert.equal(reverse.calls[0].recs, 48); // 38 needed + 10 buffer
  assert.equal(r.records.length, 38);
  assert.equal(r.coverage, 'filled');
  assert.equal((await usage()).gapCredits, 96); // 48 returned × 2
});

test('fewer addresses than needed: real count, unused credits refunded, nothing invented', async () => {
  const r = await run({ reverse: reverseOk(7) });
  assert.equal(r.records.length, 7);
  assert.equal(r.coverage, 'partial');
  assert.equal((await usage()).gapCredits, 14);
});

test('cached per user and per ~110 m area; other users are not served it', async () => {
  const reverse = reverseOk(100);
  await run({ reverse });
  const again = await run({ reverse, data: { latitude: 36.16992, longitude: -115.13984, have: 12 } });
  assert.equal(again.cached, true);
  assert.equal(reverse.calls.length, 1);
  const bob = await run({ uid: 'bob', reverse });
  assert.equal(bob.cached, false);
  assert.equal(reverse.calls.length, 2);
});

test('cacheDays 0 stores nothing', async () => {
  await run({ config: { ...ENABLED, cacheDays: 0 } });
  assert.equal((await db.collection('users/alice/gap_areas').get()).size, 0);
});

test('per-user daily limit and app-wide credit cap', async () => {
  const config = { ...ENABLED, perUserDaily: 1, cacheDays: 0 };
  await run({ config });
  await rejectsWith(run({ config }), 'user_daily_limit');
  await rejectsWith(run({ uid: 'bob', config: { ...ENABLED, dailyCredits: 100, cacheDays: 0 } }), 'app_daily_limit');
});

test('Melissa out of credits: everything refunded and gap-fill paused', async () => {
  const reverse = async () => ({ status: 'error', error: 'out_of_credits', records: [] });
  await rejectsWith(run({ reverse }), 'out_of_credits');
  const u = await usage();
  assert.equal(u.gapCredits, 0);
  assert.equal(u.gapFills, 0);
  await rejectsWith(run({ uid: 'bob' }), 'out_of_credits');
});

test('Melissa unavailable: refunded and reported, retry allowed', async () => {
  await rejectsWith(run({ reverse: async () => ({ status: 'error', error: 'timeout', records: [] }) }), 'timeout');
  assert.equal((await usage()).gapCredits, 0);
  const ok = await run();
  assert.equal(ok.records.length, 38);
});

test('verifyResidential drops businesses and charges 3 per check', async () => {
  let i = 0;
  const check = async () => ({ status: 'verified', residential: (i++ % 2) === 0 });
  const r = await run({ data: { ...POINT, have: 40 }, reverse: reverseOk(100), check, config: { ...ENABLED, verifyResidential: true, cacheDays: 0 } });
  // need 10, asked 20, 10 homes kept of 20 checked
  assert.equal(r.records.length, 10);
  assert.ok(r.records.every((x) => x.residential === true));
  assert.equal((await usage()).gapCredits, 20 * 2 + 20 * 3);
});

test('REAL Reverse GeoCoder response parses into address records', () => {
  const r = parseReverseResponse(require('./fixtures/reverse_geocoder_capitol.json'));
  assert.equal(r.status, 'ok');
  assert.equal(r.records.length, 5);
  assert.equal(r.records[0].line, '1 INDEPENDENCE SQ SW');
  assert.equal(r.records[0].state, 'DC');
  assert.equal(r.records[0].distanceMeters, Math.round(0.150827 * 1609.344));
  assert.ok(r.records.every((x) => x.id.startsWith('mel:') && x.residential === null));
});

test('parse: dedupes, skips records without a house number or location, maps GE14', () => {
  const r = parseReverseResponse({ TransmissionResults: '', Records: [
    { AddressLine1: '5 A St', Latitude: '1', Longitude: '2', MelissaAddressKey: '9' },
    { AddressLine1: '5 A St', Latitude: '1', Longitude: '2', MelissaAddressKey: '9' },
    { AddressLine1: 'A St', Latitude: '1', Longitude: '2' },
    { AddressLine1: '7 A St', Latitude: '', Longitude: '' },
  ] });
  assert.equal(r.records.length, 1);
  assert.equal(parseReverseResponse({ TransmissionResults: 'GE14' }).error, 'out_of_credits');
});

test('URL: apartments in, undeliverable and empty lots out, key once', () => {
  const u = new URL(buildReverseUrl({ latitude: 36.1, longitude: -115.1, recs: 20, miles: 3 }, 'KEY'));
  assert.match(u.searchParams.get('opt'), /IncludeApartments:on/);
  assert.match(u.searchParams.get('opt'), /IncludeUndeliverable:off/);
  assert.equal(u.searchParams.getAll('id').length, 1);
});
