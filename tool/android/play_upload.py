"""Uploads an .aab to Google Play and releases it on a testing track.

    python tool/android/play_upload.py <app-release.aab> [--track internal]

Credentials: a Google service account JSON (env PLAY_SERVICE_ACCOUNT_JSON, the
file's contents) that is invited in Play Console > Users and permissions with
release rights for com.ergan.adgag. Uses the Android Publisher API directly:
open an edit, upload the bundle, put its versionCode on the track
(status completed), commit. A failure before the commit changes nothing.
"""

import argparse
import json
import os
import sys
import time

import jwt
import requests

PACKAGE = "com.ergan.adgag"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"


def access_token(sa: dict) -> str:
    now = int(time.time())
    assertion = jwt.encode(
        {
            "iss": sa["client_email"],
            "scope": "https://www.googleapis.com/auth/androidpublisher",
            "aud": sa["token_uri"],
            "iat": now,
            "exp": now + 3600,
        },
        sa["private_key"],
        algorithm="RS256",
    )
    r = requests.post(
        sa["token_uri"],
        data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
        timeout=60,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def check(r: requests.Response, what: str) -> dict:
    if r.status_code >= 300:
        sys.exit(f"{what} failed: HTTP {r.status_code}\n{r.text}")
    return r.json() if r.text else {}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("aab")
    ap.add_argument("--track", default="internal")
    a = ap.parse_args()

    raw = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON")
    if not raw:
        sys.exit("PLAY_SERVICE_ACCOUNT_JSON is not set")
    sa = json.loads(raw)
    h = {"Authorization": f"Bearer {access_token(sa)}"}

    edit = check(requests.post(f"{API}/edits", headers=h, timeout=60), "Opening an edit")["id"]
    with open(a.aab, "rb") as f:
        bundle = check(
            requests.post(
                f"{UPLOAD}/edits/{edit}/bundles",
                params={"uploadType": "media"},
                headers={**h, "Content-Type": "application/octet-stream"},
                data=f,
                timeout=900,
            ),
            "Uploading the bundle",
        )
    version_code = bundle["versionCode"]
    check(
        requests.put(
            f"{API}/edits/{edit}/tracks/{a.track}",
            headers=h,
            json={"track": a.track, "releases": [{"versionCodes": [str(version_code)], "status": "completed"}]},
            timeout=60,
        ),
        f"Setting the {a.track} track",
    )
    check(requests.post(f"{API}/edits/{edit}:commit", headers=h, timeout=120), "Committing")
    print(f"versionCode {version_code} released on the {a.track} track")


if __name__ == "__main__":
    main()
