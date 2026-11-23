'use strict';
// Cache-first property index for the Melissa-first neighborhood.
//
// Two kinds of stored facts, each stored ONCE under a stable id:
//
//   owner_scans/{scanId}       one Melissa Reverse GeoCoder answer: the
//                              deliverable addresses nearest a center, and
//                              the disc it proves complete (`coveredMeters`).
//   owner_properties/{id}      one Property LookupProperty answer per Melissa
//                              Address Key (id `mel:<MAK>`, the same id the
//                              app already uses for households): recorded
//                              owner + property use, or why it was excluded
//                              (negative cache).
//
// Where they live (the "scope") depends on the Melissa licence:
//   shared (MELISSA_OWNER_SHARED_CACHE=true): root collections, reused by
//     every user and every overlapping search;
//   per user (default): users/{uid}/owner_scans, users/{uid}/owner_properties
//     (same code, reuse only within one user's own searches).
// Clients can never read or write either scope (firestore.rules); results
// reach the app only through the discoverOwners function.
//
// Nearest-K with coverage (serve):
//   1. load the valid scans whose disc can reach the search disc
//      (geohash-5 cells around the point, so cell boundaries never hide one);
//   2. merge their addresses (hash map by id = dedupe), sort by distance;
//   3. R = the radius around the point that the union of scan discs covers
//      (every deliverable address within R is known);
//   4. walk addresses nearest first, reading their property facts, until K
//      named homes are found;
//   5. COMPLETE only if the K-th named home lies within R and every closer
//      address is resolved; otherwise PARTIAL with exactly what is missing.

const crypto = require('crypto');
const { Timestamp } = require('firebase-admin/firestore');

const EARTH_M = 6371008.8;
const MILE_M = 1609.344;
const rad = (d) => (d * Math.PI) / 180;

function haversineMeters(lat1, lon1, lat2, lon2) {
  const dLat = rad(lat2 - lat1);
  const dLon = rad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(lat1)) * Math.cos(rad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** The point `meters` away from (lat, lon) at `bearing` radians (short distances). */
function offset(lat, lon, meters, bearing) {
  const dLat = (meters * Math.cos(bearing)) / 111320;
  const dLon = (meters * Math.sin(bearing)) / (111320 * Math.cos(rad(lat)));
  return [lat + dLat, lon + dLon];
}

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';
function geohash(lat, lon, precision) {
  let latLo = -90; let latHi = 90; let lonLo = -180; let lonHi = 180;
  let out = ''; let bit = 0; let ch = 0; let even = true;
  while (out.length < precision) {
    if (even) {
      const mid = (lonLo + lonHi) / 2;
      if (lon >= mid) { ch = (ch << 1) | 1; lonLo = mid; } else { ch <<= 1; lonHi = mid; }
    } else {
      const mid = (latLo + latHi) / 2;
      if (lat >= mid) { ch = (ch << 1) | 1; latLo = mid; } else { ch <<= 1; latHi = mid; }
    }
    even = !even;
    if (++bit === 5) { out += BASE32[ch]; bit = 0; ch = 0; }
  }
  return out;
}

/**
 * Every geohash cell of `precision` that touches the box of ±`meters` around
 * the point (so a scan just across a cell boundary is still found).
 */
function cellsAround(lat, lon, meters, precision = 5) {
  const dLat = meters / 111320;
  const dLon = meters / (111320 * Math.max(0.01, Math.cos(rad(lat))));
  // Smaller than half a precision-5 cell (0.0439°) in both directions.
  const step = 0.02;
  const cells = new Set();
  for (let a = lat - dLat; a <= lat + dLat + step; a += step) {
    for (let o = lon - dLon; o <= lon + dLon + step; o += step) {
      cells.add(geohash(Math.min(a, lat + dLat), Math.min(o, lon + dLon), precision));
    }
  }
  return [...cells];
}

/**
 * The largest radius around (lat, lon), up to `maxMeters`, whose whole disc
 * lies inside the union of the scan discs. Sampled on rings every
 * `stepMeters` (points at most `stepMeters` apart) and reported one step
 * short, so it errs on the side of "not covered".
 */
function coveredRadius(lat, lon, discs, maxMeters, stepMeters = 10) {
  if (!discs.length) return 0;
  const inside = (pLat, pLon) => discs.some((d) => haversineMeters(pLat, pLon, d.latitude, d.longitude) <= d.radius);
  if (!inside(lat, lon)) return 0;
  // A disc around the point inside ONE scan disc is covered without sampling.
  let best = 0;
  for (const d of discs) {
    best = Math.max(best, d.radius - haversineMeters(lat, lon, d.latitude, d.longitude));
  }
  if (discs.length === 1 || best >= maxMeters) return Math.max(0, Math.min(best, maxMeters));
  let r = Math.max(stepMeters, Math.floor(best / stepMeters) * stepMeters);
  for (; r <= maxMeters; r += stepMeters) {
    const n = Math.max(8, Math.ceil((2 * Math.PI * r) / stepMeters));
    for (let i = 0; i < n; i++) {
      const [pLat, pLon] = offset(lat, lon, r, (2 * Math.PI * i) / n);
      if (!inside(pLat, pLon)) return Math.max(best, r - stepMeters);
    }
  }
  return maxMeters;
}

/** Firestore collections for a scope (shared or one user's). */
function scopeOf(db, { shared, uid }) {
  const base = shared ? db : db.collection('users').doc(uid);
  return {
    id: shared ? 'shared' : `u_${uid}`,
    scans: base.collection('owner_scans'),
    properties: base.collection('owner_properties'),
  };
}

/** Deterministic scan id: same center (≈11 m) + same options = same document. */
const scanIdFor = (lat, lon, opts) => `${lat.toFixed(4)}_${lon.toFixed(4)}_${opts}`;

const SCAN_OPTIONS = 'r100_noapt';

/** A Reverse GeoCoder answer as a scan document. */
function scanDoc({ latitude, longitude, records, recs, miles, now, days }) {
  const candidates = records.map((r) => ({
    id: r.id, mak: r.mak || null, line: r.line, city: r.city || null, state: r.state || null,
    zip: r.zip || null, latitude: r.latitude, longitude: r.longitude,
    units: r.units || 0, suite: r.suite || null,
  }));
  const capped = records.length >= recs;
  const farthest = candidates.reduce(
    (m, c) => Math.max(m, haversineMeters(latitude, longitude, c.latitude, c.longitude)), 0);
  return {
    version: 1,
    source: 'melissa_reverse_geocoder',
    options: SCAN_OPTIONS,
    center: { latitude, longitude },
    geohash5: geohash(latitude, longitude, 5),
    requestedMeters: miles * MILE_M,
    // Capped at `recs`: complete only up to the farthest returned address
    // (1 m margin for ties); otherwise the whole requested radius.
    coveredMeters: capped ? Math.max(0, farthest - 1) : miles * MILE_M,
    capped,
    recordCount: candidates.length,
    candidates,
    scannedAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + days * 864e5),
  };
}

const NAMED = 'named';

/** A Property answer (or exclusion) as an owner_properties document. */
function propertyDoc({ candidate, status, property, classification, now, days }) {
  const named = status === NAMED;
  return {
    version: 1,
    id: candidate.id,
    mak: candidate.mak || (property && property.mak) || null,
    status,
    line: candidate.line, city: candidate.city || null, state: candidate.state || null, zip: candidate.zip || null,
    latitude: candidate.latitude, longitude: candidate.longitude,
    geohash: geohash(candidate.latitude, candidate.longitude, 9),
    parcelId: (property && property.parcelId) || null,
    // Owner data only on named records (never on exclusions).
    owner: named ? {
      name: property.owner.name,
      secondName: property.owner.secondName || null,
      isCompany: property.owner.isCompany === true,
      isTrust: property.owner.isTrust === true,
    } : null,
    classification: classification || null,
    yearBuilt: (named && property.yearBuilt) || null,
    source: 'melissa_property',
    checkedAt: Timestamp.fromDate(now),
    expiresAt: Timestamp.fromMillis(now.getTime() + days * 864e5),
  };
}

const valid = (doc, now) => {
  const exp = doc && doc.expiresAt;
  return Boolean(exp && exp.toMillis() > now.getTime());
};

async function loadScans(scope, lat, lon, { maxScanMeters, searchMeters, now }) {
  const cells = cellsAround(lat, lon, maxScanMeters + searchMeters);
  const docs = [];
  for (let i = 0; i < cells.length; i += 30) {
    const snap = await scope.scans.where('geohash5', 'in', cells.slice(i, i + 30)).get();
    docs.push(...snap.docs);
  }
  const live = [];
  let expired = 0;
  let reads = Math.max(1, docs.length);
  for (const d of docs) {
    const s = d.data();
    const reach = haversineMeters(lat, lon, s.center.latitude, s.center.longitude) - s.coveredMeters;
    if (reach > searchMeters) continue; // cannot touch the search disc
    if (valid(s, now)) live.push({ id: d.id, ...s }); else expired++;
  }
  return { scans: live, expired, reads };
}

/**
 * Nearest `target` named homes around the point from the cache only.
 * Returns {records, completeness, coveredMeters, unresolved, stats, reads}.
 */
async function serveFromCache(scope, { latitude, longitude, target, now, cfg }) {
  const searchMeters = cfg.maxMiles * MILE_M;
  const { scans, expired, reads: scanReads } = await loadScans(scope, latitude, longitude, {
    maxScanMeters: cfg.maxScanMiles * MILE_M, searchMeters, now,
  });
  const stats = {
    scans: scans.length, expiredScans: expired, candidates: 0, duplicateAddresses: 0,
    unitsSkipped: 0, resolved: 0, unresolved: 0, excluded: 0, duplicateParcel: 0,
    expiredProperties: 0, named: 0, propertyReads: 0,
  };
  // Hash map by id: an address seen by several scans counts once.
  const byId = new Map();
  for (const s of scans) {
    for (const c of s.candidates) {
      if (byId.has(c.id)) { stats.duplicateAddresses++; continue; }
      byId.set(c.id, { ...c, distanceMeters: haversineMeters(latitude, longitude, c.latitude, c.longitude) });
    }
  }
  const all = [...byId.values()].sort((a, b) => a.distanceMeters - b.distanceMeters);
  stats.candidates = all.length;
  const covered = coveredRadius(latitude, longitude,
    scans.map((s) => ({ latitude: s.center.latitude, longitude: s.center.longitude, radius: s.coveredMeters })),
    searchMeters, cfg.coverageStepMeters);

  const named = [];
  const unresolved = [];
  const parcels = new Set();
  let firstUnresolved = Infinity;
  const CHUNK = 60;
  let i = 0;
  while (i < all.length && named.length < target) {
    const chunk = [];
    for (; i < all.length && chunk.length < CHUNK; i++) {
      const c = all[i];
      if (c.suite || (!cfg.includeMultiFamily && c.units > 0)) { stats.unitsSkipped++; continue; }
      chunk.push(c);
    }
    if (!chunk.length) break;
    const snaps = await scope.properties.firestore.getAll(...chunk.map((c) => scope.properties.doc(c.id)));
    stats.propertyReads += snaps.length;
    for (let j = 0; j < chunk.length; j++) {
      const c = chunk[j];
      const p = snaps[j].exists ? snaps[j].data() : null;
      if (p && !valid(p, now)) stats.expiredProperties++;
      if (!p || !valid(p, now)) {
        unresolved.push(c);
        firstUnresolved = Math.min(firstUnresolved, c.distanceMeters);
        continue;
      }
      stats.resolved++;
      if (p.status !== NAMED || !p.owner || !p.owner.name) { stats.excluded++; continue; }
      if (named.length >= target) continue;
      if (p.parcelId) {
        if (parcels.has(p.parcelId)) { stats.duplicateParcel++; continue; }
        parcels.add(p.parcelId);
      }
      named.push({
        id: p.id, line: p.line, city: p.city, state: p.state, zip: p.zip,
        latitude: p.latitude, longitude: p.longitude,
        distanceMeters: Math.round(c.distanceMeters),
        owner: p.owner, classification: p.classification, yearBuilt: p.yearBuilt || null,
        source: p.source,
      });
    }
  }
  stats.named = named.length;
  stats.unresolved = unresolved.length;
  const lastNamed = named.length ? named[named.length - 1].distanceMeters : 0;

  let completeness;
  if (!scans.length) completeness = expired ? 'expired' : 'unknown';
  else if (named.length >= target && lastNamed <= covered && firstUnresolved >= lastNamed) completeness = 'complete';
  else if (covered >= searchMeters && !unresolved.some((c) => c.distanceMeters <= covered)) {
    // Every address in the whole search radius is resolved: fewer exist.
    completeness = named.length ? 'complete' : 'empty';
  } else completeness = 'partial';

  // Addresses per m² in the stored scans (to estimate unseen addresses).
  const area = scans.reduce((a, x) => a + Math.PI * x.coveredMeters ** 2, 0);
  const density = area > 0 ? scans.reduce((a, x) => a + x.recordCount, 0) / area : 0;
  return {
    records: named, completeness, coveredMeters: Math.round(covered), density,
    unresolved: unresolved.filter((c) => c.distanceMeters <= covered),
    scansNearPoint: scans.filter((s) => haversineMeters(latitude, longitude, s.center.latitude, s.center.longitude) <= 25),
    stats, reads: scanReads + stats.propertyReads,
  };
}

/**
 * What a paid discovery would still need here (for reports and budgets).
 *
 *   fill:  reach `target` named homes (the default paid behaviour);
 *   prove: also make the result provably the nearest `target` (look up
 *          unresolved addresses closer than the farthest shown home, and scan
 *          here when the stored scans do not reach that far). Only paid for
 *          when `completeCoverage` is on.
 *
 * `namedRate` = expected share of looked-up addresses that end up named
 * (Rancho del Rey pilot: 50 of 52).
 */
function planMissing(served, { target, cfg }) {
  const none = { scanNeeded: false, lookupsNeeded: 0, estimatedCredits: 0, lookupIds: [] };
  if (served.completeness === 'complete' || served.completeness === 'empty') {
    return { ...none, fill: none, prove: none };
  }
  const scanHere = served.scansNearPoint.length > 0;
  const scanCost = cfg.reverseRecords * 2;
  const credits = (scan, lookups) => (scan ? scanCost : 0) + lookups * 9;

  // Fill: named homes still missing.
  const short = Math.max(0, target - served.records.length);
  let fill = none;
  let exhaustedAtPoint = false;
  if (short > 0) {
    const want = Math.ceil(short / Math.max(0.05, cfg.namedRate));
    const fromKnown = Math.min(served.unresolved.length, want, cfg.maxLookups);
    const knownEnough = served.unresolved.length * cfg.namedRate >= short;
    // A scan at this very point already exists: another one returns the
    // same addresses (Melissa returns at most 100), so it would not help.
    const scanNeeded = !knownEnough && !scanHere;
    exhaustedAtPoint = !knownEnough && scanHere;
    const lookups = scanNeeded ? Math.min(cfg.maxLookups, Math.max(fromKnown, want)) : fromKnown;
    fill = {
      scanNeeded, lookupsNeeded: lookups, estimatedCredits: credits(scanNeeded, lookups),
      lookupIds: served.unresolved.slice(0, fromKnown).map((c) => c.id),
    };
  }

  // Prove: nothing closer than the farthest shown home may be unknown.
  const last = served.records.length >= target
    ? served.records[target - 1].distanceMeters : Infinity;
  const closer = served.unresolved.filter((c) => c.distanceMeters < last);
  const proveScan = !scanHere && last > served.coveredMeters;
  // Addresses a new scan would reveal closer than the farthest shown home
  // (estimated from the stored scans' address density).
  const unseen = proveScan && Number.isFinite(last) && served.density > 0
    ? Math.ceil(served.density * Math.PI * (last ** 2 - Math.min(last, served.coveredMeters) ** 2)) : 0;
  const proveLookups = Math.min(cfg.maxLookups, Math.max(fill.lookupsNeeded, closer.length + unseen));
  const prove = {
    scanNeeded: fill.scanNeeded || proveScan,
    lookupsNeeded: proveLookups,
    estimatedCredits: credits(fill.scanNeeded || proveScan, proveLookups),
    lookupIds: closer.slice(0, proveLookups).map((c) => c.id),
  };
  const chosen = cfg.completeCoverage ? prove : fill;
  return { ...chosen, fill, prove, exhaustedAtPoint };
}

const jobIdFor = (scopeId, lat, lon) => `${scopeId}_${geohash(lat, lon, 6)}`;
const newLeaseOwner = () => crypto.randomBytes(8).toString('hex');

module.exports = {
  MILE_M, NAMED, SCAN_OPTIONS,
  haversineMeters, offset, geohash, cellsAround, coveredRadius,
  scopeOf, scanIdFor, scanDoc, propertyDoc, loadScans, serveFromCache, planMissing,
  jobIdFor, newLeaseOwner,
};
