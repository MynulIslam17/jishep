'use strict';
// Pending owner-discovery queue (src/queue.js) against the Firestore
// emulator, with fake Melissa functions that count calls (owner names say
// "TEST": synthetic, never real people).
//
//   Exhausted budget  new users still get an answer (stored data, possibly
//                     none) and their area is queued once; nothing is spent.
//   Security          only verified, App Check requests are queued; the
//                     processor re-checks cache, account, App Check, home
//                     and every credit limit before each job.
//   Abuse             one job per area; caps on new jobs per day, open jobs
//                     and requesters per job; the queue never spends past the
//                     daily budget.
//   Data              prayer data untouched; answers stored with the 365-day
//                     policy; deleted accounts leave the queue.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { discoverOwners } = require('../src/owners');
const { processQueue, enqueueDiscovery, userVerified } = require('../src/queue');
const { cleanupUser } = require('../src/cleanup');
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
    'owner_properties', 'discovery_jobs', 'discovery_queue']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const DAY_MS = 864e5;
const NOW = new Date('2026-11-24T12:00:00Z');
const DAY = '2026-11-24';
const later = (ms) => new Date(NOW.getTime() + ms);
// Areas about 5.5 km apart: different geohash-6 cells, different jobs.
const homeOf = (area) => ({ latitude: 32.6401 + 0.05 * area, longitude: -117.0842 });
// Budget used up: the app-wide daily limit allows nothing more.
const EXHAUSTED = { enabled: true, allowOwnerNames: true, sharedCache: true, globalDailyCredits: 1e6, dailyCredits: 0, pollMs: 25 };
const OPEN = { ...EXHAUSTED, dailyCredits: 2000 };

const around = (p) => {
  const base = Math.round((p.latitude - 32) * 1e4) * 100;
  return Array.from({ length: 60 }, (_, i) => ({
    id: `mel:${base + i + 1}`, mak: String(base + i + 1), suite: null, units: 0,
    line: `${100 + i} TEST ST`, city: 'Chula Vista', state: 'CA', zip: '91910',
    latitude: p.latitude + (10 * (i + 1)) / 111195, longitude: p.longitude,
  }));
};
const counted = (fn) => { const f = async (...a) => { f.calls.push(a); return fn(...a); }; f.calls = []; return f; };
const never = () => counted(async () => { throw new Error('Melissa must not be called'); });
const reverse = () => counted(async (p) => ({ status: 'ok', records: around(p) }));
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
const property = () => counted(async (a, _k, opts) => parsePropertyResponse(body(a.mak), opts));

const setHome = (uid, area = 0) => db.doc(`users/${uid}`).set({ ...homeOf(area), displayName: uid }, { merge: true });
const ask = (uid, over = {}) => discoverOwners({
  db, uid, key: 'k', now: NOW, config: EXHAUSTED, verified: true, appVerified: true, data: {},
  reverse: never(), property: never(), ...over,
});
const jobs = async () => (await db.collection('discovery_queue').get()).docs;
const usage = async () => (await db.doc(`melissa_usage/${DAY}`).get()).data() || {};
const verifiedUser = (uid) => ({ uid, emailVerified: true, providerData: [] });
const runQueue = (over = {}) => processQueue({
  db, now: NOW, key: 'k', config: OPEN, getUser: async (uid) => verifiedUser(uid),
  reverse: never(), property: never(), ...over,
});

// ------------------------------------------------- exhausted budget, users
test('exhausted budget: a new user gets an answer (nothing stored), the area is queued, nothing is spent', async () => {
  await setHome('alice');
  const r = await ask('alice');
  assert.equal(r.records.length, 0);
  assert.equal(r.limited, 'app_daily_limit');
  assert.equal(r.queued, true);
  const [job] = await jobs();
  assert.equal(job.get('status'), 'queued');
  assert.deepEqual(Object.keys(job.get('requesters')), ['alice']);
  assert.equal(job.get('requesters').alice.appCheck, true);
  assert.equal(job.id, cache.jobIdFor('shared', homeOf(0).latitude, homeOf(0).longitude));
  const u = await usage();
  assert.equal(u.ownerCredits, undefined);
  assert.equal(u.queuedJobs, 1);
  assert.equal(u.queuedRequests, 1);
  // The job holds no coordinates, names or addresses: only uids and the area key.
  assert.equal(job.get('latitude'), undefined);
});

test('exhausted budget: users with a cached neighborhood are served and nothing is queued', async () => {
  await setHome('alice');
  const scan = reverse();
  await ask('alice', { config: OPEN, reverse: scan, property: property() }); // fills the cache
  const r = await ask('alice', { reverse: never(), property: never() }); // budget now 0
  assert.equal(r.records.length, 50);
  assert.equal(r.queued, undefined);
  assert.equal((await jobs()).length, 0);
});

test('monthly limit, out-of-credits pause and kill switch also queue; per-user limit does not', async () => {
  await setHome('m');
  assert.equal((await ask('m', { config: { ...OPEN, monthlyCredits: 0 } })).queued, true);
  await db.doc('melissa_usage/state').set({ paidDisabled: true });
  await setHome('k', 1);
  const k = await ask('k', { config: OPEN });
  assert.equal(k.limited, 'paid_disabled');
  assert.equal(k.queued, true);
  await db.doc('melissa_usage/state').set({ paidDisabled: false, outOfCreditsAt: NOW });
  await setHome('o', 2);
  assert.equal((await ask('o', { config: OPEN })).queued, true);
  await db.doc('melissa_usage/state').delete();
  await setHome('u', 3);
  const u = await ask('u', { config: { ...OPEN, perUserDaily: 0 } });
  assert.equal(u.limited, 'user_daily_limit');
  assert.equal(u.queued, undefined);
  assert.equal((await jobs()).length, 3);
});

test('security refusals are never queued: unverified account, no App Check token', async () => {
  await setHome('alice');
  assert.equal((await ask('alice', { verified: false })).limited, 'unverified');
  assert.equal((await ask('alice', { appVerified: false })).limited, 'app_check');
  assert.equal((await jobs()).length, 0);
});

test('paid discovery off (production today): cache only, nothing queued', async () => {
  await setHome('alice');
  const r = await ask('alice', { config: { ...EXHAUSTED, enabled: false } });
  assert.equal(r.queued, undefined);
  assert.equal((await jobs()).length, 0);
});

// ---------------------------------------------------------- deduplication
test('dedup: many users and repeated requests in one area make ONE job', async () => {
  for (const uid of ['a', 'b', 'c']) await setHome(uid);
  for (let i = 0; i < 3; i++) for (const uid of ['a', 'b', 'c']) await ask(uid);
  const all = await jobs();
  assert.equal(all.length, 1);
  assert.deepEqual(Object.keys(all[0].get('requesters')).sort(), ['a', 'b', 'c']);
  assert.equal((await usage()).queuedJobs, 1);
});

test('dedup: concurrent requests from one area still make one job', async () => {
  const uids = Array.from({ length: 8 }, (_, i) => `p${i}`);
  for (const uid of uids) await setHome(uid);
  await Promise.all(uids.map((uid) => ask(uid)));
  const all = await jobs();
  assert.equal(all.length, 1);
  assert.equal(Object.keys(all[0].get('requesters')).length, 8);
});

// ------------------------------------------------------------ abuse caps
test('abuse: new jobs per day are capped (repeated sign-ups in new areas)', async () => {
  const cfg = { ...EXHAUSTED, queueDailyNew: 2 };
  for (let i = 0; i < 4; i++) {
    await setHome(`s${i}`, i);
    const r = await ask(`s${i}`, { config: cfg });
    assert.equal(r.records.length, 0); // still answered
    assert.equal(r.queued, i < 2 ? true : undefined);
  }
  assert.equal((await jobs()).length, 2);
});

test('abuse: open jobs and requesters per job are capped', async () => {
  const cfg = { ...EXHAUSTED, queueMaxOpen: 1, queueMaxRequesters: 2 };
  for (const uid of ['a', 'b', 'c']) await setHome(uid);
  for (const uid of ['a', 'b', 'c']) await ask(uid, { config: cfg });
  await setHome('far', 3);
  assert.equal((await ask('far', { config: cfg })).queued, undefined);
  const all = await jobs();
  assert.equal(all.length, 1);
  assert.equal(Object.keys(all[0].get('requesters')).length, 2);
});

test('enqueueDiscovery refuses reasons that are not budget reasons', async () => {
  const r = await enqueueDiscovery(db, { jobId: 'shared_x', scopeId: 'shared', area: 'x', uid: 'a', appVerified: true, reason: 'unverified', now: NOW, cfg: {} });
  assert.equal(r.queued, false);
  assert.equal((await jobs()).length, 0);
});

// -------------------------------------------------------------- processor
test('processor: budget still used up → job waits, no Melissa call, attempt not counted', async () => {
  await setHome('alice');
  await ask('alice');
  const out = await runQueue({ config: EXHAUSTED });
  assert.equal(out.stoppedBy, 'app_daily_limit');
  assert.equal(out.waiting, 1);
  const [job] = await jobs();
  assert.equal(job.get('status'), 'queued');
  assert.equal(job.get('attempts'), 0);
  assert.ok(job.get('nextAttemptAt').toMillis() > NOW.getTime());
  assert.equal((await usage()).ownerCredits || 0, 0);
});

test('processor: when the budget allows, the job runs once, is stored for 365 days, and the user is served from cache', async () => {
  await setHome('alice');
  await db.doc('users/alice/prayer_log/e1').set({ householdId: 'mel:1', at: NOW });
  await ask('alice');
  const scan = reverse();
  const prop = property();
  const out = await runQueue({ reverse: scan, property: prop });
  assert.equal(out.done, 1);
  assert.equal(scan.calls.length, 1);
  const [job] = await jobs();
  assert.equal(job.get('status'), 'done');
  assert.deepEqual(job.get('requesters'), {});
  assert.ok(job.get('credits') > 0);
  const stored = (await db.collection('owner_properties').limit(1).get()).docs[0];
  assert.equal(stored.get('expiresAt').toMillis() - stored.get('checkedAt').toMillis(), 365 * DAY_MS);
  // Prayer data untouched.
  assert.equal((await db.doc('users/alice/prayer_log/e1').get()).exists, true);
  // The user's next request: served from cache, no new credits.
  const r = await ask('alice', { config: EXHAUSTED });
  assert.equal(r.records.length, 50);
  assert.equal(r.credits, 0);
  // A second run finds nothing to do.
  const again = await runQueue({ reverse: never(), property: never() });
  assert.equal(again.processed, 0);
});

test('processor re-checks the cache first: an area filled meanwhile costs nothing', async () => {
  await setHome('alice');
  await setHome('bob');
  await ask('alice');
  await ask('bob', { config: OPEN, reverse: reverse(), property: property() }); // fills it
  const before = (await usage()).ownerCredits;
  const out = await runQueue({ reverse: never(), property: never() });
  assert.equal(out.done, 1);
  assert.equal((await usage()).ownerCredits, before);
});

test('processor re-checks the account: unverified, disabled or deleted requesters are dropped, job cancelled', async () => {
  for (const uid of ['un', 'dis', 'gone']) await setHome(uid);
  for (const uid of ['un', 'dis', 'gone']) await ask(uid);
  const getUser = async (uid) => {
    if (uid === 'un') return { uid, emailVerified: false, providerData: [{ providerId: 'password' }] };
    if (uid === 'dis') return { uid, emailVerified: true, disabled: true, providerData: [] };
    throw Object.assign(new Error('not found'), { code: 'auth/user-not-found' });
  };
  const out = await runQueue({ getUser, reverse: never(), property: never() });
  assert.equal(out.cancelled, 1);
  const [job] = await jobs();
  assert.equal(job.get('status'), 'cancelled');
  assert.deepEqual(job.get('requesters'), {});
});

test('processor re-checks App Check: a requester queued without a token is never run', async () => {
  await enqueueDiscovery(db, {
    jobId: cache.jobIdFor('shared', homeOf(0).latitude, homeOf(0).longitude), scopeId: 'shared', area: 'x',
    uid: 'old', appVerified: false, reason: 'app_daily_limit', now: NOW, cfg: {},
  });
  await setHome('old');
  const out = await runQueue({ reverse: never(), property: never() });
  assert.equal(out.cancelled, 1);
});

test('processor re-checks the home: a requester moved by an audited correction is dropped', async () => {
  await setHome('alice');
  await ask('alice'); // pins primary_locations/alice
  await db.doc('primary_locations/alice').set({ ...homeOf(4), version: 2 });
  const out = await runQueue({ reverse: never(), property: never() });
  assert.equal(out.cancelled, 1);
});

test('processor: the next requester is used when the first is no longer authorized', async () => {
  await setHome('a');
  await setHome('b');
  await ask('a');
  await ask('b');
  const scan = reverse();
  const out = await runQueue({
    getUser: async (uid) => (uid === 'a' ? null : verifiedUser(uid)), reverse: scan, property: property(),
  });
  assert.equal(out.done, 1);
  assert.equal(scan.calls.length, 1);
});

test('processor never spends past the daily budget, however many jobs wait', async () => {
  for (let i = 0; i < 4; i++) { await setHome(`q${i}`, i); await ask(`q${i}`); }
  const scan = reverse();
  const out = await runQueue({ config: { ...OPEN, dailyCredits: 1000 }, reverse: scan, property: property() });
  assert.equal(out.done, 1);
  assert.equal(out.stoppedBy, 'app_daily_limit');
  assert.equal(scan.calls.length, 1);
  assert.ok((await usage()).ownerCredits <= 1000);
  const waiting = (await jobs()).filter((j) => j.get('status') === 'queued');
  assert.equal(waiting.length, 3);
});

test('processor respects the global daily limit shared with the other endpoints', async () => {
  await setHome('alice');
  await ask('alice');
  await db.doc(`melissa_usage/${DAY}`).set({ credits: 900 }, { merge: true }); // enrichHousehold spent
  const out = await runQueue({ config: { ...OPEN, globalDailyCredits: 1000 }, reverse: never(), property: never() });
  assert.equal(out.stoppedBy, 'app_daily_limit');
  assert.equal((await jobs())[0].get('status'), 'queued');
});

test('processor does nothing while paid discovery is off, the kill switch is on, or Melissa is paused', async () => {
  await setHome('alice');
  await ask('alice');
  assert.equal((await runQueue({ config: { ...OPEN, enabled: false } })).stoppedBy, 'disabled');
  assert.equal((await runQueue({ config: { ...OPEN, globalDailyCredits: 0 } })).stoppedBy, 'disabled');
  await db.doc('melissa_usage/state').set({ paidDisabled: true });
  assert.equal((await runQueue()).stoppedBy, 'paid_disabled');
  await db.doc('melissa_usage/state').set({ paidDisabled: false, outOfCreditsAt: NOW });
  assert.equal((await runQueue()).stoppedBy, 'out_of_credits');
  assert.equal((await jobs())[0].get('status'), 'queued');
});

test('processor: two runs at once process a job only once (claim)', async () => {
  await setHome('alice');
  await ask('alice');
  const scan = reverse();
  const prop = property();
  const outs = await Promise.all([runQueue({ reverse: scan, property: prop }), runQueue({ reverse: scan, property: prop })]);
  assert.equal(outs[0].done + outs[1].done, 1);
  assert.equal(scan.calls.length, 1);
});

test('processor: a failing lookup is retried later, then given up after the attempt limit', async () => {
  await setHome('alice');
  await ask('alice');
  const broken = counted(async () => ({ status: 'error', error: 'unavailable' }));
  let now = NOW;
  for (let i = 1; i <= 3; i++) {
    const out = await runQueue({ now, config: { ...OPEN, queueMaxAttempts: 3 }, reverse: broken, property: never() });
    assert.equal(out.processed, 1);
    now = later(i * 30 * DAY_MS / 10); // well past the back-off
  }
  const [job] = await jobs();
  assert.equal(job.get('status'), 'failed');
  assert.equal(broken.calls.length, 3);
  assert.equal((await usage()).ownerCredits || 0, 0); // failed scans are given back
});

test('processor: jobs older than the queue age expire without any lookup', async () => {
  await setHome('alice');
  await ask('alice');
  const out = await runQueue({ now: later(31 * DAY_MS), reverse: never(), property: never() });
  assert.equal(out.expired, 1);
  assert.equal((await jobs())[0].get('status'), 'expired');
});

// --------------------------------------------------------- account delete
test('account deletion removes the user from waiting jobs (and cancels a job left without requesters)', async () => {
  await setHome('a');
  await setHome('b');
  await ask('a');
  await ask('b');
  await cleanupUser(db, 'a');
  let [job] = await jobs();
  assert.deepEqual(Object.keys(job.get('requesters')), ['b']);
  await cleanupUser(db, 'b');
  [job] = await jobs();
  assert.equal(job.get('status'), 'cancelled');
});

test('userVerified: email verified or Google / Apple / phone; disabled never', () => {
  assert.equal(userVerified({ emailVerified: true }), true);
  assert.equal(userVerified({ emailVerified: false, providerData: [{ providerId: 'apple.com' }] }), true);
  assert.equal(userVerified({ emailVerified: false, providerData: [{ providerId: 'password' }] }), false);
  assert.equal(userVerified({ emailVerified: true, disabled: true }), false);
  assert.equal(userVerified(null), false);
});
