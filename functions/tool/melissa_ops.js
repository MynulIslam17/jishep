'use strict';
// Melissa operations: kill switch and usage report (blueprint §7, §7.1).
//
//   node tool/melissa_ops.js status  --project=<id>
//   node tool/melissa_ops.js report  --project=<id> [--days=30] [--json]
//   node tool/melissa_ops.js kill    --project=<id> --reason="..." [--approve=<id>]
//   node tool/melissa_ops.js unkill  --project=<id> --reason="..." [--approve=<id>]
//
// kill sets melissa_usage/state.paidDisabled=true: every paid endpoint
// (discoverOwners, discoverNearby, enrichHousehold) refuses before calling
// Melissa, within one request, no redeploy. Cached data is still served.
// Reports read only server-side counters (melissa_usage/*): counts and
// estimated credits, no names, addresses or uids.
//
// Credits here are the functions' ESTIMATES (2 per Reverse GeoCoder address,
// 9 per Property lookup). Melissa's own account balance is the authority:
// check it in the Melissa portal before and after any paid activity.

const fs = require('fs');
const path = require('path');
const { FieldValue } = require('firebase-admin/firestore');
const { args, guard, firestoreFor, where } = require('./admin_common');

const COUNTERS = [
  ['ownerCacheHits', 'Cache hits (served free)'],
  ['ownerCacheMisses', 'Cache misses (incomplete coverage)'],
  ['propertiesReused', 'Stored property answers reused'],
  ['duplicatesAvoided', 'Duplicate addresses merged (overlap)'],
  ['overlapScansUsed', 'Scans combined in overlap answers'],
  ['successfulDiscoveries', 'Paid discoveries finished'],
  ['failedDiscoveries', 'Paid discoveries failed/stopped'],
  ['ownerDiscoveries', 'Paid discoveries reserved'],
  ['ownerCredits', 'Owner credits reserved (net, estimated)'],
  ['estimatedCredits', 'Credits used (estimated)'],
  ['melissaRequests', 'Melissa requests'],
  ['failedLookups', 'Failed Property lookups'],
  ['deniedBudget', 'Denied by budget / kill switch'],
  ['deniedSecurity', 'Denied by security (location, unverified)'],
  ['ownerWaited', 'Joined another request’s discovery'],
  ['credits', 'enrichHousehold credits'],
  ['gapCredits', 'discoverNearby credits'],
];

/** Reads the day and month counter documents for the last `days` days. */
async function usageReport(db, { now = new Date(), days = 30 } = {}) {
  const ids = [];
  for (let i = 0; i < days; i++) ids.push(new Date(now.getTime() - i * 864e5).toISOString().slice(0, 10));
  const snaps = await db.getAll(...ids.map((d) => db.collection('melissa_usage').doc(d)));
  const daily = [];
  const totals = {};
  for (const s of snaps) {
    if (!s.exists) continue;
    const row = { day: s.id };
    for (const [k] of COUNTERS) {
      const v = s.get(k);
      if (typeof v === 'number' && v) { row[k] = v; totals[k] = (totals[k] || 0) + v; }
    }
    daily.push(row);
  }
  const month = await db.collection('melissa_usage').doc(`month-${now.toISOString().slice(0, 7)}`).get();
  const state = await db.collection('melissa_usage').doc('state').get();
  const hits = totals.ownerCacheHits || 0;
  const misses = totals.ownerCacheMisses || 0;
  return {
    days, daily, totals,
    monthCredits: month.exists ? month.get('ownerCredits') || 0 : 0,
    cacheHitRate: hits + misses ? hits / (hits + misses) : null,
    killSwitch: state.exists && state.get('paidDisabled') === true,
    killSwitchReason: state.exists ? state.get('paidDisabledReason') || null : null,
    outOfCreditsAt: state.exists && state.get('outOfCreditsAt') ? state.get('outOfCreditsAt').toDate().toISOString() : null,
  };
}

/** Warnings when spending approaches the configured limits. */
function warnings(report, env, { now = new Date(), threshold = 0.8 } = {}) {
  const out = [];
  const today = report.daily.find((d) => d.day === now.toISOString().slice(0, 10)) || {};
  const spentToday = (today.ownerCredits || 0) + (today.credits || 0) + (today.gapCredits || 0);
  const global = Number(env.MELISSA_GLOBAL_DAILY_CREDITS || 0);
  const monthly = Number(env.MELISSA_OWNER_MONTHLY_CREDITS || 0);
  if (global > 0 && spentToday >= threshold * global) out.push(`daily credits at ${spentToday}/${global}`);
  if (monthly > 0 && report.monthCredits >= threshold * monthly) out.push(`monthly owner credits at ${report.monthCredits}/${monthly}`);
  if (report.outOfCreditsAt) out.push(`Melissa reported out of credits at ${report.outOfCreditsAt}`);
  return out;
}

async function setKill(db, on, { reason, operator = process.env.USER || 'operator' } = {}) {
  if (!reason || String(reason).trim().length < 3) throw new Error('--reason="..." is required');
  await db.collection('melissa_usage').doc('state').set({
    paidDisabled: on,
    paidDisabledReason: String(reason).slice(0, 300),
    paidDisabledBy: String(operator).slice(0, 120),
    paidDisabledChangedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
}

/** Deploy-time settings of a project (functions/.env.<project>), if present. */
function envFor(project) {
  const file = path.join(__dirname, '..', `.env.${project}`);
  const env = {};
  if (!fs.existsSync(file)) return env;
  for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !/LICEN[CS]E|KEY|SECRET/i.test(m[1])) env[m[1]] = m[2];
  }
  return env;
}

async function main() {
  const a = args();
  const cmd = a._[0];
  const write = cmd === 'kill' || cmd === 'unkill';
  const project = guard(a, { write });
  const db = firestoreFor(project);
  console.log(`Target: ${where(project)}`);
  if (write) {
    await setKill(db, cmd === 'kill', { reason: a.reason });
    console.log(cmd === 'kill' ? 'Paid Melissa discovery DISABLED (kill switch on).' : 'Kill switch OFF (env switches and budgets still apply).');
    return;
  }
  const report = await usageReport(db, { days: Number(a.days || (cmd === 'status' ? 1 : 30)) });
  const env = envFor(project);
  if (a.json) { console.log(JSON.stringify({ ...report, warnings: warnings(report, env) }, null, 2)); return; }
  console.log(`Kill switch: ${report.killSwitch ? `ON (${report.killSwitchReason || 'no reason'})` : 'off'}`);
  console.log('Configured (functions/.env file, deployed values may differ until redeploy):');
  for (const k of ['MELISSA_OWNER_DISCOVERY_ENABLED', 'MELISSA_GLOBAL_DAILY_CREDITS', 'MELISSA_OWNER_DAILY_CREDITS',
    'MELISSA_OWNER_MONTHLY_CREDITS', 'MELISSA_OWNER_REQUEST_MAX_CREDITS', 'MELISSA_OWNER_PER_USER_DAILY', 'MELISSA_CACHE_DAYS']) {
    if (k in env) console.log(`  ${k}=${env[k]}`);
  }
  console.log(`Last ${report.days} day(s), ${report.daily.length} with activity:`);
  for (const [k, label] of COUNTERS) if (report.totals[k]) console.log(`  ${label}: ${report.totals[k]}`);
  console.log(`  Owner credits this month (net, estimated): ${report.monthCredits}`);
  if (report.cacheHitRate != null) console.log(`  Cache hit rate: ${(report.cacheHitRate * 100).toFixed(1)}%`);
  for (const w of warnings(report, env)) console.log(`WARNING: ${w}`);
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}

module.exports = { usageReport, warnings, setKill, envFor, COUNTERS };
