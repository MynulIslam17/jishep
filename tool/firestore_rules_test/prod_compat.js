// Production rules compatibility, run against an ISOLATED local emulator
// (demo- project, no network). Loads a read-only backup of the production
// documents (REST JSON written by the cutover backup) and, as each existing
// user, performs the writes the app makes, under the OLD (live) rules and the
// NEW (repository) rules. Prints only pass/fail per action and field names,
// never values.
//
//   firebase emulators:exec --only firestore --project demo-gps-cielo-compat \
//     --config <cfg> "node prod_compat.js <backup dir>"
const fs = require('fs');
const path = require('path');
const { initializeTestEnvironment } = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, getDocs, collection, serverTimestamp, Timestamp, GeoPoint,
} = require('firebase/firestore');

const dir = process.argv[2];
const docs = JSON.parse(fs.readFileSync(path.join(dir, 'firestore_docs.json'), 'utf8'));
const OLD = fs.readFileSync(path.join(dir, 'firestore.rules.live'), 'utf8');
const NEW = fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8');

function fromRest(v) {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return Timestamp.fromDate(new Date(v.timestampValue));
  if ('geoPointValue' in v) return new GeoPoint(v.geoPointValue.latitude || 0, v.geoPointValue.longitude || 0);
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromRest);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, fromRest(x)]));
  throw new Error(`unsupported value ${Object.keys(v)}`);
}
const data = (d) => fromRest({ mapValue: { fields: d.fields || {} } });

async function attempt(fn) {
  try { await fn(); return 'ok'; } catch (e) { return `DENIED (${e.code || e.message})`; }
}

async function run(label, rules) {
  const env = await initializeTestEnvironment({ projectId: 'demo-gps-cielo-compat', firestore: { rules } });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const [p, d] of Object.entries(docs)) await setDoc(doc(ctx.firestore(), p), data(d));
  });
  const results = {};
  const note = (k, r) => { results[`${k}: ${r}`] = (results[`${k}: ${r}`] || 0) + 1; };
  const users = Object.keys(docs).filter((p) => /^users\/[^/]+$/.test(p));
  for (const p of users) {
    const uid = p.split('/')[1];
    const profile = data(docs[p]);
    const token = { email_verified: true, firebase: { sign_in_provider: profile.phone ? 'phone' : 'password' } };
    if (profile.email) token.email = profile.email;
    if (profile.phone) token.phone_number = profile.phone;
    const db = env.authenticatedContext(uid, token).firestore();
    note('read own profile', await attempt(() => getDoc(doc(db, p))));
    // What the app does on launch / settings: merge a timestamp and a field.
    note('update own profile (merge updatedAt)', await attempt(() => setDoc(doc(db, p), { updatedAt: serverTimestamp() }, { merge: true })));
    note('set prayerCycleStartedAt', await attempt(() => setDoc(doc(db, p), { prayerCycleStartedAt: serverTimestamp() }, { merge: true })));
    note('write household_status', await attempt(() => setDoc(doc(db, `${p}/household_status/test-h1`), {
      isPrayed: true, isVisited: false, isInvited: false, hasFollowUp: false, updatedAt: serverTimestamp(),
    })));
    note('write prayer_log', await attempt(() => setDoc(doc(db, `${p}/prayer_log/r0_test-h1`), {
      householdId: 'test-h1', roundId: 'r0', prayedAt: serverTimestamp(), createdAt: serverTimestamp(),
    })));
    note('write prayer_rounds', await attempt(() => setDoc(doc(db, `${p}/prayer_rounds/r0`), {
      startedAt: serverTimestamp(), householdIds: ['test-h1'], size: 1, target: 50, updatedAt: serverTimestamp(),
    }, { merge: true })));
    for (const dp of Object.keys(docs).filter((x) => x.startsWith(`${p}/devices/`))) {
      const d = data(docs[dp]);
      note('refresh existing device', await attempt(() => setDoc(doc(db, dp), { token: d.token, platform: d.platform, updatedAt: serverTimestamp() })));
    }
    for (const np of Object.keys(docs).filter((x) => x.startsWith(`${p}/notifications/`))) {
      note('mark existing notification read', await attempt(() => updateDoc(doc(db, np), { isRead: true })));
    }
    note('read own notifications', await attempt(() => getDocs(collection(db, `${p}/notifications`))));
    // Never someone else's data.
    const other = users.find((x) => x !== p);
    if (other) note('read ANOTHER user profile (must be denied)', await attempt(() => getDoc(doc(db, other))));
    // Server-only caches are never client readable.
    note('read owner_properties (must be denied)', await attempt(() => getDoc(doc(db, 'owner_properties/mel:1'))));
  }
  // Extra fields in existing documents that the new rules would reject on update.
  const ALLOWED_PROFILE = ['fullName', 'email', 'phone', 'avatarUrl', 'avatarBase64', 'address', 'churchAffiliation',
    'dailyPrayerTarget', 'prayerCycleTarget', 'radiusHomes', 'searchRadiusKm', 'latitude', 'longitude',
    'prayerCycleStartedAt', 'prayerIntention', 'createdAt', 'updatedAt'];
  const extra = users.flatMap((p) => Object.keys(data(docs[p])).filter((k) => !ALLOWED_PROFILE.includes(k)));
  await env.cleanup();
  return { label, users: users.length, results, profileFieldsOutsideNewRules: [...new Set(extra)] };
}

(async () => {
  for (const [label, rules] of [['OLD (live) rules', OLD], ['NEW (repository) rules', NEW]]) {
    console.log(JSON.stringify(await run(label, rules), null, 1));
  }
})().catch((e) => { console.error(e); process.exitCode = 1; });
