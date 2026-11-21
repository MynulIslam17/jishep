/**
 * READ-ONLY backup of the `households` collection in gps-cielo, plus every
 * user's `household_status` documents that point at demo households.
 * Nothing is written to Firestore.
 *
 *   node backup.js            # writes backups/households-<timestamp>.json
 *
 * Auth: `gcloud auth print-access-token` (as seed.js). The token is never
 * printed or saved.
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { ID_PREFIX } = require('./demo_bd');

const PROJECT_ID = 'gps-cielo';
const API = 'https://firestore.googleapis.com/v1';
const DOCS = `projects/${PROJECT_ID}/databases/(default)/documents`;

const token = execFileSync('gcloud', ['auth', 'print-access-token'], {
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'ignore'],
}).trim();

async function get(url) {
  const r = await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, 'x-goog-user-project': PROJECT_ID },
  });
  if (!r.ok) throw new Error(`GET ${url.replace(API, '')} -> HTTP ${r.status}`);
  return r.json();
}

async function listAll(collectionPath) {
  const out = [];
  let pageToken = '';
  do {
    const q = `pageSize=300${pageToken ? `&pageToken=${encodeURIComponent(pageToken)}` : ''}`;
    const page = await get(`${API}/${collectionPath}?${q}`);
    out.push(...(page.documents || []));
    pageToken = page.nextPageToken || '';
  } while (pageToken);
  return out;
}

const idOf = (doc) => doc.name.split('/').pop();
const isDemoDoc = (doc) =>
  idOf(doc).startsWith(ID_PREFIX) && doc.fields?.isDemo?.booleanValue === true;

(async () => {
  const households = await listAll(`${DOCS}/households`);
  const users = await listAll(`${DOCS}/users`);
  const statuses = [];
  for (const u of users) {
    const uid = idOf(u);
    const docs = await listAll(`${DOCS}/users/${uid}/household_status`);
    for (const d of docs) {
      if (idOf(d).startsWith(ID_PREFIX)) statuses.push({ uid, doc: d });
    }
  }

  const demo = households.filter(isDemoDoc);
  const prefixedNotDemo = households.filter(
    (d) => idOf(d).startsWith(ID_PREFIX) && !isDemoDoc(d),
  );
  const other = households.filter((d) => !idOf(d).startsWith(ID_PREFIX));

  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const dir = path.join(__dirname, 'backups');
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `households-${stamp}.json`);
  fs.writeFileSync(
    file,
    JSON.stringify(
      { project: PROJECT_ID, takenAt: new Date().toISOString(), households, demoStatuses: statuses },
      null,
      2,
    ),
  );

  const perUser = {};
  for (const s of statuses) perUser[s.uid] = (perUser[s.uid] || 0) + 1;
  console.log(`Backup: ${path.relative(process.cwd(), file)}`);
  console.log(`households total: ${households.length}`);
  console.log(`  demo (id ${ID_PREFIX}* and isDemo:true): ${demo.length}`);
  console.log(`  ${ID_PREFIX}* but NOT isDemo (would be refused): ${prefixedNotDemo.length}`);
  console.log(`  other (not demo): ${other.length}${other.length ? ' -> ' + other.map(idOf).join(', ') : ''}`);
  console.log(`users: ${users.length}`);
  console.log(`user household_status docs for demo households: ${statuses.length}`);
  for (const [uid, n] of Object.entries(perUser)) console.log(`  ${uid}: ${n}`);
})().catch((e) => {
  console.error('ERROR:', e.message);
  process.exit(1);
});
