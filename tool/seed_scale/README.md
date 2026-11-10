# Scale-test seeding (Firestore emulator only)

Seeds deterministic **synthetic** households in Dhaka (dense old-city
clusters, medium clusters, sparse scatter) plus statuses for one test user,
for load and pagination testing. No npm packages are needed (Node ≥ 18).

**It cannot touch a real project:** it exits unless `FIRESTORE_EMULATOR_HOST`
points at this machine and the project id starts with `demo-` (emulator-only
projects). Every document is marked `isTest: true`, `seedSet: "scale"`, with
ids `scale_NNNNNN`; cleanup deletes only documents carrying both.

```sh
# 1. Start the emulator (from the repo root; needs a JDK on PATH)
firebase emulators:start --only firestore --project demo-gps-cielo-scale

# 2. Seed (from tool/seed_scale)
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
node seed.js --size 10000                    # 100 | 1000 | 10000 | 100000
node seed.js --size 100000 --statuses 3000   # statuses for scale-test-user
node seed.js --size 10000 --seed 7           # different, still deterministic

# 3. Remove the test data
node seed.js --cleanup
```

To run the app against it, point the app's Firestore at the emulator
(`FirebaseFirestore.instance.useFirestoreEmulator('10.0.2.2', 8080)` on the
Android emulator) in a debug build, with project id `demo-gps-cielo-scale`.

Verified on 2026-11-10: 10k and 100k seeded (100k households + 3,000
statuses in 2.4 s), same seed gives identical documents, the app's geohash
cell query returns results without a composite index, and cleanup removed
all 103,290 test documents while leaving unmarked documents in place.
