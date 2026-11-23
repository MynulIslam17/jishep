#!/usr/bin/env node
'use strict';
// Melissa capability probe (run by a developer, never by the app).
//
// Keys are read from ~/.config/gps-cielo/melissa.env (outside the repo):
//   MELISSA_SUBSCRIPTION_LICENSE=...
//   MELISSA_CREDIT_LICENSE=...
// Keys are never printed: output shows only their last 4 characters and
// every response is scrubbed of both keys before it is written.
//
//   node tool/melissa/probe.js usage          # free: services per key
//   node tool/melissa/probe.js paid --yes     # up to 4 records per key that
//                                              # works (see PAID below)
//
// Responses are saved (scrubbed) to tool/melissa/out/, which is git-ignored.

const fs = require('fs');
const os = require('os');
const path = require('path');

const ENV_FILE = path.join(os.homedir(), '.config/gps-cielo/melissa.env');
const OUT = path.join(__dirname, 'out');

function loadKeys() {
  if (!fs.existsSync(ENV_FILE)) {
    console.error(`Missing ${ENV_FILE}. Create it with the two MELISSA_* lines.`);
    process.exit(2);
  }
  const env = {};
  for (const line of fs.readFileSync(ENV_FILE, 'utf8').split('\n')) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (m) env[m[1]] = m[2].replace(/^['"]|['"]$/g, '');
  }
  return {
    subscription: env.MELISSA_SUBSCRIPTION_LICENSE || '',
    credit: env.MELISSA_CREDIT_LICENSE || '',
  };
}

const KEYS = loadKeys();
const tail = (k) => (k ? `…${k.slice(-4)}` : '(missing)');
function scrub(text) {
  let s = String(text);
  for (const k of Object.values(KEYS)) {
    if (k) s = s.split(k).join(tail(k)).split(encodeURIComponent(k)).join(tail(k));
  }
  return s;
}

async function get(url, params, key) {
  const q = new URLSearchParams({ ...params, id: key, format: 'json' });
  try {
    const res = await fetch(`${url}?${q}`, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(15000),
    });
    const text = scrub(await res.text());
    let json = null;
    try { json = JSON.parse(text); } catch { /* not JSON */ }
    return { http: res.status, json, text: json ? undefined : text.slice(0, 500) };
  } catch (e) {
    return { http: 0, error: scrub(e.message) };
  }
}

function save(name, data) {
  fs.mkdirSync(OUT, { recursive: true });
  fs.writeFileSync(path.join(OUT, `${name}.json`), scrub(JSON.stringify(data, null, 2)));
}

// A public landmark address and its coordinates (US Capitol, Washington DC)
// so no private home is looked up while testing.
const TEST = {
  a1: 'First St SE', city: 'Washington', state: 'DC', postal: '20004',
  lat: '38.889805', long: '-77.009056',
};

const PAID = [
  {
    name: 'reverse_geocoder',
    url: 'https://reversegeo.melissadata.net/V3/WEB/ReverseGeoCode/doLookup',
    params: { lat: TEST.lat, long: TEST.long, recs: '5', dist: '0.5', opt: 'IncludeApartments:on' },
  },
  {
    name: 'personator_check',
    url: 'https://personator.melissadata.net/v3/WEB/ContactVerify/doContactVerify',
    params: { act: 'Check', cols: 'GrpAddressDetails,GrpGeocode', a1: TEST.a1, city: TEST.city, state: TEST.state, postal: TEST.postal, ctry: 'US' },
  },
  {
    name: 'global_address',
    url: 'https://address.melissadata.net/V3/WEB/GlobalAddress/doGlobalAddress',
    params: { a1: TEST.a1, loc: TEST.city, admarea: TEST.state, postal: TEST.postal, ctry: 'US' },
  },
  {
    name: 'property_lookup',
    url: 'https://property.melissadata.net/v4/WEB/LookupProperty',
    params: { a1: TEST.a1, city: TEST.city, state: TEST.state, postal: TEST.postal, cols: 'GrpPropertyAddress,GrpPropertyUseInfo' },
  },
];

function codes(json) {
  if (!json) return '';
  const t = json.TransmissionResults || json.TransmissionResult || '';
  const r = Array.isArray(json.Records) && json.Records[0] ? json.Records[0].Results || '' : '';
  const n = Array.isArray(json.Records) ? json.Records.length : (json.TotalRecords || '');
  return `transmission=${t || '-'} results=${r || '-'} records=${n}`;
}

async function usage() {
  for (const [which, key] of Object.entries(KEYS)) {
    if (!key) { console.log(`${which}: key missing`); continue; }
    const r = await get('https://usage.melissadata.net/v1/license', { t: 'probe' }, key);
    save(`usage_${which}`, r);
    console.log(`${which} ${tail(key)}: HTTP ${r.http}`);
    const services = r.json && (r.json.Services || r.json.services || r.json.Products);
    if (Array.isArray(services)) {
      for (const s of services) {
        console.log('  ', JSON.stringify(s).slice(0, 300));
      }
    } else {
      console.log('  ', JSON.stringify(r.json || r.text || r.error).slice(0, 600));
    }
  }
}

async function paid() {
  if (!process.argv.includes('--yes')) {
    console.error('Paid calls spend credits. Re-run with --yes.');
    process.exit(2);
  }
  // Credit key first (pay-per-use); subscription key only for products the
  // credit key cannot use.
  for (const p of PAID) {
    for (const [which, key] of Object.entries({ credit: KEYS.credit, subscription: KEYS.subscription })) {
      if (!key) continue;
      const r = await get(p.url, p.params, key);
      save(`${p.name}_${which}`, r);
      console.log(`${p.name} [${which} ${tail(key)}] HTTP ${r.http} ${codes(r.json)} ${r.error || ''}`);
      const t = r.json && (r.json.TransmissionResults || '');
      if (r.http === 200 && !/GE(05|06|08|15|2\d)/.test(t)) break; // worked: don't spend twice
    }
  }
}

const cmd = process.argv[2];
if (cmd === 'usage') usage();
else if (cmd === 'paid') paid();
else console.log('usage: node tool/melissa/probe.js usage | paid --yes');
