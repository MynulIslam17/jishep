/**
 * Imports households into the `households` collection.
 *
 * Each document gets `geo: { geohash, geopoint }`, which the app uses to find
 * the households nearest to a user (geoflutterfire_plus).
 *
 * Usage:
 *   cd tool/seed_households
 *   npm install
 *   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *   node seed.js                   # imports households.sample.json
 *   node seed.js my-households.json
 *
 * Input: a JSON array of
 *   { "id"?, "residentName", "address", "cityStateZip", "latitude", "longitude" }
 * Records with an `id` are upserted; others get an auto id.
 */
const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');
const { geohashForLocation } = require('geofire-common');

const PROJECT_ID = 'cielo-63925';

async function main() {
  const file = path.resolve(__dirname, process.argv[2] || 'households.sample.json');
  const records = JSON.parse(fs.readFileSync(file, 'utf8'));

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();
  const collection = db.collection('households');

  let batch = db.batch();
  let pending = 0;
  let written = 0;

  for (const record of records) {
    const { id, residentName, address, cityStateZip, latitude, longitude } = record;
    if (typeof latitude !== 'number' || typeof longitude !== 'number' || !address) {
      console.warn('Skipping invalid record:', record);
      continue;
    }

    const ref = id ? collection.doc(String(id)) : collection.doc();
    batch.set(
      ref,
      {
        residentName: residentName || 'Resident',
        address,
        cityStateZip: cityStateZip || '',
        geo: {
          geohash: geohashForLocation([latitude, longitude]),
          geopoint: new admin.firestore.GeoPoint(latitude, longitude),
        },
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    pending++;
    written++;
    if (pending === 450) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }

  if (pending > 0) await batch.commit();
  console.log(`Imported ${written} households into ${PROJECT_ID}/households.`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
