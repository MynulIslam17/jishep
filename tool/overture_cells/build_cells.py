#!/usr/bin/env python3
"""Builds household cell files from Overture Maps addresses.

Reads `theme=addresses/type=address` straight from Overture's public S3
bucket (no account or key), keeps US points, and writes one gzipped JSON file
per 5-character geohash cell (split into finer cells when a cell holds more
than --max-per-file points):

  <out>/cells/<prefix>.json.gz   {"v":release,"p":prefix,"h":[{i,a,o,g,l,c,z}]}
  <out>/cells/<prefix>.json.gz   {"v":release,"p":prefix,"split":6}  (stub)
  <out>/meta.json                {"release","cellPrecision":5,"maxPerFile",...}
  <out>/report.json

Record fields: i = Overture id, a/o = lat/lon (6 decimals, ~11 cm),
g = 9-char geohash of (a, o), l = "NUMBER STREET APT UNIT" (upper case),
c = "CITY, ST", z = postcode. Missing values are left out. No file for a
cell means the cell has no addresses.

Examples:
  .venv/bin/python build_cells.py --name spring_valley \
      --bbox=-117.02,32.72,-116.96,32.76
  .venv/bin/python build_cells.py --name california --state CA
  .venv/bin/python build_cells.py --name usa
  .venv/bin/python build_cells.py --name usa --resume   # after an interruption

--resume keeps out/_<name>_work/: a finished extract (extract.json) is
reused; otherwise a fully downloaded `raw` table is reused, so the S3
download is not repeated. The release is pinned in release.txt.
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import json
import pathlib
import re
import shutil
import sys
import time
import urllib.request

import duckdb
import numpy as np
import pyarrow as pa

import geohash

BUCKET = "overturemaps-us-west-2"
CELL_PRECISION = 5
MAX_PRECISION = 9

# Each file becomes one Firestore document (1 MiB limit per document).
MAX_FILE_BYTES = 900 * 1024

# Bounding boxes used to skip Parquet row groups early (the state filter
# itself is exact). Other states still work, by scanning all US rows.
STATE_BBOX = {
    "CA": (-124.49, 32.52, -114.12, 42.02),
    "NJ": (-75.57, 38.92, -73.88, 41.36),
}


def latest_release() -> str:
    url = (
        f"https://{BUCKET}.s3.amazonaws.com/?list-type=2"
        "&prefix=release/&delimiter=/"
    )
    with urllib.request.urlopen(url, timeout=30) as resp:
        body = resp.read().decode()
    releases = re.findall(r"<Prefix>release/([^<]+)/</Prefix>", body)
    if not releases:
        sys.exit("No Overture releases found")
    return sorted(releases)[-1]


def _gh9(lat: pa.Array, lon: pa.Array) -> pa.Array:
    lat_np = np.asarray(lat.to_numpy(zero_copy_only=False), dtype=np.float64)
    lon_np = np.asarray(lon.to_numpy(zero_copy_only=False), dtype=np.float64)
    return pa.array(geohash.encode(lat_np, lon_np, MAX_PRECISION).tolist())


def connect(work_db: pathlib.Path, threads: int | None, memory: str | None):
    con = duckdb.connect(str(work_db))
    for ext in ("httpfs", "spatial"):
        con.install_extension(ext)
        con.load_extension(ext)
    con.execute("SET s3_region='us-west-2'")
    con.execute(f"SET temp_directory='{work_db.parent / 'tmp'}'")
    con.execute("SET preserve_insertion_order=false")
    con.execute("SET max_temp_directory_size='150GB'")
    if threads:
        con.execute(f"SET threads={threads}")
    if memory:
        con.execute(f"SET memory_limit='{memory}'")
    con.create_function(
        "gh9",
        _gh9,
        [duckdb.sqltypes.DOUBLE, duckdb.sqltypes.DOUBLE],
        duckdb.sqltypes.VARCHAR,
        type="arrow",
    )
    return con


# Large steps run in slices so a 16 GB machine can build the whole US. Each
# slice holds whole groups (same point, same address or same id), so the
# result is identical to running the step at once.
SLICES = 16


def sliced(con, table: str, sql: str, slices: int = SLICES) -> None:
    """CREATE TABLE <table> from `sql`, run once per slice. In `sql`, {s}
    is replaced by a condition `% SLICES = i` to append to a hash()."""
    for i in range(slices):
        q = sql.replace("{s}", f"% {slices} = {i}")
        if i == 0:
            con.execute(f"CREATE OR REPLACE TABLE {table} AS {q}")
        else:
            con.execute(f"INSERT INTO {table} {q}")


def has_table(con, name: str) -> bool:
    return con.execute(
        "SELECT count(*) FROM information_schema.tables WHERE table_name = ?",
        [name]).fetchone()[0] > 0


def extract(con, release: str, bbox, state: str | None,
            reuse_raw: bool = False) -> dict:
    src = (
        f"s3://{BUCKET}/release/{release}/theme=addresses/type=address/*"
    )
    where = ["country = 'US'"]
    if bbox:
        x0, y0, x1, y1 = bbox
        where.append(
            f"bbox.xmin >= {x0} AND bbox.xmax <= {x1} "
            f"AND bbox.ymin >= {y0} AND bbox.ymax <= {y1}"
        )
    if state:
        where.append(f"address_levels[1].value = '{state}'")
    unit = "upper(trim(unit))"
    if reuse_raw:
        print("  reusing the downloaded raw table (--resume)", flush=True)
    else:
      con.execute(
        f"""
        CREATE OR REPLACE TABLE raw AS
        SELECT
          id,
          round(ST_Y(geometry), 6) AS lat,
          round(ST_X(geometry), 6) AS lon,
          -- A home needs a house number and a street; street-only points
          -- are skipped.
          CASE WHEN nullif(trim(number), '') IS NOT NULL
                AND nullif(trim(street), '') IS NOT NULL
            THEN upper(trim(number) || ' ' || trim(street))
          END AS addr,
          CASE
            WHEN unit IS NULL OR trim(unit) = '' THEN ''
            WHEN regexp_matches({unit},
              '^(#|(APT|UNIT|STE|SUITE|BLDG|SPC|LOT|RM|FL|TRLR|PH)( |$))')
              THEN ' ' || {unit}
            ELSE ' APT ' || {unit}
          END AS unit_part,
          -- The mailing city (postal_city) first. Some states have none and
          -- put "County, Municipality" in address_levels[2] (e.g. NJ
          -- "Essex, Newark"): keep the part after the last comma.
          nullif(upper(trim(coalesce(
            nullif(trim(postal_city), ''),
            regexp_extract(address_levels[2].value, '([^,]*)$', 1)))), '')
            AS city,
          nullif(upper(trim(address_levels[1].value)), '') AS st,
          nullif(trim(postcode), '') AS zip
        FROM read_parquet('{src}')
        WHERE {' AND '.join(where)}
        """
    )
    def count(sql: str) -> int:
        return con.execute(sql).fetchone()[0]

    raw = count("SELECT count(*) FROM raw")
    no_number = count("SELECT count(*) FROM raw WHERE addr IS NULL")

    # 1. Homes: one row per label and point.
    sliced(con, "h1", """
        -- The row with the lowest id per label and point.
        SELECT v.id AS id, lat, lon, addr, unit_part,
          v.city AS city, v.st AS st, v.zip AS zip
        FROM (
          SELECT addr, unit_part, lat, lon,
            arg_min({'id': id, 'city': city, 'st': st, 'zip': zip}, id) AS v
          FROM raw WHERE addr IS NOT NULL AND hash(lat, lon) {s}
          GROUP BY addr, unit_part, lat, lon
        )
        """)
    con.execute("DROP TABLE raw")
    homes = count("SELECT count(*) FROM h1")

    # 2. Units often lack city/postcode: take them from another address at
    #    the same point (usually the building record).
    sliced(con, "h2", """
        SELECT h.id, h.lat, h.lon, h.addr, h.unit_part, h.st,
          h.city IS NULL AND p.mc IS NOT NULL
            OR h.zip IS NULL AND p.mz IS NOT NULL AS same_filled,
          coalesce(h.city, p.mc) AS city,
          coalesce(h.zip, p.mz) AS zip
        FROM (SELECT * FROM h1 WHERE hash(lat, lon) {s}) h
        JOIN (SELECT lat, lon, max(city) AS mc, max(zip) AS mz
              FROM h1 WHERE hash(lat, lon) {s} GROUP BY lat, lon) p
          USING (lat, lon)
        """)
    con.execute("DROP TABLE h1")
    same_filled = count("SELECT count(*) FROM h2 WHERE same_filled")
    # Donors for step 4, including building records dropped in step 3.
    sliced(con, "donors", """
        SELECT DISTINCT lat, lon, city, zip,
          CAST(floor(lat * 1000) AS BIGINT) AS gy,
          CAST(floor(lon * 1000) AS BIGINT) AS gx
        FROM h2 WHERE city IS NOT NULL AND zip IS NOT NULL
          AND hash(lat, lon) {s}
        """)

    # 3. A building record (no unit) is dropped when records with the same
    #    house number + street (same state, and same ZIP when both have
    #    one) have units. Matched by address, not distance. Kept otherwise.
    sliced(con, "buildings", """
        SELECT DISTINCT b.id
        FROM (SELECT id, addr, st, zip FROM h2
              WHERE unit_part = '' AND hash(addr) {s}) b
        JOIN (SELECT DISTINCT addr, st, zip FROM h2
              WHERE unit_part <> '' AND hash(addr) {s}) u
          ON u.addr = b.addr AND u.st IS NOT DISTINCT FROM b.st
        WHERE b.zip IS NULL OR u.zip IS NULL OR u.zip = b.zip
        """)
    buildings = count("SELECT count(*) FROM buildings")
    sliced(con, "h3", """
        SELECT h.* EXCLUDE (same_filled)
        FROM (SELECT * FROM h2 WHERE hash(id) {s}) h
        ANTI JOIN (SELECT id FROM buildings WHERE hash(id) {s}) b USING (id)
        """)
    con.execute("DROP TABLE h2")
    con.execute("DROP TABLE buildings")

    # 4. Still missing: city and postcode of the nearest home within 100 m
    #    that has both. Grid of 0.001° cells; ±1 cell north/south (111 m)
    #    and ±3 east/west (>= 100 m up to ~72° N).
    sliced(con, "near_fill", """
        SELECT id, arg_min({'c': city, 'z': zip}, dist) AS v
        FROM (
          SELECT m.id, d.city, d.zip,
            111320 * sqrt(power(d.lat - m.lat, 2)
              + power((d.lon - m.lon) * cos(radians(m.lat)), 2)) AS dist
          FROM (
            SELECT id, lat, lon,
              CAST(floor(lat * 1000) AS BIGINT) + dy AS gy,
              CAST(floor(lon * 1000) AS BIGINT) + dx AS gx
            FROM h3, range(-1, 2) t1(dy), range(-3, 4) t2(dx)
            WHERE (city IS NULL OR zip IS NULL) AND hash(id) {s}
          ) m
          JOIN donors d USING (gy, gx)
        )
        WHERE dist <= 100
        GROUP BY id
        """)
    near_filled = count("SELECT count(*) FROM near_fill")
    sliced(con, "pts", """
        SELECT h.id, h.lat, h.lon,
          h.addr || h.unit_part AS label,
          nullif(concat_ws(', ', coalesce(h.city, f.v.c), h.st), '') AS c,
          coalesce(h.zip, f.v.z) AS z,
          coalesce(h.city, f.v.c) IS NULL OR coalesce(h.zip, f.v.z) IS NULL
            AS incomplete
        FROM (SELECT * FROM h3 WHERE hash(id) {s}) h
        LEFT JOIN (SELECT * FROM near_fill WHERE hash(id) {s}) f USING (id)
        """)
    for t in ("h3", "donors", "near_fill"):
        con.execute(f"DROP TABLE {t}")
    still_missing = count("SELECT count(*) FROM pts WHERE incomplete")
    con.execute("ALTER TABLE pts DROP COLUMN incomplete")
    kept = count("SELECT count(*) FROM pts")
    con.execute("ALTER TABLE pts ADD COLUMN g VARCHAR")
    con.execute("UPDATE pts SET g = gh9(lat, lon)")
    con.execute("CHECKPOINT")
    return {
        "read": raw,
        "skippedNoHouseNumber": no_number,
        "duplicatesRemoved": raw - no_number - homes,
        "buildingRecordsDropped": buildings,
        "cityZipFilledSamePoint": same_filled,
        "cityZipFilledWithin100m": near_filled,
        "cityOrZipStillMissing": still_missing,
        "points": kept,
    }


def assign_files(con, max_per_file: int):
    """Each point's file prefix: the shortest prefix (>= 5) holding at most
    max_per_file points; plus the split stubs above it."""
    # Split prefixes, level by level: a prefix is split when it holds more
    # than max_per_file points (only children of split prefixes are counted).
    con.execute("CREATE OR REPLACE TABLE split_p (p VARCHAR, k INT)")
    for k in range(CELL_PRECISION, MAX_PRECISION):
        parent = (f"WHERE left(g, {k - 1}) IN (SELECT p FROM split_p "
                  f"WHERE k = {k - 1})" if k > CELL_PRECISION else "")
        con.execute(
            f"""
            INSERT INTO split_p
            SELECT left(g, {k}), {k} FROM pts {parent}
            GROUP BY 1 HAVING count(*) > {max_per_file}
            """
        )
    # A point's file: its g cut after the split prefixes above it (splits
    # are nested), i.e. the shortest prefix with <= max_per_file points.
    joins = " ".join(
        f"LEFT JOIN (SELECT p FROM split_p WHERE k = {k}) s{k} "
        f"ON s{k}.p = left(pts.g, {k})"
        for k in range(CELL_PRECISION, MAX_PRECISION)
    )
    depth = " + ".join(
        f"CAST(s{k}.p IS NOT NULL AS INT)"
        for k in range(CELL_PRECISION, MAX_PRECISION)
    )
    con.execute(
        f"""
        CREATE OR REPLACE TABLE placed AS
        SELECT pts.*, left(pts.g, {CELL_PRECISION} + {depth}) AS f
        FROM pts {joins}
        """
    )
    stubs = con.execute(
        "SELECT p, k + 1 AS split FROM split_p ORDER BY p"
    ).fetchall()
    return stubs


def _write(path: pathlib.Path, obj) -> int:
    data = gzip.compress(
        json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode(),
        compresslevel=9,
        mtime=0,
    )
    path.write_bytes(data)
    return len(data)


def write_files(con, out: pathlib.Path, release: str, stubs) -> dict:
    cells = out / "cells"
    cells.mkdir(parents=True)
    sizes = {}
    counts = {}
    for prefix, split in stubs:
        sizes[prefix] = _write(
            cells / f"{prefix}.json.gz",
            {"v": release, "p": prefix, "split": split},
        )

    cur = con.execute(
        "SELECT f, id, lat, lon, g, label, c, z FROM placed ORDER BY f, g, id"
    )
    current, rows = None, []

    def flush():
        if current is None:
            return
        sizes[current] = _write(
            cells / f"{current}.json.gz",
            {"v": release, "p": current, "h": rows},
        )
        counts[current] = len(rows)

    while True:
        batch = cur.fetchmany(50_000)
        if not batch:
            break
        for f, i, a, o, g, l, c, z in batch:
            if f != current:
                flush()
                current, rows = f, []
            rec = {"i": i, "a": a, "o": o, "g": g, "l": l}
            if c:
                rec["c"] = c
            if z:
                rec["z"] = z
            rows.append(rec)
    flush()
    return {"sizes": sizes, "counts": counts}


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--name", required=True, help="output folder under out/")
    ap.add_argument("--bbox", help="minLon,minLat,maxLon,maxLat")
    ap.add_argument("--state", help="two-letter state code, e.g. CA")
    ap.add_argument("--release", help="Overture release (default: latest)")
    ap.add_argument("--max-per-file", type=int, default=4000)
    ap.add_argument("--out", default=str(pathlib.Path(__file__).parent / "out"))
    ap.add_argument("--threads", type=int)
    ap.add_argument("--memory", help="DuckDB memory limit, e.g. 8GB")
    ap.add_argument("--resume", action="store_true",
                    help="continue an interrupted build (see above)")
    args = ap.parse_args()

    bbox = tuple(float(v) for v in args.bbox.split(",")) if args.bbox else None
    state = args.state.upper() if args.state else None
    if state and not bbox:
        bbox = STATE_BBOX.get(state)
    out = pathlib.Path(args.out) / args.name
    work = out.parent / f"_{args.name}_work"
    resume = args.resume and work.exists()
    if work.exists() and not resume:
        shutil.rmtree(work)
    work.mkdir(parents=True, exist_ok=True)
    pinned = work / "release.txt"
    if resume and pinned.exists():
        release = pinned.read_text().strip()
    else:
        release = args.release or latest_release()
        pinned.write_text(release + "\n")
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)

    t0 = time.time()
    print(f"Overture release {release}, area: "
          f"{'bbox ' + str(bbox) if bbox else 'all US'}"
          f"{', state ' + state if state else ''}", flush=True)
    con = connect(work / "work.duckdb", args.threads, args.memory)
    done = work / "extract.json"
    if resume and done.exists() and has_table(con, "pts"):
        stats = json.loads(done.read_text())
        print("  reusing the finished extract (--resume)", flush=True)
    else:
        stats = extract(con, release, bbox, state,
                        reuse_raw=resume and has_table(con, "raw"))
        done.write_text(json.dumps(stats) + "\n")
    t1 = time.time()
    print(f"  extracted {stats['points']:,} points in {t1 - t0:.0f}s",
          flush=True)
    stubs = assign_files(con, args.max_per_file)
    files = write_files(con, out, release, stubs)
    con.close()
    too_big = {p: b for p, b in files["sizes"].items() if b > MAX_FILE_BYTES}
    if too_big:
        for p, b in sorted(too_big.items(), key=lambda x: -x[1]):
            print(f"  TOO BIG: {p}.json.gz {b:,} bytes", file=sys.stderr)
        sys.exit(f"Build failed: {len(too_big)} file(s) over "
                 f"{MAX_FILE_BYTES // 1024} KB (Firestore document limit). "
                 "Lower --max-per-file.")
    shutil.rmtree(work)
    t2 = time.time()

    meta = {
        "release": release,
        "cellPrecision": CELL_PRECISION,
        "maxPerFile": args.max_per_file,
    }
    (out / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")

    sizes, counts = files["sizes"], files["counts"]
    largest = max(sizes, key=sizes.get) if sizes else None
    fullest = max(counts, key=counts.get) if counts else None
    by_len = {}
    for p in counts:
        by_len[len(p)] = by_len.get(len(p), 0) + 1
    report = {
        "name": args.name,
        "release": release,
        "bbox": bbox,
        "state": state,
        **stats,
        "dataFiles": len(counts),
        "dataFilesByPrecision": dict(sorted(by_len.items())),
        "stubFiles": len(stubs),
        "firestoreDocs": len(counts) + len(stubs),
        "totalBytes": sum(sizes.values()),
        "largestFile": largest and {
            "prefix": largest, "bytes": sizes[largest],
            "points": counts.get(largest)},
        "mostPoints": fullest and {
            "prefix": fullest, "points": counts[fullest],
            "bytes": sizes[fullest]},
        "avgBytesPerPoint": round(sum(sizes.values()) / stats["points"], 2)
        if stats["points"] else None,
        "seconds": {"extract": round(t1 - t0), "write": round(t2 - t1)},
        "builtAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
    }
    (out / "report.json").write_text(json.dumps(report, indent=2) + "\n")

    print(f"""
Report ({out})
  points kept          {stats['points']:,}
  read from Overture   {stats['read']:,}
  skipped (no number)  {stats['skippedNoHouseNumber']:,}
  duplicates removed   {stats['duplicatesRemoved']:,}
  building rows drop   {stats['buildingRecordsDropped']:,}
  city/zip same point  {stats['cityZipFilledSamePoint']:,}
  city/zip <= 100 m    {stats['cityZipFilledWithin100m']:,}
  city/zip missing     {stats['cityOrZipStillMissing']:,}
  data files           {len(counts):,}  {report['dataFilesByPrecision']}
  split stubs          {len(stubs):,}
  Firestore docs       {len(counts) + len(stubs):,}
  total size           {human(report['totalBytes'])}
  largest file         {largest}.json.gz {human(sizes[largest]) if largest else '-'}
  most points          {fullest} ({counts[fullest] if fullest else 0:,})
  bytes per point      {report['avgBytesPerPoint']}
  time                 {t2 - t0:.0f}s""")


if __name__ == "__main__":
    main()
