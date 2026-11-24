'use strict';
// Pending owner-discovery queue (2026-11-24).
//
// When a genuine, verified user's neighborhood is not cached and the paid
// budget is used up (app daily / monthly limit, Melissa out-of-credits
// pause, kill switch), discoverOwners serves what is stored and records the
// area here instead of dropping the request. A scheduled run
// (processDiscoveryQueue) resumes the lookup once the budget allows it.
//
//   discovery_queue/{jobId}   server-only (rules: no client access)
//     jobId = the discovery lease id: scope + geohash-6 cell of the home,
//     so every user of one area shares ONE job (deduplicated).
//     {status: queued|done|cancelled|expired|failed, scopeId, area,
//      requesters: {uid: {appCheck, at}}  (max queueMaxRequesters),
//      createdAt, updatedAt, nextAttemptAt, claimUntil, attempts,
//      lastReason, expiresAt, finishedAt, credits, completeness}
//
// Abuse limits (repeated sign-ups, scripts):
//   - only requests that passed every paid gate are queued: signed in,
//     verified account, valid App Check token, server-side saved home;
//   - one job per area, however many users ask (homes are locked, so one
//     account can only ever be in one area's job);
//   - at most queueDailyNew NEW jobs per UTC day (transactional counter)
//     and queueMaxOpen jobs waiting at once; jobs expire after
//     queueMaxAgeDays;
//   - processing goes through discoverOwners itself: cache first, the
//     requester's verified status and App Check flag and home re-checked,
//     then the same atomic reservation (per request, per user per day, app
//     per day / month, global daily, kill switch, out-of-credits pause).
//     The queue never has its own budget, so it cannot spend past the
//     limits; it stops a run at the first budget refusal.
//
// Nothing here touches prayer data (users/*) or the cache policy: answers
// are stored by discoverOwners with the configured 365-day freshness.
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { paidDisabled } = require('./budget');

const COLLECTION = 'discovery_queue';

// Budget refusals that queue the area (a security refusal never does).
const QUEUE_REASONS = new Set(['app_daily_limit', 'app_monthly_limit', 'out_of_credits', 'paid_disabled']);

const QUEUE_DEFAULTS = {
  queueEnabled: true,
  queueMaxOpen: 200,
  queueDailyNew: 50,
  queueMaxRequesters: 20,
  queueMaxAgeDays: 30,
  queueMaxAttempts: 5,
  queueRetryMs: 60 * 60 * 1000,
  queuePendingRetryMs: 10 * 60 * 1000,
  queueClaimMs: 10 * 60 * 1000,
  queueJobsPerRun: 5,
};

const dayKey = (now) => now.toISOString().slice(0, 10);
const ts = (ms) => Timestamp.fromMillis(ms);

async function openJobs(db) {
  const snap = await db.collection(COLLECTION).where('status', '==', 'queued').count().get();
  return snap.data().count;
}

/**
 * Records (or joins) the pending discovery for an area. Returns
 * `{queued: true, created}` or `{queued: false, why}` (queue_full,
 * queue_daily_limit, queue_disabled).
 */
async function enqueueDiscovery(db, { jobId, scopeId, area, uid, appVerified, reason, now, cfg }) {
  const c = { ...QUEUE_DEFAULTS, ...cfg };
  if (!c.queueEnabled) return { queued: false, why: 'queue_disabled' };
  if (!QUEUE_REASONS.has(reason)) return { queued: false, why: 'not_queueable' };
  const ref = db.collection(COLLECTION).doc(jobId);
  const day = db.collection('melissa_usage').doc(dayKey(now));
  // Approximate (outside the transaction); the credit limits are exact.
  const open = await openJobs(db);
  const at = ts(now.getTime());
  const entry = { appCheck: Boolean(appVerified), at };
  return db.runTransaction(async (tx) => {
    const [job, d] = await Promise.all([tx.get(ref), tx.get(day)]);
    if (job.exists && job.get('status') === 'queued') {
      const requesters = job.get('requesters') || {};
      if (!requesters[uid] && Object.keys(requesters).length < c.queueMaxRequesters) {
        tx.update(ref, { requesters: { ...requesters, [uid]: entry }, updatedAt: at, lastReason: reason });
      } else {
        tx.update(ref, { updatedAt: at, lastReason: reason });
      }
      return { queued: true, created: false };
    }
    if (open >= c.queueMaxOpen) return { queued: false, why: 'queue_full' };
    if ((d.get('queuedJobs') || 0) >= c.queueDailyNew) return { queued: false, why: 'queue_daily_limit' };
    tx.set(ref, {
      status: 'queued', scopeId, area, requesters: { [uid]: entry },
      createdAt: at, updatedAt: at, nextAttemptAt: at, claimUntil: ts(0), attempts: 0,
      lastReason: reason, expiresAt: ts(now.getTime() + c.queueMaxAgeDays * 864e5),
    });
    tx.set(day, { queuedJobs: FieldValue.increment(1) }, { merge: true });
    return { queued: true, created: true };
  });
}

/** Takes a job for this run; false when another run holds it or it moved on. */
async function claim(db, ref, nowMs, c) {
  return db.runTransaction(async (tx) => {
    const job = await tx.get(ref);
    if (!job.exists || job.get('status') !== 'queued') return false;
    const until = job.get('claimUntil');
    if (until && until.toMillis() > nowMs) return false;
    const next = job.get('nextAttemptAt');
    if (next && next.toMillis() > nowMs) return false;
    tx.update(ref, { claimUntil: ts(nowMs + c.queueClaimMs), attempts: FieldValue.increment(1) });
    return true;
  });
}

/** Email verified, or Google / Apple / phone sign-in (same rule as tokens). */
function userVerified(user) {
  if (!user || user.disabled) return false;
  if (user.emailVerified === true) return true;
  return (user.providerData || []).some((p) => ['google.com', 'apple.com', 'phone'].includes(p.providerId));
}

const SECURITY = new Set(['unverified', 'app_check']);
const DROP_ERRORS = new Set(['no_primary_location', 'outside_us', 'queue_area_changed', 'sign_in_required']);

/**
 * One scheduled run. Processes up to queueJobsPerRun due jobs, oldest
 * first. Returns counts and `stoppedBy` (disabled, paid_disabled,
 * out_of_credits, or the budget reason that ended the run).
 */
async function processQueue({ db, now = new Date(), config = {}, key, getUser, discover,
  reverse, property, log = () => {}, clock = () => Date.now(), sleep }) {
  const run = discover || require('./owners').discoverOwners;
  const { OWNER_DEFAULTS } = require('./owners');
  const c = { ...OWNER_DEFAULTS, ...QUEUE_DEFAULTS, ...config };
  const nowMs = now.getTime();
  const out = { processed: 0, done: 0, waiting: 0, cancelled: 0, expired: 0, failed: 0, stoppedBy: null };
  // No paid discovery at all: nothing to do, nothing read.
  if (!c.enabled || !c.queueEnabled || !(c.globalDailyCredits > 0)) {
    out.stoppedBy = 'disabled';
    return out;
  }
  const st = await db.collection('melissa_usage').doc('state').get();
  if (paidDisabled(st)) { out.stoppedBy = 'paid_disabled'; return out; }
  const paused = st.exists && st.get('outOfCreditsAt');
  if (paused && nowMs - paused.toMillis() < c.outOfCreditsPauseMs) { out.stoppedBy = 'out_of_credits'; return out; }

  const snap = await db.collection(COLLECTION).where('status', '==', 'queued')
    .orderBy('createdAt').limit(c.queueJobsPerRun * 4).get();
  for (const doc of snap.docs) {
    if (out.processed >= c.queueJobsPerRun || out.stoppedBy) break;
    const ref = doc.ref;
    const exp = doc.get('expiresAt');
    if (exp && exp.toMillis() <= nowMs) {
      await ref.update({ status: 'expired', requesters: {}, finishedAt: ts(nowMs) });
      out.expired++;
      continue;
    }
    if (!(await claim(db, ref, nowMs, c))) continue;
    out.processed++;
    const job = await ref.get();
    const requesters = { ...(job.get('requesters') || {}) };
    const order = Object.entries(requesters).sort((a, b) => a[1].at.toMillis() - b[1].at.toMillis());
    let result = null;
    let retryReason = null;
    let failure = null;
    for (const [uid, entry] of order) {
      // Authorization re-checked now, not trusted from the time it was queued.
      if (c.requireAppCheck && !entry.appCheck) { delete requesters[uid]; continue; }
      let user = null;
      try { user = await getUser(uid); } catch (_) { user = null; }
      if (!user) { delete requesters[uid]; continue; }
      const verified = userVerified(user);
      if (c.requireVerified && !verified) { delete requesters[uid]; continue; }
      try {
        const r = await run({
          db, uid, data: {}, key, now, config: c, verified, appVerified: Boolean(entry.appCheck),
          queue: false, expectJobId: ref.id, reverse, property, log, clock, ...(sleep ? { sleep } : {}),
        });
        if (r.limited && SECURITY.has(r.limited)) { delete requesters[uid]; continue; }
        if (r.limited === 'user_daily_limit') { retryReason = retryReason || r.limited; continue; }
        if (r.limited) { retryReason = r.limited; out.stoppedBy = r.limited; break; }
        if (r.pending) { retryReason = 'pending'; break; }
        result = r;
        break;
      } catch (e) {
        if (e && DROP_ERRORS.has(e.reason)) { delete requesters[uid]; continue; }
        failure = (e && e.reason) || 'internal';
        break;
      }
    }
    const left = Object.keys(requesters).length;
    if (result) {
      // Done: the requesters are no longer needed (data minimisation).
      await ref.update({
        status: 'done', requesters: {}, finishedAt: ts(nowMs), claimUntil: ts(0),
        credits: result.credits || 0, completeness: result.completeness,
      });
      out.done++;
      log({ event: 'queue', outcome: 'done', credits: result.credits || 0, completeness: result.completeness });
    } else if (failure) {
      const attempts = job.get('attempts') || 0;
      const final = attempts >= c.queueMaxAttempts;
      await ref.update({
        requesters: final ? {} : requesters, status: final ? 'failed' : 'queued', lastReason: failure,
        claimUntil: ts(0), nextAttemptAt: ts(nowMs + c.queueRetryMs * Math.min(8, 2 ** (attempts - 1))),
        ...(final ? { finishedAt: ts(nowMs) } : {}),
      });
      if (final) out.failed++; else out.waiting++;
      log({ event: 'queue', outcome: final ? 'failed' : 'retry', reason: failure });
    } else if (!left) {
      await ref.update({ status: 'cancelled', requesters: {}, lastReason: 'no_authorized_requester', finishedAt: ts(nowMs), claimUntil: ts(0) });
      out.cancelled++;
      log({ event: 'queue', outcome: 'cancelled' });
    } else {
      // Budget (or another lookup of this area) still in the way: the
      // attempt does not count, the job waits for the next run.
      await ref.update({
        requesters, lastReason: retryReason || 'waiting', claimUntil: ts(0),
        attempts: FieldValue.increment(-1),
        nextAttemptAt: ts(nowMs + (retryReason === 'pending' ? c.queuePendingRetryMs : c.queueRetryMs)),
      });
      out.waiting++;
      log({ event: 'queue', outcome: 'waiting', reason: retryReason });
    }
  }
  return out;
}

/** Account deleted: remove the user from every waiting job. */
async function removeRequester(db, uid) {
  const snap = await db.collection(COLLECTION).where('status', '==', 'queued').get();
  let removed = 0;
  for (const doc of snap.docs) {
    const requesters = { ...(doc.get('requesters') || {}) };
    if (!requesters[uid]) continue;
    delete requesters[uid];
    await doc.ref.update(Object.keys(requesters).length
      ? { requesters }
      : { requesters: {}, status: 'cancelled', lastReason: 'no_authorized_requester' });
    removed++;
  }
  return removed;
}

module.exports = {
  COLLECTION, QUEUE_DEFAULTS, QUEUE_REASONS, enqueueDiscovery, processQueue, removeRequester, userVerified,
};
