'use strict';
// Administrator-authorized primary-location correction (blueprint §2.1).
//
// Ordinary users choose their primary location ONCE at signup; the app has no
// control to change it and the Firestore rules refuse a client change of
// users/{uid}.latitude/longitude/address once set. When a user moves or
// picked a wrong address, support corrects it here:
//
//   - explicit: needs the operator's name and a written reason;
//   - rate-limited: at most `maxPerYear` corrections per user per 365 days;
//   - auditable: one immutable location_corrections/{id} document per change
//     (who, when, from, to, reason), server-only;
//   - cost-safe: moving a home buys nothing by itself. The next neighborhood
//     request is cache-first and every paid path keeps its budgets, so a
//     correction can never trigger an unbounded Melissa spend;
//   - preserves history: prayer status, prayer log, rounds and follow-ups are
//     NOT touched (a new prayer round starts on the next app open).
//
// Run only from tool/location_admin.js (operator credentials). There is no
// callable function for it, so no client can reach this code.

const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { inUs } = require('./owners');

class LocationError extends Error {
  constructor(reason) {
    super(reason);
    this.reason = reason;
  }
}

const DEFAULTS = { maxPerYear: 2 };

function validateCorrection({ uid, latitude, longitude, address, reason, operator }) {
  if (typeof uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(uid)) throw new LocationError('bad_uid');
  const lat = Number(latitude);
  const lon = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) throw new LocationError('bad_location');
  if (!inUs(lat, lon)) throw new LocationError('outside_us');
  if (typeof address !== 'string' || !address.trim() || address.length > 300) throw new LocationError('bad_address');
  if (typeof reason !== 'string' || reason.trim().length < 5 || reason.length > 500) throw new LocationError('reason_required');
  if (typeof operator !== 'string' || !operator.trim() || operator.length > 120) throw new LocationError('operator_required');
  return { uid, latitude: lat, longitude: lon, address: address.trim(), reason: reason.trim(), operator: operator.trim() };
}

/**
 * Moves one user's primary location (users/{uid} + primary_locations/{uid})
 * and writes the audit record, in one transaction. Returns the audit id.
 */
async function correctPrimaryLocation(db, input, { now = new Date(), config = {} } = {}) {
  const cfg = { ...DEFAULTS, ...config };
  const c = validateCorrection(input);
  const userRef = db.collection('users').doc(c.uid);
  const pinRef = db.collection('primary_locations').doc(c.uid);
  const auditRef = db.collection('location_corrections').doc();
  const yearAgo = Timestamp.fromMillis(now.getTime() - 365 * 864e5);
  const recent = db.collection('location_corrections')
    .where('uid', '==', c.uid).where('at', '>=', yearAgo);

  await db.runTransaction(async (tx) => {
    const [user, pin, prior] = await Promise.all([tx.get(userRef), tx.get(pinRef), tx.get(recent)]);
    if (!user.exists) throw new LocationError('no_such_user');
    if (prior.size >= cfg.maxPerYear) throw new LocationError('rate_limited');
    const from = {
      latitude: user.get('latitude') ?? null,
      longitude: user.get('longitude') ?? null,
      address: user.get('address') ?? null,
      pinned: pin.exists ? { latitude: pin.get('latitude'), longitude: pin.get('longitude') } : null,
    };
    const at = Timestamp.fromDate(now);
    const version = (pin.exists ? pin.get('version') || 1 : 1) + (pin.exists ? 1 : 0);
    tx.set(userRef, {
      latitude: c.latitude, longitude: c.longitude, address: c.address,
      locationConfirmedAt: at, locationVersion: version, updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(pinRef, {
      latitude: c.latitude, longitude: c.longitude, version, source: 'admin_correction',
      pinnedAt: at, correctionId: auditRef.id,
    });
    tx.create(auditRef, {
      uid: c.uid, at, operator: c.operator, reason: c.reason, from,
      to: { latitude: c.latitude, longitude: c.longitude, address: c.address }, version,
    });
  });
  return { id: auditRef.id };
}

module.exports = { correctPrimaryLocation, validateCorrection, LocationError, LOCATION_DEFAULTS: DEFAULTS };
