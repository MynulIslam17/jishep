'use strict';
// Zero-credit production setting: MELISSA_GLOBAL_DAILY_CREDITS=0 must stop
// EVERY paid Melissa request, from every endpoint, before Melissa is asked,
// even if another switch (discovery, gap-fill, owner names) were turned on
// by mistake. Firestore emulator + fake Melissa functions that count calls.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { enrichHousehold, EnrichError } = require('../src/enrich');
const { discoverNearby, DiscoverError } = require('../src/discover');
const { discoverOwners, OwnerError } = require('../src/owners');
const { overGlobalLimit } = require('../src/budget');

const ROOT = path.join(__dirname, '..');
let db;
before(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('Run with the Firestore emulator (npm test)');
  if (!getApps().length) initializeApp({ projectId: 'demo-gps-cielo-functions' });
  db = getFirestore();
});
beforeEach(async () => {
  for (const c of ['users', 'melissa_usage', 'owner_scans', 'owner_properties', 'owner_areas', 'discovery_jobs']) {
    await db.recursiveDelete(db.collection(c));
  }
});

const NOW = new Date('2026-11-22T12:00:00Z');
const DAY = '2026-11-22';

/** The production settings file, parsed as the Firebase CLI reads it. */
function prodEnv() {
  const env = {};
  for (const line of fs.readFileSync(path.join(ROOT, '.env.gps-para-el-cielo'), 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m) env[m[1]] = m[2];
  }
  return env;
}

/** A fake Melissa function that records every call (it must never run). */
const melissa = (answer) => {
  const f = async (...args) => { f.calls.push(args); return answer(...args); };
  f.calls = [];
  return f;
};
const neverReverse = () => melissa(() => ({ status: 'ok', records: [] }));
const neverProperty = () => melissa(() => ({ status: 'error', error: 'network', codes: [] }));
const neverCheck = () => melissa(() => ({ status: 'verified', codes: [] }));
const usage = async () => (await db.doc(`melissa_usage/${DAY}`).get()).data() || {};

// Every switch ON (the worst mistake), only the app-wide budget at 0.
const ALL_ON = {
  enabled: true, allowOwnerNames: true, sharedCache: true, perUserDaily: 1000,
  dailyCredits: 1e9, monthlyCredits: 1e9, perRequestMaxCredits: 920,
  perUserDailyLookups: 1000, verifyResidential: true, cacheDays: 30,
};

test('production settings: global daily credits 0, every paid switch off', () => {
  const env = prodEnv();
  assert.equal(env.MELISSA_GLOBAL_DAILY_CREDITS, '0');
  for (const k of ['MELISSA_OWNER_DISCOVERY_ENABLED', 'MELISSA_GAP_FILL_ENABLED',
    'MELISSA_ALLOW_OWNER_NAMES', 'MELISSA_OWNER_SHARED_CACHE']) {
    assert.equal(env[k], 'false', k);
  }
  assert.ok(!('MELISSA_EMULATOR_LIVE' in env));
});

test('the params library reads "0" as 0 (not unset, not the default)', () => {
  const { defineInt } = require('firebase-functions/params');
  const name = 'ZERO_BUDGET_TEST_PARAM';
  const param = defineInt(name, { default: 150 });
  process.env[name] = prodEnv().MELISSA_GLOBAL_DAILY_CREDITS;
  assert.equal(param.value(), 0);
  delete process.env[name];
  assert.equal(param.value(), 0); // missing at runtime: 0 as well (fail closed)
});

test('budget check: 0, negative, missing or NaN allows nothing', () => {
  const day = { get: () => undefined };
  for (const limit of [0, -5, undefined, null, NaN, '150']) {
    assert.equal(overGlobalLimit(day, 3, limit), true, String(limit));
  }
  assert.equal(overGlobalLimit(day, 3, 3), false);
  assert.equal(overGlobalLimit({ get: (f) => ({ credits: 1, gapCredits: 1, ownerCredits: 1 })[f] }, 1, 3), true);
});

test('enrichHousehold: budget 0 refuses before Melissa, counts nothing', async () => {
  const check = neverCheck();
  const property = neverProperty();
  for (const config of [{ ...ALL_ON, globalDailyCredits: 0 }, { ...ALL_ON }]) { // explicit 0, and unset
    await assert.rejects(
      enrichHousehold({
        db, uid: 'alice', key: 'k', now: NOW, config, check, property,
        data: { householdId: 'ovt:1', line: '1 Test St', city: 'Chula Vista', state: 'CA', zip: '91910', includeProperty: true },
      }),
      (e) => e instanceof EnrichError && e.reason === 'app_daily_limit',
    );
  }
  assert.equal(check.calls.length + property.calls.length, 0);
  assert.equal((await usage()).credits || 0, 0);
});

test('discoverNearby: budget 0 refuses before Melissa, even with gap-fill on', async () => {
  const reverse = neverReverse();
  const check = neverCheck();
  for (const config of [{ ...ALL_ON, globalDailyCredits: 0 }, { ...ALL_ON }]) {
    await assert.rejects(
      discoverNearby({
        db, uid: 'alice', key: 'k', now: NOW, config, reverse, check,
        data: { latitude: 36.1699, longitude: -115.1398, have: 12 },
      }),
      (e) => e instanceof DiscoverError && e.reason === 'app_daily_limit',
    );
  }
  assert.equal(reverse.calls.length + check.calls.length, 0);
  assert.equal((await usage()).gapCredits || 0, 0);
});

test('discoverOwners: budget 0 refuses before Melissa, even with discovery and names on', async () => {
  const reverse = neverReverse();
  const property = neverProperty();
  for (const config of [{ ...ALL_ON, globalDailyCredits: 0 }, { ...ALL_ON }]) {
    await assert.rejects(
      discoverOwners({
        db, uid: 'alice', key: 'k', now: NOW, config, reverse, property,
        data: { latitude: 32.6401, longitude: -117.0842 },
      }),
      (e) => e instanceof OwnerError && e.reason === 'app_daily_limit',
    );
  }
  assert.equal(reverse.calls.length + property.calls.length, 0);
  const u = await usage();
  assert.equal(u.ownerCredits || 0, 0);
  assert.equal(u.melissaRequests || 0, 0);
});

test('the budget is app-wide: credits spent by one endpoint count for the others', async () => {
  // 12 credits left today; enrichHousehold spends them, the next paid call
  // from any endpoint is refused before Melissa.
  const config = { ...ALL_ON, globalDailyCredits: 12, cacheDays: 0 };
  await enrichHousehold({
    db, uid: 'alice', key: 'k', now: NOW, config, check: neverCheck(),
    property: melissa(() => ({ status: 'not_found', codes: [] })),
    data: { householdId: 'ovt:1', line: '1 Test St', city: 'Chula Vista', state: 'CA', zip: '91910', includeProperty: true },
  });
  const reverse = neverReverse();
  await assert.rejects(
    discoverNearby({ db, uid: 'bob', key: 'k', now: NOW, config, reverse, check: neverCheck(),
      data: { latitude: 36.1699, longitude: -115.1398, have: 49 } }),
    (e) => e.reason === 'app_daily_limit',
  );
  await assert.rejects(
    discoverOwners({ db, uid: 'carol', key: 'k', now: NOW, config: { ...config, cacheDays: 30 }, reverse, property: neverProperty(),
      data: { latitude: 32.6401, longitude: -117.0842 } }),
    (e) => e.reason === 'app_daily_limit',
  );
  assert.equal(reverse.calls.length, 0);
});

test('budget 0 never blocks free answers: stored results are still served', async () => {
  // A stored enrichment result (cache) is returned without Melissa.
  const ref = db.doc('users/alice/enrichment/ovt:1');
  await ref.set({
    status: 'verified', property: null, codes: [], checkedAt: new Date(NOW.getTime() - 1000),
    expiresAt: new Date(NOW.getTime() + 864e5),
  });
  const check = neverCheck();
  const r = await enrichHousehold({
    db, uid: 'alice', key: 'k', now: NOW, config: { ...ALL_ON, globalDailyCredits: 0 }, check,
    data: { householdId: 'ovt:1', line: '1 Test St', city: 'Chula Vista', state: 'CA', zip: '91910' },
  });
  assert.equal(r.cached, true);
  assert.equal(check.calls.length, 0);

  // discoverOwners in cache-only mode (production) never reserves or calls.
  const reverse = neverReverse();
  const owners = await discoverOwners({
    db, uid: 'alice', key: 'k', now: NOW, reverse, property: neverProperty(),
    config: { enabled: false, allowOwnerNames: true, globalDailyCredits: 0 },
    data: { latitude: 32.6401, longitude: -117.0842 },
  });
  assert.equal(owners.records.length, 0);
  assert.equal(reverse.calls.length, 0);
});

test('every deployed function given the Melissa key also gets the app-wide budget', () => {
  const src = fs.readFileSync(path.join(ROOT, 'src/index.js'), 'utf8');
  const keyed = (src.match(/key: MELISSA_CREDIT_LICENSE\.value\(\)/g) || []).length;
  const budgeted = (src.match(/globalDailyCredits: GLOBAL_DAILY_CREDITS\.value\(\)/g) || []).length;
  assert.equal(keyed, 3); // enrichHousehold, discoverNearby, discoverOwners
  assert.equal(budgeted, keyed);
  assert.match(src, /defineInt\('MELISSA_GLOBAL_DAILY_CREDITS', \{ default: 0 \}\)/);
  // Melissa hosts are named only in the modules whose calls are budgeted.
  for (const f of fs.readdirSync(path.join(ROOT, 'src'))) {
    const text = fs.readFileSync(path.join(ROOT, 'src', f), 'utf8');
    if (/melissadata\.net/.test(text)) assert.ok(['melissa.js', 'discover.js'].includes(f), f);
  }
});

test('the deploy package can never contain recordings, secrets or local settings', () => {
  const cfg = JSON.parse(fs.readFileSync(path.join(ROOT, '..', 'firebase.json'), 'utf8'));
  const ignore = cfg.functions[0].ignore;
  for (const entry of ['.melissa-recordings', '.melissa-fixtures', '.secret.local', '.env.local', 'test', 'tool', 'node_modules']) {
    assert.ok(ignore.includes(entry), entry);
  }
  // No Melissa key in any uploaded file: compared with the real keys kept
  // outside the repository (never printed; skipped where they are absent).
  const uploaded = ['package.json', '.env.gps-para-el-cielo',
    ...fs.readdirSync(path.join(ROOT, 'src')).map((f) => `src/${f}`)];
  const keyFile = path.join(require('os').homedir(), '.config/gps-cielo/melissa.env');
  const keys = fs.existsSync(keyFile)
    ? fs.readFileSync(keyFile, 'utf8').split('\n').map((l) => l.split('=').slice(1).join('=').trim()).filter((k) => k.length >= 8)
    : [];
  for (const f of uploaded) {
    const text = fs.readFileSync(path.join(ROOT, f), 'utf8');
    assert.ok(!keys.some((k) => text.includes(k)), `Melissa key found in ${f}`);
    assert.doesNotMatch(text, /^MELISSA_[A-Z_]*LICENSE\s*=/m, f);
  }
});
