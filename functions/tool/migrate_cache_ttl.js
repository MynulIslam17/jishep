'use strict';
// 365-day cache policy migration (blueprint §4.3).
//
// Extends the freshness of the shared Melissa cache that is already paid for
// (every root owner_properties answer — named AND negative: not found,
// commercial, no owner — and every root owner_scans) to
// `checkedAt|scannedAt + 365 days`. Negatives follow the scans so a fresh
// scan never makes an excluded address "unknown" again (it would be bought
// twice). Nothing is deleted, no name,
// address, MAK or id changes, and no Melissa request is possible.
//
//   plan     READ-ONLY: counts and the exact documents that would change.
//   backup   writes <dir>/ttl-backup-<id>.json (path, old expiresAt,
//            updateTime) — mode 600, git-ignored location recommended.
//   apply    needs a backup file; updates ONLY expiresAt (+ ttlPolicy
//            metadata) with an updateTime precondition, so a document that
//            changed after the backup is skipped, never overwritten. Only
//            extends: a later expiry is never shortened. Idempotent.
//   verify   READ-ONLY: every eligible document has the 365-day expiry.
//            With --in=<backup.json> it also proves PRESERVATION: every
//            cache document in the backup still exists and its content
//            (all fields except expiresAt / ttlPolicy) has the same SHA-256
//            fingerprint as before (no record lost, no name/address changed).
//   rollback restores the backed-up expiresAt on documents still carrying
//            that migration's id (and removes ttlPolicy).
//
//   node tool/migrate_cache_ttl.js plan     --project=<id> [--days=365]
//   node tool/migrate_cache_ttl.js backup   --project=<id> --out=../.local-backups/ttl-<date>
//   node tool/migrate_cache_ttl.js apply    --project=<id> --in=<backup.json> [--approve=<id>]
//   node tool/migrate_cache_ttl.js verify   --project=<id> [--days=365] [--in=<backup.json>]
//   node tool/migrate_cache_ttl.js rollback --project=<id> --in=<backup.json> [--approve=<id>]

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { args, guard, firestoreFor, where } = require('./admin_common');

const DAY_MS = 864e5;

/** The 365-day expiry a document should have, or null if not eligible. */
function targetExpiry(collection, data, days) {
  if (collection === 'owner_properties' && typeof data.status !== 'string') return null;
  const base = collection === 'owner_scans' ? data.scannedAt : data.checkedAt;
  if (!base || typeof base.toMillis !== 'function') return null;
  return Timestamp.fromMillis(base.toMillis() + days * DAY_MS);
}

const MIGRATION_FIELDS = new Set(['expiresAt', 'ttlPolicy']);

/** Stable JSON-able form of a Firestore value (Timestamps exact to the ns). */
function canonical(v) {
  if (v === null || v === undefined) return null;
  if (Array.isArray(v)) return v.map(canonical);
  if (v instanceof Timestamp) return { $ts: `${v.seconds}.${String(v.nanoseconds).padStart(9, '0')}` };
  if (typeof v === 'object') {
    if (typeof v.latitude === 'number' && typeof v.longitude === 'number' && Object.keys(v).length === 0
      && typeof v.isEqual === 'function') return { $geo: [v.latitude, v.longitude] };
    if (typeof v.path === 'string' && typeof v.firestore === 'object') return { $ref: v.path };
    if (Buffer.isBuffer(v) || v instanceof Uint8Array) return { $bytes: Buffer.from(v).toString('base64') };
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = canonical(v[k]);
    return out;
  }
  return v;
}

/** SHA-256 of a cache document's content, ignoring what the migration
 *  itself writes (expiresAt, ttlPolicy). Same before and after apply. */
function fingerprint(data) {
  const kept = {};
  for (const k of Object.keys(data || {})) if (!MIGRATION_FIELDS.has(k)) kept[k] = data[k];
  return crypto.createHash('sha256').update(JSON.stringify(canonical(kept))).digest('hex');
}

/** path → fingerprint for every root cache document. */
async function manifest(db) {
  const docs = {};
  for (const collection of ['owner_properties', 'owner_scans']) {
    for (const d of (await db.collection(collection).get()).docs) docs[d.ref.path] = fingerprint(d.data());
  }
  return docs;
}

/** Every document in the backup still exists with the same content. */
async function preserved(db, b) {
  if (!b.manifest) throw new Error('backup has no manifest (made before fingerprints); take a new backup');
  const now = await manifest(db);
  const missing = [];
  const changed = [];
  for (const [p, fp] of Object.entries(b.manifest)) {
    if (!(p in now)) missing.push(p);
    else if (now[p] !== fp) changed.push(p);
  }
  const before = Object.keys(b.manifest).length;
  return { ok: missing.length === 0 && changed.length === 0, before, now: Object.keys(now).length, missing, changed };
}

/** Every root cache document with what the policy wants for it. */
async function plan(db, { days = 365 } = {}) {
  const rows = [];
  const counts = { owner_properties: 0, owner_scans: 0, eligible: 0, extend: 0, alreadyOk: 0, ineligible: 0 };
  for (const collection of ['owner_properties', 'owner_scans']) {
    const snap = await db.collection(collection).get();
    counts[collection] = snap.size;
    for (const d of snap.docs) {
      const data = d.data();
      const want = targetExpiry(collection, data, days);
      if (!want) { counts.ineligible++; continue; }
      counts.eligible++;
      const have = data.expiresAt && data.expiresAt.toMillis ? data.expiresAt.toMillis() : 0;
      if (have >= want.toMillis()) { counts.alreadyOk++; continue; }
      counts.extend++;
      rows.push({
        // Exact (nanosecond) update time for the write precondition.
        path: d.ref.path, collection, updateTime: { seconds: d.updateTime.seconds, nanoseconds: d.updateTime.nanoseconds },
        oldExpiresAt: have ? new Date(have).toISOString() : null, newExpiresAt: want.toDate().toISOString(),
      });
    }
  }
  return { days, counts, rows };
}

async function backup(db, { out, days = 365, now = new Date() }) {
  if (!out) throw new Error('--out=<dir> is required');
  const p = await plan(db, { days });
  const docs = await manifest(db);
  const id = `ttl${days}-${now.toISOString().replace(/[-:]/g, '').slice(0, 15)}-${crypto.randomBytes(3).toString('hex')}`;
  fs.mkdirSync(out, { recursive: true, mode: 0o700 });
  const file = path.join(out, `ttl-backup-${id}.json`);
  fs.writeFileSync(file, JSON.stringify({ id, createdAt: now.toISOString(), ...p, manifest: docs }, null, 2), { mode: 0o600 });
  return { file, id, ...p, documents: Object.keys(docs).length };
}

const readBackup = (file) => {
  if (!file) throw new Error('--in=<backup.json> is required');
  const b = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (!b.id || !Array.isArray(b.rows)) throw new Error('not a ttl backup file');
  return b;
};

async function apply(db, { file, now = new Date() }) {
  const b = readBackup(file);
  const result = { updated: 0, skippedChanged: 0, skippedAlreadyOk: 0, missing: 0, id: b.id };
  for (const r of b.rows) {
    const ref = db.doc(r.path);
    const snap = await ref.get();
    if (!snap.exists) { result.missing++; continue; }
    const want = Timestamp.fromDate(new Date(r.newExpiresAt));
    const have = snap.get('expiresAt');
    if (have && have.toMillis() >= want.toMillis()) { result.skippedAlreadyOk++; continue; }
    try {
      await ref.update({
        expiresAt: want,
        ttlPolicy: { days: b.days, migrationId: b.id, previousExpiresAt: r.oldExpiresAt, migratedAt: Timestamp.fromDate(now) },
      }, { lastUpdateTime: new Timestamp(r.updateTime.seconds, r.updateTime.nanoseconds) });
      result.updated++;
    } catch (e) {
      if (e && (e.code === 9 || e.code === 10 || /FAILED_PRECONDITION|ABORTED/.test(String(e.message)))) {
        result.skippedChanged++;
      } else throw e;
    }
  }
  return result;
}

async function verify(db, { days = 365, file } = {}) {
  const p = await plan(db, { days });
  const out = { ok: p.counts.extend === 0, counts: p.counts, remaining: p.rows.map((r) => r.path) };
  if (file) {
    out.preservation = await preserved(db, readBackup(file));
    out.ok = out.ok && out.preservation.ok;
  }
  return out;
}

async function rollback(db, { file }) {
  const b = readBackup(file);
  const result = { restored: 0, skipped: 0 };
  for (const r of b.rows) {
    const ref = db.doc(r.path);
    const snap = await ref.get();
    if (!snap.exists || snap.get('ttlPolicy.migrationId') !== b.id) { result.skipped++; continue; }
    await ref.update({
      expiresAt: r.oldExpiresAt ? Timestamp.fromDate(new Date(r.oldExpiresAt)) : FieldValue.delete(),
      ttlPolicy: FieldValue.delete(),
    }, { lastUpdateTime: snap.updateTime });
    result.restored++;
  }
  return result;
}

async function main() {
  const a = args();
  const cmd = a._[0];
  const write = ['apply', 'rollback'].includes(cmd);
  const project = guard(a, { write });
  const db = firestoreFor(project);
  const days = Number(a.days || 365);
  console.log(`Target: ${where(project)}`);
  let r;
  if (cmd === 'plan') r = await plan(db, { days });
  else if (cmd === 'backup') r = await backup(db, { out: a.out, days });
  else if (cmd === 'apply') r = await apply(db, { file: a.in });
  else if (cmd === 'verify') r = await verify(db, { days, file: a.in });
  else if (cmd === 'rollback') r = await rollback(db, { file: a.in });
  else throw new Error('usage: plan | backup | apply | verify | rollback (see header)');
  const { rows, ...summary } = r;
  console.log(JSON.stringify(summary, null, 2));
  if (rows) console.log(`${rows.length} document(s) would be extended${a.verbose ? `:\n${rows.map((x) => `  ${x.path}  ${x.oldExpiresAt} → ${x.newExpiresAt}`).join('\n')}` : ' (--verbose lists them)'}`);
  if (cmd === 'verify' && !r.ok) process.exitCode = 2;
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message); process.exit(1); });
}

module.exports = { targetExpiry, plan, backup, apply, verify, rollback, fingerprint, manifest, preserved };
