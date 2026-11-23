# Overture household cells

Builds the household cell files that are stored in Firestore as `cells/{prefix}`
(see `docs/NEIGHBORS_FEATURE_SPEC.md`, sections 2 and 3). The build fails if any
file is larger than 900 KB, because Firestore limits a document to 1 MiB.

## Setup

```sh
cd tool/overture_cells
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
(cd ../seed_households && npm install)   # geofire-common, for the test
```

## Build (local files only)

```sh
.venv/bin/python build_cells.py --name spring_valley --bbox=-117.02,32.72,-116.96,32.76
.venv/bin/python build_cells.py --name california --state CA
.venv/bin/python build_cells.py --name usa
```

Whole US: `build_cells.py --name usa --memory 9GB --threads 6` (16 GB Mac;
large steps spill to disk under `out/_usa_work/tmp`). If it stops, run the
same command with `--resume`. That reuses the finished S3 download (and a
finished extract), and the release is pinned in `out/_usa_work/release.txt`.

Check a build before importing it:

```sh
.venv/bin/python validate_cells.py out/usa [--counts states.json]
```

The validator checks:
- the 900 KB file limit and the 1 MiB Firestore document limit;
- `p` and `v` in every file;
- homes inside their cell;
- the stub/child structure;
- duplicate ids and labels.

It also reports per-state counts, and writes `out/usa/validation.json`.

The output goes to `out/<name>/`: `cells/<prefix>.json.gz`, `meta.json` and
`report.json`. The `out/` folder is git-ignored.

A `--bbox` or `--state` build cuts the cells at the edge of its area, so those
edge cells are incomplete. Neighbouring states must be built together to fill
them.

## Test

```sh
.venv/bin/python -m pytest -q test_geohash.py
```

The test checks that `geohash.py` matches `geofire-common` exactly.

## Data rules

- The source is Overture `theme=addresses/type=address` with `country = 'US'`.
  The state is `address_levels[1]`. The city is `postal_city` when set,
  otherwise `address_levels[2]` after its last comma (NJ: "Essex, Newark" →
  NEWARK).
- Points without both a house number and a street are skipped.
- A unit is written as `APT <UNIT>`, unless the unit already starts with APT,
  UNIT, STE, # and so on.
- If the same label appears more than once at the same point, only the first
  is kept.
- A building record (no unit) is dropped when records with the same house
  number + street (same state, and same ZIP when both have one) have units.
  The match is by address, not distance. A building without units is kept.
- A missing city or postcode is taken first from another address at the
  exact same point, then from the nearest address within 100 m that has
  both. If neither has one, it stays missing and the app shows only "CA".
- Attribution: "Address data © Overture Maps Foundation". Each source dataset
  has its own license (for example, San Diego is
  `LicenseRef-Public-Domain-US-CA-Law`).

## Seed Firestore (`cells/{prefix}`)

```sh
node seed_firestore.js out/new_jersey                      # dry-run, production (nothing read or written)
node seed_firestore.js out/new_jersey --emulator --write   # local emulator (127.0.0.1:8080)
node seed_firestore.js out/california --write              # production, at most 18,000 writes per run
```

- Dry-run is the default, and only the `cells` collection is ever written.
  Nothing is deleted, and project `cielo-63925` is refused.
- Production uses your `gcloud auth login` token. The token is never printed.
- Each cell file becomes one document: `v`, `h` (the gz bytes), `n`, and
  `split` for stubs. Stub documents have no `h`.
- `--max-writes N` (default 18000) keeps a run under Spark's 20k writes a
  day. A run stops cleanly and prints how many documents remain; run the same
  command the next day to continue.
- Resumable: `out/.seed_progress/<area>.<emulator|production>.json` records
  what was written, with a hash of each file. It sits outside `out/<area>/`,
  which a rebuild deletes. A doc whose file changed since it was written is
  rewritten. For docs not in the progress file, the script reads
  `v`/`n`/`split` and skips the ones that already match. It never checks more
  docs than it can still write, so reads are about equal to writes, well
  under the 50k reads/day limit.
- `--rewrite`: v/n matches are not trusted, so every doc not verified in the
  progress file is written. Use it when an area was rebuilt and its progress
  file was lost.
- Batches hold up to 400 documents and go out in requests of 8 MiB or less,
  because Firestore limits a request to 10 MiB.
- The emulator needs Java 21. One way to run it:
  `PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" firebase emulators:start --only firestore --project gps-cielo`

## Client project and region-by-region import

```sh
node seed_firestore.js out/usa --project gps-para-el-cielo                     # dry-run
node seed_firestore.js out/usa --project gps-para-el-cielo --prefixes 9q,9r --write --max-writes 100000
```

- `--project` accepts only `gps-cielo` (default) and `gps-para-el-cielo`.
  The progress file is per project
  (`.seed_progress/<area>.gps-para-el-cielo.json`).
- `--prefixes` limits a run to cells under those geohash prefixes, so one
  national build can be imported wave by wave. A split cell's children
  share its prefix and always go with it.
- Sizes, waves and costs: `docs/NATIONWIDE_CELLS.md`.
