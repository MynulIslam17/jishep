#!/usr/bin/env python3
"""Seeds the LOCAL Firebase emulators with fictional sample data for App Store
screenshots. It never talks to the real gps-cielo project.

  firebase emulators:start --only auth,firestore --project gps-cielo
  python3 tool/store_screenshots/seed_emulator.py
  flutter build ios --simulator --debug -t tool/store_screenshots/screenshot_main.dart

Every household is fictional: "Example Street" in "Sample City". The demo
account below exists only in the Auth emulator (credentials are test values,
also used by screenshot_main.dart).
"""
import datetime as dt
import json
import urllib.request

PROJECT = "gps-cielo"
FS = f"http://127.0.0.1:8080/v1/projects/{PROJECT}/databases/(default)/documents"
AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1"

DEMO_EMAIL = "maria.demo@example.com"
DEMO_PASSWORD = "screenshots-only-123"

CENTER = (40.8790, -74.0440)
_B32 = "0123456789bcdefghjkmnpqrstuvwxyz"


def geohash(lat, lng, precision=10):
    lat_r, lng_r, out, bits, bit, even = [-90.0, 90.0], [-180.0, 180.0], "", 0, 0, True
    while len(out) < precision:
        r, v = (lng_r, lng) if even else (lat_r, lat)
        mid = (r[0] + r[1]) / 2
        if v >= mid:
            bits = bits * 2 + 1
            r[0] = mid
        else:
            bits *= 2
            r[1] = mid
        even = not even
        bit += 1
        if bit == 5:
            out += _B32[bits]
            bits, bit = 0, 0
    return out


def call(method, url, body=None, owner=True):
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None)
    req.add_header("Content-Type", "application/json")
    if owner:
        req.add_header("Authorization", "Bearer owner")
    with urllib.request.urlopen(req) as r:
        return json.load(r)


def val(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, dt.datetime):
        return {"timestampValue": v.astimezone(dt.timezone.utc).isoformat().replace("+00:00", "Z")}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: val(x) for k, x in v.items()}}}
    if v is None:
        return {"nullValue": None}
    return {"stringValue": str(v)}


def put(path, data):
    call("PATCH", f"{FS}/{path}", {"fields": {k: val(v) for k, v in data.items()}})


FAMILIES = [
    "Familia Rivera", "Familia Torres", "Familia Morales", "Familia Ortiz",
    "Familia Castillo", "Familia Herrera", "Familia Vargas", "Familia Mendoza",
    "Familia Reyes", "Familia Flores", "Familia Navarro", "Familia Romero",
    "Familia Guzmán", "Familia Salazar",
]


def main():
    now = dt.datetime.now(dt.timezone.utc)
    call("DELETE", f"http://127.0.0.1:8080/emulator/v1/projects/{PROJECT}/databases/(default)/documents")
    call("DELETE", f"http://127.0.0.1:9099/emulator/v1/projects/{PROJECT}/accounts")
    uid = call("POST", f"{AUTH}/accounts:signUp?key=emulator",
               {"email": DEMO_EMAIL, "password": DEMO_PASSWORD, "returnSecureToken": True},
               owner=False)["localId"]
    # The app only lets verified email accounts in.
    call("POST", f"{AUTH}/projects/{PROJECT}/accounts:update",
         {"localId": uid, "emailVerified": True})

    households = []
    for i, name in enumerate(FAMILIES):
        lat = CENTER[0] + 0.0011 * ((i % 4) - 1.5) + 0.0002 * i
        lng = CENTER[1] + 0.0014 * ((i // 4) - 1.5)
        hid = f"sample_{i + 1:02d}"
        address = f"{101 + 4 * i} Example Street"
        households.append((hid, name, address))
        put(f"households/{hid}", {
            "residentName": name,
            "address": address,
            "cityStateZip": "Sample City, USA",
            "geo": {"geohash": geohash(lat, lng), "geopoint": None},
        })
        # geopoint must be a GeoPoint value
        call("PATCH", f"{FS}/households/{hid}?updateMask.fieldPaths=geo",
             {"fields": {"geo": {"mapValue": {"fields": {
                 "geohash": {"stringValue": geohash(lat, lng)},
                 "geopoint": {"geoPointValue": {"latitude": lat, "longitude": lng}}}}}}})

    put(f"users/{uid}", {
        "fullName": "María López",
        "email": DEMO_EMAIL,
        "address": "100 Example Street, Sample City",
        "churchAffiliation": "Sample Church",
        "homesPrayed": 4,
        "visitsMade": 2,
        "dailyPrayerTarget": 5,
        "prayerCycleTarget": 14,
        "radiusHomes": 14,
        "searchRadiusKm": 5.0,
        "latitude": CENTER[0],
        "longitude": CENTER[1],
        "prayerCycleStartedAt": now - dt.timedelta(days=2),
    })

    def status(i, **kw):
        hid, name, address = households[i]
        put(f"users/{uid}/household_status/{hid}",
            {"residentName": name, "address": address, "updatedAt": now, **kw})

    follow = (now + dt.timedelta(days=5)).strftime("%m/%d/%Y")
    status(0, isPrayed=True, prayedAt=now)
    status(1, isPrayed=True, prayedAt=now, isVisited=True,
           notes="Visited after church. They asked for prayer for their son's new job.")
    status(2, isPrayed=True, prayedAt=now - dt.timedelta(days=1), isInvited=True,
           hasFollowUp=True, followUpDate=follow,
           notes="Invited to Sunday service. Bring a welcome card next visit.")
    status(3, isPrayed=True, prayedAt=now - dt.timedelta(days=1), isVisited=True)

    put(f"users/{uid}/notifications/n1", {
        "title": "Follow-up this week",
        "message": "You planned to visit Familia Morales again.",
        "type": "followUpDue", "isRead": False, "actionRoute": "/follow-up",
        "timestamp": now - dt.timedelta(hours=2)})
    put(f"users/{uid}/notifications/n2", {
        "title": "Keep going!",
        "message": "You have prayed for 4 of your 14 neighbors this round.",
        "type": "milestone", "isRead": True, "actionRoute": "/prayer-list",
        "timestamp": now - dt.timedelta(days=1)})
    print("seeded", len(households), "households for", uid)


if __name__ == "__main__":
    main()
