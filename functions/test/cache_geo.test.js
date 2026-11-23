'use strict';
// Geospatial helpers, the spending guard and account clean-up.
const { test, before } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const geo = require('../src/property_cache');
const guard = require('../src/guard');
const { cleanupUser } = require('../src/cleanup');

test('haversine and offset agree (Chula Vista)', () => {
  const [lat, lon] = geo.offset(32.6435, -117.0185, 400, Math.PI / 3);
  assert.ok(Math.abs(geo.haversineMeters(32.6435, -117.0185, lat, lon) - 400) < 1.5);
});

test('geohash matches the reference encoder', () => {
  assert.equal(geo.geohash(57.64911, 10.40744, 11), 'u4pruydqqvj');
  assert.equal(geo.geohash(42.6, -5.6, 5), 'ezs42');
});

test('cell boundary: the cells around a point include the neighbour across the edge', () => {
  // A point 20 m south of a precision-5 cell edge.
  const lat = 32.6074 - 0.0002; // cells are 0.0439° tall; 32.607421875 is an edge
  const here = geo.geohash(lat, -117.0185, 5);
  const across = geo.geohash(lat + 0.0004, -117.0185, 5);
  assert.notEqual(here, across);
  const cells = geo.cellsAround(lat, -117.0185, 3300);
  assert.ok(cells.includes(here) && cells.includes(across));
  assert.ok(cells.length <= 30);
});

test('covered radius: one disc exactly; two overlapping discs via sampling; gaps are not covered', () => {
  const c = { latitude: 32.6435, longitude: -117.0185, radius: 500 };
  assert.equal(Math.round(geo.coveredRadius(32.6435, -117.0185, [c], 1609)), 500);
  const [la, lo] = geo.offset(32.6435, -117.0185, 200, 0);
  assert.equal(Math.round(geo.coveredRadius(la, lo, [c], 1609)), 300);
  // Second disc 400 m north: the union reaches further north than either.
  const [la2, lo2] = geo.offset(32.6435, -117.0185, 400, 0);
  const both = [c, { latitude: la2, longitude: lo2, radius: 500 }];
  const r = geo.coveredRadius(la, lo, both, 1609);
  assert.ok(r >= 300 && r <= 460, String(r));
  // Outside every disc: nothing is covered.
  const [fa, fo] = geo.offset(32.6435, -117.0185, 5000, 0);
  assert.equal(geo.coveredRadius(fa, fo, both, 1609), 0);
});

test('guard: in the emulator an unrecorded Melissa request never reaches the network', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-'));
  const before = { ...process.env };
  process.env.FUNCTIONS_EMULATOR = 'true';
  delete process.env.MELISSA_EMULATOR_LIVE;
  let real = 0;
  try {
    const f = guard.melissaFetchFor({ dir, realFetch: async () => { real++; return { status: 200 }; } });
    const res = await f('https://property.melissadata.net/v4/WEB/LookupProperty?id=K&mak=1');
    assert.equal(res.status, 503);
    assert.equal(real, 0);
    // Even MELISSA_REPLAY_ONLY=false does not open the network.
    process.env.MELISSA_REPLAY_ONLY = 'false';
    const g = guard.melissaFetchFor({ dir, realFetch: async () => { real++; return { status: 200 }; } });
    assert.equal((await g('https://reversegeo.melissadata.net/x?id=K')).status, 503);
    assert.equal(real, 0);
  } finally {
    process.env = before;
  }
  assert.ok(guard.isMelissaUrl('https://property.melissadata.net/v4'));
  assert.ok(!guard.isMelissaUrl('https://example.com/melissadata.net'));
});

test('tests themselves cannot reach the internet', async () => {
  await assert.rejects(fetch('https://property.melissadata.net/v4/WEB/LookupProperty?id=SECRET'), /Network blocked/);
  assert.ok(globalThis.__blockedFetches.every((u) => !u.includes('SECRET')));
});

let db;
before(() => {
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});

test('account deletion removes all per-user data, counters and locks; shared data stays', async () => {
  await db.recursiveDelete(db.collection('users'));
  await db.recursiveDelete(db.collection('melissa_usage'));
  await db.recursiveDelete(db.collection('discovery_jobs'));
  const u = db.doc('users/zed');
  await u.set({ fullName: 'Z' });
  for (const c of ['household_status', 'prayer_log', 'prayer_rounds', 'enrichment', 'gap_areas',
    'owner_areas', 'owner_scans', 'owner_properties']) {
    await u.collection(c).doc('x').set({ a: 1 });
  }
  await db.doc('melissa_usage/2026-11-22/users/zed').set({ ownerDiscoveries: 1 });
  await db.doc('melissa_usage/2026-11-22/users/amy').set({ ownerDiscoveries: 1 });
  await db.doc('discovery_jobs/u_zed_9mudz1').set({ status: 'done' });
  await db.doc('discovery_jobs/shared_9mudz1').set({ status: 'done' });
  await db.doc('owner_properties/mel:1').set({ status: 'named' });

  await cleanupUser(db, 'zed');
  assert.equal((await u.get()).exists, false);
  assert.equal((await u.listCollections()).length, 0);
  assert.equal((await db.doc('melissa_usage/2026-11-22/users/zed').get()).exists, false);
  assert.equal((await db.doc('melissa_usage/2026-11-22/users/amy').get()).exists, true);
  assert.equal((await db.doc('discovery_jobs/u_zed_9mudz1').get()).exists, false);
  assert.equal((await db.doc('discovery_jobs/shared_9mudz1').get()).exists, true);
  assert.equal((await db.doc('owner_properties/mel:1').get()).exists, true);
  await db.recursiveDelete(db.collection('owner_properties'));
});
