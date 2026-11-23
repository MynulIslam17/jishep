'use strict';
// Melissa Personator Consumer "Check" for one US address, on the server only.
//
// Docs: https://docs.melissa.com/cloud-api/personator-consumer/personator-consumer-reference-guide.html
// Price (developer price list, 2026-11): 3 credits per record.
//
// Only address columns are requested. No name, phone, email, demographics
// or owner data is asked for or kept. The license key is never logged and
// never returned; errors are reported with Melissa's result codes only.

const ENDPOINT =
  'https://personator.melissadata.net/v3/WEB/ContactVerify/doContactVerify';

/** Credits one Personator Check record costs (Melissa price list). */
const CHECK_CREDITS = 3;

/** Melissa result codes the app reacts to. */
const CODES = {
  // Transmission (whole request) errors.
  GE05: 'license_invalid',
  GE06: 'license_disabled',
  GE08: 'product_not_enabled',
  GE14: 'out_of_credits',
  GE15: 'license_invalid',
  GE20: 'product_not_enabled',
  GE29: 'not_available_for_credit_license',
  SE01: 'melissa_internal_error',
};

/**
 * Builds the request URL. `key` is added last; callers must never log the
 * returned URL.
 */
function buildCheckUrl(address, key) {
  const q = new URLSearchParams({
    t: address.requestId || '',
    act: 'Check',
    cols: 'GrpAddressDetails,GrpGeocode',
    a1: address.line,
    city: address.city || '',
    state: address.state || '',
    postal: address.zip || '',
    ctry: 'US',
    format: 'json',
  });
  q.set('id', key);
  return `${ENDPOINT}?${q.toString()}`;
}

function codesOf(value) {
  return String(value || '')
    .split(',')
    .map((c) => c.trim())
    .filter(Boolean);
}

function num(value) {
  const n = Number.parseFloat(value);
  return Number.isFinite(n) ? n : null;
}

function str(value, max = 200) {
  const s = String(value == null ? '' : value).trim();
  return s ? s.slice(0, max) : null;
}

/**
 * Reduces a Personator JSON response to what the app shows. Never throws:
 * an unexpected body becomes `{status: 'error', error: 'bad_response'}`.
 *
 * status:
 *  - 'verified'    AS01: a valid, deliverable address
 *  - 'partial'     address found but not fully verified (AS02/AS03)
 *  - 'not_found'   no AS01-03 code (Melissa has no match)
 *  - 'error'       transmission error (see `error`)
 */
function parseCheckResponse(body) {
  if (!body || typeof body !== 'object') {
    return { status: 'error', error: 'bad_response', codes: [] };
  }
  const transmission = codesOf(body.TransmissionResults);
  for (const code of transmission) {
    if (CODES[code]) {
      return { status: 'error', error: CODES[code], codes: transmission };
    }
  }
  if (transmission.length > 0) {
    return { status: 'error', error: 'melissa_error', codes: transmission };
  }
  const record = Array.isArray(body.Records) ? body.Records[0] : null;
  if (!record) return { status: 'error', error: 'bad_response', codes: [] };

  const codes = codesOf(record.Results);
  const has = (c) => codes.includes(c);
  let status = 'not_found';
  if (has('AS01')) status = 'verified';
  else if (has('AS02') || has('AS03')) status = 'partial';

  // DeliveryIndicator: R = residence, B = business, U = unknown.
  const delivery = str(record.DeliveryIndicator, 1);
  const residential =
    delivery === 'R' ? true : delivery === 'B' ? false : null;

  // GS05 rooftop, GS06 interpolated rooftop, GS01 street, GS03 ZIP+4 centroid.
  let geocodeLevel = null;
  if (has('GS05') || has('GS06')) geocodeLevel = 'rooftop';
  else if (has('GS01')) geocodeLevel = 'street';
  else if (has('GS03') || has('GS02')) geocodeLevel = 'zip';

  const lat = num(record.Latitude);
  const lon = num(record.Longitude);
  return {
    status,
    codes,
    address: {
      line: str(record.AddressLine1),
      suite: str(record.AddressSuiteName, 40),
      city: str(record.City, 80),
      state: str(record.State, 2),
      zip: str(record.PostalCode, 10),
    },
    residential,
    deliveryIndicator: delivery,
    addressTypeCode: str(record.AddressTypeCode, 2),
    latitude: lat != null && Math.abs(lat) <= 90 ? lat : null,
    longitude: lon != null && Math.abs(lon) <= 180 ? lon : null,
    geocodeLevel,
    melissaAddressKey: str(record.MelissaAddressKey, 20),
  };
}

class MelissaHttpError extends Error {
  constructor(status) {
    super(`Melissa HTTP ${status}`);
    this.status = status;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * One Personator Check with a timeout and up to [retries] retries on
 * network errors, HTTP 429 and 5xx (exponential backoff). A 401/403 or any
 * Melissa result code is final (no retry, so credits are not spent twice).
 */
async function checkAddress(address, key, opts = {}) {
  const {
    fetchImpl = fetch,
    timeoutMs = 8000,
    retries = 2,
    backoffMs = 400,
  } = opts;
  if (!key) return { status: 'error', error: 'not_configured', codes: [] };
  const url = buildCheckUrl(address, key);
  let lastError = 'network';
  for (let attempt = 0; attempt <= retries; attempt++) {
    if (attempt > 0) await sleep(backoffMs * 2 ** (attempt - 1));
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, {
        headers: { Accept: 'application/json' },
        signal: controller.signal,
      });
      if (res.status === 429 || res.status >= 500) {
        lastError = res.status === 429 ? 'rate_limited' : 'unavailable';
        continue;
      }
      if (res.status === 401 || res.status === 403) {
        return { status: 'error', error: 'license_invalid', codes: [] };
      }
      if (!res.ok) throw new MelissaHttpError(res.status);
      return parseCheckResponse(await res.json());
    } catch (e) {
      if (e instanceof MelissaHttpError) {
        return { status: 'error', error: 'unavailable', codes: [] };
      }
      lastError = e && e.name === 'AbortError' ? 'timeout' : 'network';
    } finally {
      clearTimeout(timer);
    }
  }
  return { status: 'error', error: lastError, codes: [] };
}

// ---------------------------------------------------------------------------
// Property LookupProperty (9 credits per record, verified on the credit
// license 2026-11-21). Building facts only by default; the owner group is
// requested only when `includeOwner` is true (off until Melissa confirms in
// writing that showing owner names in the app is allowed).

const PROPERTY_ENDPOINT = 'https://property.melissadata.net/v4/WEB/LookupProperty';
const PROPERTY_CREDITS = 9;

function buildPropertyUrl(address, key, { includeOwner = false } = {}) {
  const cols = ['GrpPropertyAddress', 'GrpPropertyUseInfo', 'GrpPropertySize', 'GrpParcel'];
  if (includeOwner) cols.push('GrpPrimaryOwner');
  // A Melissa Address Key (from Reverse GeoCoder or Personator) selects the
  // exact address; otherwise the address fields are matched.
  const q = new URLSearchParams(address.mak ? {
    t: address.requestId || '',
    mak: address.mak,
    cols: cols.join(','),
    format: 'json',
  } : {
    t: address.requestId || '',
    a1: address.line,
    city: address.city || '',
    state: address.state || '',
    postal: address.zip || '',
    cols: cols.join(','),
    format: 'json',
  });
  q.set('id', key);
  return `${PROPERTY_ENDPOINT}?${q.toString()}`;
}

/**
 * Property facts. `found` is false when Melissa has no parcel (YE codes).
 * The owner is returned only when it was requested and is present; it is
 * the recorded owner, which is not necessarily who lives there.
 */
function parsePropertyResponse(body, { includeOwner = false } = {}) {
  if (!body || typeof body !== 'object') {
    return { status: 'error', error: 'bad_response', codes: [] };
  }
  const transmission = codesOf(body.TransmissionResults);
  for (const code of transmission) {
    if (CODES[code]) return { status: 'error', error: CODES[code], codes: transmission };
  }
  if (transmission.length > 0) {
    return { status: 'error', error: 'melissa_error', codes: transmission };
  }
  const record = Array.isArray(body.Records) ? body.Records[0] : null;
  if (!record) return { status: 'error', error: 'bad_response', codes: [] };
  const codes = codesOf(record.Results);
  // YS = property found; YE = not found / error.
  const found = codes.some((c) => c.startsWith('YS'));
  if (!found) return { status: 'not_found', codes };
  const use = record.PropertyUseInfo || {};
  const size = record.PropertySize || {};
  const addr = record.PropertyAddress || {};
  const owner = record.PrimaryOwner || {};
  const parcel = record.Parcel || {};
  const year = Number.parseInt(use.YearBuilt, 10);
  const lot = num(size.AreaLotSF);
  const building = num(size.AreaBuilding);
  const out = {
    status: 'found',
    codes,
    useGroup: str(use.PropertyUseGroup, 80),
    useCode: str(use.PropertyUseStandardized, 10),
    yearBuilt: Number.isFinite(year) && year > 1600 ? year : null,
    lotSqft: lot && lot > 0 ? lot : null,
    buildingSqft: building && building > 0 ? building : null,
    latitude: num(addr.Latitude),
    longitude: num(addr.Longitude),
    mak: str(addr.MAK, 20),
    // County + parcel number: one parcel can have several addresses.
    parcelId: str(parcel.FIPSCode, 5) && str(parcel.UnformattedAPN || parcel.FormattedAPN, 40)
      ? `${str(parcel.FIPSCode, 5)}:${str(parcel.UnformattedAPN || parcel.FormattedAPN, 40)}`
      : null,
    address: {
      line: str(addr.Address, 120),
      city: str(addr.City, 80),
      state: str(addr.State, 2),
      zip: str(addr.Zip, 10),
    },
  };
  if (includeOwner && str(owner.Name1Full)) {
    out.owner = {
      name: str(owner.Name1Full, 120),
      secondName: str(owner.Name2Full, 120),
      isCompany: owner.CompanyFlag === 'Y',
      isTrust: owner.TrustFlag === 'Y',
    };
  }
  return out;
}

/** One Property lookup (same retry/timeout rules as checkAddress). */
async function lookupProperty(address, key, opts = {}) {
  const { includeOwner = false } = opts;
  return request(buildPropertyUrl(address, key, { includeOwner }), key, opts,
    (body) => parsePropertyResponse(body, { includeOwner }));
}

/** Shared GET with timeout, retries on 429/5xx/network, no retry on 401. */
async function request(url, key, opts, parse) {
  const { fetchImpl = fetch, timeoutMs = 8000, retries = 2, backoffMs = 400 } = opts;
  if (!key) return { status: 'error', error: 'not_configured', codes: [] };
  let lastError = 'network';
  for (let attempt = 0; attempt <= retries; attempt++) {
    if (attempt > 0) await sleep(backoffMs * 2 ** (attempt - 1));
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const res = await fetchImpl(url, { headers: { Accept: 'application/json' }, signal: controller.signal });
      if (res.status === 429 || res.status >= 500) {
        lastError = res.status === 429 ? 'rate_limited' : 'unavailable';
        continue;
      }
      if (res.status === 401 || res.status === 403) {
        return { status: 'error', error: 'license_invalid', codes: [] };
      }
      if (!res.ok) return { status: 'error', error: 'unavailable', codes: [] };
      return parse(await res.json());
    } catch (e) {
      lastError = e && e.name === 'AbortError' ? 'timeout' : 'network';
    } finally {
      clearTimeout(timer);
    }
  }
  return { status: 'error', error: lastError, codes: [] };
}

module.exports = {
  PROPERTY_CREDITS,
  buildPropertyUrl,
  parsePropertyResponse,
  lookupProperty,
  CHECK_CREDITS,
  CODES,
  ENDPOINT,
  buildCheckUrl,
  parseCheckResponse,
  checkAddress,
};
