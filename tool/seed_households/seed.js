/**
 * Seeds / removes SYNTHETIC demo households in the `gps-cielo` Firestore.
 *
 * Safety rules enforced here:
 *   - Only project `gps-cielo` and its `(default)` database are ever used;
 *     the retired project `cielo-63925` is refused outright.
 *   - Only documents whose id starts with `demo_bd_` are written or deleted.
 *   - An existing document at a demo id that is NOT marked `isDemo: true` is
 *     never overwritten or deleted (the whole run aborts instead).
 *   - Dry-run is the default; nothing changes without `--write`.
 *
 * Authentication: your Google Cloud CLI login (`gcloud auth login`), sent as
 * an OAuth access token to the Firestore REST API. Security rules do not
 * apply to this IAM-authorized access, so the rules stay strict for app
 * users. The token is never printed.
 *
 * Usage (from tool/seed_households):
 *   npm install
 *   node seed.js                    # dry-run: validate data, preview writes
 *   node seed.js --write            # create/update the 140 demo households
 *   node seed.js --cleanup          # dry-run: list demo households to delete
 *   node seed.js --cleanup --write  # delete only the demo households
 */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const { geohashForLocation } = require('geofire-common');
const { ID_PREFIX, DEMO_SET, EXPECTED_PER_CITY } = require('./demo_bd');

const PROJECT_ID = 'gps-cielo';
const FORBIDDEN_PROJECTS = ['cielo-63925'];
const DATABASE = '(default)';
const COLLECTION = 'households';
const DATA_FILE = path.join(__dirname, 'households.demo_bd.json');
const API = 'https://firestore.googleapis.com/v1';
const DB_PATH = `projects/${PROJECT_ID}/databases/${DATABASE}`;
const DOCS_PATH = `${DB_PATH}/documents`;

// Bangladesh bounding box, for sanity-checking coordinates.
const BD_BOUNDS = { minLat: 20.5, maxLat: 26.7, minLng: 88.0, maxLng: 92.7 };

function fail(message) {
  console.error(`\nERROR: ${message}`);
  process.exit(1);
}

function guardProject() {
  const mentioned = [
    process.env.GOOGLE_CLOUD_PROJECT,
    process.env.GCLOUD_PROJECT,
    process.env.CLOUDSDK_CORE_PROJECT,
    ...process.argv,
  ].filter(Boolean);
  for (const value of mentioned) {
    if (FORBIDDEN_PROJECTS.some((p) => String(value).includes(p))) {
      fail(`Refusing to run: ${FORBIDDEN_PROJECTS.join(', ')} must never be accessed.`);
    }
  }
  if (FORBIDDEN_PROJECTS.includes(PROJECT_ID)) fail('Invalid PROJECT_ID.');
}

function accessToken() {
  if (process.env.FIRESTORE_ACCESS_TOKEN) return process.env.FIRESTORE_ACCESS_TOKEN.trim();
  try {
    return execFileSync('gcloud', ['auth', 'print-access-token'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch (_) {
    fail('Could not get a gcloud access token. Run `gcloud auth login` first.');
  }
}

async function api(token, method, url, body) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'x-goog-user-project': PROJECT_ID,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (!response.ok) {
    let message = text;
    try {
      message = JSON.parse(text).error.message;
    } catch (_) {}
    throw new Error(`${method} ${url.replace(API, '')} -> HTTP ${response.status}: ${message}`);
  }
  return text ? JSON.parse(text) : {};
}

function loadAndValidate() {
  const records = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
  const problems = [];
  const ids = new Set();
  const perCity = {};

  for (const r of records) {
    if (typeof r.id !== 'string' || !r.id.startsWith(ID_PREFIX)) {
      problems.push(`id without ${ID_PREFIX} prefix: ${r.id}`);
    }
    if (ids.has(r.id)) problems.push(`duplicate id: ${r.id}`);
    ids.add(r.id);
    if (!/^Demo Household \d{3}$/.test(r.residentName)) {
      problems.push(`${r.id}: residentName must be a "Demo Household NNN" placeholder`);
    }
    if (!r.address || !r.address.includes('(synthetic)')) {
      problems.push(`${r.id}: address must be marked (synthetic)`);
    }
    const { latitude: lat, longitude: lng } = r;
    if (
      typeof lat !== 'number' || typeof lng !== 'number' ||
      lat < BD_BOUNDS.minLat || lat > BD_BOUNDS.maxLat ||
      lng < BD_BOUNDS.minLng || lng > BD_BOUNDS.maxLng
    ) {
      problems.push(`${r.id}: coordinates outside Bangladesh (${lat}, ${lng})`);
    }
    const expectedHash = geohashForLocation([lat, lng]);
    if (r.geohash !== expectedHash) {
      problems.push(`${r.id}: geohash ${r.geohash} != computed ${expectedHash}`);
    }
    perCity[r.city] = (perCity[r.city] || 0) + 1;
  }

  for (const [city, expected] of Object.entries(EXPECTED_PER_CITY)) {
    if (perCity[city] !== expected) {
      problems.push(`${city}: expected ${expected} records, found ${perCity[city] || 0}`);
    }
  }
  if (problems.length) fail(`Data validation failed:\n  - ${problems.join('\n  - ')}`);
  return { records, perCity };
}

function toFields(r) {
  return {
    residentName: { stringValue: r.residentName },
    address: { stringValue: r.address },
    cityStateZip: { stringValue: r.cityStateZip },
    geo: {
      mapValue: {
        fields: {
          geohash: { stringValue: r.geohash },
          geopoint: { geoPointValue: { latitude: r.latitude, longitude: r.longitude } },
        },
      },
    },
    isDemo: { booleanValue: true },
    demoSet: { stringValue: DEMO_SET },
    demoCity: { stringValue: r.city },
    demoArea: { stringValue: r.area },
  };
}

const docName = (id) => `${DOCS_PATH}/${COLLECTION}/${id}`;
const idOf = (name) => name.split('/').pop();

async function confirmDatabase(token) {
  const db = await api(token, 'GET', `${API}/${DB_PATH}`);
  if (db.name !== DB_PATH) fail(`Unexpected database ${db.name}`);
  console.log(`Project:   ${PROJECT_ID}`);
  console.log(`Database:  ${DATABASE} (${db.type}, ${db.locationId})`);
  return db;
}

async function batchGet(token, ids) {
  const found = new Map();
  for (let i = 0; i < ids.length; i += 100) {
    const result = await api(token, 'POST', `${API}/${DOCS_PATH}:batchGet`, {
      documents: ids.slice(i, i + 100).map(docName),
    });
    for (const item of result) {
      if (item.found) found.set(idOf(item.found.name), item.found);
    }
  }
  return found;
}

async function commit(token, writes) {
  for (let i = 0; i < writes.length; i += 400) {
    await api(token, 'POST', `${API}/${DOCS_PATH}:commit`, {
      writes: writes.slice(i, i + 400),
    });
  }
}

async function seed(token, write) {
  const { records, perCity } = loadAndValidate();
  console.log(`Data file: ${path.basename(DATA_FILE)} — ${records.length} synthetic records`);
  for (const [city, count] of Object.entries(perCity)) console.log(`  ${city.padEnd(11)} ${count}`);
  console.log(`IDs:       ${records[0].id} … ${records[records.length - 1].id}`);
  console.log('Sample document:');
  console.log(JSON.stringify({ id: records[0].id, ...readable(toFields(records[0])) }, null, 2));

  const existing = await batchGet(token, records.map((r) => r.id));
  const foreign = [...existing.entries()].filter(([, d]) => d.fields?.isDemo?.booleanValue !== true);
  if (foreign.length) {
    fail(`These ids exist but are NOT demo documents; nothing was written: ${foreign.map(([id]) => id).join(', ')}`);
  }
  console.log(`Existing demo docs: ${existing.size} (will be updated), new: ${records.length - existing.size}`);

  if (!write) {
    console.log('\nDRY RUN — nothing was written. Re-run with --write to apply.');
    return;
  }

  await commit(
    token,
    records.map((r) => ({
      update: { name: docName(r.id), fields: toFields(r) },
      updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }],
    })),
  );

  // Read back and verify every document.
  const after = await batchGet(token, records.map((r) => r.id));
  const bad = records.filter((r) => {
    const d = after.get(r.id);
    const geo = d?.fields?.geo?.mapValue?.fields;
    const point = geo?.geopoint?.geoPointValue;
    return !d || geo?.geohash?.stringValue !== r.geohash ||
      point?.latitude !== r.latitude || point?.longitude !== r.longitude ||
      d.fields.isDemo?.booleanValue !== true || !d.fields.updatedAt?.timestampValue;
  });
  if (bad.length) fail(`Verification failed for: ${bad.map((r) => r.id).join(', ')}`);
  console.log(`\nWROTE and verified ${after.size} demo households in ${PROJECT_ID}/${COLLECTION}.`);
}

async function cleanup(token, write) {
  const rows = await api(token, 'POST', `${API}/${DOCS_PATH}:runQuery`, {
    structuredQuery: {
      from: [{ collectionId: COLLECTION }],
      where: {
        fieldFilter: { field: { fieldPath: 'isDemo' }, op: 'EQUAL', value: { booleanValue: true } },
      },
    },
  });
  const docs = rows
    .map((row) => row.document)
    .filter((d) => d && idOf(d.name).startsWith(ID_PREFIX) && d.fields?.isDemo?.booleanValue === true);

  console.log(`Demo households found: ${docs.length}`);
  if (docs.length) console.log(`  ${docs.map((d) => idOf(d.name)).join(', ')}`);
  if (!write) {
    console.log('\nDRY RUN — nothing was deleted. Re-run with --cleanup --write to delete.');
    return;
  }
  // The updateTime precondition ensures nobody changed a doc since we checked it.
  await commit(
    token,
    docs.map((d) => ({ delete: d.name, currentDocument: { updateTime: d.updateTime } })),
  );
  const left = await batchGet(token, docs.map((d) => idOf(d.name)));
  if (left.size) fail(`Still present after delete: ${[...left.keys()].join(', ')}`);
  console.log(`\nDELETED ${docs.length} demo households. No other documents were touched.`);
}

function readable(fields, top = true) {
  const out = {};
  for (const [key, value] of Object.entries(fields)) {
    if ('stringValue' in value) out[key] = value.stringValue;
    else if ('booleanValue' in value) out[key] = value.booleanValue;
    else if ('mapValue' in value) out[key] = readable(value.mapValue.fields, false);
    else if ('geoPointValue' in value) out[key] = `GeoPoint(${value.geoPointValue.latitude}, ${value.geoPointValue.longitude})`;
  }
  if (top) out.updatedAt = '<server timestamp>';
  return out;
}

async function main() {
  guardProject();
  const args = new Set(process.argv.slice(2));
  const known = new Set(['--write', '--cleanup', '--dry-run']);
  for (const arg of args) if (!known.has(arg)) fail(`Unknown option ${arg}`);
  const write = args.has('--write') && !args.has('--dry-run');

  const token = accessToken();
  await confirmDatabase(token);
  console.log(`Mode:      ${args.has('--cleanup') ? 'cleanup' : 'seed'}${write ? ' (WRITE)' : ' (dry run)'}\n`);
  if (args.has('--cleanup')) await cleanup(token, write);
  else await seed(token, write);
}

main().catch((error) => fail(error.message));
