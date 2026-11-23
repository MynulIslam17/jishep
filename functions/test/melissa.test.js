'use strict';
// Unit tests for the Melissa client. The response bodies below are written
// by hand in the documented Personator JSON shape; they are NOT captured from
// a live Melissa call.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildCheckUrl, parseCheckResponse, checkAddress,
  buildPropertyUrl, parsePropertyResponse,
} = require('../src/melissa');
const fixture = (n) => require(`./fixtures/${n}.json`);

const ADDRESS = { line: '1240 New Jersey Ave NW', city: 'Washington', state: 'DC', zip: '20001' };
const KEY = 'TEST-KEY-not-real-1234';

const okBody = (over = {}) => ({
  TransmissionResults: '',
  Records: [{
    Results: 'AS01,GS05',
    AddressLine1: '1240 NEW JERSEY AVE NW',
    City: 'Washington', State: 'DC', PostalCode: '20001-1234',
    DeliveryIndicator: 'R', AddressTypeCode: 'S',
    Latitude: '38.906657', Longitude: '-77.015601',
    MelissaAddressKey: '8008006245',
    NameFull: 'SHOULD NOT BE KEPT',
    ...over,
  }],
});

const response = (status, body) => ({
  status, ok: status >= 200 && status < 300, json: async () => body,
});

test('the URL asks only for address columns and carries the key once', () => {
  const url = new URL(buildCheckUrl(ADDRESS, KEY));
  assert.equal(url.searchParams.get('act'), 'Check');
  assert.equal(url.searchParams.get('cols'), 'GrpAddressDetails,GrpGeocode');
  assert.equal(url.searchParams.get('a1'), ADDRESS.line);
  assert.equal(url.searchParams.get('id'), KEY);
  assert.equal(url.searchParams.getAll('id').length, 1);
  assert.ok(!url.search.includes('Append'));
});

test('a verified residential rooftop result', () => {
  const r = parseCheckResponse(okBody());
  assert.equal(r.status, 'verified');
  assert.equal(r.residential, true);
  assert.equal(r.geocodeLevel, 'rooftop');
  assert.equal(r.latitude, 38.906657);
  assert.equal(r.address.zip, '20001-1234');
  // No personal fields are carried over even if Melissa sends them.
  assert.ok(!JSON.stringify(r).includes('SHOULD NOT BE KEPT'));
});

test('business, unknown and apartment results', () => {
  assert.equal(parseCheckResponse(okBody({ DeliveryIndicator: 'B' })).residential, false);
  assert.equal(parseCheckResponse(okBody({ DeliveryIndicator: 'U' })).residential, null);
  const apt = parseCheckResponse(okBody({ AddressSuiteName: 'APT 4B', Results: 'AS01,GS01' }));
  assert.equal(apt.address.suite, 'APT 4B');
  assert.equal(apt.geocodeLevel, 'street');
});

test('partial and no-match addresses', () => {
  assert.equal(parseCheckResponse(okBody({ Results: 'AS02' })).status, 'partial');
  const none = parseCheckResponse(okBody({ Results: 'AE01', Latitude: '', Longitude: '' }));
  assert.equal(none.status, 'not_found');
  assert.equal(none.latitude, null);
});

test('transmission errors: out of credits, bad key, not enabled, credit-license only', () => {
  assert.equal(parseCheckResponse({ TransmissionResults: 'GE14', Records: [] }).error, 'out_of_credits');
  assert.equal(parseCheckResponse({ TransmissionResults: 'GE05' }).error, 'license_invalid');
  assert.equal(parseCheckResponse({ TransmissionResults: 'GE08' }).error, 'product_not_enabled');
  assert.equal(parseCheckResponse({ TransmissionResults: 'GE29' }).error, 'not_available_for_credit_license');
  assert.equal(parseCheckResponse({ TransmissionResults: 'GE99' }).error, 'melissa_error');
  assert.equal(parseCheckResponse(null).error, 'bad_response');
  assert.equal(parseCheckResponse({ Records: [] }).error, 'bad_response');
});

test('no key configured: no request is made', async () => {
  let calls = 0;
  const r = await checkAddress(ADDRESS, '', { fetchImpl: async () => { calls++; } });
  assert.equal(r.error, 'not_configured');
  assert.equal(calls, 0);
});

test('429 and 5xx are retried with backoff, then succeed', async () => {
  const statuses = [429, 503, 200];
  let calls = 0;
  const r = await checkAddress(ADDRESS, KEY, {
    backoffMs: 1,
    fetchImpl: async () => response(statuses[calls++], okBody()),
  });
  assert.equal(calls, 3);
  assert.equal(r.status, 'verified');
});

test('gives up after the retries and reports why', async () => {
  let calls = 0;
  const r = await checkAddress(ADDRESS, KEY, {
    backoffMs: 1, retries: 2,
    fetchImpl: async () => { calls++; return response(503, {}); },
  });
  assert.equal(calls, 3);
  assert.equal(r.error, 'unavailable');
});

test('a slow Melissa times out', async () => {
  const r = await checkAddress(ADDRESS, KEY, {
    timeoutMs: 20, retries: 0,
    fetchImpl: (url, { signal }) => new Promise((_, reject) => {
      signal.addEventListener('abort', () => {
        const e = new Error('aborted'); e.name = 'AbortError'; reject(e);
      });
    }),
  });
  assert.equal(r.error, 'timeout');
});

test('401 is final (no retry) and the key never appears in the result', async () => {
  let calls = 0;
  const r = await checkAddress(ADDRESS, KEY, {
    fetchImpl: async () => { calls++; return response(401, {}); },
  });
  assert.equal(calls, 1);
  assert.equal(r.error, 'license_invalid');
  assert.ok(!JSON.stringify(r).includes(KEY));
});

// Real Melissa responses (2026-11-21, credit license) for public buildings,
// saved with the key scrubbed: tool/melissa/probe.js.
test('REAL Personator Check response (1600 Pennsylvania Ave NW) parses', () => {
  const r = parseCheckResponse(fixture('personator_check_1600_pennsylvania'));
  assert.equal(r.status, 'verified');
  assert.equal(r.residential, false); // DeliveryIndicator B
  assert.equal(r.geocodeLevel, 'rooftop');
  assert.equal(r.address.zip, '20500-0005');
  assert.ok(Math.abs(r.latitude - 38.897199) < 1e-6);
});

test('REAL Property response parses; owner only when asked', () => {
  const body = fixture('property_1600_pennsylvania');
  const plain = parsePropertyResponse(body);
  assert.equal(plain.status, 'found');
  assert.equal(plain.useGroup, 'Multi-Unit Professional');
  assert.equal(plain.yearBuilt, 1840);
  assert.equal(plain.owner, undefined);
  const withOwner = parsePropertyResponse(body, { includeOwner: true });
  assert.equal(withOwner.owner.isCompany, true);
  assert.ok(withOwner.owner.name.length > 0);
});

test('property URL asks for the owner group only when allowed', () => {
  const addr = { line: '1 Main St', city: 'X', state: 'CA', zip: '' };
  assert.ok(!new URL(buildPropertyUrl(addr, KEY)).searchParams.get('cols').includes('Owner'));
  assert.ok(new URL(buildPropertyUrl(addr, KEY, { includeOwner: true })).searchParams.get('cols').includes('GrpPrimaryOwner'));
});

test('property not found (YE codes)', () => {
  const r = parsePropertyResponse({ TransmissionResults: '', Records: [{ Results: 'YE03,AE11' }] });
  assert.equal(r.status, 'not_found');
});

test('REAL Reverse GeoCoder response has addresses with coordinates and no residential flag', () => {
  const body = fixture('reverse_geocoder_capitol');
  assert.equal(body.Records.length, 5);
  for (const rec of body.Records) {
    assert.ok(rec.AddressLine1 && rec.Latitude && rec.MelissaAddressKey);
    assert.equal(rec.DeliveryIndicator, undefined);
  }
});
