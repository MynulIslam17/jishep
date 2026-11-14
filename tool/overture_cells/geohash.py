"""Vectorized standard base32 geohash.

Uses the same bisection steps as `geofire-common` (`geohashForLocation`), so
the result is identical bit for bit; see test_geohash.py.
"""

import numpy as np

ALPHABET = np.frombuffer(b"0123456789bcdefghjkmnpqrstuvwxyz", dtype=np.uint8)


def encode(lat, lon, precision: int = 9) -> np.ndarray:
    """Geohashes of the points as an array of Python str."""
    lat = np.asarray(lat, dtype=np.float64)
    lon = np.asarray(lon, dtype=np.float64)
    n = lat.shape[0]
    lat_lo = np.full(n, -90.0)
    lat_hi = np.full(n, 90.0)
    lon_lo = np.full(n, -180.0)
    lon_hi = np.full(n, 180.0)
    codes = np.zeros((n, precision), dtype=np.uint8)
    even = True
    for i in range(precision * 5):
        if even:
            mid = (lon_lo + lon_hi) / 2
            bit = lon > mid
            lon_lo = np.where(bit, mid, lon_lo)
            lon_hi = np.where(bit, lon_hi, mid)
        else:
            mid = (lat_lo + lat_hi) / 2
            bit = lat > mid
            lat_lo = np.where(bit, mid, lat_lo)
            lat_hi = np.where(bit, lat_hi, mid)
        even = not even
        codes[:, i // 5] = (codes[:, i // 5] << 1) | bit.astype(np.uint8)
    chars = ALPHABET[codes]  # (n, precision) bytes
    return chars.view(f"S{precision}").ravel().astype(str)
