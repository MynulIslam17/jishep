'use strict';
// Rebuilds the Rancho del Rey pilot into the cache-first property index FROM
// THE SAVED MELISSA RECORDINGS ONLY, then runs the location scenarios
// against it. Zero network: the fetch under the recorder throws.
//
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/pilot_scenarios.js [projectId] [--shared|--uid=<uid>]
//
// Prints COUNTS ONLY (no owner names, no addresses).
const path = require('path');
const { melissaFetch } = require('../src/recorder');
const { reverseLookup } = require('../src/discover');
const { lookupProperty } = require('../src/melissa');
const { discoverOwners } = require('../src/owners');
const geo = require('../src/property_cache');

const PILOT = { latitude: 32.6435, longitude: -117.0185 };
const RECORDINGS = path.join(__dirname, '..', '.melissa-recordings');

function replayOnly(dir = RECORDINGS) {
  const events = { replay: 0, not_recorded: 0, network: 0 };
  const fetchImpl = melissaFetch({
    dir,
    replayOnly: true,
    realFetch: async () => { events.network++; throw new Error('network forbidden'); },
    onEvent: (e) => { events[e] = (events[e] || 0) + 1; },
  });
  return { fetchImpl, events };
}

/** Rebuilds the pilot from recordings (Reverse + Property replays). */
async function rebuildPilot(db, { uid = 'pilot-rebuild', shared = true, now = new Date(), dir } = {}) {
  const { fetchImpl, events } = replayOnly(dir);
  const result = await discoverOwners({
    db, uid, data: { ...PILOT, target: 50 }, key: 'replay-only', now,
    config: {
      enabled: true, allowOwnerNames: true, sharedCache: shared, perUserDaily: 1000,
      dailyCredits: 1e9, monthlyCredits: 1e9, perRequestMaxCredits: 920, legacyCache: false,
      globalDailyCredits: 1e9, // replay-only rebuild: no network, no credits
    },
    reverse: (p, k) => reverseLookup(p, k, { fetchImpl }),
    property: (a, k, o) => lookupProperty(a, k, { ...o, fetchImpl, retries: 0 }),
  });
  return { result, events };
}

const SCENARIOS = [
  ['A same location', 0, 0],
  ['B 50 m', 50, Math.PI / 4],
  ['C 200 m', 200, Math.PI / 4],
  ['D 400 m', 400, Math.PI / 4],
  ['E 2 km', 2000, Math.PI / 4],
  ['F 5 km', 5000, Math.PI / 4],
];

/** Cache-only reads at each scenario point (discovery OFF: nothing can be called). */
async function runScenarios(db, { uid = 'user-b', shared = true, now = new Date() } = {}) {
  const rows = [];
  for (const [name, meters, bearing] of SCENARIOS) {
    const [latitude, longitude] = meters ? geo.offset(PILOT.latitude, PILOT.longitude, meters, bearing) : [PILOT.latitude, PILOT.longitude];
    const calls = { reverse: 0, property: 0 };
    const r = await discoverOwners({
      db, uid, data: { latitude, longitude, target: 50 }, key: 'none', now,
      config: { enabled: false, allowOwnerNames: true, sharedCache: shared },
      reverse: async () => { calls.reverse++; throw new Error('forbidden'); },
      property: async () => { calls.property++; throw new Error('forbidden'); },
    });
    rows.push({
      scenario: name,
      cachedAddressesNearby: r.stats.candidates,
      namedReturned: r.records.length,
      duplicatesEliminated: (r.stats.duplicateAddresses || 0) + (r.stats.duplicateParcel || 0),
      coveredMeters: r.coveredMeters,
      completeness: r.completeness,
      provablyNearest50: r.completeness === 'complete' && r.records.length === 50,
      fillReverseGeoCoder: r.missing.scanNeeded ? 1 : 0,
      fillPropertyLookups: r.missing.lookupsNeeded,
      fillEstimatedCredits: r.missing.estimatedCredits,
      proveReverseGeoCoder: r.missing.toProve.scanNeeded ? 1 : 0,
      provePropertyLookups: r.missing.toProve.lookupsNeeded,
      proveEstimatedCredits: r.missing.toProve.estimatedCredits,
      creditsUsedNow: r.credits,
      melissaCallsNow: calls.reverse + calls.property,
      firestoreReads: r.firestoreReads,
    });
  }
  return rows;
}

/** Counts that describe the recovered pilot records (no names). */
function describe(records) {
  return {
    records: records.length,
    withOwner: records.filter((r) => r.owner && r.owner.name).length,
    withSecondOwner: records.filter((r) => r.owner && r.owner.secondName).length,
    trusts: records.filter((r) => r.owner && r.owner.isTrust).length,
    companies: records.filter((r) => r.owner && r.owner.isCompany).length,
    withAddress: records.filter((r) => r.line && r.zip).length,
    stableIds: records.filter((r) => /^mel:\d+$/.test(r.id)).length,
    classes: [...new Set(records.map((r) => r.classification && r.classification.label))],
    farthestMeters: Math.max(...records.map((r) => r.distanceMeters)),
  };
}

module.exports = { PILOT, RECORDINGS, rebuildPilot, runScenarios, describe, replayOnly };

if (require.main === module) {
  (async () => {
    const { initializeApp } = require('firebase-admin/app');
    const { getFirestore } = require('firebase-admin/firestore');
    if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('emulator only (FIRESTORE_EMULATOR_HOST)');
    const projectId = process.argv[2] || 'demo-gps-cielo-functions';
    const uidArg = process.argv.find((a) => a.startsWith('--uid='));
    const shared = !uidArg;
    initializeApp({ projectId });
    const db = getFirestore();
    const uid = uidArg ? uidArg.slice(6) : 'pilot-rebuild';
    const { result, events } = await rebuildPilot(db, { uid, shared });
    // The rebuild replayed saved answers: undo its ESTIMATED credits in the
    // local counters (nothing was billed) and label the job.
    const { FieldValue } = require('firebase-admin/firestore');
    const now = new Date();
    const usage = db.collection('melissa_usage');
    await usage.doc(now.toISOString().slice(0, 10)).set({
      ownerCredits: FieldValue.increment(-result.credits), estimatedCredits: FieldValue.increment(-result.credits),
      ownerDiscoveries: FieldValue.increment(-1), replayedCredits: FieldValue.increment(result.credits),
      melissaRequests: FieldValue.increment(-(events.replay)), replayedRequests: FieldValue.increment(events.replay),
      ownerCacheMisses: FieldValue.increment(-1),
    }, { merge: true });
    await usage.doc(`month-${now.toISOString().slice(0, 7)}`).set({ ownerCredits: FieldValue.increment(-result.credits) }, { merge: true });
    const jobs = await db.collection('discovery_jobs').get();
    for (const j of jobs.docs) if (j.get('creditsUsed') === result.credits) await j.ref.set({ replayedFromRecordings: true }, { merge: true });
    console.log(JSON.stringify({ projectId, shared, uid: shared ? null : '(given)', events,
      completeness: result.completeness, credits: result.credits, stats: result.stats, pilot: describe(result.records) }, null, 1));
    if (shared) console.table(await runScenarios(db));
  })().catch((e) => { console.error(e.message); process.exit(1); });
}
