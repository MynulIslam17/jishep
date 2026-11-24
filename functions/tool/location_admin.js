'use strict';
// Operator tool for primary locations (blueprint §2.1, §2.2).
//
//   status   READ-ONLY: how many users have a valid saved location, how many
//            need the setup screen, how many are pinned on the server.
//            Counts only (no uids, addresses or coordinates printed).
//   correct  moves ONE user's primary location after a support request:
//            explicit operator + reason, max 2 per user per 365 days,
//            audited in location_corrections (src/location.js).
//   history  READ-ONLY: the correction audit for one user.
//
//   node tool/location_admin.js status  --project=<id>
//   node tool/location_admin.js correct --project=<id> --uid=<uid> --lat=<lat> --lon=<lon> \
//        --address="123 Main St, City, ST 00000" --reason="moved (ticket #)" --operator="name" \
//        [--approve=<id>]
//   node tool/location_admin.js history --project=<id> --uid=<uid>
//
// Existing users need no migration: a saved latitude/longitude IS their
// primary location (the rules lock it, the server pins it on first use).
// Users without one are sent to the location setup screen by the app.

const { args, guard, firestoreFor, where } = require('./admin_common');
const { correctPrimaryLocation } = require('../src/location');
const { inUs } = require('../src/owners');

async function status(db) {
  const users = await db.collection('users').select('latitude', 'longitude').get();
  const out = { users: users.size, validLocation: 0, needsSetup: 0, outsideUs: 0, pinned: 0 };
  for (const d of users.docs) {
    const lat = d.get('latitude');
    const lon = d.get('longitude');
    if (typeof lat !== 'number' || typeof lon !== 'number') out.needsSetup++;
    else if (!inUs(lat, lon)) out.outsideUs++;
    else out.validLocation++;
  }
  out.pinned = (await db.collection('primary_locations').count().get()).data().count;
  return out;
}

async function history(db, uid) {
  const snap = await db.collection('location_corrections').where('uid', '==', uid).get();
  return snap.docs.map((d) => ({ id: d.id, at: d.get('at').toDate().toISOString(), operator: d.get('operator'), reason: d.get('reason') }));
}

async function main() {
  const a = args();
  const cmd = a._[0];
  const project = guard(a, { write: cmd === 'correct' });
  const db = firestoreFor(project);
  console.log(`Target: ${where(project)}`);
  if (cmd === 'status') console.log(JSON.stringify(await status(db), null, 2));
  else if (cmd === 'history') console.log(JSON.stringify(await history(db, a.uid), null, 2));
  else if (cmd === 'correct') {
    const r = await correctPrimaryLocation(db, {
      uid: a.uid, latitude: a.lat, longitude: a.lon, address: a.address, reason: a.reason, operator: a.operator,
    });
    console.log(`Corrected. Audit record location_corrections/${r.id}`);
  } else throw new Error('usage: status | correct | history (see header)');
}

if (require.main === module) {
  main().catch((e) => { console.error(e.reason || e.message); process.exit(1); });
}

module.exports = { status, history };
