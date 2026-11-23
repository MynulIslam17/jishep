'use strict';
// LOCAL EMULATOR ONLY (see index.js): a fetch that saves every real Melissa
// response and answers a repeated request from the saved copy.
//
// A recording is keyed by the request URL WITHOUT the license key, and the
// key is never written to disk. Recordings hold real Melissa data (owner
// names): the folder is git-ignored and must never be committed or shared.

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

/** The request URL with the license key (`id`) removed. */
function recordingKey(url) {
  const u = new URL(url);
  u.searchParams.delete('id');
  u.searchParams.sort();
  return u.toString();
}

function fileFor(dir, url) {
  const hash = crypto.createHash('sha256').update(recordingKey(url)).digest('hex').slice(0, 32);
  return path.join(dir, `${hash}.json`);
}

const asResponse = (status, body) => ({
  status,
  ok: status >= 200 && status < 300,
  json: async () => body,
});

/**
 * fetch(url, init) → saved response if one exists; otherwise (unless
 * `replayOnly`) the real request, saved when Melissa answered with JSON.
 */
function melissaFetch({ dir, replayOnly = false, realFetch = fetch, onEvent = () => {} }) {
  return async (url, init) => {
    const file = fileFor(dir, url);
    if (fs.existsSync(file)) {
      const saved = JSON.parse(fs.readFileSync(file, 'utf8'));
      onEvent('replay');
      return asResponse(saved.status, saved.body);
    }
    if (replayOnly) {
      onEvent('not_recorded');
      // 503: treated as "unavailable" (not charged, no retry storm).
      return asResponse(503, null);
    }
    const res = await realFetch(url, init);
    if (res.status !== 200) return res;
    const body = await res.json();
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    fs.writeFileSync(file, JSON.stringify({
      request: recordingKey(url), status: res.status, body, savedAt: new Date().toISOString(),
    }), { mode: 0o600 });
    onEvent('recorded');
    return asResponse(res.status, body);
  };
}

module.exports = { melissaFetch, recordingKey, fileFor };
