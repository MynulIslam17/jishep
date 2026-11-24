'use strict';
// Removes everything stored for one user after the account is deleted:
//   users/{uid} and ALL its subcollections (statuses, prayer history,
//     notifications, devices, and the server-written Melissa results:
//     enrichment, gap_areas, owner_areas, owner_scans, owner_properties);
//   melissa_usage/{day}/users/{uid} counters;
//   discovery_jobs/u_{uid}_* (per-user discovery locks);
//   primary_locations/{uid} (the server's pinned home);
//   the uid in discovery_queue requesters (pending lookups).
// Shared (licensed) property data is not personal and is kept.
const { FieldPath } = require('firebase-admin/firestore');
const { removeRequester } = require('./queue');

async function cleanupUser(db, uid) {
  if (!uid) return { users: 0, counters: 0, jobs: 0 };
  await db.recursiveDelete(db.collection('users').doc(uid));
  await db.collection('primary_locations').doc(uid).delete();

  let counters = 0;
  const days = await db.collection('melissa_usage').listDocuments();
  for (let i = 0; i < days.length; i += 400) {
    const batch = db.batch();
    for (const day of days.slice(i, i + 400)) {
      batch.delete(day.collection('users').doc(uid));
      counters++;
    }
    await batch.commit();
  }

  const prefix = `u_${uid}_`;
  const jobs = await db.collection('discovery_jobs')
    .where(FieldPath.documentId(), '>=', prefix)
    .where(FieldPath.documentId(), '<', `${prefix}`)
    .get();
  const batch = db.batch();
  jobs.docs.forEach((d) => batch.delete(d.ref));
  if (jobs.size) await batch.commit();
  // Pending discovery queue: drop this user from waiting jobs.
  const queued = await removeRequester(db, uid);
  return { users: 1, counters, jobs: jobs.size, queued };
}

module.exports = { cleanupUser };
