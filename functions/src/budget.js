'use strict';

// App-wide Melissa budget: MELISSA_GLOBAL_DAILY_CREDITS caps the credits ALL
// endpoints together may reserve per UTC day. Every paid path
// (enrichHousehold, discoverNearby, discoverOwners) checks it inside its own
// reservation transaction, before any Melissa request.
//
// Fail closed: a limit that is 0, negative, missing or not a number allows
// nothing. 0 is the production setting until paid calls are approved.

/** Credits already reserved today by every endpoint (melissa_usage/{day}). */
function spentToday(daySnap) {
  return (daySnap.get('credits') || 0) + // enrichHousehold
    (daySnap.get('gapCredits') || 0) + // discoverNearby
    (daySnap.get('ownerCredits') || 0); // discoverOwners
}

/** True when reserving `credits` more would pass the app-wide daily limit. */
function overGlobalLimit(daySnap, credits, limit) {
  if (!Number.isFinite(limit) || limit <= 0) return true;
  return spentToday(daySnap) + credits > limit;
}

/**
 * Administrative kill switch: `melissa_usage/state.paidDisabled == true`
 * stops every paid Melissa request at once, with no redeploy (cached data is
 * still served). Set and cleared with `node tool/melissa_ops.js kill|unkill`.
 */
function paidDisabled(stateSnap) {
  return Boolean(stateSnap && stateSnap.exists !== false && stateSnap.get && stateSnap.get('paidDisabled') === true);
}

module.exports = { spentToday, overGlobalLimit, paidDisabled };
