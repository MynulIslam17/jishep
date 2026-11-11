// Runs only against the Firestore emulator (demo- project id, no network).
const fs = require('fs');
const path = require('path');
const { test, before, after, beforeEach } = require('node:test');
const {
  initializeTestEnvironment, assertSucceeds, assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, getDocs,
  query, where, orderBy, startAt, endAt, runTransaction, serverTimestamp, GeoPoint,
} = require('firebase/firestore');

let env;
// ID-token claims like the real ones the app gets.
const passwordUser = (uid, email, emailVerified = true, extra = {}) =>
  env.authenticatedContext(uid, {
    email, email_verified: emailVerified,
    firebase: { sign_in_provider: 'password' }, ...extra,
  }).firestore();
const alice = () => passwordUser('alice', 'a@example.com');
const aliceUnverified = () => passwordUser('alice', 'a@example.com', false);
const bob = () => passwordUser('bob', 'b@example.com');
const guest = () => env.unauthenticatedContext().firestore();

// What HouseholdRepository.saveStatus writes.
const status = (over = {}) => ({
  isPrayed: true, isVisited: false, isInvited: false, hasFollowUp: false,
  followUpDate: null, notes: null, residentName: 'Demo Household 001',
  address: 'Demo', prayedAt: new Date(), updatedAt: serverTimestamp(), ...over,
});

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-gps-cielo-rules',
    firestore: { rules: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') },
  });
});
after(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users/alice'), { fullName: 'Alice', email: 'a@example.com' });
    await setDoc(doc(db, 'users/alice/household_status/h1'), { isPrayed: true });
    await setDoc(doc(db, 'users/alice/notifications/n1'), { title: 't', isRead: false });
    await setDoc(doc(db, 'households/h1'), {
      residentName: 'Demo Household 001', address: 'Demo', cityStateZip: '',
      geo: { geohash: 'wh0r82gby2', geopoint: new GeoPoint(23.82, 90.36) },
    });
  });
});

test('profile: owner reads, creates (transaction) and updates own profile', async () => {
  await assertSucceeds(getDoc(doc(alice(), 'users/alice')));
  await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { address: 'x', latitude: 1, longitude: 2 }));
  // Sign up: the profile is created before the email is verified.
  const db = passwordUser('carol', 'Carol@Example.com', false);
  await assertSucceeds(runTransaction(db, async (tx) => {
    const ref = doc(db, 'users/carol');
    const snap = await tx.get(ref);
    if (!snap.exists()) {
      tx.set(ref, {
        fullName: 'Carol', email: 'carol@example.com', phone: null,
        avatarUrl: null, avatarBase64: null, address: '', churchAffiliation: '',
        dailyPrayerTarget: 5, prayerCycleTarget: 50, radiusHomes: 10,
        searchRadiusKm: 5, latitude: null, longitude: null,
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      });
    }
  }));
});

test('profile: other users and guests are denied', async () => {
  await assertFails(getDoc(doc(bob(), 'users/alice')));
  await assertFails(setDoc(doc(bob(), 'users/alice'), { fullName: 'hijack' }, { merge: true }));
  await assertFails(deleteDoc(doc(bob(), 'users/alice')));
  await assertFails(getDoc(doc(guest(), 'users/alice')));
});

test('profile: avatar larger than 300000 chars is rejected', async () => {
  await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { avatarBase64: 'a'.repeat(1000) }));
  await assertFails(updateDoc(doc(alice(), 'users/alice'), { avatarBase64: 'a'.repeat(300001) }));
});

test('household_status and notifications are private to their owner', async () => {
  await assertSucceeds(getDocs(collection(alice(), 'users/alice/household_status')));
  await assertSucceeds(setDoc(doc(alice(), 'users/alice/household_status/h2'), status(), { merge: true }));
  await assertSucceeds(getDocs(query(collection(alice(), 'users/alice/notifications'), orderBy('timestamp', 'desc'))));
  await assertSucceeds(updateDoc(doc(alice(), 'users/alice/notifications/n1'), { isRead: true }));
  await assertSucceeds(deleteDoc(doc(alice(), 'users/alice/notifications/n1')));

  await assertFails(getDocs(collection(bob(), 'users/alice/household_status')));
  await assertFails(setDoc(doc(bob(), 'users/alice/household_status/h1'), status({ isPrayed: false })));
  await assertFails(getDocs(collection(bob(), 'users/alice/notifications')));
  await assertFails(addDoc(collection(bob(), 'users/alice/notifications'), { title: 'spam' }));
});

test('households: signed-in users can read and geo-query; nobody can write', async () => {
  await assertSucceeds(getDoc(doc(alice(), 'households/h1')));
  await assertSucceeds(getDocs(query(
    collection(alice(), 'households'), orderBy('geo.geohash'), startAt('wh0r'), endAt('wh0r~'),
  )));
  await assertFails(getDoc(doc(guest(), 'households/h1')));
  await assertFails(setDoc(doc(alice(), 'households/h1'), { residentName: 'x' }, { merge: true }));
  await assertFails(addDoc(collection(alice(), 'households'), { residentName: 'x' }));
  await assertFails(deleteDoc(doc(alice(), 'households/h1')));
});

test('support_messages: create own; read and delete only own; no edits', async () => {
  const ok = { uid: 'alice', email: 'a@example.com', message: 'Help', status: 'open', createdAt: serverTimestamp() };
  const ref = await assertSucceeds(addDoc(collection(alice(), 'support_messages'), ok));
  await assertFails(addDoc(collection(alice(), 'support_messages'), { ...ok, uid: 'bob' }));
  await assertFails(addDoc(collection(alice(), 'support_messages'), { ...ok, message: 'x'.repeat(5001) }));
  await assertFails(addDoc(collection(alice(), 'support_messages'), { ...ok, message: 42 }));
  await assertFails(addDoc(collection(alice(), 'support_messages'), { ...ok, message: '' }));
  await assertFails(addDoc(collection(alice(), 'support_messages'), { ...ok, status: 'closed' }));
  await assertFails(addDoc(collection(alice(), 'support_messages'), { ...ok, extra: 1 }));
  await assertFails(addDoc(collection(guest(), 'support_messages'), ok));
  await assertFails(addDoc(collection(aliceUnverified(), 'support_messages'), ok));

  // Owner can list and delete their own (account deletion).
  await assertSucceeds(getDoc(doc(alice(), `support_messages/${ref.id}`)));
  await assertSucceeds(getDocs(query(collection(alice(), 'support_messages'), where('uid', '==', 'alice'))));
  await assertFails(updateDoc(doc(alice(), `support_messages/${ref.id}`), { status: 'closed' }));

  // Nobody else can read, list or delete it.
  await assertFails(getDoc(doc(bob(), `support_messages/${ref.id}`)));
  await assertFails(getDocs(collection(bob(), 'support_messages')));
  await assertFails(getDocs(query(collection(bob(), 'support_messages'), where('uid', '==', 'alice'))));
  await assertFails(deleteDoc(doc(bob(), `support_messages/${ref.id}`)));
  await assertFails(getDoc(doc(guest(), `support_messages/${ref.id}`)));

  await assertSucceeds(deleteDoc(doc(alice(), `support_messages/${ref.id}`)));
});

test('email verification: unverified password accounts cannot record activity', async () => {
  await assertFails(setDoc(doc(aliceUnverified(), 'users/alice/household_status/h2'), status()));
  await assertSucceeds(setDoc(doc(alice(), 'users/alice/household_status/h2'), status()));
  // Google and phone sign-ins are verified by their provider.
  const google = env.authenticatedContext('alice', {
    email: 'a@example.com', firebase: { sign_in_provider: 'google.com' },
  }).firestore();
  await assertSucceeds(setDoc(doc(google, 'users/alice/household_status/h3'), status()));
  // The unverified user can still finish their profile and location.
  await assertSucceeds(updateDoc(doc(aliceUnverified(), 'users/alice'), { address: 'x', latitude: 1, longitude: 2 }));
});

test('Sign in with Apple: hidden email, no name, verified by Apple', async () => {
  // Apple may hide the address (private relay) and send no name; the token
  // may lack email_verified. The account is still verified by Apple.
  const relay = 'x7k2p9@privaterelay.appleid.com';
  const apple = env.authenticatedContext('ann', {
    email: relay, firebase: { sign_in_provider: 'apple.com' },
  }).firestore();
  await assertSucceeds(setDoc(doc(apple, 'users/ann'), { fullName: '', email: relay }));
  await assertSucceeds(setDoc(doc(apple, 'users/ann/household_status/h1'), status()));
  // The relay address cannot be swapped for someone else's email.
  await assertFails(updateDoc(doc(apple, 'users/ann'), { email: 'b@example.com' }));
  // Another user's data stays closed.
  await assertFails(setDoc(doc(apple, 'users/alice/household_status/h9'), status()));
});

test('household_status: only the fields and types the app writes', async () => {
  const ref = (db) => doc(db, 'users/alice/household_status/h2');
  await assertFails(setDoc(ref(alice()), status({ isPrayed: 'yes' })));
  await assertFails(setDoc(ref(alice()), status({ notes: 'x'.repeat(2001) })));
  await assertFails(setDoc(ref(alice()), status({ score: 99 })));
  await assertFails(setDoc(ref(alice()), status({ updatedAt: new Date(2000, 1, 1) })));
  await assertSucceeds(setDoc(ref(alice()), status({ notes: 'Call back Sunday', hasFollowUp: true, followUpDate: '2026-11-20' })));
  // Un-pray removes prayedAt (merge + delete).
  const { deleteField } = require('firebase/firestore');
  await assertSucceeds(setDoc(ref(alice()), status({ isPrayed: false, prayedAt: deleteField() }), { merge: true }));
});

test('profile: unknown fields, bad types and out-of-range values are rejected', async () => {
  const me = doc(alice(), 'users/alice');
  await assertFails(updateDoc(me, { isAdmin: true }));
  await assertFails(updateDoc(me, { dailyPrayerTarget: 0 }));
  await assertFails(updateDoc(me, { dailyPrayerTarget: '15' }));
  await assertFails(updateDoc(me, { radiusHomes: 5000 }));
  await assertFails(updateDoc(me, { latitude: 123 }));
  await assertFails(updateDoc(me, { fullName: 'x'.repeat(101) }));
  await assertSucceeds(updateDoc(me, {
    dailyPrayerTarget: 15, radiusHomes: 20, searchRadiusKm: 5,
    prayerCycleStartedAt: new Date(), updatedAt: serverTimestamp(),
  }));
});

test('profile: email must be the account email; phone must be the verified one', async () => {
  const me = doc(alice(), 'users/alice');
  await assertFails(updateDoc(me, { email: 'someone-else@example.com' }));
  await assertSucceeds(updateDoc(me, { email: 'A@Example.com' }));

  // Not linked to a phone yet: cannot claim a number.
  await assertFails(updateDoc(me, { phone: '+8801700000000' }));
  // After SMS verification the token carries phone_number.
  const linked = passwordUser('alice', 'a@example.com', true, { phone_number: '+8801700000000' });
  await assertSucceeds(updateDoc(doc(linked, 'users/alice'), { phone: '+8801700000000' }));
  await assertFails(updateDoc(doc(linked, 'users/alice'), { phone: '+8801799999999' }));
  // Unchanged phone does not block other edits.
  await assertSucceeds(updateDoc(doc(alice(), 'users/alice'), { fullName: 'Alice B' }));
});

test('notifications: well-formed create; clients only mark read', async () => {
  const col = collection(alice(), 'users/alice/notifications');
  const ok = { title: 'Pray today', message: '15 neighbors', type: 'prayerReminder', isRead: false, actionRoute: null, timestamp: serverTimestamp() };
  await assertSucceeds(addDoc(col, ok));
  await assertFails(addDoc(col, { ...ok, type: 'phishing' }));
  await assertFails(addDoc(col, { ...ok, extra: 1 }));
  await assertFails(updateDoc(doc(alice(), 'users/alice/notifications/n1'), { title: 'changed' }));
  await assertSucceeds(updateDoc(doc(alice(), 'users/alice/notifications/n1'), { isRead: true }));
});

test('devices: owner registers and removes own push tokens only', async () => {
  const token = 'fcm-token:APA91b_abc-123';
  const device = (over = {}) => ({
    token, platform: 'ios', updatedAt: serverTimestamp(), ...over,
  });
  await assertSucceeds(setDoc(doc(alice(), `users/alice/devices/${token}`), device()));
  // Re-registering the same token overwrites the one document.
  await assertSucceeds(setDoc(doc(alice(), `users/alice/devices/${token}`), device({ platform: 'ios' })));
  await assertSucceeds(getDocs(collection(alice(), 'users/alice/devices')));
  await assertSucceeds(deleteDoc(doc(alice(), `users/alice/devices/${token}`)));

  // The document id must be the token; known platforms and fields only.
  await assertFails(setDoc(doc(alice(), 'users/alice/devices/other'), device()));
  await assertFails(setDoc(doc(alice(), `users/alice/devices/${token}`), device({ platform: 'web' })));
  await assertFails(setDoc(doc(alice(), `users/alice/devices/${token}`), device({ extra: 1 })));
  await assertFails(setDoc(doc(alice(), `users/alice/devices/${token}`), device({ updatedAt: new Date(0) })));

  // Nobody else can read or add devices for Alice.
  await assertFails(getDocs(collection(bob(), 'users/alice/devices')));
  await assertFails(setDoc(doc(bob(), `users/alice/devices/${token}`), device()));
  await assertFails(getDocs(collection(guest(), 'users/alice/devices')));
});

test('unknown collections are denied by default', async () => {
  await assertFails(getDoc(doc(alice(), 'admin/config')));
  await assertFails(setDoc(doc(alice(), 'anything/x'), { a: 1 }));
});
