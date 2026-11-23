'use strict';
// Melissa spending guard (fail closed).
//
// Every Melissa request made by these functions goes through `melissaFetchFor`.
//
//   - Deployed (not the emulator): the real fetch. Whether a call is made at
//     all is decided by the feature switches (MELISSA_OWNER_DISCOVERY_ENABLED,
//     ...), which are OFF in functions/.env.gps-para-el-cielo.
//   - Functions emulator: saved responses only (functions/.melissa-recordings).
//     An unrecorded request is refused WITHOUT touching the network, unless
//     MELISSA_EMULATOR_LIVE=true is set on purpose (never in .env.local).
//   - Tests (`node --test --require ./test/no_network.js`): any fetch throws.
//
// `installGlobalGuard()` also wraps the global fetch in the emulator, so code
// that forgets to pass a fetch (as discoverNearby did) still cannot reach a
// Melissa host.

const path = require('path');
const { melissaFetch } = require('./recorder');

const MELISSA_HOST = /(^|\.)melissadata\.net$/i;

const isMelissaUrl = (url) => {
  try {
    return MELISSA_HOST.test(new URL(String(url)).hostname);
  } catch (_) {
    return false;
  }
};

const inEmulator = () => process.env.FUNCTIONS_EMULATOR === 'true';
const emulatorLiveAllowed = () => process.env.MELISSA_EMULATOR_LIVE === 'true';

class LiveMelissaBlocked extends Error {
  constructor(url) {
    super(`Live Melissa request blocked (${new URL(String(url)).hostname})`);
    this.name = 'LiveMelissaBlocked';
  }
}

let events = { replay: 0, recorded: 0, not_recorded: 0, blocked: 0 };
const countEvent = (e) => { events[e] = (events[e] || 0) + 1; };
const guardStats = () => ({ ...events });
const resetGuardStats = () => { events = { replay: 0, recorded: 0, not_recorded: 0, blocked: 0 }; };

const RECORDINGS = path.join(__dirname, '..', '.melissa-recordings');

/**
 * The fetch to use for Melissa. In the emulator: replay-only unless
 * MELISSA_EMULATOR_LIVE=true. `realFetch` is the fetch used for a live call.
 */
function melissaFetchFor({ realFetch = originalFetch(), dir = RECORDINGS } = {}) {
  if (!inEmulator()) return realFetch;
  const live = emulatorLiveAllowed();
  return melissaFetch({
    dir,
    replayOnly: !live,
    realFetch: live ? realFetch : blockedFetch,
    onEvent: countEvent,
  });
}

async function blockedFetch(url) {
  countEvent('blocked');
  throw new LiveMelissaBlocked(url);
}

let saved = null;
const originalFetch = () => saved || globalThis.fetch;

/** Emulator only: any global fetch to a Melissa host goes through the guard. */
function installGlobalGuard() {
  if (!inEmulator() || saved) return;
  saved = globalThis.fetch;
  const guarded = melissaFetchFor({ realFetch: saved });
  globalThis.fetch = (url, init) => (isMelissaUrl(url) ? guarded(url, init) : saved(url, init));
}

module.exports = {
  isMelissaUrl, melissaFetchFor, installGlobalGuard, LiveMelissaBlocked, guardStats, resetGuardStats,
  RECORDINGS,
};
