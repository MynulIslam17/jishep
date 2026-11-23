'use strict';
// Melissa-first owner discovery: Firestore emulator + Melissa responses in
// Melissa's own JSON format, run through the real parsers. Owner names in
// the made-up responses say "TEST" so they can never be mistaken for real
// people; they exist only in this test file. Two tests use REAL saved
// Melissa responses (public buildings in Washington, DC).
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { discoverOwners, OwnerError, classify, sameAddress, validateOwners } = require('../src/owners');
const { Timestamp } = require('firebase-admin/firestore');
const { parseReverseResponse } = require('../src/discover');
const { parsePropertyResponse, buildPropertyUrl } = require('../src/melissa');
const { melissaFetch, recordingKey } = require('../src/recorder');

let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['users', 'melissa_usage', 'owner_areas', 'owner_scans', 'owner_properties', 'discovery_jobs']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const NOW = new Date('2026-11-22T12:00:00Z');
const DAY = '2026-11-22';
const POINT = { latitude: 32.6401, longitude: -117.0842 };
const ON = { enabled: true, allowOwnerNames: true, globalDailyCredits: 1e6 };

// Reverse GeoCoder records (as parseReverseResponse returns them): address
// i lies exactly 10*i m north of POINT.
const address = (i, over = {}) => ({
  id: `mel:${5000 + i}`, mak: String(5000 + i), suite: null, units: 0,
  line: `${100 + i} TEST ST`, city: 'Chula Vista', state: 'CA', zip: '91910',
  latitude: POINT.latitude + (10 * i) / 111195, longitude: POINT.longitude,
  distanceMeters: 10 * i, residential: null, ...over,
});
const reverseWith = (records) => {
  const f = async (params) => { f.calls.push(params); return { status: 'ok', records }; };
  f.calls = [];
  return f;
};

// A Melissa LookupProperty JSON body for one address.
const propertyBody = (mak, { use = '385', group = 'Residential', owner = `OWNER ${mak} TEST`,
  company = '', apn = `APN-${mak}`, results = 'YS01,YS02', addrMak = mak, zip = '91910-1234', line } = {}) => ({
  Version: 'test', TransmissionResults: '', TotalRecords: 1,
  Records: [{
    Results: results,
    Parcel: { FIPSCode: '06073', UnformattedAPN: apn },
    PropertyAddress: { Address: line || `${Number(mak) - 4900} TEST ST`, City: 'Chula Vista', State: 'CA', Zip: zip, MAK: addrMak, Latitude: '32.64', Longitude: '-117.08' },
    PrimaryOwner: owner ? { Name1Full: owner, Name2Full: '', CompanyFlag: company, TrustFlag: '' } : {},
    PropertyUseInfo: { YearBuilt: '1978', PropertyUseGroup: group, PropertyUseStandardized: use },
    PropertySize: {},
  }],
});
const propertyFrom = (bodies) => {
  const f = async (a, _key, opts) => {
    f.calls.push(a.mak);
    const b = bodies[a.mak];
    if (b && b.error) return { status: 'error', error: b.error, codes: [] };
    return parsePropertyResponse(b || propertyBody(a.mak), opts);
  };
  f.calls = [];
  return f;
};
const run = (over = {}) => discoverOwners({
  db, uid: 'alice', data: { ...POINT }, key: 'k', now: NOW, config: ON, ...over,
});
const rejectsWith = (p, reason) => assert.rejects(p, (e) => e instanceof OwnerError && e.reason === reason);
const usage = async () => (await db.doc(`melissa_usage/${DAY}`).get()).data() || {};


test('owner names off: refused; discovery off: cache only, never a Melissa call', async () => {
  const reverse = reverseWith([address(1)]);
  await rejectsWith(run({ config: { enabled: true, allowOwnerNames: false }, reverse }), 'owner_names_disabled');
  await rejectsWith(run({ uid: null, reverse }), 'sign_in_required');
  const r = await run({ config: { enabled: false, allowOwnerNames: true }, reverse });
  assert.equal(r.completeness, 'unknown');
  assert.equal(r.records.length, 0);
  assert.equal(r.missing.scanNeeded, true);
  assert.equal(r.missing.estimatedCredits, 200 + 56 * 9); // 50 named at 90% → 56 lookups
  assert.equal(reverse.calls.length, 0);
  assert.equal((await usage()).ownerCredits, undefined);
});

test('input is checked', () => {
  assert.throws(() => validateOwners({ latitude: 51.5, longitude: -0.1 }), /outside_us/);
  assert.throws(() => validateOwners({ ...POINT, target: 51 }), /bad_target/);
  assert.equal(validateOwners(POINT).target, 50);
});

test('keeps only same-address residential parcels with an owner; stores every answer once', async () => {
  const records = [
    address(1), // single family, named
    address(2), // commercial
    address(3), // no owner on record
    address(4), // Melissa returned a different address key
    address(5), // parcel not found
    address(6), // same parcel as #1
    address(7), // condo, named
    address(8), // apartment building
    address(9, { suite: 'APT 2' }), // unit: skipped before any lookup
    address(10, { units: 12 }), // multi-unit building: skipped
    address(11, { mak: null }), // no key: matched by house number + ZIP
    address(12), // lookup error (network): not charged, not stored
  ];
  const property = propertyFrom({
    5002: propertyBody('5002', { use: '170', group: 'Commercial' }),
    5003: propertyBody('5003', { owner: '' }),
    5004: propertyBody('5004', { addrMak: '9999' }),
    5005: { Version: 't', TransmissionResults: '', Records: [{ Results: 'YE03' }] },
    5006: propertyBody('5006', { apn: 'APN-5001' }),
    5007: propertyBody('5007', { use: '366', group: 'Residential' }),
    5008: propertyBody('5008', { use: '360', group: 'Multi-Unit/Multi-Family Residential' }),
    5012: { error: 'network' },
  });
  const fallback = propertyBody('5011', { addrMak: '', line: '111 TEST ST' });
  const prop = async (a, k, o) => (a.mak ? property(a, k, o) : parsePropertyResponse(fallback, o));
  const reverse = reverseWith(records);
  const r = await run({ reverse, property: prop });

  assert.deepEqual(r.records.map((x) => x.id), ['mel:5001', 'mel:5007', 'mel:5011']);
  assert.equal(r.records[0].owner.name, 'OWNER 5001 TEST');
  assert.equal(r.records[0].distanceMeters, 10);
  assert.equal(r.records[0].classification.label, 'Single Family Residential');
  assert.equal(r.records[1].classification.label, 'Condominium');
  assert.equal(r.coverage, 'partial');
  assert.equal(r.completeness, 'partial'); // #12 is still unresolved
  assert.equal(reverse.calls[0].apartments, false);
  const s = r.stats;
  assert.equal(s.addressesFound, 12);
  assert.equal(s.unitsSkipped, 2);
  assert.equal(s.lookups, 10);
  assert.equal(s.nonResidential, 1);
  assert.equal(s.noOwner, 1);
  assert.equal(s.mismatch, 1);
  assert.equal(s.notFound, 1);
  assert.equal(s.duplicateParcel, 1);
  assert.equal(s.multiFamily, 1);
  assert.equal(s.errors, 1);
  assert.equal(s.named, 3);
  // 12 addresses x 2 + 9 charged lookups x 9 (the network error is free).
  assert.equal(r.credits, 12 * 2 + 9 * 9);
  assert.equal((await usage()).ownerCredits, r.credits);
  assert.equal((await db.doc(`melissa_usage/month-2026-11`).get()).get('ownerCredits'), r.credits);
  // One scan, one document per answered address (exclusions without owner data).
  const props = await db.collection('users/alice/owner_properties').get();
  assert.equal(props.size, 9);
  const excluded = props.docs.filter((d) => d.get('status') !== 'named');
  assert.ok(excluded.every((d) => d.get('owner') === null));
  assert.equal((await db.collection('users/alice/owner_scans').get()).size, 1);
  // The retry only looks up the one unresolved address (negative cache).
  const again = await run({ reverse: reverseWith(records), property: propertyFrom({}) });
  assert.equal(again.credits, 9);
  assert.equal(again.stats.lookups, 1);
  assert.equal(again.completeness, 'complete'); // whole 1-mile radius resolved
  assert.equal(again.records.length, 4);
});

test('stops looking up once the target is reached; nearest first; provably complete', async () => {
  const records = Array.from({ length: 100 }, (_, i) => address(100 - i)); // farthest first
  const property = propertyFrom({});
  const r = await run({ data: { ...POINT, target: 10 }, reverse: reverseWith(records), property,
    config: { ...ON, concurrency: 4 } });
  assert.equal(r.records.length, 10);
  assert.equal(r.coverage, 'full');
  assert.equal(r.completeness, 'complete');
  assert.deepEqual(r.records.map((x) => x.distanceMeters), [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);
  // 3 batches of 4: no more lookups than needed to cross the target.
  assert.equal(property.calls.length, 12);
  assert.equal(r.credits, 100 * 2 + 12 * 9);
  // 100 returned = Melissa's cap: complete only up to the farthest address.
  assert.ok(r.coveredMeters >= 990 && r.coveredMeters <= 1000);
});

test('never invents: fewer named homes are returned as they are, and maxLookups caps spending', async () => {
  const records = Array.from({ length: 30 }, (_, i) => address(i + 1));
  const bodies = Object.fromEntries(records.map((a, i) => [a.mak, i % 3 === 0
    ? propertyBody(a.mak) : propertyBody(a.mak, { use: '170', group: 'Commercial' })]));
  const r = await run({ reverse: reverseWith(records), property: propertyFrom(bodies), config: { ...ON, maxLookups: 20 } });
  assert.equal(r.stats.lookups, 20);
  assert.equal(r.records.length, 7);
  assert.ok(r.records.every((x) => x.owner.name.endsWith('TEST')));
  assert.equal(r.coverage, 'partial');
  assert.equal((await usage()).ownerCredits, 30 * 2 + 20 * 9);
});

test('same user again is free; other users pay unless the shared cache is on', async () => {
  const records = [address(1), address(2)];
  const first = await run({ reverse: reverseWith(records), property: propertyFrom({}) });
  const reverse = reverseWith(records);
  const property = propertyFrom({});
  const again = await run({ reverse, property });
  assert.equal(again.cached, true);
  assert.equal(again.credits, 0);
  assert.equal(reverse.calls.length + property.calls.length, 0);
  assert.deepEqual(again.records, first.records);
  const bob = await run({ uid: 'bob', reverse: reverseWith(records), property: propertyFrom({}) });
  assert.equal(bob.cached, false); // per-user scope (licence default)

  const shared = { ...ON, sharedCache: true };
  await run({ config: shared, reverse: reverseWith(records), property: propertyFrom({}) });
  const carolReverse = reverseWith(records);
  const carol = await run({ uid: 'carol', config: shared, reverse: carolReverse, property: propertyFrom({}) });
  assert.equal(carol.cached, true);
  assert.equal(carolReverse.calls.length, 0);
  // Shared data lives in root collections, never under a user.
  assert.equal((await db.collection('owner_scans').get()).size, 1);
});

test('limits: per request, per user per day, app per day and per month', async () => {
  const far = { latitude: POINT.latitude + 0.05, longitude: POINT.longitude };
  const cfg = { ...ON, perUserDaily: 1 };
  await run({ config: cfg, reverse: reverseWith([address(1)]), property: propertyFrom({}) });
  await rejectsWith(run({ config: cfg, data: far, reverse: reverseWith([]) }), 'user_daily_limit');
  await rejectsWith(run({ uid: 'bob', config: { ...ON, dailyCredits: 100 }, reverse: reverseWith([]) }), 'app_daily_limit');
  await rejectsWith(run({ uid: 'carol', config: { ...ON, monthlyCredits: 100 }, reverse: reverseWith([]) }), 'app_monthly_limit');
  // A small per-request ceiling shrinks the lookups instead of refusing.
  const prop = propertyFrom({});
  const dan = await run({ uid: 'dan', config: { ...ON, perRequestMaxCredits: 200 + 5 * 9 },
    reverse: reverseWith(Array.from({ length: 30 }, (_, i) => address(i + 1))), property: prop });
  assert.equal(prop.calls.length, 5);
  assert.ok(dan.credits <= 245);
  await rejectsWith(run({ uid: 'eve', config: { ...ON, perRequestMaxCredits: 150 }, reverse: reverseWith([]) }), 'request_budget');
});

test('out of credits: stops, pauses, keeps the finished work, serves it from the cache', async () => {
  const records = Array.from({ length: 10 }, (_, i) => address(i + 1));
  const r = await run({ reverse: reverseWith(records), property: propertyFrom({ 5003: { error: 'out_of_credits' } }),
    config: { ...ON, concurrency: 1 } });
  assert.equal(r.stopped, 'out_of_credits');
  assert.equal(r.records.length, 2);
  assert.ok((await db.doc('melissa_usage/state').get()).get('outOfCreditsAt'));
  await rejectsWith(run({ uid: 'bob', reverse: reverseWith(records), property: propertyFrom({}) }), 'out_of_credits');
  // Alice keeps her 2 homes while paused; nothing is called.
  const property = propertyFrom({});
  const again = await run({ property });
  assert.equal(again.limited, 'out_of_credits');
  assert.equal(again.records.length, 2);
  assert.equal(property.calls.length, 0);
});

test('Reverse GeoCoder failure: nothing charged, nothing counted', async () => {
  const reverse = async () => ({ status: 'error', error: 'license_invalid', records: [] });
  await rejectsWith(run({ reverse }), 'license_invalid');
  const u = await usage();
  assert.equal(u.ownerCredits, 0);
  assert.equal(u.ownerDiscoveries, 0);
});

test('a crash part-way: the next request resumes, repeating no finished lookup', async () => {
  const records = Array.from({ length: 20 }, (_, i) => address(i + 1));
  let n = 0;
  const crashing = async (a, k, o) => {
    if (++n > 6) throw new Error('instance killed');
    return parsePropertyResponse(propertyBody(a.mak), o);
  };
  await assert.rejects(run({ reverse: reverseWith(records), property: crashing, config: { ...ON, concurrency: 1 } }));
  assert.equal((await db.collection('users/alice/owner_properties').get()).size, 6);
  const job = (await db.collection('discovery_jobs').get()).docs[0];
  assert.equal(job.get('status'), 'failed');
  const reverse = reverseWith(records);
  const property = propertyFrom({});
  const r = await run({ data: { ...POINT, target: 10 }, reverse, property });
  assert.equal(reverse.calls.length, 0); // scan kept
  assert.deepEqual(property.calls, ['5007', '5008', '5009', '5010']);
  assert.equal(r.records.length, 10);
  assert.equal(r.completeness, 'complete');
});

test('100 simultaneous users, same uncached area: ONE paid discovery', async () => {
  const records = Array.from({ length: 60 }, (_, i) => address(i + 1));
  const reverse = reverseWith(records);
  const property = propertyFrom({});
  const shared = { ...ON, sharedCache: true, perUserDaily: 100, waitMs: 10000, pollMs: 20 };
  const results = await Promise.all(Array.from({ length: 100 }, (_, i) => run({
    uid: `user${i}`, config: shared, reverse, property,
  })));
  assert.equal(reverse.calls.length, 1);
  assert.equal(new Set(property.calls).size, property.calls.length); // no address twice
  assert.ok(property.calls.length <= 52);
  assert.ok(results.every((x) => x.records.length === 50 && !x.pending));
  assert.equal(results.filter((x) => !x.cached).length, 1);
  assert.equal((await usage()).ownerCredits, 60 * 2 + property.calls.length * 9);
});

test('a lease held by a crashed instance expires; waiting requests get pending', async () => {
  const shared = { ...ON, sharedCache: true, waitMs: 60, pollMs: 20, leaseMs: 150000 };
  const { geohash } = require('../src/property_cache');
  await db.doc(`discovery_jobs/shared_${geohash(POINT.latitude, POINT.longitude, 6)}`).set({
    status: 'running', leaseOwner: 'ghost', leaseExpiresAt: Timestamp.fromMillis(Date.now() + 60000),
  });
  const reverse = reverseWith([address(1)]);
  const waiting = await run({ config: shared, reverse, property: propertyFrom({}) });
  assert.equal(waiting.pending, true);
  assert.equal(reverse.calls.length, 0);
  const later = await run({ config: shared, reverse, property: propertyFrom({}), clock: () => Date.now() + 120000 });
  assert.equal(reverse.calls.length, 1);
  assert.equal(later.records.length, 1);
});

test('expired cache: names are never served, and nothing is refreshed without permission', async () => {
  await run({ reverse: reverseWith([address(1), address(2)]), property: propertyFrom({}) });
  const later = new Date(NOW.getTime() + 31 * 864e5);
  const reverse = reverseWith([]);
  const r = await run({ now: later, config: { enabled: false, allowOwnerNames: true }, reverse });
  assert.equal(r.completeness, 'expired');
  assert.equal(r.records.length, 0);
  assert.equal(reverse.calls.length, 0);
});

test('the earlier per-area cache (owner_areas) is still served, free', async () => {
  const { areaKey } = require('../src/discover');
  await db.doc(`users/alice/owner_areas/${areaKey(POINT.latitude, POINT.longitude)}`).set({
    records: [{ id: 'mel:1', line: '1 TEST ST', owner: { name: 'OWNER TEST' } }], coverage: 'partial', stats: {},
    expiresAt: Timestamp.fromMillis(NOW.getTime() + 864e5),
  });
  const reverse = reverseWith([address(1)]);
  const r = await run({ reverse });
  assert.equal(r.completeness, 'legacy');
  assert.equal(r.records.length, 1);
  assert.equal(reverse.calls.length, 0);
});

test('classification follows Melissa property-use codes', () => {
  const c = (useCode, useGroup) => classify({ useCode, useGroup }).kind;
  assert.equal(c('385', 'Residential'), 'single_family');
  assert.equal(c('386', 'Residential'), 'condo');
  assert.equal(c('372', 'Multi-Unit/Multi-Family Residential'), 'multi_family');
  assert.equal(c('170', 'Commercial'), 'non_residential');
  assert.equal(c('', 'Residential'), 'residential');
  assert.equal(c('', ''), 'unclassified');
  assert.equal(c('', 'Commercial'), 'non_residential');
});

test('REAL responses: Capitol-area addresses and a federal building are not residential', async () => {
  const fixture = (f) => JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures', f), 'utf8'));
  const found = parseReverseResponse(fixture('reverse_geocoder_capitol.json'));
  assert.equal(found.records.length, 5);
  assert.ok(found.records.every((x) => x.mak));
  const real = parsePropertyResponse(fixture('property_1600_pennsylvania.json'), { includeOwner: true });
  assert.equal(real.status, 'found');
  assert.equal(classify(real).kind, 'non_residential'); // 136, Multi-Unit Professional
  assert.ok(real.parcelId);
  assert.ok(sameAddress({ mak: real.mak }, real));

  // The whole flow on real responses. The saved parcel is 1600 Pennsylvania
  // Ave, not one of the five Capitol addresses, so the address-key check
  // rejects all five (a wrong match is never shown).
  const r = await run({
    data: { latitude: 38.888, longitude: -77.009 },
    reverse: async () => found,
    property: async (_a, _k, o) => parsePropertyResponse(fixture('property_1600_pennsylvania.json'), o),
  });
  assert.equal(r.records.length, 0);
  assert.equal(r.stats.mismatch, 5);
  // And at its own address the federal building is excluded as non-residential.
  const own = await run({
    uid: 'bob', data: { latitude: 38.897, longitude: -77.036 },
    reverse: async () => parseReverseResponse(fixture('reverse_geocoder_white_house.json')),
    property: async (_a, _k, o) => parsePropertyResponse(fixture('property_1600_pennsylvania.json'), o),
  });
  assert.equal(own.records.length, 0);
  assert.equal(own.stats.nonResidential, 1);
});

test('Property is looked up by Melissa Address Key when there is one', () => {
  const u = new URL(buildPropertyUrl({ mak: '123', line: '1 A ST', zip: '1' }, 'KEY', { includeOwner: true }));
  assert.equal(u.searchParams.get('mak'), '123');
  assert.equal(u.searchParams.get('a1'), null);
  assert.match(u.searchParams.get('cols'), /GrpPrimaryOwner/);
  assert.match(u.searchParams.get('cols'), /GrpParcel/);
});

test('recorder: saves real responses without the key and replays them for free', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'melissa-rec-'));
  let real = 0;
  const realFetch = async () => { real++; return { status: 200, ok: true, json: async () => ({ hello: 1 }) }; };
  const f = melissaFetch({ dir, realFetch });
  const url = 'https://property.melissadata.net/v4/WEB/LookupProperty?id=SECRET&mak=1&format=json';
  assert.deepEqual(await (await f(url)).json(), { hello: 1 });
  assert.deepEqual(await (await f(url.replace('SECRET', 'OTHER'))).json(), { hello: 1 });
  assert.equal(real, 1);
  const saved = fs.readFileSync(path.join(dir, fs.readdirSync(dir)[0]), 'utf8');
  assert.ok(!saved.includes('SECRET'));
  assert.ok(!recordingKey(url).includes('SECRET'));
  const replayOnly = melissaFetch({ dir, replayOnly: true, realFetch });
  assert.equal((await replayOnly(url.replace('mak=1', 'mak=2'))).status, 503);
  assert.equal(real, 1);
});
