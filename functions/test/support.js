'use strict';
// Test helper: discoverOwners searches only around the caller's SAVED home
// (users/{uid}.latitude/longitude). Older tests ask about a point directly;
// this saves that point as the caller's home first, then calls the real
// function as a verified account (unless the test says otherwise).
const owners = require('../src/owners');

async function discoverOwnersAtHome({ noHome = false, ...args }) {
  const { db, uid, data } = args;
  if (uid && !noHome && data && data.latitude != null) {
    const home = { latitude: Number(data.latitude), longitude: Number(data.longitude) };
    await db.doc(`users/${uid}`).set(home, { merge: true });
    // The server pins the first home it sees; simulate "this user lives here".
    await db.doc(`primary_locations/${uid}`).set(home);
  }
  return owners.discoverOwners({ verified: true, appVerified: true, ...args });
}

module.exports = { discoverOwnersAtHome };
