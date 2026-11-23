"""geohash.encode must match geofire-common's geohashForLocation exactly.

Run: .venv/bin/python -m pytest test_geohash.py
Needs node and tool/seed_households/node_modules (npm install there).
"""

import json
import pathlib
import subprocess

import numpy as np

import geohash

HERE = pathlib.Path(__file__).resolve().parent
SEED = HERE.parent / "seed_households"

NODE = """
const { geohashForLocation } = require('geofire-common');
const pts = JSON.parse(require('fs').readFileSync(0, 'utf8'));
process.stdout.write(JSON.stringify(pts.map(([a, o]) => geohashForLocation([a, o], 9))));
"""


def _geofire(points):
    out = subprocess.run(
        ["node", "-e", NODE],
        input=json.dumps(points),
        capture_output=True,
        text=True,
        check=True,
        cwd=SEED,
    )
    return json.loads(out.stdout)


def test_matches_geofire_common():
    rng = np.random.default_rng(42)
    random_world = np.column_stack(
        [rng.uniform(-90, 90, 20000), rng.uniform(-180, 180, 20000)]
    )
    random_us = np.column_stack(
        [rng.uniform(18, 72, 20000), rng.uniform(-180, -65, 20000)]
    )
    edges = np.array(
        [
            [0, 0], [0, -180], [0, 180], [-90, 0], [90, 0], [45, 90],
            [-45, -90], [32.7268967, -116.9635121], [32.72, -117.02],
            [22.5, 11.25], [89.9999999, 179.9999999], [-89.9999999, -179.9999999],
        ],
        dtype=np.float64,
    )
    pts = np.vstack([random_world, random_us, edges])
    ours = list(geohash.encode(pts[:, 0], pts[:, 1], 9))
    theirs = _geofire(pts.tolist())
    mismatches = [
        (p.tolist(), a, b) for p, a, b in zip(pts, ours, theirs) if a != b
    ]
    assert not mismatches, mismatches[:10]
