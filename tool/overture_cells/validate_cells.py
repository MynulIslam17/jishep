#!/usr/bin/env python3
"""Checks a build_cells.py output folder before it is imported.

  .venv/bin/python validate_cells.py out/usa [--counts states.json]

Checks every file (independently of the build's own report):
  - gz file <= 900 KB, and the Firestore document it becomes < 1 MiB
  - valid JSON; `p` = file name; `v` = meta release
  - data files: <= maxPerFile homes; every home has id, lat/lon, geohash,
    label; its geohash starts with the cell prefix and matches its lat/lon
  - stubs: split = len(prefix) + 1, at least one child exists, and no data
    file has the same prefix
  - every data/stub file longer than 5 chars has a stub parent
  - no Overture id appears twice anywhere; no same label at the same point
Then reports totals, per-state counts (from "CITY, ST"), units, missing
city/ZIP, and, with --counts, each state vs the raw Overture count.

Writes <dir>/validation.json and prints a summary. Exit 1 on any error.
"""
from __future__ import annotations

import argparse
import collections
import gzip
import hashlib
import json
import multiprocessing as mp
import pathlib
import re
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import geohash  # noqa: E402

MAX_FILE_BYTES = 900 * 1024
FIRESTORE_DOC_LIMIT = 1024 * 1024
UNIT_RE = re.compile(r" (APT|UNIT|STE|SUITE|BLDG|SPC|LOT|RM|FL|TRLR|PH|#)( |\d|$)|#")


def doc_bytes(prefix: str, gz_len: int, release: str, split: int | None) -> int:
    """Firestore storage size of the document (name + fields + 32)."""
    name = len(f"cells/{prefix}") + 1 + 16
    fields = (2 + len(release) + 1) + (2 + 8)  # v, n
    fields += (2 + 8) if split else (2 + gz_len)  # split or h
    return name + fields + 32


def check_file(args):
    path, release, max_per = args
    prefix = path.name[: -len(".json.gz")]
    gz = path.read_bytes()
    out = {"prefix": prefix, "bytes": len(gz), "errors": [], "split": None,
           "n": 0, "states": collections.Counter(), "units": 0,
           "noCity": 0, "noZip": 0, "dupLabel": 0, "ids": None}
    try:
        body = json.loads(gzip.decompress(gz))
    except Exception as e:  # noqa: BLE001
        out["errors"].append(f"{prefix}: unreadable ({e})")
        return out
    if body.get("p") != prefix:
        out["errors"].append(f"{prefix}: p={body.get('p')}")
    if body.get("v") != release:
        out["errors"].append(f"{prefix}: v={body.get('v')}")
    if len(gz) > MAX_FILE_BYTES:
        out["errors"].append(f"{prefix}: {len(gz)} bytes > 900 KB")
    split = body.get("split")
    out["doc"] = doc_bytes(prefix, len(gz), release, split)
    if out["doc"] >= FIRESTORE_DOC_LIMIT:
        out["errors"].append(f"{prefix}: Firestore doc {out['doc']} >= 1 MiB")
    if split is not None:
        out["split"] = split
        if split != len(prefix) + 1:
            out["errors"].append(f"{prefix}: split={split}")
        return out
    homes = body.get("h") or []
    out["n"] = len(homes)
    if not homes:
        out["errors"].append(f"{prefix}: empty data file")
    # A 9-character cell (about 5 m) cannot be split further: one very
    # large building may exceed max_per there. Size is still checked above.
    if len(homes) > max_per and len(prefix) < 9:
        out["errors"].append(f"{prefix}: {len(homes)} homes > {max_per}")
    if len(homes) > max_per:
        out["oversize9"] = len(homes)
    ids, lats, lons, seen = [], [], [], set()
    bad = 0
    for h in homes:
        i, a, o, g, l = h.get("i"), h.get("a"), h.get("o"), h.get("g"), h.get("l")
        if not (i and isinstance(a, (int, float)) and isinstance(o, (int, float))
                and g and l) or not str(g).startswith(prefix):
            bad += 1
            continue
        ids.append(int.from_bytes(hashlib.blake2b(i.encode(), digest_size=8).digest(), "little"))
        lats.append(a); lons.append(o)
        key = (l, a, o)
        if key in seen:
            out["dupLabel"] += 1
        seen.add(key)
        c = h.get("c")
        st = c.rsplit(", ", 1)[-1] if c else "?"
        out["states"][st] += 1
        if not c or ", " not in c:
            out["noCity"] += 1
        if not h.get("z"):
            out["noZip"] += 1
        if UNIT_RE.search(l):
            out["units"] += 1
    if bad:
        out["errors"].append(f"{prefix}: {bad} homes missing fields or outside the cell")
    if lats:
        # The stored geohash must match the stored coordinates.
        g9 = geohash.encode(np.array(lats), np.array(lons), len(prefix))
        g9 = [x.decode() if isinstance(x, bytes) else str(x) for x in g9]
        wrong = sum(1 for x in g9 if x != prefix)
        if wrong:
            out["errors"].append(f"{prefix}: {wrong} homes whose lat/lon is in another cell")
    out["ids"] = np.array(ids, dtype=np.uint64)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--counts", help="states.json from a raw Overture count")
    ap.add_argument("--workers", type=int, default=max(1, mp.cpu_count() - 2))
    a = ap.parse_args()
    d = pathlib.Path(a.dir)
    meta = json.loads((d / "meta.json").read_text())
    release, max_per = meta["release"], meta["maxPerFile"]
    files = sorted((d / "cells").glob("*.json.gz"))
    print(f"Validating {len(files):,} files in {d} (release {release})", flush=True)

    errors, stubs, data = [], {}, {}
    states = collections.Counter()
    total = units = no_city = no_zip = dup_label = 0
    doc_total = gz_total = 0
    largest = ("", 0)
    oversize9 = {}
    id_parts = []
    with mp.Pool(a.workers) as pool:
        for k, r in enumerate(pool.imap_unordered(
                check_file, [(f, release, max_per) for f in files], chunksize=64)):
            errors += r["errors"]
            gz_total += r["bytes"]; doc_total += r.get("doc", 0)
            if r.get("oversize9"):
                oversize9[r["prefix"]] = r["oversize9"]
            if r["bytes"] > largest[1]:
                largest = (r["prefix"], r["bytes"])
            if r["split"] is not None:
                stubs[r["prefix"]] = r["split"]
            else:
                data[r["prefix"]] = r["n"]
                total += r["n"]; units += r["units"]
                no_city += r["noCity"]; no_zip += r["noZip"]
                dup_label += r["dupLabel"]; states.update(r["states"])
                if r["ids"] is not None:
                    id_parts.append(r["ids"])
            if (k + 1) % 50000 == 0:
                print(f"  {k + 1:,} files checked", flush=True)

    # Structure: stubs have children, no stub/data clash, parents exist.
    children = collections.Counter()
    for p in list(data) + list(stubs):
        if len(p) > 5:
            children[p[:-1]] += 1
            if p[:-1] not in stubs:
                errors.append(f"{p}: no stub for parent {p[:-1]}")
    for p in stubs:
        if p in data:
            errors.append(f"{p}: both stub and data file")
        if not children[p]:
            errors.append(f"{p}: stub without children")

    ids = np.concatenate(id_parts) if id_parts else np.array([], np.uint64)
    ids.sort()
    dup_ids = int((ids[1:] == ids[:-1]).sum()) if len(ids) > 1 else 0
    if dup_ids:
        errors.append(f"{dup_ids} Overture ids appear more than once")
    if dup_label:
        errors.append(f"{dup_label} homes repeat a label at the same point")

    report = {
        "release": release,
        "files": len(files),
        "dataFiles": len(data),
        "stubs": len(stubs),
        "firestoreDocs": len(data) + len(stubs),
        "homes": total,
        "units": units,
        "missingCity": no_city,
        "missingZip": no_zip,
        "gzBytes": gz_total,
        "firestoreStorageBytes": doc_total,
        "largestFile": {"prefix": largest[0], "bytes": largest[1]},
        "dataFilesByPrecision": dict(sorted(collections.Counter(len(p) for p in data).items())),
        "unsplittableCells": oversize9,
        "states": dict(states.most_common()),
        "errors": errors[:200],
        "errorCount": len(errors),
    }
    if a.counts:
        raw = dict(json.loads(pathlib.Path(a.counts).read_text())["states"])
        report["vsRawCount"] = {
            st: {"raw": n, "built": states.get(st, 0),
                 "pct": round(100 * states.get(st, 0) / n, 1) if n else None}
            for st, n in sorted(raw.items(), key=lambda x: -x[1])}
    (d / "validation.json").write_text(json.dumps(report, indent=1) + "\n")

    print(f"""
Validation ({d})
  Firestore docs   {report['firestoreDocs']:,} ({len(stubs):,} stubs)
  homes            {total:,} ({units:,} units)
  gz size          {gz_total / 1e9:.2f} GB, largest {largest[0]} {largest[1] / 1024:.0f} KB
  Firestore size   {doc_total / 1e9:.2f} GB (docs only; cells fields are not indexed)
  missing city/zip {no_city:,} / {no_zip:,}
  states           {len(states)}
  errors           {len(errors)}""")
    for e in errors[:20]:
        print("   ", e)
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
