'use strict';
// The paid Rancho del Rey pilot, rebuilt from the SAVED Melissa recordings
// (functions/.melissa-recordings, git-ignored, real data), plus location
// scenarios. Zero network: the recorder replays only, the fetch under it
// throws, and test/no_network.js blocks every non-local host.
//
// The recordings exist only on the developer's machine; without them the
// real-data tests are skipped (the synthetic ones always run).
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { discoverOwnersAtHome: discoverOwners } = require('./support');
const geo = require('../src/property_cache');
const pilot = require('../tool/pilot_scenarios');

const NOW = new Date('2026-11-22T12:00:00Z');
const haveRecordings = fs.existsSync(pilot.RECORDINGS) && fs.readdirSync(pilot.RECORDINGS).length >= 53;
const real = haveRecordings ? test : test.skip;

let db;
before(() => {
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['primary_locations', 'users', 'melissa_usage', 'owner_scans', 'owner_properties', 'discovery_jobs']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const cacheOnly = (uid, latitude, longitude, over = {}) => discoverOwners({
  db, uid, data: { latitude, longitude, target: 50 }, key: 'none', now: NOW,
  config: { enabled: false, allowOwnerNames: true, sharedCache: true, ...over },
  reverse: async () => { throw new Error('Melissa must not be called'); },
  property: async () => { throw new Error('Melissa must not be called'); },
});

real('the 50 paid homes are rebuilt from the recordings alone (0 network, 0 unrecorded)', async () => {
  const { result, events } = await pilot.rebuildPilot(db, { now: NOW });
  assert.deepEqual(events, { replay: 53, not_recorded: 0, network: 0 });
  const d = pilot.describe(result.records);
  assert.equal(d.records, 50);
  assert.equal(d.withOwner, 50);
  assert.equal(d.withAddress, 50);
  assert.equal(d.stableIds, 50);
  assert.equal(d.withSecondOwner, 26);
  assert.deepEqual(d.classes, ['Single Family Residential']);
  assert.equal(result.stats.addressesFound, 100);
  assert.equal(result.stats.lookups, 52);
  assert.equal(result.stats.notFound, 2);
  assert.equal(result.completeness, 'complete');
  // The same Melissa answers as the original run: 100 x 2 + 52 x 9.
  assert.equal(result.credits, 668);
  assert.equal(globalThis.__blockedFetches.length, 0);
  // Stored once: 1 scan, 52 property answers (50 named + 2 not found).
  assert.equal((await db.collection('owner_scans').get()).size, 1);
  const props = await db.collection('owner_properties').get();
  assert.equal(props.size, 52);
  assert.equal(props.docs.filter((p) => p.get('status') === 'named').length, 50);
});

real('scenarios A–F around the pilot: reuse, honest completeness, zero Melissa calls', async () => {
  await pilot.rebuildPilot(db, { now: NOW });
  const rows = Object.fromEntries((await pilot.runScenarios(db, { now: NOW })).map((r) => [r.scenario[0], r]));
  for (const r of Object.values(rows)) {
    assert.equal(r.melissaCallsNow, 0);
    assert.equal(r.creditsUsedNow, 0);
  }
  // A: same point, another user: the full, provable 50, free.
  assert.equal(rows.A.namedReturned, 50);
  assert.equal(rows.A.provablyNearest50, true);
  assert.equal(rows.A.fillEstimatedCredits, 0);
  // B–D: 50 stored names reused; not PROVABLY the nearest 50 any more.
  for (const k of ['B', 'C', 'D']) {
    assert.equal(rows[k].namedReturned, 50, k);
    assert.equal(rows[k].completeness, 'partial', k);
    assert.equal(rows[k].fillEstimatedCredits, 0, k);
    assert.ok(rows[k].proveEstimatedCredits > 0, k);
  }
  assert.ok(rows.B.coveredMeters > rows.C.coveredMeters);
  // E, F: nothing stored there: a cache miss, never a call.
  for (const k of ['E', 'F']) {
    assert.equal(rows[k].namedReturned, 0, k);
    assert.equal(rows[k].completeness, 'unknown', k);
    assert.equal(rows[k].fillReverseGeoCoder, 1, k);
  }
});

real('restart / repeat visit by the same user: identical result, 0 credits, no calls', async () => {
  await pilot.rebuildPilot(db, { uid: 'alice', shared: false, now: NOW });
  const a = await cacheOnly('alice', pilot.PILOT.latitude, pilot.PILOT.longitude, { sharedCache: false });
  const b = await cacheOnly('alice', pilot.PILOT.latitude, pilot.PILOT.longitude, { sharedCache: false });
  assert.equal(a.records.length, 50);
  assert.deepEqual(a.records, b.records);
  assert.equal(b.completeness, 'complete');
  // Without the licensed shared cache another user gets nothing from Alice.
  const bob = await cacheOnly('bob', pilot.PILOT.latitude, pilot.PILOT.longitude, { sharedCache: false });
  assert.equal(bob.records.length, 0);
});

// ---- Synthetic fixtures (always run) -----------------------------------

const P = { latitude: 32.6435, longitude: -117.0185 };
const ON = { enabled: true, allowOwnerNames: true, sharedCache: true, perUserDaily: 50, globalDailyCredits: 1e6 };
/** n addresses on a ring grid around (lat, lon), ids from `base`. */
function grid(lat, lon, n, base, spacing = 30) {
  const out = [];
  for (let i = 0; out.length < n; i++) {
    const ring = Math.floor(Math.sqrt(i));
    const [a, o] = geo.offset(lat, lon, spacing * (ring + 1), i * 2.399963);
    out.push({
      id: `mel:${base + out.length}`, mak: String(base + out.length), suite: null, units: 0,
      line: `${base + out.length} TEST ST`, city: 'Chula Vista', state: 'CA', zip: '91910',
      latitude: a, longitude: o, distanceMeters: null,
    });
  }
  return out;
}
const namedProperty = (calls) => async (a) => {
  calls.push(a.mak);
  return {
    status: 'found', mak: a.mak, parcelId: `06073:${a.mak}`, useCode: '385', useGroup: 'Residential',
    address: { line: a.line, zip: a.zip }, owner: { name: `OWNER ${a.mak} TEST`, secondName: null },
  };
};

test('G: geohash boundary: a scan just across a cell edge is found and reused', async () => {
  // Precision-5 cells are 0.0439453125° tall; this latitude is an edge.
  const edge = Math.ceil(P.latitude / 0.0439453125) * 0.0439453125;
  const south = { latitude: edge - 0.0003, longitude: P.longitude };
  const north = { latitude: edge + 0.0003, longitude: P.longitude };
  assert.notEqual(geo.geohash(south.latitude, south.longitude, 5), geo.geohash(north.latitude, north.longitude, 5));
  const calls = [];
  const homes = grid(south.latitude, south.longitude, 100, 7000, 15);
  await discoverOwners({ db, uid: 'a', data: south, key: 'k', now: NOW, config: ON,
    reverse: async () => ({ status: 'ok', records: homes }), property: namedProperty(calls) });
  const before = calls.length;
  const r = await cacheOnly('b', north.latitude, north.longitude);
  assert.equal(r.stats.scans, 1);
  assert.equal(r.records.length, 50);
  assert.equal(calls.length, before);
});

test('I: overlapping areas: shared addresses counted once, no property ever paid twice', async () => {
  const calls = [];
  const reverses = [];
  const [bLat, bLon] = geo.offset(P.latitude, P.longitude, 260, Math.PI / 2);
  const areaA = grid(P.latitude, P.longitude, 100, 8000, 30); // capped scan
  // B's scan: the 30 of A's addresses nearest to B, plus 70 new ones.
  const dB = (x) => geo.haversineMeters(bLat, bLon, x.latitude, x.longitude);
  const nearB = [...areaA].sort((x, y) => dB(x) - dB(y)).slice(0, 30);
  const areaB = [...nearB, ...grid(bLat, bLon, 70, 9000, 25)];
  const reverse = async (p) => {
    reverses.push(p);
    return { status: 'ok', records: reverses.length === 1 ? areaA : areaB };
  };
  await discoverOwners({ db, uid: 'a', data: P, key: 'k', now: NOW, config: ON, reverse, property: namedProperty(calls) });
  assert.equal(calls.length, 52); // 13 batches of 4, then 50 named
  // B, 260 m away, default (fill only): 50 stored names reused, nothing paid.
  const fill = await discoverOwners({ db, uid: 'b', data: { latitude: bLat, longitude: bLon }, key: 'k', now: NOW,
    config: ON, reverse, property: namedProperty(calls) });
  assert.equal(fill.records.length, 50);
  assert.equal(fill.cached, true);
  assert.equal(reverses.length, 1);
  assert.equal(fill.completeness, 'partial');
  // B again, paying to PROVE the nearest 50: one scan at B, and only
  // addresses never looked up before are paid for.
  const prove = await discoverOwners({ db, uid: 'c', data: { latitude: bLat, longitude: bLon }, key: 'k', now: NOW,
    config: { ...ON, completeCoverage: true }, reverse, property: namedProperty(calls) });
  assert.equal(reverses.length, 2);
  assert.equal(new Set(calls).size, calls.length);
  assert.ok(prove.stats.duplicateAddresses >= 30, String(prove.stats.duplicateAddresses));
  assert.equal(prove.records.length, 50);
  assert.ok(calls.slice(52).every((m) => Number(m) >= 9000 || !areaA.slice(0, 52).some((x) => x.mak === m)));
});

test('M: unmatched addresses are remembered (negative cache) and not retried', async () => {
  const homes = grid(P.latitude, P.longitude, 10, 6000);
  const calls = [];
  const property = async (a) => { calls.push(a.mak); return { status: 'not_found' }; };
  await discoverOwners({ db, uid: 'a', data: P, key: 'k', now: NOW, config: ON,
    reverse: async () => ({ status: 'ok', records: homes }), property });
  assert.equal(calls.length, 10);
  const again = await discoverOwners({ db, uid: 'b', data: P, key: 'k', now: NOW, config: ON,
    reverse: async () => { throw new Error('no'); }, property });
  assert.equal(calls.length, 10);
  assert.equal(again.completeness, 'empty'); // the whole radius is known: no homes
});
