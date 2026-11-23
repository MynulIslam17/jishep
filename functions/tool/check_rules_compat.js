// READ-ONLY check: would existing documents still pass firestore.rules when
// the app updates them? Rules validate the whole document after a merge, so
// one old field outside the allowed list blocks every later update of that
// document.
//
// Never writes. Runs against the emulator by default:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/check_rules_compat.js gps-para-el-cielo
// Against a real project only with --read-production (needs the client's
// approval and read access; prints counts and field names, never values).
'use strict';

const admin = require('firebase-admin');

// Keep in step with firestore.rules (validProfile, household_status,
// prayer_log, prayer_rounds).
const ALLOWED = {
  profile: [
    'fullName', 'email', 'phone', 'avatarUrl', 'avatarBase64', 'address',
    'churchAffiliation', 'dailyPrayerTarget', 'prayerCycleTarget',
    'radiusHomes', 'searchRadiusKm', 'latitude', 'longitude',
    'prayerCycleStartedAt', 'prayerIntention', 'createdAt', 'updatedAt',
  ],
  household_status: [
    'isPrayed', 'isVisited', 'isInvited', 'hasFollowUp', 'followUpDate',
    'notes', 'residentName', 'address', 'prayedAt', 'updatedAt',
  ],
  prayer_log: ['householdId', 'roundId', 'prayedAt', 'createdAt'],
  prayer_rounds: [
    'startedAt', 'completedAt', 'householdIds', 'members', 'center', 'target',
    'size', 'updatedAt',
  ],
};
const BOOLS = ['isPrayed', 'isVisited', 'isInvited', 'hasFollowUp'];

function extraKeys(data, allowed) {
  return Object.keys(data).filter((k) => !allowed.includes(k));
}

async function main() {
  const project = process.argv[2];
  const production = process.argv.includes('--read-production');
  if (!project) throw new Error('usage: check_rules_compat.js <projectId> [--read-production]');
  if (project === 'cielo-63925') throw new Error('never this project');
  if (!process.env.FIRESTORE_EMULATOR_HOST && !production) {
    throw new Error('No FIRESTORE_EMULATOR_HOST: refusing to read a real project without --read-production');
  }
  admin.initializeApp({ projectId: project });
  const db = admin.firestore();

  const report = { users: 0, problems: {} };
  const note = (kind, detail) => {
    const key = `${kind}: ${detail}`;
    report.problems[key] = (report.problems[key] || 0) + 1;
  };

  const users = await db.collection('users').get();
  report.users = users.size;
  for (const u of users.docs) {
    for (const k of extraKeys(u.data(), ALLOWED.profile)) note('profile extra field', k);
    const statuses = await u.ref.collection('household_status').get();
    for (const s of statuses.docs) {
      const d = s.data();
      for (const k of extraKeys(d, ALLOWED.household_status)) note('household_status extra field', k);
      for (const b of BOOLS) if (typeof d[b] !== 'boolean') note('household_status not bool', b);
      if (s.id.length > 128) note('household_status', 'id longer than 128');
    }
    for (const sub of ['prayer_log', 'prayer_rounds']) {
      const docs = await u.ref.collection(sub).get();
      for (const x of docs.docs) {
        for (const k of extraKeys(x.data(), ALLOWED[sub])) note(`${sub} extra field`, k);
      }
    }
  }
  const problems = Object.entries(report.problems);
  console.log(`users checked: ${report.users}`);
  if (!problems.length) console.log('OK: every document can still be updated under the new rules');
  for (const [k, n] of problems) console.log(`BLOCKS UPDATES  ${k}  (${n} docs)`);
  process.exitCode = problems.length ? 1 : 0;
}

main().catch((e) => { console.error(e.message); process.exitCode = 2; });
