// Moves the recovered Rancho del Rey owner records (already paid for) from
// the LOCAL emulator into the canonical SHARED cache of a target Firestore,
// so the cache-first discoverOwners serves them with no new Melissa call.
//
// STEPS, each its own process (run from functions/):
//
//   export   (local emulator only, read-only)
//      FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node tool/migrate_pilot.js export \
//        --uid=<emulator uid> --out=../.local-backups/migration-<date>
//      → snapshot.json (+ snapshot.sha256), mode 600, git-ignored. No keys.
//
//   plan     (target, READ-ONLY): what would be created / already exists /
//      has expired / conflicts. Writes nothing.
//      node tool/migrate_pilot.js plan --project=gps-para-el-cielo --in=<dir>
//
//   apply    (target, WRITES). Refused unless --approve=<project>, checked
//      BEFORE anything connects to the target. (The project owner removed the
//      former --licence requirement on 2026-11-23; no Melissa agreement
//      reference is recorded or implied.)
//      node tool/migrate_pilot.js apply --project=gps-para-el-cielo --in=<dir> \
//        --approve=gps-para-el-cielo
//      Create-only: each write carries the precondition "document does not
//      exist", so an existing document is NEVER overwritten (skipped and
//      reported), even if it appeared after the plan. Expired records are
//      never written. Writes manifest-<id>.json next to the snapshot.
//
//   verify   (target, READ-ONLY): reads every snapshot document back and
//      compares it field by field (the added `migration` field aside).
//
//   rollback (target): deletes ONLY documents listed in a manifest for this
//      target that still carry that migration's id, with an updateTime
//      precondition (a document changed since it was read is kept).
//      node tool/migrate_pilot.js rollback --project=gps-para-el-cielo --in=<dir> \
//        --approve=gps-para-el-cielo
//
// Targets: only `owner_scans/{id}` and `owner_properties/{id}` at the root
// (the canonical shared cache, read by discoverOwners when
// MELISSA_OWNER_SHARED_CACHE=true). Nothing else is touched. Ids, addresses,
// MAKs, coordinates, owners (name, secondName, isCompany, isTrust),
// classification, parcel and dates are copied unchanged; one field
// `migration {id, from, at}` is added. Expiry dates are NOT extended.
//
// Transport: the Firestore REST API, the same code for the emulator
// (FIRESTORE_EMULATOR_HOST set) and a real project (the signed-in gcloud
// account's access token; never printed, no key file). This tool has no
// Melissa code: it cannot make a Melissa request.
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const FORBIDDEN_PROJECTS = new Set(['cielo-63925']);
const COLLECTIONS = ['owner_scans', 'owner_properties'];
const FROM = 'local-emulator-pilot';

function args(argv = process.argv.slice(2)) {
  const out = { _: [] };
  for (const a of argv) {
    const m = a.match(/^--([^=]+)=(.*)$/);
    if (m) out[m[1]] = m[2]; else out._.push(a);
  }
  return out;
}

const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const expiresMs = (doc) => (doc.expiresAt && doc.expiresAt.__ts ? Date.parse(doc.expiresAt.__ts) : NaN);

// ---- snapshot JSON  <->  Firestore REST values ----------------------------
// Snapshot encoding: Timestamp → {__ts: ISO}, GeoPoint → {__geo: [lat, lon]}.
function toRest(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(toRest) } };
  if (typeof v.__ts === 'string') return { timestampValue: v.__ts };
  if (Array.isArray(v.__geo)) return { geoPointValue: { latitude: v.__geo[0], longitude: v.__geo[1] } };
  return { mapValue: { fields: fieldsOf(v) } };
}
const fieldsOf = (obj) => Object.fromEntries(Object.entries(obj).map(([k, x]) => [k, toRest(x)]));

function fromRest(v) {
  if ('nullValue' in v) return null;
  if ('booleanValue' in v) return v.booleanValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return Number(v.doubleValue);
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return { __ts: new Date(v.timestampValue).toISOString() };
  if ('geoPointValue' in v) return { __geo: [v.geoPointValue.latitude || 0, v.geoPointValue.longitude || 0] };
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fromRest);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, fromRest(x)]));
  return undefined;
}

/** Same value? Timestamps compare at millisecond precision. */
function same(a, b) {
  if (a && b && typeof a === 'object' && typeof b === 'object') {
    if (a.__ts && b.__ts) return Date.parse(a.__ts) === Date.parse(b.__ts);
    const ka = Object.keys(a); const kb = Object.keys(b);
    return ka.length === kb.length && ka.every((k) => same(a[k], b[k]));
  }
  return a === b;
}

// ---- target -----------------------------------------------------------------
/** A REST client for one project's (default) database. */
function target(project, { fetchImpl = globalThis.fetch, token } = {}) {
  if (!project) throw new Error('--project is required');
  if (FORBIDDEN_PROJECTS.has(project)) throw new Error(`refused: ${project}`);
  const emu = process.env.FIRESTORE_EMULATOR_HOST;
  const root = `projects/${project}/databases/(default)/documents`;
  const base = emu ? `http://${emu}/v1/${root}` : `https://firestore.googleapis.com/v1/${root}`;
  let bearer = emu ? 'owner' : token;
  const headers = () => {
    if (!bearer) bearer = execFileSync('gcloud', ['auth', 'print-access-token'], { encoding: 'utf8' }).trim();
    return {
      Authorization: `Bearer ${bearer}`,
      'Content-Type': 'application/json',
      ...(emu ? {} : { 'x-goog-user-project': project }),
    };
  };
  async function call(url, init = {}) {
    const res = await fetchImpl(url, { ...init, headers: headers() });
    const body = await res.json().catch(() => ({}));
    return { status: res.status, body };
  }
  const name = (p) => `${root}/${p}`;
  return {
    where: emu ? `emulator ${emu}` : `PRODUCTION project ${project}`,
    /** {exists, data, updateTime} */
    async get(p) {
      const r = await call(`${base}/${p}`);
      if (r.status === 404) return { exists: false };
      if (r.status !== 200) throw new Error(`read ${p}: HTTP ${r.status} ${r.body.error?.status || ''}`);
      return { exists: true, data: fromRest({ mapValue: { fields: r.body.fields || {} } }), updateTime: r.body.updateTime };
    },
    /** 'created' | 'exists'. Never overwrites (precondition exists=false). */
    async create(p, data, migrationId) {
      const r = await call(`${base}:commit`, {
        method: 'POST',
        body: JSON.stringify({
          writes: [{
            update: { name: name(p), fields: { ...fieldsOf(data), migration: toRest({ id: migrationId, from: FROM }) } },
            currentDocument: { exists: false },
            updateTransforms: [{ fieldPath: 'migration.at', setToServerValue: 'REQUEST_TIME' }],
          }],
        }),
      });
      if (r.status === 200) return 'created';
      const s = r.body.error?.status;
      if (r.status === 409 || s === 'ALREADY_EXISTS' || s === 'FAILED_PRECONDITION') return 'exists';
      throw new Error(`create ${p}: HTTP ${r.status} ${s || ''}`);
    },
    /** Deletes only if unchanged since `updateTime`. */
    async remove(p, updateTime) {
      const r = await call(`${base}:commit`, {
        method: 'POST',
        body: JSON.stringify({ writes: [{ delete: name(p), currentDocument: { updateTime } }] }),
      });
      if (r.status === 200) return true;
      const s = r.body.error?.status;
      if (r.status === 409 || s === 'FAILED_PRECONDITION' || s === 'NOT_FOUND') return false;
      throw new Error(`delete ${p}: HTTP ${r.status} ${s || ''}`);
    },
  };
}

function readSnapshot(dir) {
  if (!dir) throw new Error('--in is required');
  const text = fs.readFileSync(path.join(dir, 'snapshot.json'), 'utf8');
  const want = fs.readFileSync(path.join(dir, 'snapshot.sha256'), 'utf8').trim();
  if (sha256(text) !== want) throw new Error('snapshot checksum mismatch: refusing');
  const snap = JSON.parse(text);
  for (const p of Object.keys(snap.docs)) {
    const [c, id, extra] = p.split('/');
    if (!COLLECTIONS.includes(c) || !id || extra !== undefined) throw new Error(`unexpected path in snapshot: ${p}`);
  }
  return snap;
}

// ---- steps ------------------------------------------------------------------
async function exportStep(a) {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('export reads the LOCAL emulator only (set FIRESTORE_EMULATOR_HOST)');
  if (!a.uid || !a.out) throw new Error('--uid and --out are required');
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: a.source || 'gps-para-el-cielo' });
  const db = admin.firestore();
  const encode = (v) => {
    if (v instanceof admin.firestore.Timestamp) return { __ts: v.toDate().toISOString() };
    if (v instanceof admin.firestore.GeoPoint) return { __geo: [v.latitude, v.longitude] };
    if (Array.isArray(v)) return v.map(encode);
    if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, encode(x)]));
    return v;
  };
  const snapshot = { createdAt: new Date().toISOString(), sourceUid: a.uid, docs: {} };
  for (const c of COLLECTIONS) {
    const docs = await db.collection(`users/${a.uid}/${c}`).get();
    for (const d of docs.docs) snapshot.docs[`${c}/${d.id}`] = encode(d.data());
  }
  fs.mkdirSync(a.out, { recursive: true, mode: 0o700 });
  const text = JSON.stringify(snapshot);
  fs.writeFileSync(path.join(a.out, 'snapshot.json'), text, { mode: 0o600 });
  fs.writeFileSync(path.join(a.out, 'snapshot.sha256'), `${sha256(text)}\n`, { mode: 0o600 });
  const props = Object.entries(snapshot.docs).filter(([k]) => k.startsWith('owner_properties/'));
  return {
    exported: Object.keys(snapshot.docs).length,
    scans: Object.keys(snapshot.docs).length - props.length,
    properties: props.length,
    named: props.filter(([, v]) => v.status === 'named').length,
    out: a.out,
  };
}

async function planStep(a, deps = {}) {
  const snap = readSnapshot(a.in);
  const t = target(a.project, deps);
  const now = (deps.now || new Date()).getTime();
  const report = { mode: 'plan (read-only)', target: t.where, create: 0, exists: 0, expired: 0, conflicts: [] };
  for (const [p, v] of Object.entries(snap.docs)) {
    if (!(expiresMs(v) > now)) { report.expired++; continue; }
    const cur = await t.get(p);
    if (!cur.exists) { report.create++; continue; }
    report.exists++;
    if (cur.data.migration?.from !== FROM) report.conflicts.push(p);
  }
  const exp = Object.values(snap.docs).map(expiresMs).filter(Number.isFinite);
  report.earliestExpiry = new Date(Math.min(...exp)).toISOString().slice(0, 10);
  return report;
}

/** Checked before anything connects to the target. */
function requireApproval(a, { write }) {
  if (!a.project) throw new Error('--project is required');
  if (FORBIDDEN_PROJECTS.has(a.project)) throw new Error(`refused: ${a.project}`);
  if (a.approve !== a.project) throw new Error(`refused: --approve=${a.project} is required`);
}

async function applyStep(a, deps = {}) {
  requireApproval(a, { write: true });
  const snap = readSnapshot(a.in);
  const t = target(a.project, deps);
  const now = (deps.now || new Date()).getTime();
  const id = `pilot-${new Date().toISOString().replace(/[:.]/g, '-')}-${crypto.randomBytes(3).toString('hex')}`;
  const manifest = { id, project: a.project, target: t.where, authorization: process.env.FIRESTORE_EMULATOR_HOST
    ? 'local emulator'
    : 'project owner instruction (--approve); no Melissa agreement reference recorded', created: [], skipped: [], expired: [] };
  for (const [p, v] of Object.entries(snap.docs)) {
    if (!(expiresMs(v) > now)) { manifest.expired.push(p); continue; }
    if ((await t.create(p, v, id)) === 'created') manifest.created.push(p); else manifest.skipped.push(p);
  }
  // Only a migration that wrote something needs a manifest for rollback.
  const file = manifest.created.length ? `manifest-${id}.json` : null;
  if (file) fs.writeFileSync(path.join(a.in, file), JSON.stringify(manifest, null, 1), { mode: 0o600 });
  return { mode: 'apply', target: t.where, id, created: manifest.created.length, skipped: manifest.skipped.length,
    expiredNotWritten: manifest.expired.length, manifest: file };
}

async function verifyStep(a, deps = {}) {
  const snap = readSnapshot(a.in);
  const t = target(a.project, deps);
  const report = { mode: 'verify (read-only)', target: t.where, identical: 0, missing: [], different: [], notOurs: [] };
  for (const [p, v] of Object.entries(snap.docs)) {
    const cur = await t.get(p);
    if (!cur.exists) { report.missing.push(p); continue; }
    const { migration, ...data } = cur.data;
    if (migration?.from !== FROM) report.notOurs.push(p);
    if (same(data, v)) report.identical++; else report.different.push(p);
  }
  return report;
}

async function rollbackStep(a, deps = {}) {
  requireApproval(a, { write: false });
  if (!a.in) throw new Error('--in is required');
  const t = target(a.project, deps);
  const files = fs.readdirSync(a.in).filter((f) => f.startsWith('manifest-'));
  let deleted = 0; let kept = 0;
  for (const f of files) {
    const m = JSON.parse(fs.readFileSync(path.join(a.in, f), 'utf8'));
    if (m.project !== a.project || m.target !== t.where) continue;
    for (const p of m.created) {
      const cur = await t.get(p);
      // Only documents this migration created and nobody has changed since.
      if (cur.exists && cur.data.migration?.id === m.id && await t.remove(p, cur.updateTime)) deleted++; else kept++;
    }
  }
  return { mode: 'rollback', target: t.where, deleted, notOurs: kept };
}

const STEPS = { export: exportStep, plan: planStep, apply: applyStep, verify: verifyStep, rollback: rollbackStep };

if (require.main === module) {
  (async () => {
    const a = args();
    const step = STEPS[a._[0]];
    if (!step) throw new Error('usage: migrate_pilot.js export|plan|apply|verify|rollback --...');
    console.log(JSON.stringify(await step(a)));
  })().catch((e) => { console.error(e.message); process.exitCode = 1; });
}

module.exports = { args, toRest, fromRest, same, target, readSnapshot, planStep, applyStep, verifyStep, rollbackStep, requireApproval };
