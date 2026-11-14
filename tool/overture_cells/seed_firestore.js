#!/usr/bin/env node
/**
 * Writes household cell files (from build_cells.py) to Firestore as
 * `cells/{prefix}`:
 *
 *   v: string      Overture release
 *   h: Bytes       the .json.gz file, unchanged       (data cells only)
 *   n: int         number of households               (0 on stubs)
 *   split: int     child precision                    (stubs only)
 *
 * Safety:
 *   - Dry-run is the default; nothing is written without --write.
 *   - Production is project `gps-cielo` only; `cielo-63925` is refused.
 *   - Only the `cells` collection is written. Nothing is ever deleted (the
 *     Bangladesh `households` test data is left alone).
 *   - --max-writes (default 18000) keeps a run under the Spark plan's 20k
 *     writes/day. The run stops cleanly and prints how many remain.
 *   - Resumable: a progress file per area and target records what was
 *     written, with a hash of each file. A doc is rewritten when its file
 *     changed since (a rebuilt area). For docs not in the progress file,
 *     those whose v, n (and split) already match in Firestore are skipped.
 *
 * Auth: production uses your gcloud login (`gcloud auth login`) like
 * tool/seed_households; the token is never printed. --emulator talks to the
 * local emulator (FIRESTORE_EMULATOR_HOST, default 127.0.0.1:8080).
 *
 * Usage (from tool/overture_cells):
 *   node seed_firestore.js out/new_jersey                      # dry-run, production
 *   node seed_firestore.js out/new_jersey --emulator           # dry-run, emulator
 *   node seed_firestore.js out/new_jersey --emulator --write
 *   node seed_firestore.js out/california --write --max-writes 18000
 *   node seed_firestore.js out/new_jersey --write --rewrite   # rewrite docs even
 *       if v/n match (content changed but the progress file was lost)
 */
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const PROJECT_ID = 'gps-cielo';
const FORBIDDEN_PROJECTS = ['cielo-63925'];
const COLLECTION = 'cells';
const BATCH = 400;
const MAX_DOC_BYTES = 900 * 1024;

function fail(message) {
  console.error(`\nERROR: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const args = { dir: null, write: false, emulator: false, rewrite: false, maxWrites: 18000 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--write') args.write = true;
    else if (a === '--emulator') args.emulator = true;
    else if (a === '--rewrite') args.rewrite = true;
    else if (a === '--dry-run') args.write = false;
    else if (a === '--max-writes') args.maxWrites = Number(argv[++i]);
    else if (a.startsWith('--max-writes=')) args.maxWrites = Number(a.split('=')[1]);
    else if (a === '-h' || a === '--help') {
      console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]);
      process.exit(0);
    } else if (a.startsWith('-')) fail(`Unknown option ${a}`);
    else if (!args.dir) args.dir = a;
    else fail(`Unexpected argument ${a}`);
  }
  if (!args.dir) fail('Usage: node seed_firestore.js <out/area> [--emulator] [--write] [--max-writes N]');
  if (!Number.isInteger(args.maxWrites) || args.maxWrites <= 0) fail('--max-writes must be a positive integer');
  return args;
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
}

function target(args) {
  if (args.emulator) {
    const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
    return {
      name: 'emulator',
      label: `emulator ${host} (project ${PROJECT_ID})`,
      api: `http://${host}/v1`,
      token: () => 'owner',
    };
  }
  let cached;
  return {
    name: 'production',
    label: `PRODUCTION project ${PROJECT_ID}`,
    api: 'https://firestore.googleapis.com/v1',
    token: () => {
      if (cached) return cached;
      if (process.env.FIRESTORE_ACCESS_TOKEN) return (cached = process.env.FIRESTORE_ACCESS_TOKEN.trim());
      try {
        cached = execFileSync('gcloud', ['auth', 'print-access-token'], {
          encoding: 'utf8',
          stdio: ['ignore', 'pipe', 'ignore'],
        }).trim();
        return cached;
      } catch (_) {
        fail('Could not get a gcloud access token. Run `gcloud auth login` first.');
      }
    },
  };
}

async function api(t, method, url, body) {
  const response = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${t.token()}`,
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
    throw new Error(`${method} ${url.replace(t.api, '')} -> HTTP ${response.status}: ${message}`);
  }
  return text ? JSON.parse(text) : {};
}

/** Every cell file in <dir>/cells, as the document it becomes. */
function loadCells(dir) {
  const cellsDir = path.join(dir, 'cells');
  if (!fs.existsSync(cellsDir)) fail(`No cells folder in ${dir}`);
  const meta = JSON.parse(fs.readFileSync(path.join(dir, 'meta.json'), 'utf8'));
  const cells = [];
  for (const file of fs.readdirSync(cellsDir).sort()) {
    if (!file.endsWith('.json.gz')) continue;
    const prefix = file.slice(0, -'.json.gz'.length);
    if (!/^[0-9bcdefghjkmnpqrstuvwxyz]{5,9}$/.test(prefix)) fail(`Bad cell name ${file}`);
    const gz = fs.readFileSync(path.join(cellsDir, file));
    if (gz.length > MAX_DOC_BYTES) fail(`${file} is ${gz.length} bytes (> 900 KB)`);
    const body = JSON.parse(zlib.gunzipSync(gz).toString('utf8'));
    if (body.p !== prefix) fail(`${file}: p is ${body.p}`);
    if (body.v !== meta.release) fail(`${file}: v ${body.v} != meta release ${meta.release}`);
    const hash = crypto.createHash('sha1').update(gz).digest('hex').slice(0, 16);
    if (body.split) {
      cells.push({ prefix, v: body.v, n: 0, split: body.split, gz: null, hash });
    } else {
      cells.push({ prefix, v: body.v, n: body.h.length, split: null, gz, hash });
    }
  }
  return { meta, cells };
}

function toFields(c) {
  const fields = { v: { stringValue: c.v }, n: { integerValue: String(c.n) } };
  if (c.split) fields.split = { integerValue: String(c.split) };
  else fields.h = { bytesValue: c.gz.toString('base64') };
  return fields;
}

function matches(c, doc) {
  const f = (doc && doc.fields) || {};
  return (
    f.v?.stringValue === c.v &&
    Number(f.n?.integerValue) === c.n &&
    (c.split ? Number(f.split?.integerValue) === c.split : f.split === undefined)
  );
}

const MAX_REQUEST_BYTES = 8 * 1024 * 1024;

/** Splits docs into groups whose encoded size stays under one request. */
function byRequestSize(docs) {
  const parts = [];
  let part = [];
  let size = 0;
  for (const c of docs) {
    const bytes = (c.gz ? Math.ceil(c.gz.length / 3) * 4 : 0) + 512;
    if (part.length && size + bytes > MAX_REQUEST_BYTES) {
      parts.push(part);
      part = [];
      size = 0;
    }
    part.push(c);
    size += bytes;
  }
  if (part.length) parts.push(part);
  return parts;
}

function docName(prefix) {
  return `projects/${PROJECT_ID}/databases/(default)/documents/${COLLECTION}/${prefix}`;
}

/** v / n / split of existing docs (one read each; h is not downloaded). */
async function existing(t, prefixes) {
  const out = await api(t, 'POST', `${t.api}/projects/${PROJECT_ID}/databases/(default)/documents:batchGet`, {
    documents: prefixes.map(docName),
    mask: { fieldPaths: ['v', 'n', 'split'] },
  });
  const found = {};
  for (const r of out) if (r.found) found[r.found.name.split('/').pop()] = r.found;
  return found;
}

function human(bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  let i = 0;
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024;
    i++;
  }
  return `${bytes.toFixed(1)} ${units[i]}`;
}

async function main() {
  guardProject();
  const args = parseArgs(process.argv.slice(2));
  const t = target(args);
  const dir = path.resolve(args.dir);
  const { meta, cells } = loadCells(dir);

  // Kept outside out/<area>/, which a rebuild deletes.
  const progressDir = path.join(path.dirname(dir), '.seed_progress');
  fs.mkdirSync(progressDir, { recursive: true });
  const progressFile = path.join(progressDir, `${path.basename(dir)}.${t.name}.json`);
  const progress = fs.existsSync(progressFile) ? JSON.parse(fs.readFileSync(progressFile, 'utf8')) : {};
  // Written before with exactly this file content (hash of the gz file).
  // A doc skipped because v/n matched (content not compared) is marked
  // matchedOnly; --rewrite does not count it as done.
  const done = (c) => {
    const p = progress[c.prefix];
    return p && p.hash === c.hash && !(args.rewrite && p.matchedOnly);
  };
  // Written before, but the file has changed since (e.g. a rebuilt area):
  // rewrite it without trusting a v/n match in Firestore.
  const changed = (c) => {
    const p = progress[c.prefix];
    return p && p.hash !== c.hash;
  };
  const todo = cells.filter((c) => !done(c));
  const bytes = cells.reduce((s, c) => s + (c.gz ? c.gz.length : 0), 0);
  const households = cells.reduce((s, c) => s + c.n, 0);

  console.log(`Target:      ${t.label}`);
  console.log(`Mode:        ${args.write ? 'WRITE' : 'dry-run (add --write to write)'}` +
    `${args.rewrite ? ', REWRITE (v/n match not trusted)' : ''}`);
  console.log(`Area:        ${path.relative(process.cwd(), dir)} (release ${meta.release})`);
  console.log(`Cell docs:   ${cells.length.toLocaleString()} (${cells.filter((c) => c.split).length} stubs), ` +
    `${households.toLocaleString()} households, ${human(bytes)}`);
  console.log(`In progress file: ${(cells.length - todo.length).toLocaleString()} done, ${todo.length.toLocaleString()} to go`);
  console.log(`This run:    at most ${args.maxWrites.toLocaleString()} writes, ${BATCH} per batch`);

  if (!args.write) {
    const planned = Math.min(todo.length, args.maxWrites);
    console.log(`\nDry-run: would check and write up to ${planned.toLocaleString()} docs ` +
      `(${Math.ceil(planned / BATCH)} batches); ${(todo.length - planned).toLocaleString()} would remain.`);
    console.log('Nothing was read or written.');
    return;
  }

  let writes = 0;
  let skipped = 0;
  let reads = 0;
  let failed = 0;
  for (let i = 0; i < todo.length && writes < args.maxWrites; ) {
    // Never check more docs than can still be written in this run.
    const batch = todo.slice(i, i + Math.min(BATCH, args.maxWrites - writes));
    i += batch.length;
    const found = await existing(t, batch.map((c) => c.prefix));
    reads += batch.length;
    const toWrite = [];
    for (const c of batch) {
      if (!args.rewrite && !changed(c) && matches(c, found[c.prefix])) {
        progress[c.prefix] = { v: c.v, n: c.n, split: c.split, hash: c.hash, matchedOnly: true };
        skipped++;
      } else {
        toWrite.push(c);
      }
    }
    const room = args.maxWrites - writes;
    const now = toWrite.slice(0, room);
    // A request may be at most 10 MiB, so a batch goes out in parts of
    // at most MAX_REQUEST_BYTES (base64 grows the files by a third).
    for (const part of byRequestSize(now)) {
      const res = await api(t, 'POST', `${t.api}/projects/${PROJECT_ID}/databases/(default)/documents:batchWrite`, {
        writes: part.map((c) => ({ update: { name: docName(c.prefix), fields: toFields(c) } })),
      });
      part.forEach((c, k) => {
        const status = res.status && res.status[k];
        if (!status || !status.code) {
          progress[c.prefix] = { v: c.v, n: c.n, split: c.split, hash: c.hash };
          writes++;
        } else {
          failed++;
          console.error(`\n  ${c.prefix}: ${status.message}`);
        }
      });
      fs.writeFileSync(progressFile, JSON.stringify(progress));
    }
    fs.writeFileSync(progressFile, JSON.stringify(progress));
    process.stdout.write(`\r\x1b[K  written ${writes.toLocaleString()}, already there ${skipped.toLocaleString()}, failed ${failed}`);
    if (now.length < toWrite.length) break; // write budget used up
  }

  const remaining = cells.filter((c) => !done(c)).length;
  console.log(`\n\nDone: ${writes.toLocaleString()} written, ${skipped.toLocaleString()} already matched, ` +
    `${failed} failed, ${reads.toLocaleString()} docs checked (reads).`);
  if (remaining) {
    console.log(`${remaining.toLocaleString()} docs remain. Run the same command again ` +
      `(e.g. tomorrow, after the daily quota resets) to continue.`);
  } else {
    console.log('All cell docs for this area are in Firestore.');
  }
  if (failed) process.exitCode = 1;
}

main().catch((e) => fail(e.message));
