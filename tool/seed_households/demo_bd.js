/**
 * Generates SYNTHETIC Bangladesh test households (development/testing only).
 *
 * Every record is fictional: placeholder names ("Demo Household 001"), no
 * real residents, phone numbers or private street addresses. Coordinates are
 * scattered (deterministically) within ~350 m (Demra: ~2 km) of public
 * neighborhood/area centers, not at specific residences.
 *
 *   node demo_bd.js            # rewrites households.demo_bd.json
 */
const fs = require('fs');
const path = require('path');
const { geohashForLocation } = require('geofire-common');

const ID_PREFIX = 'demo_bd_';
const DEMO_SET = 'bd_v1';

// [city, area, approximate public area center lat, lng, count, spread m]
const AREAS = [
  ['Dhaka', 'Mirpur', 23.8223, 90.3654, 7],
  ['Dhaka', 'Dhanmondi', 23.7465, 90.376, 7],
  ['Dhaka', 'Uttara', 23.8759, 90.3795, 7],
  ['Dhaka', 'Gulshan', 23.7925, 90.4078, 7],
  ['Dhaka', 'Mohammadpur', 23.7662, 90.3589, 6],
  ['Dhaka', 'Motijheel', 23.733, 90.4172, 6],
  ['Chattogram', 'Agrabad', 22.326, 91.812, 7],
  ['Chattogram', 'Nasirabad', 22.364, 91.823, 7],
  ['Chattogram', 'Halishahar', 22.329, 91.779, 6],
  ['Sylhet', 'Zindabazar', 24.896, 91.868, 5],
  ['Sylhet', 'Uposhohor', 24.888, 91.885, 5],
  ['Rajshahi', 'Shaheb Bazar', 24.366, 88.599, 5],
  ['Rajshahi', 'Uposhohor', 24.379, 88.617, 5],
  ['Khulna', 'Sonadanga', 22.818, 89.548, 5],
  ['Khulna', 'Khalishpur', 22.855, 89.537, 5],
  ['Barishal', 'Sadar Road', 22.701, 90.37, 5],
  ['Barishal', 'Nathullabad', 22.713, 90.348, 5],
  // Added 2026-11-10: a larger set (to test paging) spread over ~2 km of
  // Demra. Appended last so demo_bd_001-100 stay exactly the same.
  ['Dhaka', 'Demra', 23.721, 90.483, 40, 2000],
];

const EXPECTED_PER_CITY = {
  Dhaka: 80,
  Chattogram: 20,
  Sylhet: 10,
  Rajshahi: 10,
  Khulna: 10,
  Barishal: 10,
};

/** Small deterministic PRNG (mulberry32) so the data is reproducible. */
function prng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function round6(value) {
  return Math.round(value * 1e6) / 1e6;
}

function buildDemoHouseholds() {
  const random = prng(20261109);
  const records = [];
  let n = 0;
  for (const [city, area, lat, lng, count, spread = 350] of AREAS) {
    for (let i = 0; i < count; i++) {
      n++;
      const number = String(n).padStart(3, '0');
      // Uniform point in a disc of radius `spread` around the area center.
      const radiusM = spread * Math.sqrt(random());
      const angle = 2 * Math.PI * random();
      const latitude = round6(lat + (radiusM * Math.cos(angle)) / 111320);
      const longitude = round6(
        lng +
          (radiusM * Math.sin(angle)) /
            (111320 * Math.cos((lat * Math.PI) / 180)),
      );
      records.push({
        id: `${ID_PREFIX}${number}`,
        residentName: `Demo Household ${number}`,
        address: `Demo location ${number}, ${area} (synthetic)`,
        cityStateZip: `${city}, Bangladesh · TEST DATA`,
        city,
        area,
        latitude,
        longitude,
        geohash: geohashForLocation([latitude, longitude]),
      });
    }
  }
  return records;
}

module.exports = {
  ID_PREFIX,
  DEMO_SET,
  EXPECTED_PER_CITY,
  buildDemoHouseholds,
};

if (require.main === module) {
  const file = path.join(__dirname, 'households.demo_bd.json');
  fs.writeFileSync(file, `${JSON.stringify(buildDemoHouseholds(), null, 2)}\n`);
  console.log(`Wrote ${file}`);
}
