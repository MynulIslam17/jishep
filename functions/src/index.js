'use strict';
// Cloud Functions for GPS Para el Cielo (project gps-para-el-cielo).
//
// enrichHousehold: a signed-in user asks Melissa to check the address of one
// household they opened. The Melissa credit license lives in Secret Manager
// (MELISSA_CREDIT_LICENSE) and never reaches the app.
//
// Deploy (needs the Cloud Functions, Cloud Build, Artifact Registry, Secret
// Manager and Cloud Run APIs, and matching roles):
//   firebase functions:secrets:set MELISSA_CREDIT_LICENSE --project gps-para-el-cielo
//   firebase deploy --only functions --project gps-para-el-cielo

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { defineSecret, defineInt, defineBoolean } = require('firebase-functions/params');
const { logger } = require('firebase-functions');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { enrichHousehold, EnrichError } = require('./enrich');
const { discoverNearby, DiscoverError, reverseLookup } = require('./discover');
const { discoverOwners, OwnerError } = require('./owners');
const { checkAddress, lookupProperty } = require('./melissa');

initializeApp();

// Melissa spending guard (src/guard.js), fail closed:
//   deployed: the real fetch, used only when a feature switch is on;
//   Functions emulator: saved responses only (functions/.melissa-recordings,
//     git-ignored, real data). An unrecorded request is refused without any
//     network access unless MELISSA_EMULATOR_LIVE=true is set on purpose.
// installGlobalGuard() also catches code that uses the global fetch.
const { melissaFetchFor, installGlobalGuard } = require('./guard');
installGlobalGuard();
const emulatorFetch = () => melissaFetchFor();

const MELISSA_CREDIT_LICENSE = defineSecret('MELISSA_CREDIT_LICENSE');
const PER_USER_DAILY_LOOKUPS = defineInt('MELISSA_PER_USER_DAILY_LOOKUPS', { default: 20 });
// App-wide daily Melissa credits for ALL endpoints together (src/budget.js).
// 0 = no paid Melissa call at all; the default is 0 so a missing value
// fails closed.
const GLOBAL_DAILY_CREDITS = defineInt('MELISSA_GLOBAL_DAILY_CREDITS', { default: 0 });
const CACHE_DAYS = defineInt('MELISSA_CACHE_DAYS', { default: 30 });
// `enforceAppCheck` takes a plain boolean (a params expression is an object
// and would always count as true), so it is read from the functions .env
// file at deploy time. Set ENFORCE_APP_CHECK=true once App Check is
// registered for both apps.
const ENFORCE_APP_CHECK = process.env.ENFORCE_APP_CHECK === 'true';
// Owner names from Melissa Property (public record): OFF until Melissa's
// license is confirmed to allow showing them (app owner, 2026-11-22).
const ALLOW_OWNER_NAMES = defineBoolean('MELISSA_ALLOW_OWNER_NAMES', { default: false });

exports.enrichHousehold = onCall(
  {
    region: 'us-central1',
    secrets: [MELISSA_CREDIT_LICENSE],
    enforceAppCheck: ENFORCE_APP_CHECK,
    timeoutSeconds: 30,
    memory: '256MiB',
    maxInstances: 5,
  },
  async (request) => {
    const fetchImpl = emulatorFetch();
    try {
      return await enrichHousehold({
        db: getFirestore(),
        uid: request.auth && request.auth.uid,
        data: request.data,
        key: MELISSA_CREDIT_LICENSE.value(),
        config: {
          perUserDailyLookups: PER_USER_DAILY_LOOKUPS.value(),
          globalDailyCredits: GLOBAL_DAILY_CREDITS.value(),
          cacheDays: CACHE_DAYS.value(),
          allowOwnerNames: ALLOW_OWNER_NAMES.value(),
        },
        check: (a, k, o) => checkAddress(a, k, { ...o, fetchImpl }),
        property: (a, k, o) => lookupProperty(a, k, { ...o, fetchImpl }),
        // No uid, address or key in logs: outcome and Melissa codes only.
        log: (entry) => logger.info(entry),
      });
    } catch (e) {
      if (e instanceof EnrichError) throw new HttpsError(e.code, e.reason);
      logger.error({ event: 'enrich', outcome: 'crash', message: String(e && e.message) });
      throw new HttpsError('internal', 'internal');
    }
  },
);

// Gap-filler: Melissa Reverse GeoCoder addresses where Overture has fewer
// than 50 homes. OFF until production spending is approved:
//   MELISSA_GAP_FILL_ENABLED=true (functions/.env.gps-para-el-cielo)
const GAP_FILL_ENABLED = defineBoolean('MELISSA_GAP_FILL_ENABLED', { default: false });
const GAP_PER_USER_DAILY = defineInt('MELISSA_GAP_PER_USER_DAILY', { default: 3 });
const GAP_DAILY_CREDITS = defineInt('MELISSA_GAP_DAILY_CREDITS', { default: 300 });
const GAP_VERIFY_RESIDENTIAL = defineBoolean('MELISSA_GAP_VERIFY_RESIDENTIAL', { default: false });

exports.discoverNearby = onCall(
  {
    region: 'us-central1',
    secrets: [MELISSA_CREDIT_LICENSE],
    enforceAppCheck: ENFORCE_APP_CHECK,
    timeoutSeconds: 60,
    memory: '256MiB',
    maxInstances: 3,
  },
  async (request) => {
    const fetchImpl = emulatorFetch();
    try {
      return await discoverNearby({
        db: getFirestore(),
        uid: request.auth && request.auth.uid,
        data: request.data,
        key: MELISSA_CREDIT_LICENSE.value(),
        config: {
          enabled: GAP_FILL_ENABLED.value(),
          perUserDaily: GAP_PER_USER_DAILY.value(),
          dailyCredits: GAP_DAILY_CREDITS.value(),
          globalDailyCredits: GLOBAL_DAILY_CREDITS.value(),
          verifyResidential: GAP_VERIFY_RESIDENTIAL.value(),
          cacheDays: CACHE_DAYS.value(),
        },
        reverse: (params, k) => reverseLookup(params, k, { fetchImpl }),
        check: (a, k, o) => checkAddress(a, k, { ...o, fetchImpl }),
        log: (entry) => logger.info(entry),
      });
    } catch (e) {
      if (e instanceof DiscoverError) throw new HttpsError(e.code, e.reason);
      logger.error({ event: 'gap', outcome: 'crash', message: String(e && e.message) });
      throw new HttpsError('internal', 'internal');
    }
  },
);

// Melissa-first neighborhood: nearby residential properties with their
// recorded owner (Reverse GeoCoder + Property). OFF until the pilot is
// approved AND Melissa confirms owner names may be shown:
//   MELISSA_OWNER_DISCOVERY_ENABLED=true and MELISSA_ALLOW_OWNER_NAMES=true
// Cost per new area: up to 100 x 2 (Reverse GeoCoder) + up to
// MELISSA_OWNER_MAX_LOOKUPS x 9 (Property) credits; unused credits are
// given back to the counters.
const OWNER_ENABLED = defineBoolean('MELISSA_OWNER_DISCOVERY_ENABLED', { default: false });
const OWNER_PER_USER_DAILY = defineInt('MELISSA_OWNER_PER_USER_DAILY', { default: 5 });
const OWNER_DAILY_CREDITS = defineInt('MELISSA_OWNER_DAILY_CREDITS', { default: 2000 });
const OWNER_MAX_LOOKUPS = defineInt('MELISSA_OWNER_MAX_LOOKUPS', { default: 80 });
const OWNER_RADIUS_MILES = defineInt('MELISSA_OWNER_RADIUS_MILES', { default: 1 });
const OWNER_SHARED_CACHE = defineBoolean('MELISSA_OWNER_SHARED_CACHE', { default: false });
const OWNER_MONTHLY_CREDITS = defineInt('MELISSA_OWNER_MONTHLY_CREDITS', { default: 20000 });
const OWNER_REQUEST_MAX_CREDITS = defineInt('MELISSA_OWNER_REQUEST_MAX_CREDITS', { default: 920 });
const OWNER_NEGATIVE_CACHE_DAYS = defineInt('MELISSA_OWNER_NEGATIVE_CACHE_DAYS', { default: 90 });

exports.discoverOwners = onCall(
  {
    region: 'us-central1',
    secrets: [MELISSA_CREDIT_LICENSE],
    enforceAppCheck: ENFORCE_APP_CHECK,
    timeoutSeconds: 120,
    memory: '256MiB',
    maxInstances: 5,
  },
  async (request) => {
    const fetchImpl = emulatorFetch();
    try {
      return await discoverOwners({
        db: getFirestore(),
        uid: request.auth && request.auth.uid,
        data: request.data,
        key: MELISSA_CREDIT_LICENSE.value(),
        config: {
          enabled: OWNER_ENABLED.value(),
          allowOwnerNames: ALLOW_OWNER_NAMES.value(),
          perUserDaily: OWNER_PER_USER_DAILY.value(),
          dailyCredits: OWNER_DAILY_CREDITS.value(),
          globalDailyCredits: GLOBAL_DAILY_CREDITS.value(),
          maxLookups: OWNER_MAX_LOOKUPS.value(),
          maxMiles: OWNER_RADIUS_MILES.value(),
          sharedCache: OWNER_SHARED_CACHE.value(),
          monthlyCredits: OWNER_MONTHLY_CREDITS.value(),
          perRequestMaxCredits: OWNER_REQUEST_MAX_CREDITS.value(),
          negativeCacheDays: OWNER_NEGATIVE_CACHE_DAYS.value(),
          cacheDays: CACHE_DAYS.value(),
        },
        reverse: (params, k) => reverseLookup(params, k, { fetchImpl }),
        property: (a, k, o) => lookupProperty(a, k, { ...o, fetchImpl }),
        // Counts only: no uid, address or name in logs.
        log: (entry) => logger.info(entry),
      });
    } catch (e) {
      if (e instanceof OwnerError) throw new HttpsError(e.code, e.reason);
      logger.error({ event: 'owners', outcome: 'crash', message: String(e && e.message) });
      throw new HttpsError('internal', 'internal');
    }
  },
);

// Account deleted (Firebase Auth): remove every per-user document the app
// cannot delete itself (server-written Melissa results, usage counters).
// The app deletes the rest (statuses, prayer history, notifications) first.
const { cleanupUser } = require('./cleanup');
const functionsV1 = require('firebase-functions/v1');
exports.cleanupDeletedUser = functionsV1.region('us-central1').auth.user().onDelete(async (user) => {
  const removed = await cleanupUser(getFirestore(), user.uid);
  logger.info({ event: 'cleanup', outcome: 'done', ...removed });
});
