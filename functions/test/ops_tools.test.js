'use strict';
// Operator tools against the Firestore emulator (synthetic data only):
// the 365-day TTL migration (backup → apply → verify → rollback, idempotent,
// never shortens, never overwrites a changed document, never deletes), the
// kill switch / usage report, the audited location correction, and the
// production write guard.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const ttl = require('../tool/migrate_cache_ttl');
const ops = require('../tool/melissa_ops');
const locAdmin = require('../tool/location_admin');
const { guard } = require('../tool/admin_common');
const { correctPrimaryLocation, LocationError } = require('../src/location');
const { discoverOwners } = require('../src/owners');

let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['owner_properties', 'owner_scans', 'users', 'primary_locations', 'location_corrections', 'melissa_usage']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const CHECKED = new Date('2026-11-22T10:00:00Z');
const ts = (d) => Timestamp.fromDate(d);
const plus = (days) => ts(new Date(CHECKED.getTime() + days * 864e5));
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'ttl-'));

async function seedCache() {
  for (let i = 1; i <= 3; i++) {
    await db.doc(`owner_properties/mel:${i}`).set({
      id: `mel:${i}`, status: 'named', owner: { name: `OWNER ${i} TEST` }, checkedAt: ts(CHECKED), expiresAt: plus(30),
    });
  }
  await db.doc('owner_properties/mel:9').set({ id: 'mel:9', status: 'not_found', owner: null, checkedAt: ts(CHECKED), expiresAt: plus(90) });
  await db.doc('owner_scans/s1').set({ center: { latitude: 32.6, longitude: -117 }, scannedAt: ts(CHECKED), expiresAt: plus(30), candidates: [] });
}

test('TTL: plan → backup → apply → verify → re-apply (idempotent) → rollback', async () => {
  await seedCache();
  const p = await ttl.plan(db);
  assert.deepEqual(p.counts, { owner_properties: 4, owner_scans: 1, eligible: 5, extend: 5, alreadyOk: 0, ineligible: 0 });
  const b = await ttl.backup(db, { out: tmp() });
  assert.equal((fs.statSync(b.file).mode & 0o777), 0o600);
  const r = await ttl.apply(db, { file: b.file });
  assert.equal(r.updated, 5);
  const doc = (await db.doc('owner_properties/mel:1').get()).data();
  assert.equal(doc.expiresAt.toMillis(), plus(365).toMillis());
  assert.equal(doc.owner.name, 'OWNER 1 TEST'); // nothing else changed
  assert.equal(doc.ttlPolicy.previousExpiresAt, plus(30).toDate().toISOString());
  // Negative answers follow the scans (never re-bought while a scan lists them).
  assert.equal((await db.doc('owner_properties/mel:9').get()).get('expiresAt').toMillis(), plus(365).toMillis());
  assert.equal((await ttl.verify(db)).ok, true);
  const again = await ttl.apply(db, { file: b.file });
  assert.equal(again.updated, 0);
  assert.equal(again.skippedAlreadyOk, 5);
  const rb = await ttl.rollback(db, { file: b.file });
  assert.equal(rb.restored, 5);
  assert.equal((await db.doc('owner_properties/mel:9').get()).get('expiresAt').toMillis(), plus(90).toMillis());
  assert.equal((await db.doc('owner_properties/mel:1').get()).get('expiresAt').toMillis(), plus(30).toMillis());
  assert.equal((await db.doc('owner_properties/mel:1').get()).get('ttlPolicy'), undefined);
  assert.equal((await db.collection('owner_properties').get()).size, 4); // nothing deleted
});

test('TTL: never shortens a later expiry; a document changed after backup is skipped', async () => {
  await seedCache();
  await db.doc('owner_properties/mel:2').update({ expiresAt: plus(500) });
  const b = await ttl.backup(db, { out: tmp() });
  assert.equal(b.counts.alreadyOk, 1);
  await db.doc('owner_properties/mel:3').update({ owner: { name: 'CHANGED TEST' } }); // changed after backup
  const r = await ttl.apply(db, { file: b.file });
  assert.equal(r.skippedChanged, 1);
  assert.equal((await db.doc('owner_properties/mel:2').get()).get('expiresAt').toMillis(), plus(500).toMillis());
  assert.equal((await db.doc('owner_properties/mel:3').get()).get('owner.name'), 'CHANGED TEST');
});

test('TTL: migrated records are served by discoverOwners until day 365', async () => {
  const cache = require('../src/property_cache');
  const home = { latitude: 32.6401, longitude: -117.0842 };
  const recs = Array.from({ length: 3 }, (_, i) => ({ id: `mel:${100 + i}`, mak: String(100 + i), line: `${i} TEST ST`, zip: '91910',
    latitude: home.latitude + (10 * (i + 1)) / 111195, longitude: home.longitude, units: 0, suite: null }));
  await db.collection('owner_scans').doc('s').set(cache.scanDoc({ ...home, records: recs, recs: 100, miles: 1, now: CHECKED, days: 30 }));
  for (const c of recs) {
    await db.doc(`owner_properties/${c.id}`).set(cache.propertyDoc({ candidate: c, status: 'named', now: CHECKED, days: 30,
      property: { owner: { name: 'OWNER TEST' } }, classification: { kind: 'single_family' } }));
  }
  await db.doc('users/u').set(home);
  const askAt = (days) => discoverOwners({ db, uid: 'u', key: 'k', verified: true, appVerified: true, now: new Date(CHECKED.getTime() + days * 864e5),
    config: { enabled: false, allowOwnerNames: true, sharedCache: true }, data: {} });
  assert.equal((await askAt(60)).records.length, 0); // past the old 30 days
  const b = await ttl.backup(db, { out: tmp() });
  await ttl.apply(db, { file: b.file });
  assert.equal((await askAt(60)).records.length, 3);
  assert.equal((await askAt(364)).records.length, 3);
  assert.equal((await askAt(366)).records.length, 0);
});

test('TTL: the production shape (50 named + 2 not found + 1 scan = 53) is preserved, proven by fingerprints', async () => {
  for (let i = 1; i <= 50; i++) {
    await db.doc(`owner_properties/mel:${i}`).set({ id: `mel:${i}`, status: 'named', owner: { name: `OWNER ${i} TEST` },
      address: { line: `${i} TEST ST`, zip: '91910' }, point: { latitude: 32.6 + i / 1e4, longitude: -117 },
      checkedAt: ts(CHECKED), expiresAt: plus(30) });
  }
  for (const i of [51, 52]) {
    await db.doc(`owner_properties/mel:${i}`).set({ id: `mel:${i}`, status: 'not_found', owner: null, checkedAt: ts(CHECKED), expiresAt: plus(90) });
  }
  await db.doc('owner_scans/s1').set({ center: { latitude: 32.6, longitude: -117 }, scannedAt: ts(CHECKED), expiresAt: plus(30),
    candidates: [{ id: 'mel:1', line: '1 TEST ST' }] });
  const b = await ttl.backup(db, { out: tmp() });
  assert.equal(b.documents, 53);
  assert.equal(b.counts.extend, 53);
  const r = await ttl.apply(db, { file: b.file });
  assert.equal(r.updated, 53);
  const v = await ttl.verify(db, { file: b.file });
  assert.equal(v.ok, true);
  assert.deepEqual(v.preservation, { ok: true, before: 53, now: 53, missing: [], changed: [] });
  // Any later loss or content change is caught.
  await db.doc('owner_properties/mel:7').update({ 'owner.name': 'CHANGED TEST' });
  await db.doc('owner_properties/mel:52').delete();
  const bad = await ttl.verify(db, { file: b.file });
  assert.equal(bad.ok, false);
  assert.deepEqual(bad.preservation.changed, ['owner_properties/mel:7']);
  assert.deepEqual(bad.preservation.missing, ['owner_properties/mel:52']);
});

test('TTL fingerprint: ignores expiresAt / ttlPolicy and key order; sees every other change', () => {
  const base = { status: 'named', owner: { name: 'A TEST', isCompany: false }, checkedAt: ts(CHECKED), expiresAt: plus(30) };
  const f = ttl.fingerprint(base);
  assert.equal(ttl.fingerprint({ ...base, expiresAt: plus(365), ttlPolicy: { days: 365 } }), f);
  assert.equal(ttl.fingerprint({ expiresAt: plus(1), checkedAt: ts(CHECKED), owner: { isCompany: false, name: 'A TEST' }, status: 'named' }), f);
  assert.notEqual(ttl.fingerprint({ ...base, owner: { name: 'B TEST', isCompany: false } }), f);
  assert.notEqual(ttl.fingerprint({ ...base, checkedAt: new Timestamp(ts(CHECKED).seconds, 1) }), f); // nanosecond exact
  assert.notEqual(ttl.fingerprint({ ...base, extra: null }), f);
});

test('kill switch and usage report', async () => {
  const now = new Date('2026-11-24T08:00:00Z');
  await db.doc('melissa_usage/2026-11-24').set({ ownerCacheHits: 9, ownerCacheMisses: 1, ownerCredits: 700, propertiesReused: 400, deniedSecurity: 2 });
  await db.doc('melissa_usage/month-2026-11').set({ ownerCredits: 700 });
  await ops.setKill(db, true, { reason: 'incident test', operator: 'tester' });
  const r = await ops.usageReport(db, { now, days: 7 });
  assert.equal(r.killSwitch, true);
  assert.equal(r.killSwitchReason, 'incident test');
  assert.equal(r.totals.ownerCacheHits, 9);
  assert.equal(r.cacheHitRate, 0.9);
  assert.deepEqual(ops.warnings(r, { MELISSA_GLOBAL_DAILY_CREDITS: '800', MELISSA_OWNER_MONTHLY_CREDITS: '20000' }, { now }),
    ['daily credits at 700/800']);
  await assert.rejects(ops.setKill(db, false, {}), /reason/);
  await ops.setKill(db, false, { reason: 'resolved' });
  assert.equal((await ops.usageReport(db, { now })).killSwitch, false);
});

test('location correction: explicit, audited, rate-limited, US-only; history kept', async () => {
  await db.doc('users/u1').set({ latitude: 32.64, longitude: -117.08, address: 'OLD TEST ADDRESS' });
  await db.doc('users/u1/household_status/mel:1').set({ isPrayed: true });
  await db.doc('primary_locations/u1').set({ latitude: 32.64, longitude: -117.08, version: 1 });
  const input = { uid: 'u1', latitude: 32.70, longitude: -117.10, address: '1 NEW TEST ST, San Diego, CA', reason: 'moved, ticket 12', operator: 'support' };
  await assert.rejects(correctPrimaryLocation(db, { ...input, reason: '' }), (e) => e instanceof LocationError && e.reason === 'reason_required');
  await assert.rejects(correctPrimaryLocation(db, { ...input, latitude: 51.5, longitude: -0.1 }), (e) => e.reason === 'outside_us');
  const r = await correctPrimaryLocation(db, input);
  const audit = (await db.doc(`location_corrections/${r.id}`).get()).data();
  assert.equal(audit.from.address, 'OLD TEST ADDRESS');
  assert.equal(audit.to.latitude, 32.70);
  assert.equal((await db.doc('primary_locations/u1').get()).get('version'), 2);
  assert.equal((await db.doc('users/u1').get()).get('latitude'), 32.70);
  assert.equal((await db.doc('users/u1/household_status/mel:1').get()).get('isPrayed'), true);
  await correctPrimaryLocation(db, { ...input, latitude: 32.71 });
  await assert.rejects(correctPrimaryLocation(db, { ...input, latitude: 32.72 }), (e) => e.reason === 'rate_limited');
  assert.equal((await locAdmin.history(db, 'u1')).length, 2);
  const st = await locAdmin.status(db);
  assert.deepEqual(st, { users: 1, validLocation: 1, needsSetup: 0, outsideUs: 0, pinned: 1 });
});

test('tools refuse production writes without --approve, and cielo-63925 always', () => {
  const saved = process.env.FIRESTORE_EMULATOR_HOST;
  delete process.env.FIRESTORE_EMULATOR_HOST;
  try {
    assert.throws(() => guard({ project: 'gps-para-el-cielo' }, { write: true }), /--approve=gps-para-el-cielo/);
    assert.equal(guard({ project: 'gps-para-el-cielo', approve: 'gps-para-el-cielo' }, { write: true }), 'gps-para-el-cielo');
    assert.equal(guard({ project: 'gps-para-el-cielo' }, { write: false }), 'gps-para-el-cielo');
    assert.throws(() => guard({ project: 'cielo-63925', approve: 'cielo-63925' }, { write: false }), /never/);
  } finally {
    process.env.FIRESTORE_EMULATOR_HOST = saved;
  }
});
