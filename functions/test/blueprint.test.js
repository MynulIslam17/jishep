'use strict';
// Blueprint (docs/GPS_PARA_EL_CIELO_MASTER_BLUEPRINT.md) guarantees, tested
// against the Firestore emulator with fake Melissa functions that count
// calls. Owner names here say "TEST": synthetic, never real people.
//
//   §2.1/§8  the server searches only around the SAVED primary location;
//            forged coordinates are refused; no saved home = no search.
//   §7       paid discovery needs a verified account; the kill switch stops
//            every paid endpoint at once; budgets return "limited", not loops.
//   §4.3     365-day freshness; expiry never deletes a record.
//   §5.6     overlap / duplicate / boundary / multi-unit edge cases.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { discoverOwners, OwnerError, isVerifiedToken, validateOwners } = require('../src/owners');
const { enrichHousehold, EnrichError } = require('../src/enrich');
const { discoverNearby, DiscoverError } = require('../src/discover');
const { parsePropertyResponse } = require('../src/melissa');
const cache = require('../src/property_cache');
const { cleanupUser } = require('../src/cleanup');

let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['primary_locations', 'users', 'melissa_usage', 'owner_areas', 'owner_scans', 'owner_properties', 'discovery_jobs']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const NOW = new Date('2026-11-24T12:00:00Z');
const DAY = '2026-11-24';
const HOME = { latitude: 32.6401, longitude: -117.0842 };
const ON = { enabled: true, allowOwnerNames: true, sharedCache: true, globalDailyCredits: 1e6 };
const CACHE_ONLY = { enabled: false, allowOwnerNames: true, sharedCache: true };

// Address i lies 10*i m north of `at` (MAK 5000+i unless `base` given).
const address = (i, at = HOME, base = 5000, over = {}) => ({
  id: `mel:${base + i}`, mak: String(base + i), suite: null, units: 0,
  line: `${100 + i} TEST ST`, city: 'Chula Vista', state: 'CA', zip: '91910',
  latitude: at.latitude + (10 * i) / 111195, longitude: at.longitude, ...over,
});
const counted = (fn) => { const f = async (...a) => { f.calls.push(a); return fn(...a); }; f.calls = []; return f; };
const reverseWith = (records) => counted(async () => ({ status: 'ok', records }));
const propertyBody = (mak, { owner = `OWNER ${mak} TEST`, second = '', use = '385' } = {}) => ({
  Version: 'test', TransmissionResults: '', TotalRecords: 1,
  Records: [{
    Results: 'YS01,YS02',
    Parcel: { FIPSCode: '06073', UnformattedAPN: `APN-${mak}` },
    PropertyAddress: { Address: 'X', City: 'Chula Vista', State: 'CA', Zip: '91910-1234', MAK: mak, Latitude: '32.64', Longitude: '-117.08' },
    PrimaryOwner: { Name1Full: owner, Name2Full: second, CompanyFlag: '', TrustFlag: '' },
    PropertyUseInfo: { YearBuilt: '1978', PropertyUseGroup: 'Residential', PropertyUseStandardized: use },
    PropertySize: {},
  }],
});
const propertyFrom = (over = {}) => counted(async (a, _k, opts) => {
  const o = over[a.mak];
  if (o && o.error) return { status: 'error', error: o.error, codes: [] };
  return parsePropertyResponse(propertyBody(a.mak, o || {}), opts);
});
const never = () => counted(async () => { throw new Error('Melissa must not be called'); });
const setHome = (uid, at = HOME) => db.doc(`users/${uid}`).set({ latitude: at.latitude, longitude: at.longitude }, { merge: true });
const usage = async () => (await db.doc(`melissa_usage/${DAY}`).get()).data() || {};
const ask = (over = {}) => discoverOwners({
  db, uid: 'alice', key: 'k', now: NOW, config: ON, verified: true, appVerified: true, data: {}, ...over,
});

/** Seeds one stored scan around `at` with `n` addresses, all named. */
async function seedScan(at, n, base, { coveredMeters, named = true, now = NOW, days = 365 } = {}) {
  const records = Array.from({ length: n }, (_, i) => address(i + 1, at, base));
  const doc = cache.scanDoc({ latitude: at.latitude, longitude: at.longitude, records, recs: 100, miles: 1, now, days });
  if (coveredMeters != null) doc.coveredMeters = coveredMeters;
  await db.collection('owner_scans').doc(cache.scanIdFor(at.latitude, at.longitude, cache.SCAN_OPTIONS)).set(doc);
  if (named) {
    for (const c of records) {
      await db.collection('owner_properties').doc(c.id).set(cache.propertyDoc({
        candidate: c, status: cache.NAMED, now, days,
        property: { owner: { name: `OWNER ${c.mak} TEST` }, parcelId: `P-${c.mak}` },
        classification: { kind: 'single_family' },
      }));
    }
  }
  return records;
}

// ---------------------------------------------------------------- §2.1 / §8
test('location authority: no saved home → refused; forged far coordinates → refused, 0 calls', async () => {
  const reverse = never();
  await assert.rejects(ask({ reverse }), (e) => e instanceof OwnerError && e.reason === 'no_primary_location');
  await setHome('alice');
  const far = { latitude: HOME.latitude + 0.05, longitude: HOME.longitude }; // ~5.5 km
  await assert.rejects(ask({ data: far, reverse }),
    (e) => e instanceof OwnerError && e.code === 'permission-denied' && e.reason === 'location_not_authorized');
  assert.equal(reverse.calls.length, 0);
  assert.equal((await usage()).deniedSecurity, 1);
});

test('location authority: no coordinates or the saved ones (old app) search the saved home', async () => {
  await setHome('alice');
  await seedScan(HOME, 60, 5000);
  const a = await ask({ config: CACHE_ONLY, reverse: never() });
  // An older app sends its saved home (within tolerance): same answer.
  const near = { latitude: HOME.latitude + 0.0005, longitude: HOME.longitude }; // ~55 m
  const b = await ask({ config: CACHE_ONLY, data: near, reverse: never() });
  assert.equal(a.records.length, 50);
  assert.deepEqual(b.records.map((r) => r.id), a.records.map((r) => r.id));
  assert.equal(a.records[0].distanceMeters, 10); // measured from the saved home
});

test('location authority: a saved home outside the US, or a non-numeric one, is refused', async () => {
  await db.doc('users/alice').set({ latitude: 51.5, longitude: -0.12 });
  await assert.rejects(ask(), (e) => e.reason === 'outside_us');
  await db.doc('users/alice').set({ latitude: '32.6', longitude: '-117' });
  await assert.rejects(ask(), (e) => e.reason === 'no_primary_location');
  assert.throws(() => validateOwners({ latitude: 'x', longitude: 1 }), /bad_location/);
  assert.equal(validateOwners(undefined).latitude, null);
});

test('location lock: re-creating the profile elsewhere does not move the server’s home', async () => {
  await setHome('alice');
  await seedScan(HOME, 60, 5000);
  await ask({ config: CACHE_ONLY, reverse: never() }); // first use pins HOME
  const pin = (await db.doc('primary_locations/alice').get()).data();
  assert.equal(pin.latitude, HOME.latitude);
  assert.equal(pin.source, 'first_use');
  // The client deletes and re-creates users/alice 30 km away …
  const elsewhere = { latitude: HOME.latitude + 0.27, longitude: HOME.longitude };
  await db.doc('users/alice').set(elsewhere);
  // … and asks with those coordinates: refused; without them: still HOME.
  await assert.rejects(ask({ data: elsewhere, config: CACHE_ONLY }), (e) => e.reason === 'location_not_authorized');
  const r = await ask({ config: CACHE_ONLY, reverse: never() });
  assert.equal(r.records[0].distanceMeters, 10);
});

test('two first requests at once pin the same home', async () => {
  await setHome('alice');
  const results = await Promise.all(Array.from({ length: 8 }, () => ask({ config: CACHE_ONLY, reverse: never() })));
  assert.equal(results.length, 8);
  assert.equal((await db.doc('primary_locations/alice').get()).get('latitude'), HOME.latitude);
});

// --------------------------------------------------------------------- §7
test('verified accounts only: an unverified account gets the cache, never a paid call', async () => {
  await setHome('alice');
  const reverse = reverseWith([address(1)]);
  const r = await ask({ verified: false, reverse, property: never() });
  assert.equal(r.limited, 'unverified');
  assert.equal(reverse.calls.length, 0);
  assert.equal((await db.collection('discovery_jobs').get()).size, 0);
  assert.equal(isVerifiedToken({ email_verified: true }), true);
  assert.equal(isVerifiedToken({ email_verified: false, firebase: { sign_in_provider: 'password' } }), false);
  for (const p of ['google.com', 'apple.com', 'phone']) {
    assert.equal(isVerifiedToken({ firebase: { sign_in_provider: p } }), true);
  }
  assert.equal(isVerifiedToken(undefined), false);
});

test('kill switch: every paid endpoint stops at once; stored data is still served', async () => {
  await setHome('alice');
  // 10 named homes from a scan centred ~300 m away that reaches the home:
  // paid discovery would be wanted (a scan here + lookups).
  const away = { latitude: HOME.latitude - 300 / 111195, longitude: HOME.longitude };
  await seedScan(away, 10, 5000, { coveredMeters: 400 });
  await db.doc('melissa_usage/state').set({ paidDisabled: true });
  const reverse = reverseWith([]);
  const r = await ask({ reverse, property: never() });
  assert.equal(r.limited, 'paid_disabled');
  assert.equal(r.records.length, 10); // cached homes still shown
  assert.equal(reverse.calls.length, 0);
  const all = { ...ON, perUserDailyLookups: 100, verifyResidential: false, cacheDays: 30, perUserDaily: 10, dailyCredits: 1e6 };
  await assert.rejects(enrichHousehold({ appVerified: true, db, uid: 'alice', key: 'k', now: NOW, config: all, check: never(),
    data: { householdId: 'ovt:1', line: '1 Test St', city: 'Chula Vista', state: 'CA', zip: '91910' } }),
  (e) => e instanceof EnrichError && e.reason === 'paid_disabled');
  await assert.rejects(discoverNearby({ appVerified: true, db, uid: 'alice', key: 'k', now: NOW, config: all, reverse: never(), check: never(),
    data: { latitude: 36.1699, longitude: -115.1398, have: 10 } }),
  (e) => e instanceof DiscoverError && e.reason === 'paid_disabled');
  // Switched back on: the same request may pay again.
  await db.doc('melissa_usage/state').set({ paidDisabled: false }, { merge: true });
  const after = await ask({ reverse: reverseWith(Array.from({ length: 60 }, (_, i) => address(i + 20))), property: propertyFrom() });
  assert.equal(after.limited, undefined);
});

test('budget exhausted, uncached area: empty "limited" answer, no retry storm, 0 calls', async () => {
  await setHome('alice');
  const reverse = reverseWith([address(1)]);
  for (let i = 0; i < 3; i++) {
    const r = await ask({ config: { ...ON, monthlyCredits: 10 }, reverse });
    assert.equal(r.limited, 'app_monthly_limit');
    assert.equal(r.records.length, 0);
  }
  assert.equal(reverse.calls.length, 0);
  assert.equal((await usage()).deniedBudget, 3);
});

test('repeated accounts cannot multiply spending: app-wide daily cap holds across new uids', async () => {
  const cfg = { ...ON, dailyCredits: 1000 }; // room for one discovery's reservation (920)
  const results = [];
  for (let i = 0; i < 5; i++) {
    const at = { latitude: HOME.latitude + i * 0.05, longitude: HOME.longitude };
    await setHome(`farm${i}`, at);
    results.push(await ask({ uid: `farm${i}`, config: cfg,
      reverse: reverseWith(Array.from({ length: 30 }, (_, j) => address(j + 1, at, 10000 * (i + 1)))),
      property: propertyFrom() }));
  }
  const u = await usage();
  assert.ok(u.ownerCredits > 0 && u.ownerCredits <= 1000, `spent ${u.ownerCredits}`);
  assert.equal(results[0].limited, undefined);
  assert.ok(results.slice(1).some((r) => r.limited === 'app_daily_limit'));
});

// -------------------------------------------------------------------- §4.3
test('365-day freshness: stored with a 365-day expiry; stale is not served but never deleted', async () => {
  await setHome('alice');
  await ask({ reverse: reverseWith([address(1), address(2)]), property: propertyFrom() });
  const p = (await db.doc('owner_properties/mel:5001').get()).data();
  const s = (await db.collection('owner_scans').get()).docs[0].data();
  const days = (t) => Math.round((t.toMillis() - NOW.getTime()) / 864e5);
  assert.equal(days(p.expiresAt), 365);
  assert.equal(days(s.expiresAt), 365);
  const day364 = await ask({ now: new Date(NOW.getTime() + 364 * 864e5), config: CACHE_ONLY, reverse: never() });
  assert.equal(day364.records.length, 2);
  const day366 = await ask({ now: new Date(NOW.getTime() + 366 * 864e5), config: CACHE_ONLY, reverse: never() });
  assert.equal(day366.records.length, 0);
  assert.equal(day366.completeness, 'expired');
  assert.equal((await db.collection('owner_properties').get()).size, 2); // still there
});

// -------------------------------------------------------------------- §5.6
test('A/B 1 m apart: B is served entirely from A’s purchase, 0 credits', async () => {
  await setHome('a');
  const records = Array.from({ length: 60 }, (_, i) => address(i + 1));
  await ask({ uid: 'a', reverse: reverseWith(records), property: propertyFrom() });
  const b = { latitude: HOME.latitude + 1 / 111195, longitude: HOME.longitude };
  await setHome('b', b);
  const r = await ask({ uid: 'b', reverse: never(), property: never() });
  assert.equal(r.records.length, 50);
  assert.equal(r.credits, 0);
  assert.equal(r.cached, true);
});

test('B overlaps two cached scans (A and C): merged, deduplicated by MAK, nearest first, 0 calls', async () => {
  const A = { latitude: 32.6400, longitude: -117.0850 };
  const C = { latitude: 32.6400, longitude: -117.0830 }; // ~190 m east
  await seedScan(A, 40, 5000);
  // C repeats A's first 20 MAKs (same properties seen by both scans).
  const cRecords = [...Array.from({ length: 20 }, (_, i) => address(i + 1, A, 5000)),
    ...Array.from({ length: 40 }, (_, i) => address(i + 1, C, 7000))];
  const cDoc = cache.scanDoc({ latitude: C.latitude, longitude: C.longitude, records: cRecords, recs: 100, miles: 1, now: NOW, days: 365 });
  await db.collection('owner_scans').doc(cache.scanIdFor(C.latitude, C.longitude, cache.SCAN_OPTIONS)).set(cDoc);
  for (const c of cRecords.slice(20)) {
    await db.collection('owner_properties').doc(c.id).set(cache.propertyDoc({
      candidate: c, status: cache.NAMED, now: NOW, days: 365,
      property: { owner: { name: `OWNER ${c.mak} TEST` }, parcelId: `P-${c.mak}` }, classification: { kind: 'single_family' },
    }));
  }
  const B = { latitude: 32.6400, longitude: -117.0840 };
  await setHome('bob', B);
  const r = await ask({ uid: 'bob', config: CACHE_ONLY, reverse: never() });
  const ids = r.records.map((x) => x.id);
  assert.equal(new Set(ids).size, ids.length); // no duplicates
  assert.equal(r.stats.duplicateAddresses, 20);
  assert.equal(r.stats.scans, 2);
  for (let i = 1; i < r.records.length; i++) assert.ok(r.records[i].distanceMeters >= r.records[i - 1].distanceMeters);
  assert.equal(r.records.length, 50);
  assert.equal((await usage()).propertiesReused > 0, true);
});

test('B overlaps five cached scans: one answer, every property once', async () => {
  const centers = Array.from({ length: 5 }, (_, k) => ({ latitude: 32.64, longitude: -117.0850 + k * 0.0005 }));
  for (let k = 0; k < 5; k++) await seedScan(centers[k], 15, 20000 + k * 100);
  await setHome('bob', centers[2]);
  const r = await ask({ uid: 'bob', config: CACHE_ONLY, reverse: never() });
  assert.equal(r.stats.scans, 5);
  assert.equal(new Set(r.records.map((x) => x.id)).size, r.records.length);
  assert.equal(r.records.length, 50);
});

test('geohash boundary: a scan just across a geohash-5 edge is still found', async () => {
  // 32.651367 is a geohash-5 latitude edge near Chula Vista.
  const edge = 32.6513671875;
  const A = { latitude: edge + 0.0004, longitude: -117.08 };
  const B = { latitude: edge - 0.0004, longitude: -117.08 };
  assert.notEqual(cache.geohash(A.latitude, A.longitude, 5), cache.geohash(B.latitude, B.longitude, 5));
  await seedScan(A, 60, 5000);
  await setHome('bob', B);
  const r = await ask({ uid: 'bob', config: CACHE_ONLY, reverse: never() });
  assert.equal(r.stats.scans, 1);
  assert.equal(r.records.length, 50);
});

test('negative answers last as long as the scan: no re-purchase on day 200', async () => {
  await setHome('alice');
  const records = [address(1), address(2)];
  await ask({ reverse: reverseWith(records), property: propertyFrom({ 5002: { owner: '' } }) });
  assert.equal((await db.doc('owner_properties/mel:5002').get()).get('status'), 'no_owner');
  const property = never();
  const r = await ask({ now: new Date(NOW.getTime() + 200 * 864e5), reverse: never(), property });
  assert.equal(property.calls.length, 0);
  assert.equal(r.records.length, 1);
});

test('multi-unit buildings and suites are skipped; a second owner is kept; no owner = excluded', async () => {
  await setHome('alice');
  const records = [
    address(1), address(2, HOME, 5000, { units: 12 }), address(3, HOME, 5000, { suite: 'APT 4' }),
    address(4), address(5),
  ];
  const r = await ask({
    reverse: reverseWith(records),
    property: propertyFrom({ 5004: { second: 'SECOND OWNER TEST' }, 5005: { owner: '' } }),
  });
  const ids = r.records.map((x) => x.id);
  assert.deepEqual(ids, ['mel:5001', 'mel:5004']);
  assert.equal(r.records[1].owner.secondName, 'SECOND OWNER TEST');
  assert.equal(r.stats.noOwner, 1);
});

test('a scan with only 15 valid homes is returned as 15 (never padded)', async () => {
  await setHome('alice');
  const r = await ask({ reverse: reverseWith(Array.from({ length: 15 }, (_, i) => address(i + 1))), property: propertyFrom() });
  assert.equal(r.records.length, 15);
  assert.equal(r.coverage, 'partial');
});

test('Melissa empty / timeout / rate-limited: nothing invented, nothing charged on uncharged errors', async () => {
  await setHome('alice');
  const empty = await ask({ reverse: reverseWith([]), property: never() });
  assert.equal(empty.records.length, 0);
  await db.recursiveDelete(db.collection('owner_scans'));
  await db.recursiveDelete(db.collection('discovery_jobs'));
  await setHome('t');
  const timeout = counted(async () => ({ status: 'error', error: 'timeout', records: [] }));
  await assert.rejects(ask({ uid: 't', reverse: timeout }), (e) => e.reason === 'timeout');
  const rate = counted(async () => ({ status: 'error', error: 'rate_limited', records: [] }));
  await setHome('r');
  await assert.rejects(ask({ uid: 'r', reverse: rate }), (e) => e.code === 'resource-exhausted');
  // Empty scan: 0 addresses returned = 0 credits; errors: reservation given back.
  assert.equal((await usage()).ownerCredits || 0, 0);
});

test('retry after partial progress never pays twice for a finished lookup', async () => {
  await setHome('alice');
  const records = Array.from({ length: 30 }, (_, i) => address(i + 1));
  const first = propertyFrom({ 5010: { error: 'out_of_credits' } });
  await ask({ reverse: reverseWith(records), property: first, config: { ...ON, concurrency: 1 } });
  await db.doc('melissa_usage/state').set({ outOfCreditsAt: null }, { merge: true });
  const second = propertyFrom();
  await ask({ reverse: never(), property: second });
  const firstDone = first.calls.map((c) => c[0].mak).filter((m) => m !== '5010');
  const again = second.calls.map((c) => c[0].mak);
  assert.equal(again.filter((m) => firstDone.includes(m)).length, 0);
});

test('account deletion mid-life: the user’s private data goes, shared properties stay', async () => {
  await setHome('alice');
  await ask({ reverse: reverseWith([address(1), address(2)]), property: propertyFrom() });
  await db.doc('users/alice/household_status/mel:5001').set({ isPrayed: true });
  await db.doc('discovery_jobs/u_alice_9mudq0').set({ status: 'done' });
  await db.doc('discovery_jobs/u_alicex_9mudq0').set({ status: 'done' }); // another user
  await cleanupUser(db, 'alice');
  assert.equal((await db.doc('primary_locations/alice').get()).exists, false);
  assert.equal((await db.doc('users/alice/household_status/mel:5001').get()).exists, false);
  assert.equal((await db.doc('discovery_jobs/u_alice_9mudq0').get()).exists, false);
  assert.equal((await db.doc('discovery_jobs/u_alicex_9mudq0').get()).exists, true);
  assert.equal((await db.collection('owner_properties').get()).size, 2);
  assert.equal((await db.collection('owner_scans').get()).size, 1);
});

test('expired lease from a restarted function: the next request continues', async () => {
  await setHome('alice');
  const jobId = cache.jobIdFor('shared', HOME.latitude, HOME.longitude);
  await db.doc(`discovery_jobs/${jobId}`).set({
    status: 'running', leaseOwner: 'crashed', leaseExpiresAt: Timestamp.fromMillis(Date.now() - 1000),
  });
  const reverse = reverseWith([address(1)]);
  const r = await ask({ reverse, property: propertyFrom() });
  assert.equal(reverse.calls.length, 1);
  assert.equal(r.records.length, 1);
});
