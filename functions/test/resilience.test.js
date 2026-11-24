'use strict';
// Resilience against the Firestore emulator with fake Melissa functions that
// count calls (owner names say "TEST": synthetic, never real people).
//
//   App Check   paid Melissa only with a valid App Check token; apps without
//               one (builds before App Check) keep the stored data.
//   Expiry      a record that expires while a request is running: `now` is
//               fixed per request, and a re-lookup happens exactly once even
//               when several users ask at the same moment.
//   Outage      Firestore UNAVAILABLE: no Melissa call is made without a
//               working database, credits are never under-counted, and a
//               lease that could not be released blocks a second paid job
//               until it expires.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { discoverOwners, isAppCheckVerified } = require('../src/owners');
const { enrichHousehold, EnrichError } = require('../src/enrich');
const { discoverNearby, DiscoverError } = require('../src/discover');
const { parsePropertyResponse } = require('../src/melissa');
const cache = require('../src/property_cache');

let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['primary_locations', 'users', 'melissa_usage', 'owner_areas', 'owner_scans',
    'owner_properties', 'discovery_jobs']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const DAY_MS = 864e5;
const NOW = new Date('2026-11-24T12:00:00Z');
const DAY = '2026-11-24';
const at = (ms) => new Date(NOW.getTime() + ms);
const HOME = { latitude: 32.6401, longitude: -117.0842 };
const ON = { enabled: true, allowOwnerNames: true, sharedCache: true, globalDailyCredits: 1e6, pollMs: 25 };
const CACHE_ONLY = { enabled: false, allowOwnerNames: true, sharedCache: true };

const address = (i, base = 7000) => ({
  id: `mel:${base + i}`, mak: String(base + i), suite: null, units: 0,
  line: `${100 + i} TEST ST`, city: 'Chula Vista', state: 'CA', zip: '91910',
  latitude: HOME.latitude + (10 * i) / 111195, longitude: HOME.longitude,
});
const ADDRESSES = Array.from({ length: 60 }, (_, i) => address(i + 1));
const counted = (fn) => { const f = async (...a) => { f.calls.push(a); return fn(...a); }; f.calls = []; return f; };
const never = () => counted(async () => { throw new Error('Melissa must not be called'); });
const reverseWith = (records) => counted(async () => ({ status: 'ok', records }));
const body = (mak) => ({
  Version: 'test', TransmissionResults: '', TotalRecords: 1,
  Records: [{
    Results: 'YS01,YS02',
    Parcel: { FIPSCode: '06073', UnformattedAPN: `APN-${mak}` },
    PropertyAddress: { Address: 'X', City: 'Chula Vista', State: 'CA', Zip: '91910-1234', MAK: mak, Latitude: '32.64', Longitude: '-117.08' },
    PrimaryOwner: { Name1Full: `OWNER ${mak} TEST`, Name2Full: '', CompanyFlag: '', TrustFlag: '' },
    PropertyUseInfo: { YearBuilt: '1978', PropertyUseGroup: 'Residential', PropertyUseStandardized: '385' },
    PropertySize: {},
  }],
});
const property = (gate) => counted(async (a, _k, opts) => {
  if (gate) await gate;
  return parsePropertyResponse(body(a.mak), opts);
});
const usage = async () => (await db.doc(`melissa_usage/${DAY}`).get()).data() || {};
const setHome = () => db.doc('users/alice').set(HOME, { merge: true });
const ask = (over = {}) => discoverOwners({
  db, uid: 'alice', key: 'k', now: NOW, config: ON, verified: true, appVerified: true, data: {}, ...over,
});

/** A fresh scan at the home, and its addresses' owner records stored at
 *  `propsAt` (so they expire 365 days later). */
async function seed({ propsAt = NOW, scanAt = NOW } = {}) {
  await db.collection('owner_scans').doc(cache.scanIdFor(HOME.latitude, HOME.longitude, cache.SCAN_OPTIONS))
    .set(cache.scanDoc({ ...HOME, records: ADDRESSES, recs: 100, miles: 1, now: scanAt, days: 365 }));
  for (const c of ADDRESSES) {
    await db.collection('owner_properties').doc(c.id).set(cache.propertyDoc({
      candidate: c, status: cache.NAMED, now: propsAt, days: 365,
      property: { owner: { name: `OWNER ${c.mak} TEST` } }, classification: { kind: 'single_family' },
    }));
  }
}

// ------------------------------------------------------------- App Check
test('App Check: request.app with an appId counts; missing / empty does not', () => {
  assert.equal(isAppCheckVerified({ appId: '1:123:ios:abc', token: {} }), true);
  assert.equal(isAppCheckVerified(undefined), false);
  assert.equal(isAppCheckVerified({}), false);
  assert.equal(isAppCheckVerified({ appId: '' }), false);
});

test('App Check: without a token paid discovery is refused (limited) and stored data is served', async () => {
  await setHome();
  const reverse = never();
  const r = await ask({ appVerified: false, reverse, property: never() });
  assert.equal(r.limited, 'app_check');
  assert.equal(reverse.calls.length, 0);
  assert.equal((await usage()).deniedSecurity, 1);
  assert.equal((await db.collection('discovery_jobs').get()).size, 0); // no lease, no reservation
  assert.equal((await usage()).ownerCredits, undefined);
  // The same request from a genuine app pays once.
  const ok = reverseWith(ADDRESSES);
  await ask({ reverse: ok, property: property() });
  assert.equal(ok.calls.length, 1);
});

test('App Check: an old app (no token) still gets a complete stored neighborhood', async () => {
  await setHome();
  await seed();
  const r = await ask({ appVerified: false, reverse: never(), property: never() });
  assert.equal(r.records.length, 50);
  assert.equal(r.limited, undefined);
});

test('App Check: enrichHousehold / discoverNearby refuse a paid lookup without a token, serve cache with one missing', async () => {
  const data = { householdId: 'ovt:1', line: '1 TEST ST', city: 'Chula Vista', state: 'ca', zip: '91910' };
  const check = never();
  const config = { globalDailyCredits: 1e6 };
  await assert.rejects(enrichHousehold({ db, uid: 'alice', data, key: 'k', now: NOW, config, check }),
    (e) => e instanceof EnrichError && e.reason === 'app_check_required');
  await assert.rejects(discoverNearby({ db, uid: 'alice', data: { ...HOME, have: 10 }, key: 'k', now: NOW,
    config: { enabled: true, globalDailyCredits: 1e6 }, reverse: never(), check }),
  (e) => e instanceof DiscoverError && e.reason === 'app_check_required');
  assert.equal(check.calls.length, 0);
  // A stored answer is still served without a token.
  await db.doc('users/alice/enrichment/ovt:1').set({
    status: 'verified', property: null, expiresAt: new Date(NOW.getTime() + DAY_MS),
  });
  const r = await enrichHousehold({ db, uid: 'alice', data, key: 'k', now: NOW, config, check });
  assert.equal(r.cached, true);
});

// ------------------------------------------------- expiry during a request
test('expiry: a record expiring 1 s after the request started is served for that whole request', async () => {
  await setHome();
  // Owner records stored 365 days minus 1 s ago → they expire at NOW + 1 s.
  await seed({ propsAt: new Date(NOW.getTime() - 365 * DAY_MS + 1000) });
  const r = await ask({ now: NOW, reverse: never(), property: never() });
  assert.equal(r.records.length, 50);
  assert.equal(r.completeness, 'complete');
});

test('expiry: after expiry only the stale owner records are re-bought, once each; nothing deleted or duplicated', async () => {
  await setHome();
  await seed({ propsAt: new Date(NOW.getTime() - 365 * DAY_MS + 1000) });
  const prop = property();
  const r = await ask({ now: at(2000), reverse: never(), property: prop });
  const maks = prop.calls.map((c) => c[0].mak);
  assert.equal(new Set(maks).size, maks.length); // each address at most once
  assert.ok(maks.length >= 50 && maks.length <= 60);
  assert.equal(r.records.length, 50);
  assert.equal((await db.collection('owner_properties').get()).size, 60);
  const one = (await db.doc(`owner_properties/${ADDRESSES[0].id}`).get()).data();
  assert.equal(one.expiresAt.toMillis(), at(2000).getTime() + 365 * DAY_MS); // renewed, same doc id
});

test('expiry: two users asking while the re-lookup runs → Melissa asked once per address', async () => {
  await setHome();
  await db.doc('users/bob').set(HOME);
  await seed({ propsAt: new Date(NOW.getTime() - 365 * DAY_MS + 1000) });
  let release;
  const gate = new Promise((r) => { release = r; });
  const propA = property(gate);
  const propB = property();
  const a = ask({ now: at(2000), reverse: never(), property: propA });
  await new Promise((r) => setTimeout(r, 150)); // A holds the lease, lookups in flight
  const b = discoverOwners({ db, uid: 'bob', key: 'k', now: at(3000), config: ON, verified: true,
    appVerified: true, data: {}, reverse: never(), property: propB });
  setTimeout(release, 150);
  const [ra, rb] = await Promise.all([a, b]);
  assert.equal(propB.calls.length, 0); // B waited for A and read its answer
  assert.equal(new Set(propA.calls.map((c) => c[0].mak)).size, propA.calls.length);
  assert.equal(rb.records.length, 50);
  assert.deepEqual(rb.records.map((x) => x.id), ra.records.map((x) => x.id));
});

// --------------------------------------------------------- Firestore outage
const OPS = new Set(['get', 'getAll', 'set', 'update', 'create', 'delete', 'add', 'commit', 'runTransaction', 'listDocuments']);
const unavailable = () => Object.assign(new Error('14 UNAVAILABLE: test outage'), { code: 14 });
/** The real database, except that every read / write / transaction fails
 *  with UNAVAILABLE while `state.down` is true. */
function flaky(target, state) {
  return new Proxy(target, {
    get(t, prop) {
      const v = Reflect.get(t, prop, t);
      if (typeof v !== 'function') return v;
      return (...args) => {
        // A WriteBatch queues set/update/delete synchronously; only its
        // commit talks to the server.
        const batch = typeof t.commit === 'function';
        if (state.down && (batch ? prop === 'commit' : OPS.has(prop))) return Promise.reject(unavailable());
        const out = v.apply(t, args);
        return out && typeof out === 'object' && typeof out.then !== 'function' ? flaky(out, state) : out;
      };
    },
  });
}

test('outage: Firestore down from the start → every endpoint fails fast, 0 Melissa calls', async () => {
  await setHome();
  const state = { down: true };
  const down = flaky(db, state);
  const reverse = never();
  const prop = never();
  const check = never();
  const isOutage = (e) => e && e.code === 14;
  await assert.rejects(discoverOwners({ db: down, uid: 'alice', key: 'k', now: NOW, config: ON, verified: true,
    appVerified: true, data: {}, reverse, property: prop }), isOutage);
  await assert.rejects(discoverOwners({ db: down, uid: 'alice', key: 'k', now: NOW, config: CACHE_ONLY,
    verified: true, appVerified: true, data: {}, reverse, property: prop }), isOutage);
  await assert.rejects(enrichHousehold({ db: down, uid: 'alice', appVerified: true, key: 'k', now: NOW,
    data: { householdId: 'ovt:1', line: '1 TEST ST', city: 'Chula Vista', state: 'ca', zip: '91910' },
    config: { globalDailyCredits: 1e6 }, check }), isOutage);
  await assert.rejects(discoverNearby({ db: down, uid: 'alice', appVerified: true, key: 'k', now: NOW,
    data: { ...HOME, have: 10 }, config: { enabled: true, globalDailyCredits: 1e6 }, reverse, check }), isOutage);
  assert.equal(reverse.calls.length + prop.calls.length + check.calls.length, 0);
  state.down = false;
  assert.equal((await db.collection('discovery_jobs').get()).size, 0);
  assert.deepEqual(await usage(), {});
});

test('outage: Firestore fails after Melissa answered → error, credits stay counted, no second paid job until the lease expires', async () => {
  await setHome();
  const state = { down: false };
  const down = flaky(db, state);
  // The outage starts the moment Melissa answers (before the scan is stored).
  const reverse = counted(async () => { state.down = true; return { status: 'ok', records: ADDRESSES }; });
  await assert.rejects(discoverOwners({ db: down, uid: 'alice', key: 'k', now: NOW, config: ON, verified: true,
    appVerified: true, data: {}, reverse, property: never() }), (e) => e.code === 14);
  assert.equal(reverse.calls.length, 1);
  state.down = false;

  // Over-counted, never under-counted: the reservation could not be settled.
  assert.ok((await usage()).ownerCredits >= 200);
  const jobs = await db.collection('discovery_jobs').get();
  assert.equal(jobs.size, 1);
  assert.equal(jobs.docs[0].get('status'), 'running'); // could not be released

  // Right after recovery: the stuck lease stops a second paid job.
  const again = reverseWith(ADDRESSES);
  const r = await ask({ reverse: again, property: property(), config: { ...ON, waitMs: 100 } });
  assert.equal(r.pending, true);
  assert.equal(again.calls.length, 0);

  // After the lease expires (150 s) one new paid job may run; budgets still apply.
  const later = () => Date.now() + 200000;
  const r2 = await ask({ reverse: again, property: property(), clock: later });
  assert.equal(again.calls.length, 1);
  assert.equal(r2.records.length, 50);
});

test('outage: Firestore fails mid-lookups → stored answers kept, nothing deleted, error returned', async () => {
  await setHome();
  const state = { down: false };
  const down = flaky(db, state);
  let n = 0;
  const prop = counted(async (a, _k, opts) => {
    if (++n === 20) state.down = true; // outage after 20 answers
    return parsePropertyResponse(body(a.mak), opts);
  });
  await assert.rejects(discoverOwners({ db: down, uid: 'alice', key: 'k', now: NOW, config: ON, verified: true,
    appVerified: true, data: {}, reverse: reverseWith(ADDRESSES), property: prop }), (e) => e.code === 14);
  state.down = false;
  const before = (await db.collection('owner_properties').get()).docs.map((d) => d.id);
  const stored = before.length;
  assert.ok(stored > 0 && stored < 20, `stored ${stored}`); // answers written before the outage survive
  // Next discovery (after the lease) asks Melissa only for what is missing.
  const prop2 = property();
  await ask({ reverse: never(), property: prop2, clock: () => Date.now() + 200000 });
  const asked = new Set(prop2.calls.map((c) => c[0].requestId));
  assert.equal(prop2.calls.length, asked.size);
  for (const id of before) assert.equal(asked.has(id), false, `re-bought ${id}`);
  assert.ok((await db.collection('owner_properties').get()).size >= stored); // nothing deleted
});
