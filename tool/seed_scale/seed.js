/**
 * Seeds / removes SYNTHETIC test households for scale testing — in the
 * Firebase Emulator Suite ONLY.
 *
 * Safety (enforced, not optional):
 *   - FIRESTORE_EMULATOR_HOST must be set and point at this machine
 *     (localhost / 127.0.0.1 / ::1). Without it the script exits.
 *   - The project id must start with `demo-` (Firebase "demo" projects exist
 *     only in the emulator and can never reach a real project). `gps-cielo`
 *     and `cielo-63925` are refused by name as well.
 *   - Every document written is marked `isTest: true` and `seedSet: <name>`;
 *     cleanup deletes only documents with that marker and id prefix.
 *
 * Data: deterministic (seeded PRNG) households in Dhaka — very dense old-city
 * clusters, medium clusters and a sparse scatter — plus optional statuses
 * (prayed / visited / invited / follow-up) for one test user, with spread
 * `updatedAt` times.
 *
 * Usage (from tool/seed_scale; the emulator must be running, e.g.
 *   firebase emulators:start --only firestore --project demo-gps-cielo-scale):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node seed.js --size 10000
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node seed.js --size 100000 --statuses 3000
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node seed.js --cleanup
 * Options:
 *   --size N        100 | 1000 | 10000 | 100000 (or any N up to 200000)
 *   --seed S        PRNG seed (default 42); same seed → same data
 *   --statuses N    statuses for --uid (default: 3% of size, max 5000)
 *   --uid U         test user id for statuses (default scale-test-user)
 *   --project P     demo-* project id (default demo-gps-cielo-scale)
 *   --cleanup       delete this tool's test data instead of seeding
 */
'use strict';

const args = parseArgs(process.argv.slice(2));
const PROJECT = args.project || 'demo-gps-cielo-scale';
const SEED_SET = 'scale';
const ID_PREFIX = 'scale_';
const FORBIDDEN = ['gps-cielo', 'cielo-63925'];

function fail(message) {
  console.error(`\nERROR: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) fail(`Unexpected argument: ${a}`);
    const key = a.slice(2);
    if (key === 'cleanup') out.cleanup = true;
    else out[key] = argv[++i];
  }
  return out;
}

function guard() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) {
    fail('FIRESTORE_EMULATOR_HOST is not set. This tool writes to the ' +
      'Firestore emulator only (e.g. FIRESTORE_EMULATOR_HOST=127.0.0.1:8080).');
  }
  const hostname = host.startsWith('[')
    ? host.slice(1, host.indexOf(']'))
    : host.split(':')[0];
  if (!['localhost', '127.0.0.1', '::1'].includes(hostname)) {
    fail(`FIRESTORE_EMULATOR_HOST=${host} is not this machine. Refusing.`);
  }
  if (!PROJECT.startsWith('demo-')) {
    fail(`Project "${PROJECT}" is not a demo-* project. Refusing: only ` +
      'emulator-only demo projects may be seeded.');
  }
  if (FORBIDDEN.some((p) => PROJECT === p)) fail(`Project ${PROJECT} refused.`);
  return `http://${host}/v1/projects/${PROJECT}/databases/(default)/documents`;
}

// --- deterministic data ----------------------------------------------------

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
function geohash(lat, lng, precision = 10) {
  let minLat = -90, maxLat = 90, minLng = -180, maxLng = 180;
  let hash = '', bit = 0, ch = 0, even = true;
  while (hash.length < precision) {
    if (even) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) { ch = (ch << 1) | 1; minLng = mid; } else { ch <<= 1; maxLng = mid; }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; minLat = mid; } else { ch <<= 1; maxLat = mid; }
    }
    even = !even;
    if (++bit === 5) { hash += BASE32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

const DENSE = [[23.7104, 90.4074], [23.7286, 90.4182]]; // Old Dhaka, ~170 m
const MEDIUM = [[23.7460, 90.3760], [23.7808, 90.4067], [23.7210, 90.4830]];
const AREAS = ['Lalbagh', 'Bangshal', 'Dhanmondi', 'Gulshan', 'Demra', 'Mirpur'];

function households(size, seed) {
  const rnd = mulberry32(seed);
  const gauss = () => {
    const u = 1 - rnd(), v = rnd();
    return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  };
  const out = [];
  for (let i = 0; i < size; i++) {
    const r = rnd();
    let lat, lng, area;
    if (r < 0.4) {
      const k = Math.floor(rnd() * DENSE.length);
      lat = DENSE[k][0] + gauss() * 0.0015;
      lng = DENSE[k][1] + gauss() * 0.0015;
      area = AREAS[k];
    } else if (r < 0.8) {
      const k = Math.floor(rnd() * MEDIUM.length);
      lat = MEDIUM[k][0] + gauss() * 0.006;
      lng = MEDIUM[k][1] + gauss() * 0.006;
      area = AREAS[2 + k];
    } else {
      lat = 23.68 + rnd() * 0.16;
      lng = 90.33 + rnd() * 0.18;
      area = AREAS[5];
    }
    const id = `${ID_PREFIX}${String(i).padStart(6, '0')}`;
    out.push({
      id,
      fields: {
        residentName: { stringValue: `Test Household ${i}` },
        address: { stringValue: `${100 + (i % 900)} Test Road, ${area}, Dhaka` },
        isTest: { booleanValue: true },
        seedSet: { stringValue: SEED_SET },
        geo: {
          mapValue: {
            fields: {
              geohash: { stringValue: geohash(lat, lng) },
              geopoint: { geoPointValue: { latitude: lat, longitude: lng } },
            },
          },
        },
      },
    });
  }
  return out;
}

function statuses(homes, count, seed) {
  const rnd = mulberry32(seed + 1);
  const picked = new Set();
  while (picked.size < Math.min(count, homes.length)) {
    picked.add(Math.floor(rnd() * homes.length));
  }
  const now = Date.now();
  return [...picked].map((index, n) => {
    const r = rnd();
    const isPrayed = r < 0.7;
    const isVisited = rnd() < 0.25;
    const isInvited = rnd() < 0.2;
    const hasFollowUp = rnd() < 0.1;
    // Spread over the last 120 days.
    const updated = new Date(now - Math.floor(rnd() * 120 * 86400e3));
    const f = {
      isPrayed: { booleanValue: isPrayed },
      isVisited: { booleanValue: isVisited },
      isInvited: { booleanValue: isInvited },
      hasFollowUp: { booleanValue: hasFollowUp },
      residentName: homes[index].fields.residentName,
      address: homes[index].fields.address,
      isTest: { booleanValue: true },
      seedSet: { stringValue: SEED_SET },
      updatedAt: { timestampValue: updated.toISOString() },
    };
    if (isPrayed) f.prayedAt = { timestampValue: updated.toISOString() };
    if (hasFollowUp) f.notes = { stringValue: `Follow-up note ${n}` };
    return { id: homes[index].id, fields: f };
  });
}

// --- emulator REST ---------------------------------------------------------

async function commit(base, writes) {
  const root = base.replace(/\/documents$/, '');
  for (let i = 0; i < writes.length; i += 500) {
    await fetch(`${root}/documents:commit`, {
      method: 'POST',
      headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
      body: JSON.stringify({ writes: writes.slice(i, i + 500) }),
    }).then(async (res) => {
      if (!res.ok) fail(`commit → ${res.status} ${await res.text()}`);
    });
  }
}

function docName(base, path) {
  const root = base.replace(/^http:\/\/[^/]+\/v1\//, '');
  return `${root}/${path}`;
}

async function seed(base) {
  const size = Number(args.size);
  if (!Number.isInteger(size) || size < 1 || size > 200000) {
    fail('--size must be an integer from 1 to 200000 (100, 1000, 10000, 100000).');
  }
  const seedValue = Number(args.seed ?? 42);
  const uid = args.uid || 'scale-test-user';
  const statusCount = Number(args.statuses ?? Math.min(5000, Math.round(size * 0.03)));

  const homes = households(size, seedValue);
  const started = Date.now();
  await commit(base, homes.map((h) => ({
    update: { name: docName(base, `households/${h.id}`), fields: h.fields },
  })));
  const st = statuses(homes, statusCount, seedValue);
  await commit(base, st.map((s) => ({
    update: {
      name: docName(base, `users/${uid}/household_status/${s.id}`),
      fields: s.fields,
    },
  })));
  console.log(`Seeded ${homes.length} households and ${st.length} statuses ` +
    `(user ${uid}, seed ${seedValue}) into ${PROJECT} on the emulator in ` +
    `${((Date.now() - started) / 1000).toFixed(1)} s.`);
}

async function listMarked(base, collectionPath) {
  const root = base.replace(/\/documents$/, '');
  const parent = collectionPath.includes('/')
    ? `/documents/${collectionPath.split('/').slice(0, -1).join('/')}`
    : '/documents';
  const collectionId = collectionPath.split('/').pop();
  const names = [];
  let startAfter = null;
  while (true) {
    const query = {
      structuredQuery: {
        from: [{ collectionId }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'seedSet' },
            op: 'EQUAL',
            value: { stringValue: SEED_SET },
          },
        },
        orderBy: [{ field: { fieldPath: '__name__' } }],
        select: { fields: [{ fieldPath: '__name__' }] },
        limit: 1000,
        ...(startAfter && {
          startAt: { values: [{ referenceValue: startAfter }], before: false },
        }),
      },
    };
    const rows = await fetch(`${root}${parent}:runQuery`, {
      method: 'POST',
      headers: { Authorization: 'Bearer owner', 'Content-Type': 'application/json' },
      body: JSON.stringify(query),
    }).then((r) => r.json());
    const batch = rows.filter((r) => r.document).map((r) => r.document.name);
    // Only this tool's ids, even among marked documents.
    names.push(...batch.filter((n) => n.split('/').pop().startsWith(ID_PREFIX)));
    if (batch.length < 1000) return names;
    startAfter = batch[batch.length - 1];
  }
}

async function cleanup(base) {
  const uid = args.uid || 'scale-test-user';
  const names = [
    ...(await listMarked(base, 'households')),
    ...(await listMarked(base, `users/${uid}/household_status`)),
  ];
  await commit(base, names.map((name) => ({ delete: name })));
  console.log(`Deleted ${names.length} test documents (seedSet "${SEED_SET}") ` +
    `from ${PROJECT} on the emulator.`);
}

(async () => {
  const base = guard();
  if (args.cleanup) await cleanup(base);
  else await seed(base);
})().catch((e) => fail(e.message));
