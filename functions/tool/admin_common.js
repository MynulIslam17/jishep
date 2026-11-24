'use strict';
// Shared helpers for the operator tools (melissa_ops.js, migrate_cache_ttl.js,
// location_admin.js). They use the Admin SDK:
//   - emulator: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 (no credentials);
//   - a real project: Application Default Credentials of the signed-in
//     operator (`gcloud auth application-default login`), never a key file.
// Writes to a real project are refused unless --approve=<project> matches,
// checked BEFORE connecting. cielo-63925 is always refused.
// None of these tools contains Melissa code: they cannot spend credits.

const FORBIDDEN = new Set(['cielo-63925']);

function args(argv = process.argv.slice(2)) {
  const out = { _: [] };
  for (const a of argv) {
    const m = a.match(/^--([^=]+)(?:=(.*))?$/);
    if (m) out[m[1]] = m[2] === undefined ? true : m[2]; else out._.push(a);
  }
  return out;
}

const emulator = () => Boolean(process.env.FIRESTORE_EMULATOR_HOST);

/** Throws unless the project is allowed (and approved when writing for real). */
function guard(a, { write }) {
  const project = a.project;
  if (!project) throw new Error('--project=<id> is required');
  if (FORBIDDEN.has(project)) throw new Error(`refused: ${project} must never be touched`);
  if (write && !emulator() && a.approve !== project) {
    throw new Error(`refused: writing to PRODUCTION ${project} needs --approve=${project}`);
  }
  return project;
}

/** An Admin SDK Firestore for the project (a named app per project). */
function firestoreFor(project) {
  const { initializeApp, getApps, applicationDefault } = require('firebase-admin/app');
  const { getFirestore } = require('firebase-admin/firestore');
  const name = `tool-${project}`;
  const app = getApps().find((x) => x.name === name) || initializeApp(
    emulator() ? { projectId: project } : { projectId: project, credential: applicationDefault() }, name);
  return getFirestore(app);
}

const where = (project) => (emulator() ? `emulator ${process.env.FIRESTORE_EMULATOR_HOST} (${project})` : `PRODUCTION ${project}`);

module.exports = { args, guard, firestoreFor, where, emulator, FORBIDDEN };
