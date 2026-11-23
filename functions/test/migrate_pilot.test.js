'use strict';
// The pilot migration tool (tool/migrate_pilot.js) against the Firestore
// emulator, with a synthetic snapshot (no real owner data): create-only,
// idempotent, never overwrites, verifies field by field, rolls back only its
// own documents, refuses a real project without approval BEFORE
// connecting.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const m = require('../tool/migrate_pilot');

const PROJECT = 'demo-gps-cielo-functions';
let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: PROJECT });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['owner_scans', 'owner_properties', 'users', 'melissa_usage']) await db.recursiveDelete(db.collection(c));
});

const NOW = new Date('2026-11-23T00:00:00Z');
const later = (days) => ({ __ts: new Date(NOW.getTime() + days * 864e5).toISOString() });

function property(i, { expired = false } = {}) {
  return {
    version: 1, id: `mel:${1000 + i}`, mak: String(1000 + i), status: 'named',
    line: `${100 + i} TEST ST`, city: 'CHULA VISTA', state: 'CA', zip: '91910',
    latitude: 32.64 + i / 1e4, longitude: -117.02 - i / 1e4, geohash: '9mudq',
    parcelId: `P-${i}`, owner: { name: `OWNER TEST ${i}`, secondName: i === 1 ? 'SECOND TEST' : null, isCompany: false, isTrust: false },
    classification: { kind: 'residential', label: 'Single Family Residential', code: '1001', group: 'R' },
    yearBuilt: 1990, source: 'melissa', checkedAt: later(-1), expiresAt: expired ? later(-1) : later(29),
  };
}

function snapshotDir(docs) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'migrate-'));
  const text = JSON.stringify({ createdAt: NOW.toISOString(), sourceUid: 'u', docs });
  fs.writeFileSync(path.join(dir, 'snapshot.json'), text);
  fs.writeFileSync(path.join(dir, 'snapshot.sha256'), `${crypto.createHash('sha256').update(text).digest('hex')}\n`);
  return dir;
}

const docs = () => ({
  'owner_scans/32.6400_-117.0200_r100_noapt': {
    version: 1, latitude: 32.64, longitude: -117.02, coveredMeters: 310.5,
    records: [{ id: 'mel:1001', d: 12 }], checkedAt: later(-1), expiresAt: later(29),
  },
  ...Object.fromEntries([1, 2, 3].map((i) => [`owner_properties/mel:${1000 + i}`, property(i)])),
  'owner_properties/mel:1009': property(9, { expired: true }),
});
const run = { project: PROJECT, approve: PROJECT };
const deps = { now: NOW };

test('plan is read-only; apply creates; a second apply creates nothing', async () => {
  const dir = snapshotDir(docs());
  const plan = await m.planStep({ ...run, in: dir }, deps);
  assert.equal(plan.create, 4);
  assert.equal(plan.expired, 1);
  assert.equal((await db.collection('owner_properties').get()).size, 0);

  const first = await m.applyStep({ ...run, in: dir }, deps);
  assert.equal(first.created, 4);
  assert.equal(first.expiredNotWritten, 1);
  const again = await m.applyStep({ ...run, in: dir }, deps);
  assert.equal(again.created, 0);
  assert.equal(again.skipped, 4);
  assert.equal(again.manifest, null);
  assert.equal((await db.collection('owner_properties').get()).size, 3);
  assert.equal((await db.doc('owner_properties/mel:1009').get()).exists, false); // expired: never written
});

test('every field is copied unchanged (names, second owner, MAK, coordinates, class, dates)', async () => {
  const dir = snapshotDir(docs());
  await m.applyStep({ ...run, in: dir }, deps);
  const v = await m.verifyStep({ ...run, in: dir }, deps);
  assert.equal(v.identical, 4);
  assert.deepEqual(v.different, []);
  const d = (await db.doc('owner_properties/mel:1001').get()).data();
  assert.equal(d.owner.name, 'OWNER TEST 1');
  assert.equal(d.owner.secondName, 'SECOND TEST');
  assert.equal(d.mak, '1001');
  assert.equal(d.latitude, property(1).latitude);
  assert.equal(d.classification.label, 'Single Family Residential');
  assert.equal(d.expiresAt.toDate().toISOString(), later(29).__ts); // expiry not extended
  assert.equal(d.migration.from, 'local-emulator-pilot');
  assert.ok(d.migration.at.toDate() instanceof Date);
});

test('an existing document is never overwritten; unrelated data untouched', async () => {
  await db.doc('owner_properties/mel:1002').set({ status: 'named', owner: { name: 'ALREADY THERE' } });
  await db.doc('owner_properties/mel:7777').set({ status: 'named', owner: { name: 'UNRELATED' } });
  await db.doc('users/alice/household_status/mel:1001').set({ isPrayed: true });
  const dir = snapshotDir(docs());
  const plan = await m.planStep({ ...run, in: dir }, deps);
  assert.deepEqual(plan.conflicts, ['owner_properties/mel:1002']);
  const r = await m.applyStep({ ...run, in: dir }, deps);
  assert.equal(r.created, 3);
  assert.equal(r.skipped, 1);
  assert.equal((await db.doc('owner_properties/mel:1002').get()).get('owner.name'), 'ALREADY THERE');
  assert.equal((await db.doc('owner_properties/mel:7777').get()).get('owner.name'), 'UNRELATED');
  assert.equal((await db.doc('users/alice/household_status/mel:1001').get()).get('isPrayed'), true);

  const rb = await m.rollbackStep({ ...run, in: dir }, deps);
  assert.equal(rb.deleted, 3);
  assert.equal((await db.doc('owner_properties/mel:1002').get()).exists, true);
  assert.equal((await db.doc('owner_properties/mel:7777').get()).exists, true);
  assert.equal((await db.doc('users/alice/household_status/mel:1001').get()).exists, true);
  assert.equal((await db.collection('owner_scans').get()).size, 0);
});

test('rollback keeps a migrated document someone changed afterwards', async () => {
  const dir = snapshotDir(docs());
  await m.applyStep({ ...run, in: dir }, deps);
  await db.doc('owner_properties/mel:1003').update({ 'migration.id': 'someone-else' });
  const rb = await m.rollbackStep({ ...run, in: dir }, deps);
  assert.equal(rb.deleted, 3);
  assert.equal(rb.notOurs, 1);
  assert.equal((await db.doc('owner_properties/mel:1003').get()).exists, true);
});

test('a real project: refused without approval, before connecting', async () => {
  const dir = snapshotDir(docs());
  const saved = process.env.FIRESTORE_EMULATOR_HOST;
  let calls = 0;
  const spy = { ...deps, token: 'unused', fetchImpl: async () => { calls++; throw new Error('must not connect'); } };
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST; // a real project from here on
    await assert.rejects(m.applyStep({ project: 'gps-para-el-cielo', in: dir }, spy), /--approve=gps-para-el-cielo/);
    await assert.rejects(m.applyStep({ project: 'gps-para-el-cielo', approve: 'gps-para-el', in: dir }, spy), /--approve/);
    await assert.rejects(m.rollbackStep({ project: 'gps-para-el-cielo', in: dir }, spy), /--approve/);
    await assert.rejects(m.planStep({ project: 'cielo-63925', in: dir }, spy), /refused/);
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = saved;
  }
  assert.equal(calls, 0);
});

test('a tampered or unexpected snapshot is refused', async () => {
  const dir = snapshotDir(docs());
  fs.appendFileSync(path.join(dir, 'snapshot.json'), ' ');
  await assert.rejects(m.planStep({ ...run, in: dir }, deps), /checksum/);
  const bad = snapshotDir({ 'users/alice/household_status/x': { a: 1 } });
  await assert.rejects(m.planStep({ ...run, in: bad }, deps), /unexpected path/);
});

test('REST value encoding round-trips the snapshot shape', () => {
  const v = property(1);
  assert.ok(m.same(m.fromRest(m.toRest(v)), v));
  assert.ok(m.same(m.fromRest(m.toRest({ g: { __geo: [32.6, -117] } })), { g: { __geo: [32.6, -117] } }));
});

test('after migration, production settings serve the same records to every user with zero Melissa calls', async () => {
  // A realistic snapshot built with the cache's own document builders.
  const cache = require('../src/property_cache');
  const { Timestamp } = require('firebase-admin/firestore');
  const { discoverOwners } = require('../src/owners');
  const enc = (v) => (v instanceof Timestamp ? { __ts: v.toDate().toISOString() }
    : Array.isArray(v) ? v.map(enc)
      : v && typeof v === 'object' ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, enc(x)])) : v);
  const lat = 32.6435; const lon = -117.0185; const made = new Date(NOW.getTime() - 864e5);
  const cands = Array.from({ length: 8 }, (_, i) => ({
    id: `mel:${2000 + i}`, mak: String(2000 + i), line: `${10 + i} TEST AVE`, city: 'CHULA VISTA', state: 'CA', zip: '91910',
    latitude: lat + (i + 1) * 1e-4, longitude: lon,
  }));
  const snapDocs = {
    [`owner_scans/${cache.scanIdFor(lat, lon, cache.SCAN_OPTIONS)}`]: enc(cache.scanDoc({
      latitude: lat, longitude: lon, records: cands, recs: 100, miles: 1, now: made, days: 30,
    })),
  };
  for (const c of cands) {
    snapDocs[`owner_properties/${c.id}`] = enc(cache.propertyDoc({
      candidate: c, status: 'named', now: made, days: 30,
      property: { owner: { name: `OWNER ${c.mak}`, secondName: null }, parcelId: null },
      classification: { kind: 'residential', label: 'Single Family Residential' },
    }));
  }
  const dir = snapshotDir(snapDocs);
  assert.equal((await m.applyStep({ ...run, in: dir }, deps)).created, 9);

  // Production as it will be configured once the licence allows sharing:
  // discovery OFF, app budget 0, names ON, shared cache ON.
  const config = { enabled: false, allowOwnerNames: true, sharedCache: true, globalDailyCredits: 0, cacheDays: 30 };
  const never = async () => { throw new Error('Melissa must not be called'); };
  const ask = (uid) => discoverOwners({ db, uid, key: 'k', now: NOW, config, reverse: never, property: never,
    data: { latitude: lat, longitude: lon, target: 5 } });
  const a = await ask('alice');
  const b = await ask('bob');
  assert.equal(a.records.length, 5);
  assert.deepEqual(b.records.map((r) => r.id), a.records.map((r) => r.id));
  assert.equal(a.records[0].owner.name, 'OWNER 2000');
  assert.equal(a.credits || 0, 0);
  // One canonical copy; nothing copied into either user's documents.
  assert.equal((await db.collection('owner_properties').get()).size, 8);
  assert.equal((await db.collection('users/alice/owner_properties').get()).size, 0);
  assert.equal((await db.collection('users/bob/owner_properties').get()).size, 0);
  // Only cache-hit counters: no Melissa request, no credit.
  const day = (await db.doc(`melissa_usage/${NOW.toISOString().slice(0, 10)}`).get()).data() || {};
  assert.equal(day.ownerCacheHits, 2);
  for (const k of ['melissaRequests', 'ownerCredits', 'estimatedCredits', 'credits']) assert.equal(day[k] || 0, 0, k);
});
