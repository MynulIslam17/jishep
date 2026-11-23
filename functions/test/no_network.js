'use strict';
// Loaded before every test (`node --test --require ./test/no_network.js`).
// Tests must never reach the internet: Melissa is replaced by fakes or saved
// recordings. Any fetch to a non-local host (Melissa included) throws and is
// recorded in `globalThis.__blockedFetches`; local emulators stay reachable.
const blocked = [];
const real = globalThis.fetch;
const LOCAL = new Set(['127.0.0.1', 'localhost', '::1', '[::1]']);
globalThis.fetch = async (url, init) => {
  const u = new URL(String(url instanceof Request ? url.url : url));
  if (LOCAL.has(u.hostname)) return real(url, init);
  u.searchParams.delete('id');
  blocked.push(u.toString());
  throw new Error(`Network blocked in tests: ${u.hostname}`);
};
globalThis.__blockedFetches = blocked;
